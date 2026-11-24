# Bootstrap a Windows Python environment with Anaconda.bat

[Anaconda.bat](Anaconda.bat) creates a Python installation beside the batch file. With the files shipped in this repository, it uses Micromamba to create the sibling `Anaconda` directory, activates the installation, installs the project packages, and writes two package inventories on a full run. Activation lasts for the bootstrap run. Use `conda_far.bat` afterward to work in the environment.

## Build and use the shipped environment

**Before the first run**, check whether you need the contents of your current pip and uv caches. Cache setup replaces the current user's pip and uv cache directories with junctions. On the Conda route, the bootstrap also recursively removes `%APPDATA%\mamba` if it exists. By default it pauses before removing that directory. `/q` suppresses that pause. See [Cache and filesystem changes](#cache-and-filesystem-changes).

1. Copy the contents of [windows/](./) into the local directory that will host the environment. Open a clean Windows Command Prompt there, with no Python or Conda environment active or on `PATH`. The bootstrap enables command extensions and delayed expansion.
2. Make sure `curl.exe` and `tar.exe` are on `PATH`. The downloads target Windows x64. The shipped `msbuild.bat` detects and verifies an installed MSVC toolchain during preactivation. If the C++ Build Tools are missing, install them separately. The script displays NVIDIA driver information when `nvidia-smi.exe` is available. A missing GPU or failed GPU query only produces a warning.
3. Run the bootstrap and inspect its exit status.

   ```bat
   call Anaconda.bat
   echo %ERRORLEVEL%
   ```

4. On a fresh, successful full run, look beside `Anaconda.bat` for `Anaconda_generated.yml` and `Anaconda.pip.txt`. To open the installed environment from the same clean prompt, run the following command. It launches FAR Manager if available, otherwise an interactive CMD session.

   ```bat
   call conda_far.bat
   ```

## Command-line options

```bat
Anaconda.bat [/init] [/q] [/nocolor]
```

| Option | Effect |
| --- | --- |
| No options | Create and verify the base environment, apply dependency files, then export inventories. |
| `/init` | Stop after activating the new base and running its `python.exe --version`. Skip the main YAML, pip requirement files, and both exports. The usual input checks still apply. |
| `/q` | Omit the extra `-v` on package operations and skip the pause before deleting `%APPDATA%\mamba`. Progress messages and errors are still printed. |
| `/nocolor` | Use plain-text status labels. Defining `NO_COLOR` or `NOCOLOR` also selects plain text. |

Options are case-insensitive and can be combined. The parser accepts `/`, `-`, `--`, or a bare option name. It warns and skips unknown arguments. To build only the base, for example, run `call Anaconda.bat /init`. A later invocation sees the existing interpreter and exits immediately, so choose a full run on the first invocation if you want the dependency imports and exports.

## Choose the bootstrap inputs

