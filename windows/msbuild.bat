@echo off

:: ============================================================================
::  Purpose:
::    Detects and activates Microsoft Build Tools (MSVC) environment if needed.
::    This script is idempotent and can be safely re-run.
::
::  Behavior:
::    - If MS Build Tools already active (VSINSTALLDIR set), exits successfully.
::    - Otherwise, checks explicit env vars, custom paths, PATH, vswhere, and
::      standard installation directories.
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
echo == %WARN%                                                                  %WARN% ==
echo == %WARN%                     MS Build Tools Check                         %WARN% ==
echo == %WARN%                                                                  %WARN% ==
echo == %WARN% CLI: "%~f0" %*
echo ====================================================================================
echo ====================================================================================
echo:

set "EXIT_STATUS=1"
set "_VCVARS="

:: --- 1. Check if already activated ---

echo %INFO% MSBuild: Checking if already activated...
if defined VSINSTALLDIR if exist "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat" (
    echo %INFO% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
    echo %OKOK% MSBuild: Environment already active. Skipping activation.
    set "EXIT_STATUS=0"
    goto :MSBUILD_ACTIVATED
)

:: --- 2. Check explicit environment variables (VCVARS, BUILDTOOLS, MSBUILDTOOLS) ---

echo %INFO% MSBuild: Checking if VCVARS points to vcvarsall.bat.
if defined VCVARS if exist "%VCVARS%" (
    set "_VCVARS=%VCVARS%"
    echo %INFO% MSBuild: VCVARS points to "%VCVARS%". Attempting activation...
    goto :MSBUILD_ACTIVATION
)

echo %INFO% MSBuild: Checking if BUILDTOOLS or MSBUILDTOOLS point to the "BuildTools" directory.
if defined BUILDTOOLS if exist "%BUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat" (
    set "_VCVARS=%BUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat"
    goto :MSBUILD_ACTIVATION
)
if defined MSBUILDTOOLS if exist "%MSBUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat" (
    set "_VCVARS=%MSBUILDTOOLS%\VC\Auxiliary\Build\vcvarsall.bat"
    goto :MSBUILD_ACTIVATION
)

:: --- 3. Check custom locations and junctions in dev ---

set "_MSVS=%~dp0..\Microsoft Visual Studio"
echo %INFO% MSBuild: Checking for custom locations of VS editions in "%_MSVS%\{VERSION}\{KIND}".
if exist "%_MSVS%" (
    for /f "usebackq delims=" %%Y in (`dir /b /ad /O:-N "%_MSVS%" 2^>nul`) do (
        for /d %%E in ("%_MSVS%\%%Y\*") do (
            if exist "%%E\VC\Auxiliary\Build\vcvarsall.bat" (
                set "_VCVARS=%%E\VC\Auxiliary\Build\vcvarsall.bat"
                goto :MSBUILD_ACTIVATION
            )
        )
    )
)

echo %INFO% MSBuild: Checking custom fallback locations for BuildTools.
for %%D in (
    "%~dp0..\MSBuildTools"
    "%~dp0..\BuildTools"
    "%~d0\dev\MSBuildTools"
    "%~d0\dev\BuildTools"
) do (
    if exist "%%~D\VC\Auxiliary\Build\vcvarsall.bat" (
        set "_VCVARS=%%~D\VC\Auxiliary\Build\vcvarsall.bat"
        goto :MSBUILD_ACTIVATION
    )
)

:: --- 4. Check PATH for vcvarsall.bat or BuildTools ---

echo %INFO% MSBuild: Checking if vcvarsall.bat is on the PATH.
for /f "usebackq tokens=* delims=" %%A in (`where vcvarsall.bat 2^>nul`) do (
    if exist "%%~A" (
        set "_VCVARS=%%~A"
        echo %INFO% MSBuild: Found vcvarsall.bat on the PATH: "%%~A". Attempting activation...
        goto :MSBUILD_ACTIVATION
    )
)

