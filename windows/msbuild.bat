@echo off

:: ============================================================================
::  Purpose:
::    Detects and activates 64-bit Microsoft Build Tools (MSVC) environment.
::    This script is idempotent and can be safely re-run.
::
::  Behavior:
::    - If 64-bit MS Build Tools are already active (VSINSTALLDIR, x64 arch,
::      and cl.exe/link.exe on PATH), exits successfully.
::    - Otherwise, checks explicit env vars, custom paths, PATH, vswhere, and
::      standard installation directories for a valid vcvars64.bat.
::    - Activates 64-bit environment via vcvars64.bat when found.
::
::  Preconditions:
::    - NOCOLOR: If set, gracefully falls back to no color.
::    - Does NOT require DelayedExpansion in the caller's environment.
::
::  Exit codes:
::    0 = success
::    1 = activation failed or not found
:: ============================================================================

call :COLOR_SCHEME

echo:
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%                    MS Build Tools Check                    %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo == %WARN% CLI: "%~f0" %*
echo ====================================================================================
echo ====================================================================================
echo:

set "EXIT_STATUS=1"
set "_VCVARS64="

:: --- 1. Check if already activated (x64 + cl.exe + link.exe) ---

echo %INFO% MSBuild: Checking if 64-bit environment is already activated...
call :VERIFY_X64_ACTIVE
if errorlevel 1 goto :MSBUILD_SEARCH
echo %INFO% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR:"=%".
echo %OKOK% MSBuild: 64-bit environment already active. Skipping activation.
set "EXIT_STATUS=0"
goto :MSBUILD_ACTIVATED

:MSBUILD_SEARCH

:: --- 2. Check explicit environment variables (VCVARS, BUILDTOOLS, MSBUILDTOOLS) ---

echo %INFO% MSBuild: Checking if VCVARS points to vcvarsall.bat or vcvars64.bat.
if defined VCVARS call :CHECK_VCVARS
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

echo %INFO% MSBuild: Checking if BUILDTOOLS or MSBUILDTOOLS point to the "BuildTools" directory.
if defined BUILDTOOLS call :CHECK_BUILDTOOLS
if defined _VCVARS64 goto :MSBUILD_ACTIVATION
if defined MSBUILDTOOLS call :CHECK_MSBUILDTOOLS
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

:: --- 3. Check custom locations and junctions in dev ---

set "_MSVS=%~dp0..\Microsoft Visual Studio"
echo %INFO% MSBuild: Checking for custom locations of VS editions in "%_MSVS%\{VERSION}\{KIND}".
call :SCAN_VS_ROOT "%_MSVS%"
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

echo %INFO% MSBuild: Checking custom fallback locations for BuildTools.
for %%D in (
    "%~dp0..\MSBuildTools"
    "%~dp0..\BuildTools"
    "%~d0\dev\MSBuildTools"
    "%~d0\dev\BuildTools"
) do if not defined _VCVARS64 call :TRY_ROOT "%%~fD"
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

:: --- 4. Check PATH for vcvarsall.bat or BuildTools ---

echo %INFO% MSBuild: Checking if vcvarsall.bat is on the PATH.
for /f "usebackq tokens=* delims=" %%A in (`where.exe $PATH:vcvarsall.bat 2^>nul`) do if not defined _VCVARS64 call :TRY_FILE "%%~fA"
if defined _VCVARS64 echo %INFO% MSBuild: Found vcvars64.bat via PATH: "%_VCVARS64%". Attempting activation...
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

echo %INFO% MSBuild: Checking if "BuildTools" or its parent are on the PATH.
set "_PATH="
if defined Path set "_PATH=%Path:"=%"
if defined _PATH set "_PATH="%_PATH:;=";"%""
for %%A in (%_PATH%) do if not "%%~A"=="" (
    if not defined _VCVARS64 call :TRY_ROOT "%%~A"
    if not defined _VCVARS64 call :TRY_ROOT "%%~A\BuildTools"
)
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

:: --- 5. Query vswhere.exe if available ---

