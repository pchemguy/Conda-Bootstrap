---
project: https://chatgpt.com/g/g-p-6afc2115d3b481918cfff04fa63d722d
url: https://chatgpt.com/c/6afc32cd-eb8c-83e9-a6ee-3c2cbe3b1a4d
---

# Conda Bootstrap

Conda Bootstrap uses Micromamba to create a complete, project-local Conda environment on Windows or Linux. Copy the files for your platform into the directory that will host the environment. Run `Anaconda.bat` on Windows or `Anaconda.sh` on Linux to install Python, Conda, Mamba, Micromamba, uv, and your project packages under `Anaconda/`, beside the script. No system Python or Conda is required. For later sessions, run `conda_far.bat` on Windows or source the generated `Anaconda_activate.sh` in Bash.

## Choose the packages

Use the YAML manifests for Conda packages. They specify `conda-forge` with `nodefaults`. Both harnesses use `--no-rc` for Conda package installation, so add any additional channel to `channels` in the manifest that needs it.

Use `Anaconda.txt` for packages or builds you want from PyPI, an alternate index, or a direct wheel URL. After the Conda packages install successfully, uv installs the requirements listed there. If a Conda build is unavailable and a suitable wheel exists, declare it in `Anaconda.txt` and remove the Conda requirement. A failed Conda solve stops the bootstrap.

| File | When it is used | Windows defaults | Linux defaults |
| --- | --- | --- | --- |
| `Anaconda_bootstrap.yml` | Creates the base environment on first install. | [Python and package managers, Git, Hatch, Ruff, mypy, pytest and plugins, coverage, and profiling tools](windows/Anaconda_bootstrap.yml) | [Python and package managers, Git, Hatch, Ruff, and mypy](linux/Anaconda_bootstrap.yml) |
| `Anaconda.yml` | Adds Conda project dependencies on a full run. | [Node.js, PyYAML, NumPy, pandas, Polars, and other libraries](windows/Anaconda.yml) | [pytest and plugins, coverage, pyinstrument, and pyperf](linux/Anaconda.yml) |
| `Anaconda.txt` | Installs pip-style requirements into the same environment with uv. | [flowmark](windows/Anaconda.txt) | [flowmark](linux/Anaconda.txt) |
| `Anaconda_extra.yml` | Optional Conda packages installed on request. | — | [Node.js, PyYAML, NumPy, pandas, Polars, and other libraries](linux/Anaconda_extra.yml) |

<details>
<summary>Requirements examples for an alternate index and a direct wheel</summary><br>

To add the PyTorch CUDA index for `torch`, put these lines in `Anaconda.txt`.<br>

<code>
--extra-index-url https://download.pytorch.org/whl/cu129<br>
torch
</code>
<br>

To install spaCy’s small English pipeline, `en_core_web_sm`, put its release wheel URL on a line in `Anaconda.txt`.<br><br>

```text
https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl
```

</details>

## Windows harness

### Bootstrap the environment

Copy the **contents** of [windows/](windows/) into the local directory that will hold the harness and environment, for example `D:\Dev\MyProject`. Edit the manifests beside `Anaconda.bat` if you want a different package set. The batch file uses its own directory and filename (`%~dpn0`) as the installation prefix, so this copy creates `D:\Dev\MyProject\Anaconda\python.exe`.

**Before the first run, check the shared cache paths.** The harness redirects `%LOCALAPPDATA%\pip\cache` and `%LOCALAPPDATA%\uv\cache` to a shared cache using junctions. It deletes the contents of ordinary directories at those paths. To select the shared cache, set `_CACHE` to an existing writable directory before running the bootstrap. If `%APPDATA%\mamba` exists, the Conda bootstrap pauses before recursively deleting it. `/q` skips that pause.

On x64 Windows, open a Command Prompt without an active Python or Conda environment. The bootstrap uses `curl.exe` and `tar.exe`.

```bat
cd /d D:\Dev\MyProject
Anaconda.bat
```

**Base only or full install.** Choose `Anaconda.bat /init` if you want to stop after the base Python check. Once `Anaconda\python.exe` exists, subsequent bootstrap runs exit immediately. To rebuild from changed manifests or retry an incomplete install, move the existing prefix aside and start a fresh run. The [Windows bootstrap guide](windows/Anaconda.md) also covers the alternative NuGet CPython workflow.

### Work in the environment

From the directory containing the copied harness, run the launcher each time you need an interactive session.

```bat
conda_far.bat
```