echo %INFO% MSBuild: Checking if "BuildTools" or its parent are on the PATH.
if defined Path (
    set "_PATH=%Path:"=%"
    set "_PATH="%_PATH:;=";"%""
    for %%A in (%_PATH%) do (
        if not "%%~A"=="" (
            if exist "%%~A\VC\Auxiliary\Build\vcvarsall.bat" (
                set "_VCVARS=%%~A\VC\Auxiliary\Build\vcvarsall.bat"
                goto :MSBUILD_ACTIVATION
            )
            if exist "%%~A\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" (
                set "_VCVARS=%%~A\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
                goto :MSBUILD_ACTIVATION
            )
        )
    )
)

:: --- 5. Query vswhere.exe if available ---

set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%_VSWHERE%" (
    echo %INFO% MSBuild: Querying vswhere.exe for latest Visual Studio with C++ tools.
    for /f "usebackq delims=" %%I in (`"%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        if exist "%%I\VC\Auxiliary\Build\vcvarsall.bat" (
            set "_VCVARS=%%I\VC\Auxiliary\Build\vcvarsall.bat"
            goto :MSBUILD_ACTIVATION
        )
    )
)

:: --- 6. Check default locations of VS editions (64-bit and 32-bit Program Files) ---

for %%P in ("%ProgramFiles%\Microsoft Visual Studio" "%ProgramFiles(x86)%\Microsoft Visual Studio") do (
    echo %INFO% MSBuild: Checking for default locations of VS editions in "%%~P\{VERSION}\{KIND}".
    if exist "%%~P" (
        for /f "usebackq delims=" %%Y in (`dir /b /ad /O:-N "%%~P" 2^>nul`) do (
            for /d %%E in ("%%~P\%%Y\*") do (
                if exist "%%E\VC\Auxiliary\Build\vcvarsall.bat" (
                    set "_VCVARS=%%E\VC\Auxiliary\Build\vcvarsall.bat"
                    goto :MSBUILD_ACTIVATION
                )
            )
        )
    )
)

:: --- MSBuildTools not found ---

set "EXIT_STATUS=1"
echo %ERROR% MSBuild: MS Build Tools activation script not found.
echo %ERROR% MSBuild: If MS Build Tools are installed, either
echo %ERROR% MSBuild:   - start this script from a preactivated MS Build Tools shell
echo %ERROR% MSBuild:   - see script notes above regarding checked locations and variables
echo %ERROR% MSBuild: See this accepted SO answer https://stackoverflow.com/a/64262038/17472988
echo %ERROR% MSBuild: regarding MS Build Tools installation.
echo:
goto :MSBUILD_ACTIVATED

:MSBUILD_ACTIVATION

:: --- MSBuildTools found ---

if not exist "%_VCVARS:all.bat=64.bat%" (
    echo %ERROR% MSBuild: 64-bit activation script not found at "%_VCVARS:all.bat=64.bat%".
    set "EXIT_STATUS=1"
    goto :MSBUILD_ACTIVATED
)

set "VSCMD_SKIP_SENDTELEMETRY=1"
echo:
echo %WARN% MSBuild: Activating MS Build Tools.
echo %INFO% MSBuild: Calling "%_VCVARS:all.bat=64.bat%"
echo:
call "%_VCVARS:all.bat=64.bat%"
set "EXIT_STATUS=%ERRORLEVEL%"
echo:
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% MSBuild: vcvars64.bat returned an error.
    set "EXIT_STATUS=1"
    goto :MSBUILD_ACTIVATED
)

if not defined VSINSTALLDIR (
    echo %ERROR% MSBuild: Activation returned success, but VSINSTALLDIR is missing. Aborting...
    set "EXIT_STATUS=1"
    goto :MSBUILD_ACTIVATED
)

if exist "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvarsall.bat" (
    set "EXIT_STATUS=0"
    echo %OKOK% MSBuild: MS Build Tools activation succeeded.
    echo %OKOK% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
) else (
    set "EXIT_STATUS=1"
    echo %ERROR% MSBuild: MS Build Tools activation failed.
    echo %ERROR% MSBuild: Used script "%_VCVARS:all.bat=64.bat%".
)

:MSBUILD_ACTIVATED

set "INFO="
set "OKOK="
set "WARN="
set "ERROR="
set "_MSVS="
set "_VCVARS="
set "_PATH="
set "_VSWHERE="
set "EXIT_STATUS=" & exit /b %EXIT_STATUS%


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
