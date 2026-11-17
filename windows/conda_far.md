# Windows development environment activation

[conda_far.bat](conda_far.bat) prepares an existing Windows Python or Conda installation for development. It configures tool caches, loads MSVC when `msbuild.bat` is available, activates Python, and runs any local configuration scripts. It can initialize caches before bootstrap, launch an interactive session, prepare the caller's shell, or run a single command.

Activation changes the filesystem as well as the shell environment. See [Cache configuration](#cache-configuration) and [MSVC and the linker](#msvc-and-the-linker) for the paths it can replace.

## Prerequisites

- Use Windows CMD with command extensions enabled. Any argument, including `/nocolor`, requires delayed expansion in the caller. Start a CMD session with `cmd.exe /E:ON /V:ON`, or use `setlocal EnableExtensions EnableDelayedExpansion` in a calling batch file.
- Start from a clean shell. The script rejects a defined `CONDA_PREFIX` and any `python.exe` or `conda.bat` that `where.exe` finds in the working directory or on `PATH`.
- Activation modes require an installation containing `python.exe`, `condabin\conda.bat`, and `condabin\mamba.bat`. The default installation is `Anaconda` beside the script. `/cache` can run before the installation exists.
- The script needs write access to the selected cache root and permission to create directory junctions under `%LOCALAPPDATA%`.

## Workflows

The examples use CMD from the repository root.

### Initialize caches before installing Python

In a clean CMD session with delayed expansion enabled, run:

```bat
call windows\conda_far.bat /cache
```

A successful call returns `0` and leaves the selected cache root in `_CACHE` for the caller. This mode still checks for an existing Conda prefix or visible Python or Conda commands, then creates cache directories and replaces the profile cache junctions. It returns before validating the installation or running the linker rename, MSVC setup, Conda activation, configuration scripts, or a command or child shell. Any `CONDA_BAT` and `MAMBA_BAT` paths exposed by this mode are provisional.

### Open an interactive development session

```bat
call windows\conda_far.bat
```

After setup, the script looks for `far.bat` first and `far.exe` second. It includes the activated prefix in the FAR launch command. If neither launcher is found, it opens an interactive CMD and changes to `CONDA_PREFIX`. In this no-argument workflow, the script enables delayed expansion locally if needed. When it does, the child inherits the activated environment and the local environment scope ends when the script returns.

### Activate the caller for a build

From a batch file run from the repository root:

```bat
@echo off
setlocal EnableExtensions EnableDelayedExpansion
call windows\conda_far.bat /batch
if not "%ERRORLEVEL%"=="0" exit /b 1
python.exe --version
```

Run subsequent build commands in that same shell. When the caller uses `setlocal`, the activation is available within its local scope.

### Prepare an installation during bootstrap

[Anaconda.bat](Anaconda.bat) calls `conda_far.bat` at two points in the bootstrap workflow.

1. `/cache` prepares the cache root before the Micromamba and uv downloads. The bootstrap script uses the returned `_CACHE` for these downloads.
2. After creating the installation, the bootstrap script sets `_CONDA_PREFIX` to the new prefix and calls `/preactivate`. This performs the same activation as `/batch`, returns to the bootstrap script, and retains `_CACHE`, `CONDA_BAT`, and `MAMBA_BAT` for later steps.

### Run one command and return

From a clean CMD session with delayed expansion enabled:

```bat
call windows\conda_far.bat /cli "python.exe --version"
```

The script activates the environment, runs the configuration files, and executes the supplied command using CMD `call`. It returns the command's status. The parser accepts `/cli "command"` and `/cli="command"`. For a command with nested quoting or shell metacharacters, put it in a batch file and pass a command that invokes that file.

### Use a custom installation or cache

From a clean CMD session with delayed expansion enabled:

```bat
set "_CONDA_PREFIX=D:\Dev\Conda"
set "_CACHE=D:\Dev\Cache"
call windows\conda_far.bat /batch /nocolor
```

The cache override must already exist to be selected. See the cache selection order below.

## Configuration

| Input | Effect |
| --- | --- |
| `_CONDA_PREFIX` | Selects the installation containing `python.exe` and the two activation wrappers. The default is `Anaconda` beside the script. |
| `_CACHE` | Uses an existing path as the cache root. Standalone `/cache` and `/preactivate` retain the resolved root for the caller. Ordinary `/batch` cleanup clears it. |
| `CONDA_PKGS_DIRS` | Uses a caller-supplied package cache path or defaults to `<cache root>\Python\pkgs`. The directory creation step treats a supplied value as one path. |
| `/nocolor`, `NOCOLOR`, `NO_COLOR` | Select plain text diagnostics. The option and `NO_COLOR` set `NOCOLOR=1`. |
| `JAVA_HOME` | Retains an existing value. Otherwise, the script sets it if it finds the bundled JVM under `Library\lib\jvm` or `Library\jre`. |
| `config_*.bat` | Calls each matching batch file beside `conda_far.bat` after activation and before the selected workflow continues. A nonzero result stops setup. |

Option names are case-insensitive. The parser accepts `/`, `-`, or `--` prefixes and warns before skipping unrecognized tokens. Without a recognized mode option, it follows the interactive workflow. After parsing, `/cache` takes precedence over other mode options and returns after cache setup. In the activation flow, `/cli` runs before the return checks for `/batch` and `/preactivate`.

## Setup order and results

1. Parse options, select the prefix, and check delayed expansion.
2. Check for an active or visible Python or Conda environment. For activation modes, verify the three required installation files.
3. Configure cache directories and junctions. `/cache` returns at this point. Activation modes continue with the linker handling described below.
4. Call the sibling `msbuild.bat` when present. A missing file produces a warning and skips MSVC setup. A nonzero result aborts activation. Success sets `DISTUTILS_USE_SDK=1` for builds that reuse the configured toolchain.
5. Call the selected `condabin\conda.bat` with `activate`. Use `PYTHON_HOME` as a fallback if the wrapper leaves `CONDA_PREFIX` unset. Check for `python.exe` under the resulting prefix and obtain `PYTHON_VERSION` from `python.exe --version`.
6. Check for the bundled JVM, run local configuration scripts, and continue in the selected mode.

Successful `/batch` and `/preactivate` leave the activated environment and wrapper paths available to the caller. `/cache` and `/preactivate` also return the cache root as `_CACHE`. Cleanup clears parsed arguments and the diagnostic prefix variables `INFO`, `OKOK`, `WARN`, and `ERROR`. At entry, the script clears any ordinary environment variable named `ERRORLEVEL` so CMD's status expansion can be used.

## Filesystem changes

### Cache configuration

The cache root is selected in the following order.

1. Use `_CACHE` when it already exists.
2. Otherwise, choose `\Downloads` on the script's drive if it exists, or `%USERPROFILE%\Downloads`.
3. Within that default selection, prefer an existing `CACHE` child of Downloads, then an existing `\CACHE` on the script's drive, then the Downloads directory itself.

The script checks whether it can create and remove a probe directory named `$$$_DELETEME_ACCESS_CHECK_$$$` under the selected root. It recursively removes a directory that already exists at that path before probing. If `\Temp` exists on the script's drive, the script sets `TEMP` and `TMP` to it.

| Variable | Path |
| --- | --- |
| `CONDA_PKGS_DIRS` | `<cache root>\Python\pkgs` by default |
| `PIP_CACHE_DIR` | `<cache root>\Python\pip\cache` |
| `UV_CACHE_DIR` | `<cache root>\Python\uv\cache` |
| `GIT_CACHE` | First existing `H:\GitHub` or `\GitHub` on the script's drive. Otherwise, `<cache root>\GitHub`. |
| `NPM_CONFIG_CACHE` | `<cache root>\npm` |
| `PNPM_HOME` | `<cache root>\pnpm` |
| `XDG_CACHE_HOME` | `<cache root>\pnpm-cache` |
| `ELECTRON_CACHE` | `<cache root>\electron` |
| `ELECTRON_BUILDER_CACHE` | `<cache root>\electron-builder` |
| `PLAYWRIGHT_BROWSERS_PATH` | `<cache root>\playwright` |

Both `/cache` and full activation configure the same cache paths. They create junctions at `%LOCALAPPDATA%\pip\cache` and `%LOCALAPPDATA%\uv\cache` pointing to the selected pip and uv caches. Before creating each junction, the script removes an existing entry at that cache path with `rmdir /S /Q`. An ordinary cache directory and its contents are deleted without migration.

### MSVC and the linker

If the selected prefix contains `Library\usr\bin\link.exe`, the script renames it to `link_.exe` before calling `msbuild.bat`. If `link_.exe` already exists, the script deletes it before attempting the rename. Cache and linker changes can remain on disk if a later activation step fails.

## Exit status and troubleshooting

| Outcome | Exit status |
| --- | --- |
| Successful `/cache`, `/batch`, or `/preactivate` | `0` |
| `/cli`, FAR, or interactive CMD completes | The command or child shell's status |
| Setup fails | A nonzero status, either `1` or the status of the failing step |

- **Delayed expansion disabled.** Enable it in the caller before passing options.
- **Python or Conda already visible.** Run `where.exe python.exe` and `where.exe conda.bat` in the launching shell. Check for an active `CONDA_PREFIX` and for executables or Windows app aliases found by the lookup.
- **Cache or junction setup fails.** Check the printed paths, write permissions, and any process holding the existing cache directory open.
- **MSVC or linker check fails.** Follow the verification and collision diagnostics in [msbuild.md](msbuild.md).
