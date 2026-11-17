@echo off
rem Activate native x64 MSVC in the calling CMD session.
rem See README.md for discovery order, environment variables, and exit codes.

setlocal EnableExtensions DisableDelayedExpansion
if /i "%~1"=="--msbuild-probe" goto :probe

set "_MSBUILD_SELF=%~f0"
set "_MSBUILD_CANDIDATE="
if defined VCVARS (
    for %%I in ("%VCVARS%") do set "_MSBUILD_CANDIDATE=%%~fI"
)

call :toolchain_ready && goto :already_ready
if defined VSCMD_VER goto :incompatible_shell
if defined VSCMD_ARG_HOST_ARCH goto :incompatible_shell
if defined VSCMD_ARG_TGT_ARCH goto :incompatible_shell
if defined VCINSTALLDIR goto :incompatible_shell
if defined VCToolsInstallDir goto :incompatible_shell

if defined VCVARS (
    call :try_candidate && goto :activate
    call :log ERROR "VCVARS does not activate native x64 MSVC: %%VCVARS%%"
    exit /b 1
)

for %%H in (BUILDTOOLS MSBUILDTOOLS) do (
    call :search_hint %%H && goto :activate
)

set "_MSBUILD_NATIVE_PROGRAM_FILES=%ProgramW6432%"
if not defined _MSBUILD_NATIVE_PROGRAM_FILES set "_MSBUILD_NATIVE_PROGRAM_FILES=%ProgramFiles%"
set "_MSBUILD_X86_PROGRAM_FILES=%ProgramFiles(x86)%"

call :search_registered && goto :activate

for %%R in ("%_MSBUILD_NATIVE_PROGRAM_FILES%" "%_MSBUILD_X86_PROGRAM_FILES%" "%~dp0..") do (
    if not "%%~R"=="" (
        set "_MSBUILD_ROOT=%%~R\Microsoft Visual Studio"
        call :search_visual_studio_root && goto :activate
    )
)

call :search_path && goto :activate

rem Check junctions in the repository, beside it, and on the script's drive.
for %%R in ("%~dp0.." "%~dp0..\.." "%~d0\dev") do (
    for %%J in (MSBuildTools BuildTools) do (
        set "_MSBUILD_CANDIDATE=%%~R\%%J\VC\Auxiliary\Build\vcvarsall.bat"
        call :try_candidate && goto :activate
    )
)

call :log ERROR "No usable native x64 MSVC installation found. Set VCVARS to its vcvarsall.bat."
exit /b 1

:already_ready
for %%I in ("%VSINSTALLDIR%\.") do set "_MSBUILD_ACTIVE_ROOT=%%~fI"
for %%I in ("%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat") do set "_MSBUILD_ACTIVE_VCVARS=%%~fI"
if defined VCVARS if /i not "%_MSBUILD_CANDIDATE%"=="%_MSBUILD_ACTIVE_VCVARS%" (
    call :log ERROR "VCVARS selects a different installation from the active MSVC environment. Open a clean CMD session."
    exit /b 1
)
call :log OK "Native x64 MSVC is already active at %%_MSBUILD_ACTIVE_ROOT%%."
exit /b 0

:incompatible_shell
call :log ERROR "The current MSVC environment is incomplete or uses a different architecture. Open a clean CMD session."
exit /b 1

:search_hint
if not defined %~1 exit /b 1
setlocal EnableDelayedExpansion
set "_MSBUILD_HINT=!%~1!"
endlocal & set "_MSBUILD_CANDIDATE=%_MSBUILD_HINT%\VC\Auxiliary\Build\vcvarsall.bat"
call :try_candidate && exit /b 0
call :log WARN "Skipping unusable %~1 location: %%_MSBUILD_CANDIDATE%%"
exit /b 1

