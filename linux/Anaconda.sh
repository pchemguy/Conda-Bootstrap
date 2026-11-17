#!/usr/bin/env bash
# Build a Conda base prefix beside this script. Source the generated launcher to use it.
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
    printf 'Run this bootstrap as a script. Source the generated activation script afterward.\n' >&2
    return 2
fi
set -eo pipefail

usage() {
    printf 'Usage: %s [--init]\n' "${0##*/}"
    printf '  --init   Create or verify the base and its activation script only.\n'
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

mode=full
while (( $# )); do
    case $1 in
        --init) mode=init ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fail "Unknown argument: $1" ;;
    esac
    shift
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
name=${BASH_SOURCE[0]##*/}
prefix="$script_dir/${name%.sh}"
bootstrap="${prefix}_bootstrap.yml"
launcher="${prefix}_activate.sh"

[[ $prefix != *[[:space:]]* ]] || fail "Use a prefix without whitespace. Conda entry points embed the Python path: $prefix"
if [[ -e $launcher || -L $launcher ]]; then
    [[ -f $launcher && -r $launcher ]] || fail "Activation launcher is not a readable file: $launcher"
fi
[[ -f $bootstrap ]] || fail "Missing bootstrap manifest: $bootstrap"
[[ $(uname -s) == Linux ]] || fail "This bootstrap requires Linux."
# Serialize runs for this script without leaving a lock file in the project.
exec {lock_fd}<"${BASH_SOURCE[0]}"
flock -n "$lock_fd" || fail "Another bootstrap is running for $prefix."

work_dir=$(mktemp -d -- "$script_dir/.${name}.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
unset PYTHONHOME PYTHONPATH
export PYTHONNOUSERSITE=1
export MAMBA_ROOT_PREFIX="$prefix"

if [[ -e $prefix || -L $prefix ]]; then
    [[ -f $prefix/conda-meta/history ]] || fail "Existing path is not a Conda environment: $prefix"
else
    case $(uname -m) in
        x86_64) platform=linux-64 ;;
        aarch64|arm64) platform=linux-aarch64 ;;
        *) fail "Unsupported Linux architecture: $(uname -m)" ;;
    esac
    printf 'Creating %s from %s\n' "$prefix" "$bootstrap"
    url="https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-$platform"
    curl --fail --location --retry 3 --silent --show-error --output "$work_dir/micromamba" "$url"
    chmod +x "$work_dir/micromamba"
    "$work_dir/micromamba" install --yes --no-rc --name base --file "$bootstrap"
fi

for tool in python conda mamba micromamba uv; do
    [[ -x $prefix/bin/$tool ]] || fail "Missing $prefix/bin/$tool. Check the bootstrap manifest and the installation."
done
[[ -r $prefix/bin/activate ]] || fail "Missing Conda activation script under $prefix/bin."
"$prefix/bin/conda" env config vars set --prefix "$prefix" "MAMBA_ROOT_PREFIX=$prefix" PYTHONNOUSERSITE=1

if [[ $mode == full && -f $prefix.yml ]]; then
    "$prefix/bin/micromamba" env update --yes --no-rc --use-uv --prefix "$prefix" --file "$prefix.yml"
fi

# Load package-provided hooks before using the environment, including on --init.
source "$prefix/bin/activate" "$prefix"
[[ $CONDA_PREFIX == "$prefix" ]] || fail "Conda activated an unexpected prefix: $CONDA_PREFIX"
"$prefix/bin/python" --version

if [[ ! -e $launcher && ! -L $launcher ]]; then
    {
        printf '%s\n' '#!/usr/bin/env bash' '# Source this file to activate the local Conda environment.'
        printf '%s\n' 'if [[ ${BASH_SOURCE[0]} == "$0" ]]; then' \
            '    echo "Source this script in Bash to activate the environment." >&2' '    exit 2' 'fi'
        printf 'source %q %q\n' "$prefix/bin/activate" "$prefix"
    } > "$work_dir/activate.sh"
    mv -- "$work_dir/activate.sh" "$launcher"
fi

if [[ $mode == full ]]; then
    if [[ -f $prefix.txt ]]; then
        "$prefix/bin/uv" pip install --python "$prefix/bin/python" --requirement "$prefix.txt"
    fi
    "$prefix/bin/conda" env export --prefix "$prefix" --no-builds > "$work_dir/environment.yml"
    "$prefix/bin/uv" pip list --python "$prefix/bin/python" > "$work_dir/packages.txt"
    mv -- "$work_dir/environment.yml" "${prefix}_generated.yml"
    mv -- "$work_dir/packages.txt" "$prefix.pip.txt"
fi

printf 'Activate in Bash with: source %q\n' "$launcher"
