# MSVC activation on Windows

[msbuild.bat](msbuild.bat) prepares the current Windows Command Prompt for C and C++ builds targeting x64. It reuses a shell that passes its toolchain checks. Otherwise, it searches for a Visual Studio installation and calls Microsoft's `vcvars64.bat`.

## Run the script

Use Windows CMD with command extensions enabled. The script uses `where.exe` and `findstr.exe`. Caller delayed expansion is optional. The Visual Studio C++ tools must be installed. Leave `ERRORLEVEL` unset as an ordinary environment variable so CMD's `%ERRORLEVEL%` expansion reports the preceding command's status.

From the repository root, run the following in the CMD session where you want to build.

```bat
call windows\msbuild.bat
```

From another batch file beside `msbuild.bat`, use the script directory and check the result before continuing.

```bat
call "%~dp0msbuild.bat"
if errorlevel 1 exit /b 1
```

| Return code | Meaning |
| --- | --- |
| `0` | The existing environment passed verification, or `vcvars64.bat` ran and the resulting environment passed verification. |
| `1` | Discovery found no candidate, the activation script failed, or verification failed. |

## Configure discovery

Set overrides in the calling CMD session. For example, to use a custom Build Tools installation, set `BUILDTOOLS` to its root and call the script.

```bat
set "BUILDTOOLS=C:\BuildTools"
call windows\msbuild.bat
```

| Variable | Value |
| --- | --- |
| `VCVARS` | Path to an existing `vcvarsall.bat` or `vcvars64.bat`. The script selects `vcvars64.bat` in that file's directory. |
| `BUILDTOOLS` | Visual Studio or Build Tools installation root containing both `VC\Auxiliary\Build\vcvarsall.bat` and `VC\Auxiliary\Build\vcvars64.bat`. |
| `MSBUILDTOOLS` | Another installation root with the same required layout, checked after `BUILDTOOLS`. |
| `NOCOLOR` | Set to any nonempty value, such as `1`, for plain text diagnostics. |

The script checks the current shell before consulting overrides. If the installation directory, target architecture, and compiler checks pass but the linker check fails, it returns `1` immediately. If any of the initial checks fail, discovery follows the order below.

1. `VCVARS`, `BUILDTOOLS`, then `MSBUILDTOOLS`. An unusable override is skipped.
2. `Microsoft Visual Studio\<version>\<edition>` at the repository root.
3. Directories or junctions named `MSBuildTools` or `BuildTools` at the repository root, then under `\dev` on the drive containing the script.
4. `where.exe vcvarsall.bat`, which searches the working directory and `PATH`. Each match needs a sibling `vcvars64.bat`.
5. `vswhere.exe` under `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer`. The query requests the latest registered instance with `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, including standalone Build Tools.
6. `Microsoft Visual Studio\<version>\<edition>` under `%ProgramFiles%`, then under `%ProgramFiles(x86)%`. The repository-local and standard scans sort the version directory names in descending order and select the first edition with both activation files.

The separate scan for installation roots or their parents on `PATH` currently has no entries to inspect because the script clears its `_PATH` scratch variable before the loop. Set `BUILDTOOLS` or `MSBUILDTOOLS` for those installations. Once discovery selects a candidate, an activation or verification failure ends the invocation.

## What verification checks

- `VSINSTALLDIR` points to an installation containing both activation scripts under `VC\Auxiliary\Build`, `VSCMD_ARG_TGT_ARCH` is `x64`, and `where.exe` can find `cl.exe`.
- The `link.exe /?` output contains `Microsoft (R) Incremental Linker` or `/INCREMENTAL`. The first `link.exe` and `cl.exe` paths reported by `where.exe` must also have the same parent directory.

The architecture check uses the target architecture. Compiler verification is based on command lookup and the directory comparison.

## Troubleshoot activation

- **Activation script missing.** Check that the Visual Studio C++ tools are installed. For a custom installation, set `VCVARS` to the full path to its `vcvars64.bat` or set `BUILDTOOLS` to the installation root.
- **Linker collision.** Run `where.exe link.exe` and `where.exe cl.exe` in the same CMD session. If Git, MSYS, or another toolchain supplies the first linker, start a clean CMD session or adjust the directory or `PATH` order so that CMD finds the Microsoft linker from the same directory as the compiler.
- **Activation command or post-activation verification failed.** Check the printed `vcvars64.bat` path and the preceding vendor output. Retry from a clean CMD session after correcting the reported issue. The failed attempt may have changed the current environment.

## Effects on the calling shell

`vcvars64.bat` applies the MSVC and Windows SDK settings in the calling shell. The wrapper sets `VSCMD_SKIP_SENDTELEMETRY=1` before invoking it and leaves that value in the caller. On exit it clears `INFO`, `OKOK`, `WARN`, `ERROR`, `EXIT_STATUS`, and its other scratch variables, including any preexisting values under those names.

[conda_far.bat](conda_far.bat) calls the script during environment setup when it is present. It stops on activation failure and sets `DISTUTILS_USE_SDK=1` after successful activation.
