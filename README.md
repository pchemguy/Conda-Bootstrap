---
project: https://chatgpt.com/g/g-p-6afc2115d3b481918cfff04fa63d722d
url: https://chatgpt.com/c/6afc32cd-eb8c-83e9-a6ee-3c2cbe3b1a4d
---

# Conda Bootstrap

Conda Bootstrap uses Micromamba to create a project-local Python environment on Windows (CMD) or Linux (Bash), without a preinstalled Python or Conda. Both harnesses install Python, Conda, Mamba, Micromamba, and uv in a directory named after the bootstrap script. This directory is the environment’s *prefix*. Edit the adjacent manifests to choose packages, then activate the prefix in the shell where you work.

## Windows harness

On Windows, three batch files handle different parts of the workflow. [Anaconda.bat](windows/Anaconda.bat) builds the environment. [conda_far.bat](windows/conda_far.bat) activates it for an interactive session, a batch build, or a single command. [msbuild.bat](windows/msbuild.bat) prepares the x64 Visual C++ toolchain used by native builds.

### Build and open the environment

Start a **clean Command Prompt** in the repository root on x64 Windows. The harness requires `curl.exe` and `tar.exe` on `PATH`. With the shipped `msbuild.bat`, install the Visual Studio C++ Build Tools before bootstrapping. Leave `CONDA_PREFIX` unset and check that `where.exe python.exe` and `where.exe conda.bat` find nothing in the current directory or on `PATH`. A Windows app execution alias for Python counts as a match.

**Before the first run**, check the existing cache directories. The harness replaces `%LOCALAPPDATA%\pip\cache` and `%LOCALAPPDATA%\uv\cache` with junctions to its selected cache. It deletes the contents of ordinary directories at those paths. The Conda bootstrap also removes `%APPDATA%\mamba` recursively if it exists, pausing first unless `/q` is set. To choose the cache root, set `_CACHE` to an existing writable directory before running the scripts.

Run the bootstrap, then open the environment if it succeeds.

```bat
call windows\Anaconda.bat && call windows\conda_far.bat
```

The bootstrap creates `windows\Anaconda` and returns to the original prompt. The second command opens FAR Manager when available, or an interactive CMD session otherwise. Inside that session, `echo %CONDA_PREFIX%` shows the active prefix and `where.exe python.exe` should list its interpreter first.

### Choose the dependencies

Keep the manifests beside `Anaconda.bat`. The script calls `conda_far.bat /cache` before downloading or reusing Micromamba and uv. It builds the prefix from the bootstrap YAML, calls `conda_far.bat /preactivate`, and checks the new interpreter before installing project packages.

| Input, in processing order | Purpose |
| --- | --- |
| [Anaconda_bootstrap.yml](windows/Anaconda_bootstrap.yml) | Defines the base environment on conda-forge. The shipped file includes the package managers, Python, Git, Hatch, Ruff, and mypy. |
| [Anaconda.yml](windows/Anaconda.yml) | Adds project packages through Mamba. The shipped selection includes Node.js, NumPy, pandas, Polars, and pytest. |
| `*.req.txt` | Installs each matching requirements file with the activated `pip.exe`. |
| `requirements.txt`, then [Anaconda.txt](windows/Anaconda.txt) | Installs each file that exists with `uv pip install --system` in the activated environment. The shipped `Anaconda.txt` adds `flowmark`. |

A full Conda build writes `Anaconda_generated.yml` (Conda environment export without build strings) and `Anaconda.pip.txt` (the `uv pip list` package inventory) beside the script.

**Choose full or base-only on the first run.** `/init` stops after activating and checking the base. Once `windows\Anaconda\python.exe` exists, any later bootstrap invocation returns success immediately. This also applies after an interrupted build. To rebuild from the manifests, move the existing prefix aside first. `/q` reduces package-manager output and skips the Mamba-directory pause. `/nocolor` selects plain status labels.

For a new Conda prefix, the script requires the bootstrap YAML plus either the main YAML or a sibling `pyproject.toml`. When the bootstrap YAML is absent and `pyproject.toml` exists, the script attempts a standalone NuGet CPython installation. Its version parser cannot read the documented `requires-python = ">=3.10"` example, and its generated activation wrappers cannot apply a Conda YAML. The [Windows bootstrap guide](windows/Anaconda.md) describes this fallback and the recovery paths.