set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%_VSWHERE%" (
    echo %INFO% MSBuild: Querying vswhere.exe for latest Visual Studio with C++ tools.
    for /f "usebackq delims=" %%I in (`call "%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do if not defined _VCVARS64 call :TRY_ROOT "%%~fI"
)
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

:: --- 6. Check default locations of VS editions (64-bit and 32-bit Program Files) ---

for %%P in ("%ProgramFiles%\Microsoft Visual Studio" "%ProgramFiles(x86)%\Microsoft Visual Studio") do if not defined _VCVARS64 (
    echo %INFO% MSBuild: Checking for default locations of VS editions in "%%~P\{VERSION}\{KIND}".
    call :SCAN_VS_ROOT "%%~P"
)
if defined _VCVARS64 goto :MSBUILD_ACTIVATION

:: --- MSBuildTools not found ---

set "EXIT_STATUS=1"
echo %ERROR% MSBuild: MS Build Tools 64-bit activation script (vcvars64.bat) not found.
echo %ERROR% MSBuild: If MS Build Tools are installed, either
echo %ERROR% MSBuild:   - start this script from a preactivated x64 MS Build Tools shell
echo %ERROR% MSBuild:   - see script notes above regarding checked locations and variables
echo %ERROR% MSBuild: See this accepted SO answer https://stackoverflow.com/a/64262038/17472988
echo %ERROR% MSBuild: regarding MS Build Tools installation.
echo:
goto :MSBUILD_ACTIVATED

:MSBUILD_ACTIVATION

:: --- MSBuildTools found ---

if not exist "%_VCVARS64%" (
    echo %ERROR% MSBuild: 64-bit activation script not found at "%_VCVARS64%".
    set "EXIT_STATUS=1"
    goto :MSBUILD_ACTIVATED
)

set "VSCMD_SKIP_SENDTELEMETRY=1"
set "ERRORLEVEL="
echo:
echo %WARN% MSBuild: Activating MS Build Tools.
echo %INFO% MSBuild: Calling "%_VCVARS64%"
echo:
call "%_VCVARS64%"
if errorlevel 1 (
    echo:
    echo %ERROR% MSBuild: vcvars64.bat returned an error.
    set "EXIT_STATUS=1"
    goto :MSBUILD_ACTIVATED
)
echo:

call :VERIFY_X64_ACTIVE
if errorlevel 1 (
    set "EXIT_STATUS=1"
    echo %ERROR% MSBuild: MS Build Tools activation failed verification: x64 cl.exe/link.exe not active.
    echo %ERROR% MSBuild: Used script "%_VCVARS64%".
    goto :MSBUILD_ACTIVATED
)

set "EXIT_STATUS=0"
echo %OKOK% MSBuild: MS Build Tools activation succeeded.
echo %OKOK% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR:"=%".

:MSBUILD_ACTIVATED

set "INFO="
set "OKOK="
set "WARN="
set "ERROR="
set "_MSVS="
set "_VCVARS64="
set "_PATH="
set "_VSWHERE="
set "_TMP_VAL="
set "_TMP_VSDIR="
set "EXIT_STATUS=" & exit /b %EXIT_STATUS%


:: ============================================================================ SUBROUTINES BEGIN
:CHECK_VCVARS
set "_TMP_VAL=%VCVARS:"=%"
call :TRY_FILE "%_TMP_VAL%"
set "_TMP_VAL="
if defined _VCVARS64 echo %INFO% MSBuild: VCVARS points to "%VCVARS:"=%". Attempting activation...
exit /b 0

:CHECK_BUILDTOOLS
set "_TMP_VAL=%BUILDTOOLS:"=%"
call :TRY_ROOT "%_TMP_VAL%"
set "_TMP_VAL="
exit /b 0

:CHECK_MSBUILDTOOLS
set "_TMP_VAL=%MSBUILDTOOLS:"=%"
call :TRY_ROOT "%_TMP_VAL%"
set "_TMP_VAL="
exit /b 0

:TRY_FILE
if "%~1"=="" exit /b 1
if not exist "%~1" exit /b 1
if not exist "%~dp1vcvars64.bat" exit /b 1
set "_VCVARS64=%~dp1vcvars64.bat"
exit /b 0

:TRY_ROOT
if "%~1"=="" exit /b 1
if not exist "%~1\VC\Auxiliary\Build\vcvarsall.bat" exit /b 1
if not exist "%~1\VC\Auxiliary\Build\vcvars64.bat" exit /b 1
set "_VCVARS64=%~1\VC\Auxiliary\Build\vcvars64.bat"
exit /b 0

:SCAN_VS_ROOT
if "%~1"=="" exit /b 1
if not exist "%~1" exit /b 1
for /f "usebackq delims=" %%Y in (`dir /b /ad /O:-N "%~1" 2^>nul`) do for /d %%E in ("%~1\%%Y\*") do if not defined _VCVARS64 call :TRY_ROOT "%%~fE"
if defined _VCVARS64 exit /b 0
exit /b 1

:VERIFY_X64_ACTIVE
if not defined VSINSTALLDIR exit /b 1
set "_TMP_VSDIR=%VSINSTALLDIR:"=%"
if not defined _TMP_VSDIR exit /b 1
if not exist "%_TMP_VSDIR%\VC\Auxiliary\Build\vcvarsall.bat" set "_TMP_VSDIR=" & exit /b 1
if not exist "%_TMP_VSDIR%\VC\Auxiliary\Build\vcvars64.bat" set "_TMP_VSDIR=" & exit /b 1
set "_TMP_VSDIR="
if /i not "%VSCMD_ARG_TGT_ARCH%"=="x64" exit /b 1
where.exe /q $PATH:cl.exe
if errorlevel 1 exit /b 1
where.exe /q $PATH:link.exe
if errorlevel 1 exit /b 1
exit /b 0
:: ============================================================================ SUBROUTINES END


:: ============================================================================ COLOR_SCHEME BEGIN
:COLOR_SCHEME
if defined NOCOLOR (
    set  "INFO= [INFO]  "
    set  "OKOK= [-OK-]  "
    set  "WARN= [WARN]  "
    set "ERROR= [ERROR] "
) else (
    set  "INFO=[100;92m [INFO]  [0m"
    set  "OKOK=[103;94m [-OK-]  [0m"
    set  "WARN=[106;35m [WARN]  [0m"
    set "ERROR=[105;34m [ERROR] [0m"
)
exit /b 0
:: ============================================================================ COLOR_SCHEME END
