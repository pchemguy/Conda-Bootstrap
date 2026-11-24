# Check the Windows build environment

[msbuild.bat](msbuild.bat) makes an installed Visual Studio C++ toolchain available in the current CMD session and checks the tools needed for native builds. It can verify an existing x86 or x64 developer prompt. When it sets up a fresh shell, it calls Microsoft's `vcvars64.bat` for an x64 target. If the compiler is missing, install the [Visual Studio C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) separately and rerun the check.

## Use the checker

**For a project Conda environment**, run [conda_far.bat](conda_far.md) as usual. It calls the sibling checker before activating the target prefix. A successful check also tells setuptools to reuse the prepared toolchain through `DISTUTILS_USE_SDK=1`.

**For a standalone build**, start CMD with `cmd.exe /E:ON /V:ON` and run the following from the directory containing your copy of the harness. Command extensions and delayed expansion must be enabled when the checker starts.

```bat
call msbuild.bat
echo %ERRORLEVEL%
```

A build script beside the checker can then build a project from a working directory containing its NMake makefile.

```bat
@echo off
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0msbuild.bat"
if not "%ERRORLEVEL%"=="0" exit /b %ERRORLEVEL%
nmake.exe
```

**Exit status.** The final verification returns `0` when all required checks pass and `1` otherwise. It runs even if discovery found no activation script or the selected `vcvars64.bat` reported an error. Use the final status to decide whether to build. Read the earlier messages to see which installation was found and what activation did.

## How the toolchain is selected

If `VSINSTALLDIR` is defined, the checker goes straight to verification. To select a different installation, start a fresh CMD with delayed expansion enabled and set `VCVARS` to the full path of its activation script. Otherwise discovery proceeds in the following order.

| Order | Where the checker looks |
| --- | --- |
| 1 | Use `VCVARS` if defined. An existing `vcvarsall.bat` selects the sibling `vcvars64.bat`. If `VCVARS` is unset, use the first `where.exe vcvars64.bat` match. An unusable explicit value falls through to step 2. |
| 2 | Look under `%ProgramFiles%\Microsoft Visual Studio`, then `%ProgramFiles(x86)%\Microsoft Visual Studio`, then `..\Microsoft Visual Studio` relative to the checker directory. Under each root, visit version directories in descending name order and take the first edition containing `VC\Auxiliary\Build\vcvars64.bat`. |
| 3 | Look for `MSBuildTools`, then `BuildTools`, one directory above the checker. Repeat under `\dev` on the checker's drive. |
| 4 | Check the installation roots named by `MSBUILDTOOLS`, `BUILDTOOLS`, then `MSBUILD`. Each must contain `VC\Auxiliary\Build\vcvars64.bat`. |

The checker calls the first candidate once, with `VSCMD_SKIP_SENDTELEMETRY=1`, then verifies the resulting shell. The vendor script's environment changes, the telemetry setting, and the checker's top-level variables remain in the caller's scope. Set `NO_COLOR=1` or `NOCOLOR=1` for plain diagnostics.

## What verification checks

| Check | Passing condition |
| --- | --- |
| Visual Studio environment | `VisualStudioVersion` is defined, `VCINSTALLDIR` exists, and `VSCMD_ARG_TGT_ARCH` is `x86` or `x64`. |
| Commands | `where.exe` finds `nmake.exe`, `cl.exe`, `link.exe`, `lib.exe`, `dumpbin.exe`, and `curl.exe`. The checker reports the first path for each. A missing `tclsh.exe` gives a warning. |
| Windows tar | `%windir%\System32\tar.exe` exists. |
| Microsoft linker | `link.exe /?` output contains `Microsoft (R) Incremental Linker` or `/INCREMENTAL` (case-insensitive). See the collision workflow below. |
| ICU for SQLite builds | When `USE_ICU=1`, the active prefix's versioned ICU common DLLs match the MSVC target. |

## Resolve an MSYS and MSVC linker collision

MSYS provides a file-link utility named `link.exe`. If CMD finds it before the Microsoft linker, native builds invoke the wrong program. The checker handles the executable that CMD resolves at the time of verification. When called by `conda_far.bat`, this is **before** the launcher adds the target Conda environment to `PATH`. To check the resulting environment for a build, call `msbuild.bat` directly in the activated shell.

1. Run the resolved linker's help check. If it identifies Microsoft, a different directory for `cl.exe` and `link.exe` produces a warning and the linker check passes.
2. If identification fails, derive a companion batch path from the resolved executable. For example, `D:\Dev\MyProject\Anaconda\Library\usr\bin\link.exe` maps to `D:\Dev\MyProject\Anaconda.bat`. If that file exists, attempt to rename the resolved executable to `link_.exe`. A missing companion or an existing backup leaves the conflict unresolved and verification fails.
3. After a successful rename, resolve both commands again. The new linker's help must identify Microsoft and its directory must match that of `cl.exe`. The rename persists even if verification fails afterward.

If recovery is unavailable or fails, inspect the lookup order in the same CMD session. Correct the directory taking precedence and rerun the checker.

```bat
where.exe cl.exe
where.exe link.exe
link.exe /?
```

## Check Conda ICU before building SQLite

For an ICU-enabled SQLite build, activate the intended Conda prefix first. Leave `USE_ICU` unset during `conda_far.bat` activation, since the launcher calls the checker before it sets `CONDA_PREFIX`. Then run the checker again in that activated CMD session with delayed expansion enabled.

```bat
set "USE_ICU=1"
call "D:\Dev\MyProject\msbuild.bat"
echo %ERRORLEVEL%
```

The checker inspects `%CONDA_PREFIX%\Library\bin` for names such as `icuuc76.dll`. At least one `icuuc<digits>.dll` must exist. For every match, `dumpbin.exe /nologo /headers` must report PE machine `14C` for x86 or `8664` for x64. A missing active prefix, missing DLL, unreadable machine field, or architecture mismatch fails verification. Use `set "USE_ICU="` to turn off this check for later calls in the same shell.