All paths below are relative to the batch file, regardless of the caller's working directory. The script's filename determines the installation prefix and the names of its matching files. For example, renaming `Anaconda.bat` to `Project.bat` changes the prefix to `Project\` and the bootstrap YAML to `Project_bootstrap.yml`. The sibling helper keeps the fixed name `conda_far.bat`. The bootstrap passes the renamed prefix to the helper during creation. To activate it later, set `_CONDA_PREFIX` to its full path before calling the helper.

| Files present beside `Anaconda.bat` | Result for a new prefix |
| --- | --- |
| `Anaconda_bootstrap.yml` and `Anaconda.yml` | Micromamba creates the base. A full run applies the main YAML after activation. This is the repository configuration. |
| `Anaconda_bootstrap.yml` and `pyproject.toml`, without `Anaconda.yml` | Micromamba creates the base. The TOML file satisfies the input check. The script skips the main YAML and continues with pip inputs on a full run. |
| All three | The bootstrap and main YAML files supply the Conda inputs. The script ignores the TOML contents. |
| `pyproject.toml` without `Anaconda_bootstrap.yml` | Selects the NuGet CPython fallback, even when `Anaconda.yml` exists. See its parsing and package-management limits below. |
| Neither bootstrap YAML nor TOML, or bootstrap YAML alone with neither main YAML nor TOML | Stops before cache setup. Pip requirement files do not satisfy either check. |

The shipped [bootstrap YAML](Anaconda_bootstrap.yml) selects `conda-forge` with `nodefaults` and requests Python, Conda, Mamba, Micromamba, uv, pipx, Git, Hatch, Ruff, mypy, pytest and plugins, coverage, and profiling tools. The [main YAML](Anaconda.yml) adds project dependencies including Node.js, NumPy, pandas, and Polars. The final named [pip requirements file](Anaconda.txt) adds `flowmark`. To customize a fresh build, edit the file for the stage that should install each dependency.

## What a full run does

1. **Check the prefix.** If `Anaconda\python.exe` exists, return `0` immediately. This happens before prerequisite checks, activation, imports, version checks, or exports.
2. **Prepare the cache and bootstrap tools.** Check the helper and host tools, resolve the input files, then call `conda_far.bat /cache`. In both bootstrap modes, obtain Micromamba and uv from the cache or their latest GitHub releases and run each cached executable with `--version`.
3. **Create the installation.** In Conda mode, clear `%APPDATA%\mamba` if present and run Micromamba `create --yes --no-rc --use-uv` with the bootstrap YAML and an explicit `--prefix`. If the caller has set `PKGS`, its contents are appended to the create command as additional arguments. The alternate creation path is described in [NuGet CPython fallback](#nuget-cpython-fallback).
4. **Activate and verify Python.** Pass the new prefix to `conda_far.bat /preactivate` via `_CONDA_PREFIX`. The helper configures caches again, calls the sibling MSVC checker when available, activates the prefix through its wrapper, and runs any sibling `config_*.bat` files. It returns to the bootstrap with `CONDA_BAT` and `MAMBA_BAT` available. The bootstrap checks `%CONDA_PREFIX%\python.exe` and runs it with `--version`. An `/init` run ends here.
5. **Install dependencies in order.** Each row runs only when its input exists. A failing package command stops the remaining stages.

   | Order | Input | Command used after activation |
   | --- | --- | --- |
   | 1 | `Anaconda.yml` | `call "%MAMBA_BAT%" env update --yes --no-rc --use-uv -f "<file>" --prefix "%CONDA_PREFIX%"` |
   | 2 | Each sibling `*.req.txt` | `pip.exe install -r "<file>"`, once per match in CMD's enumeration order |
   | 3 | `requirements.txt` | `uv.exe pip install --system -r "<file>"` |
   | 4 | `Anaconda.txt` | `uv.exe pip install --system -r "<file>"` |

   The table omits the default `-v` for readability. The pip stages use the commands visible in the activated shell. The earlier uv version check uses the cached executable by absolute path.

6. **Write inventories.** On the Conda route, `conda.bat env export --no-builds` writes `Anaconda_generated.yml`. On either route reaching this stage, `uv.exe pip list` writes `Anaconda.pip.txt` as a human-readable package/version table. Output redirection overwrites existing files of the same name. A failed export can leave a partial file. The bootstrap's local shell settings expire on return.

## NuGet CPython fallback

Without a bootstrap YAML, the script reads `requires-python` from `pyproject.toml` to choose a Windows CPython `python` package from NuGet. It does not install the project or read `[project].dependencies`. Standalone CPython still goes through the shared Micromamba and uv download checks and the same activation helper.

**Version parsing limitation.** The script header gives `requires-python = ">=3.10"` as its example. The implementation reads only the first two space- or `=`-delimited fields, so the `=` in `>=` separates `3.10` from the field it keeps. The example therefore fails to supply the intended version prefix. For a versioned build with the shipped script, specify the Python constraint in the bootstrap YAML, for example `python=3.10` under `dependencies`.

With a usable prefix, the script proceeds through these steps.

1. Read or download `Python\python.json` in the cache. Select the last matching textual version prefix encountered in NuGet's index, skipping entries containing `-`. A prefix such as `3.1` can also match `3.10`.
2. Reuse or download `Python\python.<version>.nupkg`. Extract its `tools` tree with `tar.exe`, then use `robocopy.exe` to move its contents to the installation root.
3. Create the `bin`, `Library\bin`, `Scripts`, and `condabin` directories. Write identical `conda.bat` and `mamba.bat` activation wrappers in `condabin`. They set `PYTHON_HOME`, `CONDA_PREFIX`, and `PATH` and print the Python version.
4. Use the extracted interpreter's `-m pip` to upgrade and force-reinstall `pip`, `pipx`, `setuptools`, `wheel`, and `uv`, then enter the shared activation and pip stages (subject to `/init`).

These wrappers ignore their arguments. If a main YAML is present, the later `mamba.bat env update` call runs the activation wrapper again and can report success without installing the YAML dependencies. Use pip requirement files for dependencies on this route. Only `Anaconda.pip.txt` is written at export, even though the final status message names both files.

## Cache and filesystem changes

To select a shared download cache, set `_CACHE` to an existing writable directory before running the bootstrap. Otherwise, the helper chooses a Downloads or cache directory on the script drive or under the user profile. It needs permission to create directories and profile junctions. The following paths are relative to the selected cache root.

| Cached artifact | Reuse behavior |
| --- | --- |
| `micromamba\micromamba.exe` | Reuse if present. Otherwise download the latest `micromamba-win-64` asset. |
| `uv\uv.exe`, `uv\uv-x86_64-pc-windows-msvc.zip` | Prefer the executable, then extract a cached ZIP, then download and extract a ZIP if both are missing. |
| `Python\python.json`, `Python\python.<version>.nupkg` | NuGet fallback only. Existing metadata and the selected package are reused without a refresh. |

The cache helper replaces `%LOCALAPPDATA%\pip\cache` and `%LOCALAPPDATA%\uv\cache` with junctions to the shared cache. If either path contains an ordinary directory, its contents are recursively deleted without migration.

During preactivation, the sibling MSVC checker can rename the `link.exe` already visible to CMD if it detects a collision and finds a matching local bootstrap file. This change, like the cache changes and downloads, persists after the bootstrap returns. See the [activation and cache guide](conda_far.md) and the [MSVC collision workflow](msbuild.md#resolve-an-msys-and-msvc-linker-collision).

## Exit status and recovery

| What you see | What to check or do |
| --- | --- |
| `0` with “Skipping bootstrapping” | The prefix already contains `python.exe`. It may be a complete installation, an `/init` base, or the result of a failed run. The skip verifies only file existence. |
| A full build fails after Python was created | Record the first failing command. Preserve the partial prefix by moving it aside before starting a fresh bootstrap. A plain rerun would take the existing-Python shortcut. |
| A cached tool fails its version check or extraction | Check the exact path printed in the log. Move the affected executable or archive aside to trigger a fresh download or extraction. A cached uv ZIP is reused if only `uv.exe` is missing. |
| The launcher finds an existing Python or Conda environment | Inspect `set CONDA_PREFIX`, `where.exe python.exe`, and `where.exe conda.bat` in the launching prompt. A Windows app execution alias for Python also counts. |
| MSVC verification fails before Conda activation | Read the first failed tool check. For a linker collision, compare the first results from `where.exe cl.exe` and `where.exe link.exe` in the affected session. See [MSVC verification](msbuild.md#what-verification-checks). |
| A dependency or export fails | Use the first nonzero command status and the file or tool named immediately above it. Earlier installations and any exports already written remain on disk. |

The bootstrap returns `0` for a successful full run, a successful `/init` run, or the existing-interpreter shortcut. Setup errors return a nonzero status, often the failing tool's exit code. For example, a calling batch file beside the copied bootstrap can pass the status back to its caller. Use `/q` here only when automatic removal of `%APPDATA%\mamba` is intended.

```bat
@echo off
call "%~dp0Anaconda.bat" /q /nocolor
exit /b %ERRORLEVEL%
```