### Activate for development or automation

For an existing installation, start each workflow from a clean CMD session. When passing an option to `conda_far.bat`, enable delayed expansion in the caller with `cmd.exe /E:ON /V:ON` or `setlocal EnableExtensions EnableDelayedExpansion` in a batch file.

| Goal | Command from the repository root |
| --- | --- |
| Open an interactive development session | `call windows\conda_far.bat` |
| Activate the calling batch file and continue its build | `call windows\conda_far.bat /batch` |
| Activate, run one command, and return its exit status | `call windows\conda_far.bat /cli "python.exe --version"` |

During activation, `msbuild.bat` reuses a verified x64 build shell or locates and calls `vcvars64.bat`. It checks that `cl.exe` and the Microsoft `link.exe` resolve from the same directory. The activation wrapper handles a conflicting MSYS `Library\usr\bin\link.exe` by renaming it to `link_.exe`, replacing any previous backup. After MSVC setup, it sets `DISTUTILS_USE_SDK=1` so setuptools can reuse the toolchain. It then activates the Conda prefix, checks for a bundled JVM if `JAVA_HOME` is unset, and calls sibling `config_*.bat` scripts for project-specific settings.

For cache selection, custom prefixes, and activation hooks, see the [activation guide](windows/conda_far.md). For compiler discovery and linker diagnostics, see the [MSVC guide](windows/msbuild.md).

## Linux harness

[Anaconda.sh](linux/Anaconda.sh) installs a complete Conda base in `linux/Anaconda/` and generates `linux/Anaconda_activate.sh` beside it. Linux builds use the system C toolchain and normal package-manager caches. Use Bash on glibc-based x86-64 or AArch64 Linux with `curl`, `flock`, and standard GNU utilities. Choose a writable installation path without whitespace because installed command-line tools can embed the absolute interpreter path.

### Build, activate, and verify

Run these commands from the repository root. The bootstrap runs in its own process. Source the generated launcher in each shell that needs the environment.

```bash
./linux/Anaconda.sh &&
    source ./linux/Anaconda_activate.sh &&
    python -c 'import sys; print(sys.prefix)'
```

The printed path should end in `linux/Anaconda`. Use `conda deactivate` to leave the environment. For a single command in automation, the prefix's Conda can also run a program directly from a fresh shell.

```bash
./linux/Anaconda/bin/conda run --prefix "$PWD/linux/Anaconda" python --version
```

### Configure and update the environment

| Input | How the harness uses it |
| --- | --- |
| [Anaconda_bootstrap.yml](linux/Anaconda_bootstrap.yml) | Required. On the first run, a temporary Micromamba executable installs the base at the script-named prefix. |
| [Anaconda.yml](linux/Anaconda.yml) | A full run applies this optional Conda manifest with the prefix's Micromamba. The shipped selection includes pytest, coverage, profiling tools, and PyYAML. |
| [Anaconda.txt](linux/Anaconda.txt) | After activation, the prefix's uv installs these optional pip requirements against the same Python interpreter. |
| [Anaconda_extra.yml](linux/Anaconda_extra.yml) | Separate manifest for additional packages, including Node.js, NumPy, pandas, and Polars. Apply it explicitly when those tools are needed. |

Use `./linux/Anaconda.sh --init` for the base and its launcher. A subsequent full run **reuses the base**, applies the project manifests, and writes `linux/Anaconda_generated.yml` and `linux/Anaconda.pip.txt`. Rerun after editing `Anaconda.yml` or `Anaconda.txt`. Removing an entry from a manifest leaves the installed package in place.

To install the extra packages in an activated environment, run this from the repository root.

```bash
micromamba env update --yes --no-rc --prefix "$CONDA_PREFIX" --file ./linux/Anaconda_extra.yml
```

The launcher activates the prefix through Conda, so package-provided activation hooks run in the current shell. For example, adding `openjdk` to `Anaconda.yml` lets the package's hook set `JAVA_HOME` on activation. Local settings can use paired scripts under `etc/conda/activate.d/` and `etc/conda/deactivate.d/` in the prefix. See the [Linux bootstrap guide](linux/Anaconda.md) for customization and the [agent setup recipe](linux/AGENTS.md) for a compact workflow.
