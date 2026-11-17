# Windows toolkit

## Activate native x64 MSVC

From a Windows Command Prompt or another batch file, run:

```bat
call windows\msbuild.bat
```

The script uses the installed Microsoft C++ Build Tools and supports CMD with delayed expansion on or off. Installation paths must be free of literal `!` characters. On success the compiler, linker, and SDK environment are available in the calling CMD session. Exit code `0` indicates a validated native x64 toolchain. Exit code `1` indicates failed activation, failed validation, or no usable installation. Open a clean CMD session if an incompatible or incomplete Visual Studio environment is already active.

A usable native x64 environment is reused. In a clean session, discovery checks the following locations in order:

1. `VCVARS`, an explicit path to `vcvarsall.bat`. An unusable override returns an error.
2. `BUILDTOOLS` and `MSBUILDTOOLS`, optional Visual Studio installation directories.
3. Visual Studio instances registered with the installer and reported by `vswhere.exe`, newest first, with the x86/x64 C++ component installed.
4. `Microsoft Visual Studio` under the native and x86 Program Files directories and at the repository root.
5. Absolute PATH entries containing `vcvarsall.bat`, the Visual Studio installation root, or the parent of a `BuildTools` directory.
6. `MSBuildTools` and `BuildTools` directories or junctions at the repository root, beside the repository, and under `\dev` on the script's drive.

Set path variables using CMD syntax such as `set "VCVARS=C:\path\to\vcvarsall.bat"`. Set `NOCOLOR` or `NO_COLOR` for plain diagnostics. The script probes candidates in child CMD sessions before activating one in the caller. After activation, it verifies the host and target architectures and the resolved compiler and linker paths.
