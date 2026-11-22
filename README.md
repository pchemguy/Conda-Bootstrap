# Conda Bootstrap

Conda Bootstrap creates a project-local Python environment on Windows or Linux using Micromamba. Copy the files for your platform into the directory that will host the environment, choose the packages in the supplied manifests, and run the bootstrap once. The default manifests install Python, Conda, Mamba, Micromamba, and uv under `Anaconda/`, beside the bootstrap script. On subsequent visits, use the activation script to work in that environment. No existing Python or Conda installation is required.

## Windows harness

### Set up a project

1. Copy the **contents** of [windows/](windows/) into the local directory that will hold the harness and its environment. For example, copying them into `D:\Dev\MyProject` puts `Anaconda.bat` and `conda_far.bat` directly in that directory. The resulting interpreter will be `D:\Dev\MyProject\Anaconda\python.exe`.
2. Edit the dependency files beside `Anaconda.bat`. Use the files as supplied for the default package set.

   | File | What belongs here |
   | --- | --- |
   | [Anaconda_bootstrap.yml](windows/Anaconda_bootstrap.yml) | The base environment. The supplied manifest includes Python, the package managers, Git, Hatch, Ruff, and mypy. |
   | [Anaconda.yml](windows/Anaconda.yml) | Project dependencies installed through Conda. The supplied manifest includes Node.js, pytest, NumPy, pandas, and Polars. |
   | [Anaconda.txt](windows/Anaconda.txt) | Python requirements installed with uv after the Conda packages. The supplied file adds `flowmark`. |

3. On x64 Windows, open a Command Prompt without an active Python or Conda environment and run the copied bootstrap. It uses `curl.exe` and `tar.exe`.

   ```bat
   cd /d D:\Dev\MyProject
   Anaconda.bat
   ```

### Use the installed environment

From the local harness directory, run `conda_far.bat` whenever you want to work in the environment.

```bat
cd /d D:\Dev\MyProject
conda_far.bat
```

The launcher activates `Anaconda\`, applies any sibling `config_*.bat` files, and opens FAR Manager if available or an interactive CMD session otherwise. Python and the installed tools are available there.

For an automated build, use `/batch` to activate the calling batch file and continue with your own commands. This example assumes your batch file is beside `conda_far.bat`.

```bat
@echo off
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0conda_far.bat" /batch
if errorlevel 1 exit /b %errorlevel%
python --version
```

To run just one command, use `conda_far.bat /cli "python --version"` from a CMD session started with `cmd.exe /E:ON /V:ON`. The launcher returns the command’s exit status. See the [activation guide](windows/conda_far.md) for the other modes and configuration hooks.

### How the Windows bootstrap works

[Anaconda.bat](windows/Anaconda.bat) calls `conda_far.bat /cache` to select a shared cache, downloads or reuses Micromamba and uv, and creates `Anaconda\` from the bootstrap YAML. It then calls `conda_far.bat /preactivate` to activate the new environment for the rest of the installation. After verifying Python, it applies `Anaconda.yml` with Mamba. It then processes any `*.req.txt` files with pip, followed by `requirements.txt` and `Anaconda.txt` with uv when present. A full run writes `Anaconda_generated.yml` and `Anaconda.pip.txt` beside the batch file and returns to the original prompt.

**Effects on existing caches.** Cache setup replaces `%LOCALAPPDATA%\pip\cache` and `%LOCALAPPDATA%\uv\cache` with junctions to the shared cache. It deletes the contents of ordinary directories at those paths. Set `_CACHE` to an existing writable directory to choose the cache location. On the Conda installation path, the bootstrap also pauses before recursively removing an existing `%APPDATA%\mamba`. The `/q` switch skips that pause and reduces package-manager output.

**Visual C++ tools.** During activation, `conda_far.bat` calls the sibling [msbuild.bat](windows/msbuild.bat) if present. It detects an already configured x64 MSVC shell or searches for an installed Visual Studio or Microsoft Build Tools C++ toolchain and activates it through `vcvars64.bat`. If it cannot find the tools, activation stops and the helper points you to installation instructions. You install the Build Tools yourself. If the helper is absent, activation skips the MSVC step. See the [toolchain detection guide](windows/msbuild.md) for search paths and diagnostics.

**Base-only installs and reruns.** `Anaconda.bat /init` stops after creating, activating, and checking the base. Once `Anaconda\python.exe` exists, the bootstrap returns success immediately, even if an earlier run stopped before installing all project packages. Choose a full run initially if you want the project manifests applied. To rebuild, move the old prefix aside and run `Anaconda.bat` again. The [Windows bootstrap guide](windows/Anaconda.md) also documents the alternate NuGet CPython path and its `pyproject.toml` parsing limits.

## Linux harness

### Set up a project

Copy the **contents** of [linux/](linux/) into the local directory that will hold the harness and environment. Use a writable path without whitespace on glibc-based x86-64 or AArch64 Linux. The bootstrap uses Bash, `curl`, `flock`, and standard GNU utilities. Native builds use the configured system compiler.

Edit the manifests beside [Anaconda.sh](linux/Anaconda.sh) before running it.

| File | How the harness uses it |
| --- | --- |
| [Anaconda_bootstrap.yml](linux/Anaconda_bootstrap.yml) | Defines the base. A temporary Micromamba executable installs it into `Anaconda/` on the first run. |
| [Anaconda.yml](linux/Anaconda.yml) | Adds Conda project packages on a full run. The supplied file includes pytest, coverage, profiling tools, and PyYAML. |
| [Anaconda.txt](linux/Anaconda.txt) | Adds pip requirements through uv using the prefix’s Python. |
| [Anaconda_extra.yml](linux/Anaconda_extra.yml) | Provides optional packages such as Node.js, NumPy, pandas, and Polars. Apply this manifest separately when needed. |

From the directory containing the copied files, run the bootstrap and source the launcher it generates.

```bash
bash ./Anaconda.sh &&
    source ./Anaconda_activate.sh &&
    python -c 'import sys; print(sys.prefix)'
```

The printed path is the local `Anaconda/` directory. A full run writes `Anaconda_generated.yml` and `Anaconda.pip.txt` beside the script.

### Activate, update, or extend the environment

- **Start a new session.** Run `source ./Anaconda_activate.sh` from the harness directory in each Bash shell that needs the environment. Use `conda deactivate` when finished. Sourcing the launcher also runs Conda package hooks, including the `JAVA_HOME` setup when a conda-forge OpenJDK is installed.
- **Run a single command.** From the same directory, use `./Anaconda/bin/conda run --prefix "$PWD/Anaconda" python --version`.
- **Build in stages.** Run `bash ./Anaconda.sh --init` to create the base and launcher. A later `bash ./Anaconda.sh` reuses the base and applies the project manifests. Run it again after changing `Anaconda.yml` or `Anaconda.txt`.
- **Install the extras.** With the environment active, run `micromamba env update --yes --no-rc --prefix "$CONDA_PREFIX" --file ./Anaconda_extra.yml` from the harness directory.

See the [Linux bootstrap guide](linux/Anaconda.md) for activation settings and the [agent setup recipe](linux/AGENTS.md) for a compact workflow.