The launcher activates `Anaconda\`, runs any sibling `config_*.bat` files, and opens FAR Manager if available or an interactive Command Prompt otherwise. For an automated build, call the launcher with `/batch` from your own batch file. This example places both files in the same directory.

```bat
@echo off
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0conda_far.bat" /batch
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
python --version
```

To run a single command, use `conda_far.bat /cli "python --version"` in a CMD session started with `cmd.exe /E:ON /V:ON`. The launcher returns the command’s exit status. See the [activation guide](windows/conda_far.md) for the other modes and configuration hooks.

### Bootstrap and activation details

[Anaconda.bat](windows/Anaconda.bat) calls `conda_far.bat /cache` to prepare the cache, downloads or reuses Micromamba and uv, and creates the base from `Anaconda_bootstrap.yml`. It calls `conda_far.bat /preactivate` to activate the prefix and then checks Python. A full run applies `Anaconda.yml` with Mamba, installs any sibling `*.req.txt` files with pip, then applies `requirements.txt` and `Anaconda.txt` with uv when present. It writes `Anaconda_generated.yml` (Conda export) and `Anaconda.pip.txt` (Python package list) beside the script and returns to the original prompt.

During activation, `conda_far.bat` calls [msbuild.bat](windows/msbuild.bat) if it is present. The helper checks whether an x64 MSVC toolchain is already active. Otherwise, it searches for an installed Visual Studio or Build Tools C++ toolchain and calls its `vcvars64.bat`. If discovery fails, activation stops and the helper points you to installation instructions. Installing the Build Tools is a separate manual step. When the helper is absent, Conda activation proceeds.

**MSYS and MSVC both provide `link.exe`.** Before calling the MSVC helper, `conda_far.bat` renames the prefix’s `Library\usr\bin\link.exe` to `link_.exe` when present. In an already active x64 shell or after calling `vcvars64.bat`, `msbuild.bat` checks which `link.exe` CMD finds first. Its `/?` output must identify the Microsoft linker or contain `/INCREMENTAL`, and its directory must match that of the first `cl.exe`. If an MSYS copy wins the search or the tool directories differ, the helper reports the conflicting paths and stops activation. Use `where.exe link.exe` and `where.exe cl.exe` in that CMD session to identify which directory takes precedence. See the [toolchain detection guide](windows/msbuild.md).

## Linux harness

### Bootstrap the environment

Copy the **contents** of [linux/](linux/) into the local directory that will hold the harness and environment. Choose a writable path without whitespace. Use Bash on glibc-based x86-64 or AArch64 Linux with `curl`, `flock`, and standard GNU utilities available. Native builds use the configured system toolchain. The package managers use their normal caches.

Edit the manifests beside `Anaconda.sh`, then run the following from that directory.

```bash
bash ./Anaconda.sh
```

On first install, [Anaconda.sh](linux/Anaconda.sh) downloads a temporary Micromamba executable to create the `Anaconda/` base. A full run uses the installed Micromamba to apply `Anaconda.yml`, activates the prefix, and uses uv to install `Anaconda.txt` against `Anaconda/bin/python`. It generates `Anaconda_activate.sh` beside the bootstrap, preserves an existing launcher, and writes `Anaconda_generated.yml` and `Anaconda.pip.txt`.

### Work in the environment

Source the generated launcher in each Bash shell that needs the environment. The launcher loads the prefix into the current shell, so its executables are on `PATH` and package activation hooks run. For example, conda-forge OpenJDK sets `JAVA_HOME` when installed. The Python check below prints the absolute path to the adjacent `Anaconda/` directory.

```bash
source ./Anaconda_activate.sh
python -c 'import sys; print(sys.prefix)'
```

Use `conda deactivate` when finished. To run one command from a fresh shell in the harness directory, invoke the installed Conda directly.

```bash
./Anaconda/bin/conda run --prefix "$PWD/Anaconda" python --version
```

### Build in stages or add packages

- **Base only.** Run `bash ./Anaconda.sh --init` to create or verify the base and generate the launcher. A later full `bash ./Anaconda.sh` reuses that base, applies the project manifests, and writes the inventories.
- **Update project dependencies.** After editing `Anaconda.yml` or `Anaconda.txt`, rerun `bash ./Anaconda.sh`. The bootstrap YAML is read for package installation only when creating the base. Removing an entry from a project manifest does not remove an already installed package.
- **Install the optional extras.** From the harness directory with the environment active, apply the extra manifest explicitly. The supplied manifest installs Node.js, so you can verify the result with `node --version`.

```bash
micromamba env update --yes --no-rc --prefix "$CONDA_PREFIX" --file ./Anaconda_extra.yml
node --version
```

See the [Linux bootstrap guide](linux/Anaconda.md) for package hooks, project variables, and custom launchers. The [agent setup recipe](linux/AGENTS.md) gives the build and activation commands in compact form.