:search_registered
set "_MSBUILD_INSTALLER_ROOT=%_MSBUILD_X86_PROGRAM_FILES%"
if not defined _MSBUILD_INSTALLER_ROOT set "_MSBUILD_INSTALLER_ROOT=%_MSBUILD_NATIVE_PROGRAM_FILES%"
if not defined _MSBUILD_INSTALLER_ROOT exit /b 1
set "_MSBUILD_VSWHERE=%_MSBUILD_INSTALLER_ROOT%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%_MSBUILD_VSWHERE%" exit /b 1
for /f "usebackq delims=" %%I in (`call "%_MSBUILD_VSWHERE%" -nologo -sort -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set "_MSBUILD_CANDIDATE=%%I\VC\Auxiliary\Build\vcvarsall.bat"
    call :try_candidate && exit /b 0
)
exit /b 1

:search_visual_studio_root
if not exist "%_MSBUILD_ROOT%\." exit /b 1
for /f "delims=" %%V in ('dir /b /ad /o:-n "%_MSBUILD_ROOT%" 2^>nul') do (
    for /d %%I in ("%_MSBUILD_ROOT%\%%V\*") do (
        set "_MSBUILD_CANDIDATE=%%I\VC\Auxiliary\Build\vcvarsall.bat"
        call :try_candidate && exit /b 0
    )
)
exit /b 1

:search_path
set "_MSBUILD_PATH=%PATH:"=%"
for %%D in ("%_MSBUILD_PATH:;=" "%") do (
    set "_MSBUILD_ROOT=%%~D"
    call :search_path_root && exit /b 0
)
exit /b 1

:search_path_root
if not "%_MSBUILD_ROOT:~1,2%"==":\" if not "%_MSBUILD_ROOT:~1,2%"==":/" if not "%_MSBUILD_ROOT:~0,2%"=="\\" exit /b 1
for %%I in (
    "%_MSBUILD_ROOT%\vcvarsall.bat"
    "%_MSBUILD_ROOT%\VC\Auxiliary\Build\vcvarsall.bat"
    "%_MSBUILD_ROOT%\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
) do (
    set "_MSBUILD_CANDIDATE=%%~I"
    call :try_candidate && exit /b 0
)
exit /b 1

:try_candidate
if not exist "%_MSBUILD_CANDIDATE%" exit /b 1
if exist "%_MSBUILD_CANDIDATE%\." exit /b 1
for %%I in ("%_MSBUILD_CANDIDATE%") do set "_MSBUILD_CANDIDATE=%%~fI"
rem Changes from a failed vendor script stay in the child CMD session.
"%ComSpec%" /d /e:on /v:off /s /c ""%%_MSBUILD_SELF%%" --msbuild-probe" >nul 2>&1 && exit /b 0
call :log WARN "Skipping an installation that failed native x64 activation: %%_MSBUILD_CANDIDATE%%"
exit /b 1

:probe
set "VSINSTALLDIR="
set "VSCMD_SKIP_SENDTELEMETRY=1"
call "%%_MSBUILD_CANDIDATE%%" amd64 || exit /b 1
call :toolchain_ready && exit /b 0
exit /b 1

:activate
rem Use an unused variable so CALL can expand the path on its second parse.
set "_MSBUILD_HANDOFF=_CONDA_BOOTSTRAP_VCVARS"
:choose_handoff
if defined %_MSBUILD_HANDOFF% (
    set "_MSBUILD_HANDOFF=_%_MSBUILD_HANDOFF%"
    goto :choose_handoff
)
for %%I in ("%_MSBUILD_CANDIDATE%") do (
    endlocal
    set "%_MSBUILD_HANDOFF%=%%~I"
    call :activate_in_caller %_MSBUILD_HANDOFF%
    if errorlevel 1 (
        set "%_MSBUILD_HANDOFF%="
        exit /b 1
    )
    set "%_MSBUILD_HANDOFF%="
)
exit /b 0

:activate_in_caller
if defined VSCMD_SKIP_SENDTELEMETRY goto :run_activation
set "VSCMD_SKIP_SENDTELEMETRY=1"
call :run_activation %~1 && (
    set "VSCMD_SKIP_SENDTELEMETRY="
    exit /b 0
)
set "VSCMD_SKIP_SENDTELEMETRY="
exit /b 1

:run_activation
call :log INFO "Activating native x64 MSVC with %%%~1%%"
rem Discovery runs here only in a shell without an active MSVC environment.
set "VSINSTALLDIR="
call "%%%~1%%" amd64 || (
    call :log ERROR "vcvarsall.bat returned a failure: %%%~1%%"
    exit /b 1
)
call :toolchain_ready || (
    call :log ERROR "The native x64 toolchain did not pass validation after running %%%~1%%"
    exit /b 1
)
call :log OK "Native x64 MSVC is active."
exit /b 0

:toolchain_ready
setlocal EnableExtensions EnableDelayedExpansion
if not defined VSINSTALLDIR exit /b 1
if not defined VCToolsInstallDir exit /b 1
if /i not "%VSCMD_ARG_HOST_ARCH%"=="x64" if /i not "%VSCMD_ARG_HOST_ARCH%"=="amd64" exit /b 1
if /i not "%VSCMD_ARG_TGT_ARCH%"=="x64" if /i not "%VSCMD_ARG_TGT_ARCH%"=="amd64" exit /b 1
for %%I in ("%VCToolsInstallDir%\bin\Hostx64\x64") do set "_MSBUILD_BIN=%%~fI"
for %%T in (cl.exe link.exe) do (
    set "_MSBUILD_RESOLVED=%%~$PATH:T"
    if not defined NoDefaultCurrentDirectoryInExePath if exist "%%T" set "_MSBUILD_RESOLVED=%%~fT"
    if not defined _MSBUILD_RESOLVED exit /b 1
    for %%I in ("!_MSBUILD_RESOLVED!") do (
        if /i not "%%~fI"=="!_MSBUILD_BIN!\%%T" exit /b 1
    )
)
exit /b 0

:log
setlocal EnableExtensions DisableDelayedExpansion
set "_MSBUILD_MESSAGE=%~2"
set "_MSBUILD_PREFIX=[%~1]"
if not defined NOCOLOR if not defined NO_COLOR (
    if /i "%~1"=="INFO" set "_MSBUILD_PREFIX=[100;92m [INFO] [0m"
    if /i "%~1"=="OK" set "_MSBUILD_PREFIX=[103;94m [-OK-] [0m"
    if /i "%~1"=="WARN" set "_MSBUILD_PREFIX=[106;35m [WARN] [0m"
    if /i "%~1"=="ERROR" set "_MSBUILD_PREFIX=[105;34m [ERROR] [0m"
)
setlocal EnableDelayedExpansion
if /i "%~1"=="ERROR" (
    >&2 echo !_MSBUILD_PREFIX! MSBuild: !_MSBUILD_MESSAGE!
) else (
    echo !_MSBUILD_PREFIX! MSBuild: !_MSBUILD_MESSAGE!
)
exit /b 0
