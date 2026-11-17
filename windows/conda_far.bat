@echo off

:: ============================================================================
:: Activate an existing Windows Python/Conda environment and load local configs.
:: Use a clean CMD session. Any argument requires caller delayed expansion.
:: With no arguments, launch FAR Manager or an interactive CMD at the prefix.
:: /batch and /preactivate return to the caller after setup.
:: /cli "command" runs one command in the activated environment.
:: /nocolor or NOCOLOR selects plain text diagnostics.
:: Returns the setup, command, or child shell status.
:: See conda_far.md for workflows, configuration, and filesystem changes.
:: ============================================================================

set "ERRORLEVEL="
set "FINAL_EXIT_CODE=0"
set "EXIT_STATUS=1"

:: --- Escape sequence templates for color coded console output ---

call :COLOR_SCHEME

:: --- Parse arguments and preserve top-level context ---

call :PARSE_ARGS %*
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Failed to parse arguments. Aborting...
    goto :CLEANUP
)

:: --- Re-apply color scheme in case /nocolor was passed ---

call :COLOR_SCHEME

echo:
echo ==========================================================================
echo %INFO% Setting up environment
echo %INFO%
echo %WARN% CLI: "%~f0" %*
echo ==========================================================================
echo:

:: --- Select the target prefix and activation wrappers ---

if defined _CONDA_PREFIX (
    set "__CONDA_PREFIX=%_CONDA_PREFIX:"=%"
) else (
    set "__CONDA_PREFIX=%~dp0Anaconda"
)
set "CONDA_BAT=%__CONDA_PREFIX%\condabin\conda.bat"
set "MAMBA_BAT=%__CONDA_PREFIX%\condabin\mamba.bat"

:: --- Require caller delayed expansion with arguments or enable it locally ---

call :CHECK_DELAYED_EXPANSION
if not "%ERRORLEVEL%"=="0" (
    if defined _ARGS (
        rem --- Delayed Expansion is disabled, running in non-interactive mode ---
        set "FINAL_EXIT_CODE=%ERRORLEVEL%"
        echo %ERROR% Delayed Expansion is disabled while running in non-interactive mode. Aborting...
        goto :CLEANUP
    )
    rem --- Delayed Expansion is disabled, running in interactive mode (no arguments supplied) ---
    setlocal EnableDelayedExpansion EnableExtensions
)

:: --- Check for an active Conda prefix or visible Python/Conda commands ---

call :NO_ROOT_ENVIRONMENT
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Aborting due to pre-existing Python/Conda environment.
    goto :CLEANUP
)

:: --- Check required prefix files before cache setup or linker renaming ---

if not exist "%__CONDA_PREFIX%\python.exe" (
    echo %ERROR% Python not found: "%__CONDA_PREFIX%\python.exe". Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)
if not exist "%CONDA_BAT%" (
    echo %ERROR% Conda activation script not found: "%CONDA_BAT%". Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)
if not exist "%MAMBA_BAT%" (
    echo %ERROR% Mamba activation script not found: "%MAMBA_BAT%". Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)

:: --- Configure tool caches and profile cache junctions ---

call :CACHE_DIR
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to configure CACHE directory. Aborting...
    set "FINAL_EXIT_CODE=%EXIT_STATUS%"
    goto :CLEANUP
)
if not defined _CACHE (
    echo %ERROR% Failed to set CACHE directory. Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)
echo:

:: --- Rename m2 link.exe before MSBuild check, if present ---

if exist "%__CONDA_PREFIX%\Library\usr\bin\link.exe" (
    echo %INFO% Renaming m2 link.exe to link_.exe to resolve MSBuild linker collision.
    if exist "%__CONDA_PREFIX%\Library\usr\bin\link_.exe" (
        echo %WARN% Removing previous backup "%__CONDA_PREFIX%\Library\usr\bin\link_.exe".
        del /F /Q "%__CONDA_PREFIX%\Library\usr\bin\link_.exe"
        if not "!ERRORLEVEL!"=="0" (
            echo %ERROR% Failed to remove existing "%__CONDA_PREFIX%\Library\usr\bin\link_.exe". Aborting...
            set "FINAL_EXIT_CODE=1"
            goto :CLEANUP
        )
    )
    move "%__CONDA_PREFIX%\Library\usr\bin\link.exe" "%__CONDA_PREFIX%\Library\usr\bin\link_.exe" >nul
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to rename "%__CONDA_PREFIX%\Library\usr\bin\link.exe". Aborting...
        set "FINAL_EXIT_CODE=1"
        goto :CLEANUP
    )
)

:: --- MS Build Tools ---

if not exist "%~dp0msbuild.bat" (
    echo %WARN% MSBUILD activation script not found: "%~dp0msbuild.bat". Skipping...
    goto :MSBUILD_SKIP
)
call "%~dp0msbuild.bat"
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    call :COLOR_SCHEME
    echo %ERROR% MSBuild activation failed. Aborting...
    goto :CLEANUP
)

:: --- Restore color variables cleared by msbuild.bat ---

call :COLOR_SCHEME

:: --- Have Python/setuptools/distutils use preactivated MS Build Tools environment ---

set "DISTUTILS_USE_SDK=1"

:MSBUILD_SKIP

:: --- Activate Conda environment ---

echo:
echo %WARN% Activating Conda PREFIX "%__CONDA_PREFIX%".
call "%CONDA_BAT%" activate
if not "%ERRORLEVEL%"=="0" (
    set "FINAL_EXIT_CODE=%ERRORLEVEL%"
    echo %ERROR% Conda environment activation failed. Aborting...
    goto :CLEANUP
)
if not defined CONDA_PREFIX (
    set "CONDA_PREFIX=%PYTHON_HOME%"
)
if not defined CONDA_PREFIX (
    echo %ERROR% Conda environment activation failed - Neither CONDA_PREFIX nor PYTHON_HOME is defined. Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)
if not exist "!CONDA_PREFIX!\python.exe" (
    echo %ERROR% Conda environment activation failed - Python "!CONDA_PREFIX!\python.exe" not found. Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)

set "PYTHON_VERSION="
for /f "usebackq tokens=2" %%V in (`python.exe --version 2^>^&1`) do (
    set "PYTHON_VERSION=%%V"
)
if not defined PYTHON_VERSION (
    echo %ERROR% Failed to determine PYTHON_VERSION from python.exe. Aborting...
    set "FINAL_EXIT_CODE=1"
    goto :CLEANUP
)

:: --- Set JAVA_HOME when a bundled JVM is present ---

if not defined JAVA_HOME (
    if exist "%CONDA_PREFIX%\Library\lib\jvm\bin\server\jvm.dll" (
        set "JAVA_HOME=%CONDA_PREFIX%\Library\lib\jvm"
    ) else if exist "%CONDA_PREFIX%\Library\jre\bin\server\jvm.dll" (
        set "JAVA_HOME=%CONDA_PREFIX%\Library"
    )
)

echo %OKOK% Conda activation succeeded (Python %PYTHON_VERSION%).

:: --- Run optional config_*.bat files from the script directory ---

echo:
echo %INFO% ========== Loading Configs ==========
echo:
for %%F in ("%~dp0config_*.bat") do (
    echo %INFO% Loading "%%~F"
    call "%%~F"
    set "EXIT_STATUS=!ERRORLEVEL!"
    call :COLOR_SCHEME
    if not "!EXIT_STATUS!"=="0" (
        echo %ERROR% Aborting due to failing to apply "%%~F" settings.
        set "FINAL_EXIT_CODE=!EXIT_STATUS!"
        goto :CLEANUP
    )
)
echo %OKOK% Loaded extra environment settings.
echo:

:: --- Execute CLI, if defined ---

if defined _ARG_CLI goto :RUN_CLI

:: --- Use "/batch" or "/preactivate" to activate shell environment without starting FAR MANAGER ---

if defined _ARG_BATCH (
    set "FINAL_EXIT_CODE=0"
    goto :CLEANUP
)
if defined _ARG_PREACTIVATE (
    set "FINAL_EXIT_CODE=0"
    goto :CLEANUP
)

:: --- Try far.bat, then far.exe, then an interactive CMD ---

set "_FARMANAGER="
for %%A in ("far.bat" "far.exe") do if not defined _FARMANAGER (
    where.exe /q "%%~A"
    if "!ERRORLEVEL!"=="0" (
        set "_FARMANAGER=%%~A"
    )
)

if not defined _FARMANAGER goto :START_CMD_SHELL

echo %INFO% Launching FAR Manager: "%_FARMANAGER%" in "%CONDA_PREFIX%"
call :CLEAR_VARS
cmd.exe /E:ON /V:ON /C "%_FARMANAGER% ""%CONDA_PREFIX%"""
set "FINAL_EXIT_CODE=%ERRORLEVEL%"
set "_FARMANAGER="
goto :CLEANUP

:START_CMD_SHELL
echo %WARN% FAR Manager (far.bat / far.exe) not found on PATH. Opening interactive cmd.exe session...
call :CLEAR_VARS
cmd.exe /E:ON /V:ON /K cd /d "%CONDA_PREFIX%"
set "FINAL_EXIT_CODE=%ERRORLEVEL%"
goto :CLEANUP

:RUN_CLI
echo %INFO% Running "!_ARG_CLI!"
set "_RUN_CMD=%_ARG_CLI%"
call :CLEAR_VARS
call %_RUN_CMD%
set "FINAL_EXIT_CODE=%ERRORLEVEL%"
set "_RUN_CMD="
if not "%FINAL_EXIT_CODE%"=="0" (
    call :COLOR_SCHEME
    echo %ERROR% CLI command failed with exit code %FINAL_EXIT_CODE%.
)
goto :CLEANUP
:: ============================================================================
:: ============================================================================
:: ============================================================================


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME
:: ---------------------------------------------------------------------
:: Set diagnostic prefixes and honor /nocolor, NOCOLOR, and NO_COLOR.
:: ---------------------------------------------------------------------

if defined _ARG_NOCOLOR set "NOCOLOR=1"
if defined NO_COLOR set "NOCOLOR=1"
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
:: ============================================================================
:: ============================================================================ COLOR_SCHEME END


:: ============================================================================ PARSE_ARGS BEGIN
:: ============================================================================
:: Parse mode and color options. Shift arguments in this subroutine so the
:: top-level %0 continues to refer to the script.

:PARSE_ARGS

echo:
echo ==================== PARSING ARGUMENTS ====================
echo:

set "_ARGS="
if not "%~1"=="" set "_ARGS=TRUE"

set "_ARG_BATCH="
set "_ARG_PREACTIVATE="
set "_ARG_NOCOLOR="
set "_ARG_CLI="

:PARSE_NEXT_ARG

set "__ARG1=%~1"
set "__ARG2=%~2"
if "%__ARG1%"=="" goto :PARSE_ARGS_DONE
if "%__ARG1:~0,2%"=="--" (
    set "__ARG1=%__ARG1:~2%"
    goto :PARSE_ARG_TOKEN
)
if "%__ARG1:~0,1%"=="/" (
    set "__ARG1=%__ARG1:~1%"
    goto :PARSE_ARG_TOKEN
)
if "%__ARG1:~0,1%"=="-" (
    set "__ARG1=%__ARG1:~1%"
    goto :PARSE_ARG_TOKEN
)

:PARSE_ARG_TOKEN

echo %INFO% ~~~~~ Parsing "%__ARG1%" ~~~~~.

if /I "%__ARG1%"=="batch" (
    set "_ARG_BATCH=1"
    echo %INFO% Using BATCH MODE.
    shift
    goto :PARSE_NEXT_ARG
)

if /I "%__ARG1%"=="preactivate" (
    set "_ARG_PREACTIVATE=1"
    echo %INFO% Using PREACTIVATE MODE.
    shift
    goto :PARSE_NEXT_ARG
)

if /I "%__ARG1%"=="nocolor" (
    set "_ARG_NOCOLOR=1"
    echo %INFO% Using basic monochrome console output.
    shift
    goto :PARSE_NEXT_ARG
)

if /I "%__ARG1:~0,4%"=="cli=" (
    set "_ARG_CLI=%__ARG1:~4%"
    goto :VALIDATE_ARG_CLI
)

if /I "%__ARG1%"=="cli" (
    set "_ARG_CLI=%__ARG2%"
    shift
    goto :VALIDATE_ARG_CLI
)

echo %WARN% Skipping unknown argument "%__ARG1%".
shift
goto :PARSE_NEXT_ARG

:VALIDATE_ARG_CLI
if not defined _ARG_CLI (
    echo %ERROR% CLI argument cannot be empty. Aborting...
    set "__ARG1="
    set "__ARG2="
    exit /b 1
)
set "_ARG_BATCH=1"
shift
goto :PARSE_NEXT_ARG

:PARSE_ARGS_DONE

set "__ARG1="
set "__ARG2="

exit /b 0
:: ============================================================================
:: ============================================================================ PARSE_ARGS END


:: ============================================================================ CLEANUP BEGIN
:: ============================================================================
:: Set FINAL_EXIT_CODE and jump to CLEANUP to return the script status.
:: CLEAR_VARS also runs before a command or child shell starts. It leaves
:: CONDA_BAT and MAMBA_BAT available to callers such as Anaconda.bat.

:CLEANUP
call :CLEAR_VARS
if not defined FINAL_EXIT_CODE set "FINAL_EXIT_CODE=0"
set "FINAL_EXIT_CODE=" & exit /b %FINAL_EXIT_CODE%

:CLEAR_VARS
set "_ARGS="
set "_ARG_BATCH="
set "_ARG_PREACTIVATE="
set "_ARG_NOCOLOR="
set "_ARG_CLI="
set "__ARG1="
set "__ARG2="
set "_CACHE="
set "_PKGS_DIR="
set "_CONDA_EXE="
set "_CONDA_ROOT="
set "__CONDA_PREFIX="
set "_DUMMY="
set "SRC="
set "DST="
set "DELAYED_EXPANSION="
set  "INFO="
set  "OKOK="
set  "WARN="
set "ERROR="
set "EXIT_STATUS="
exit /b 0
:: ============================================================================
:: ============================================================================ CLEANUP END


:: ============================================================================ CACHE_DIR BEGIN
:: ============================================================================
:CACHE_DIR
:: Set cache paths, create missing directories, and replace profile cache paths
:: with junctions. Return 1 if a required filesystem operation fails.
:: --------------------------------------------------------
:: Temp directory
:: --------------------------------------------------------
echo:
if exist "%~d0\Temp" (
    set "TEMP=%~d0\Temp"
    set "TMP=%~d0\Temp"
    echo %INFO% TEMP: "!TEMP!"
    echo %INFO% TMP:  "!TMP!"
)

:: --------------------------------------------------------
:: Determine cache directory
:: --------------------------------------------------------
if defined _CACHE if exist "%_CACHE%" (
    goto :CACHE_DIR_SET
)

if exist "%~d0\Downloads" (
    set "_CACHE=%~d0\Downloads"
) else (
    set "_CACHE=%USERPROFILE%\Downloads"
)

if exist "%_CACHE%\CACHE" (
    set "_CACHE=%_CACHE%\CACHE"
    goto :CACHE_DIR_SET
)

if exist "%~d0\CACHE" (
    set "_CACHE=%~d0\CACHE"
    goto :CACHE_DIR_SET
)

:CACHE_DIR_SET
:: --------------------------------------------------------
:: Verify file system access
:: --------------------------------------------------------
set "_DUMMY=%_CACHE%\$$$_DELETEME_ACCESS_CHECK_$$$"
if exist "%_DUMMY%" (
    rmdir /Q /S "%_DUMMY%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to delete pre-existing test directory "%_DUMMY%".
        echo %ERROR% Expected full access at "%_CACHE%". Aborting...
        set "_CACHE="
        exit /b 1
    )
)
if exist "%_DUMMY%" (
    echo %ERROR% Test directory "%_DUMMY%" still exists after removal attempt.
    echo %ERROR% Expected full access at "%_CACHE%". Aborting...
    set "_CACHE="
    exit /b 1
)

mkdir "%_DUMMY%"
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Failed to create test directory "%_DUMMY%".
    echo %ERROR% Expected full access at "%_CACHE%". Aborting...
    set "_CACHE="
    exit /b 1
)
if not exist "%_DUMMY%" (
    echo %ERROR% Test directory "%_DUMMY%" was not created.
    echo %ERROR% Expected full access at "%_CACHE%". Aborting...
    set "_CACHE="
    exit /b 1
)
rmdir /Q /S "%_DUMMY%"
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Failed to clean up test directory "%_DUMMY%".
    set "_CACHE="
    exit /b 1
)

:: --------------------------------------------------------
:: CONDA_PKGS_DIRS
:: --------------------------------------------------------
set "_PKGS_DIR=%_CACHE%\Python\pkgs"

if not defined CONDA_PKGS_DIRS (
    set "CONDA_PKGS_DIRS=%_PKGS_DIR%"
) else (
    set "_PKGS_DIR=%CONDA_PKGS_DIRS%"
)
if not exist "%CONDA_PKGS_DIRS%" (
    mkdir "%CONDA_PKGS_DIRS%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create directory "%CONDA_PKGS_DIRS%".
        set "_CACHE="
        exit /b 1
    )
)

:: --------------------------------------------------------
:: PIP_CACHE_DIR and UV_CACHE_DIR
:: --------------------------------------------------------
set "PIP_CACHE_DIR=%_CACHE%\Python\pip\cache"
set "UV_CACHE_DIR=%_CACHE%\Python\uv\cache"

if not exist "%PIP_CACHE_DIR%" (
    mkdir "%PIP_CACHE_DIR%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create directory "%PIP_CACHE_DIR%".
        set "_CACHE="
        exit /b 1
    )
)
if not exist "%UV_CACHE_DIR%" (
    mkdir "%UV_CACHE_DIR%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create directory "%UV_CACHE_DIR%".
        set "_CACHE="
        exit /b 1
    )
)

echo %INFO% CACHE                    directory: "%_CACHE%".
echo %INFO% CONDA_PKGS_DIRS          directory: "%CONDA_PKGS_DIRS%".
echo %INFO% PIP_CACHE_DIR            directory: "%PIP_CACHE_DIR%".
echo %INFO% UV_CACHE_DIR             directory: "%UV_CACHE_DIR%".

set "SRC=%PIP_CACHE_DIR%"
set "DST=%LOCALAPPDATA%\pip"
if not exist "%DST%" (
    mkdir "%DST%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%DST%".
        exit /b 1
    )
)
if exist "%DST%\cache" (
    rmdir /S /Q "%DST%\cache"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to remove existing "%DST%\cache".
        exit /b 1
    )
)
mklink /j "%DST%\cache" "%SRC%" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Failed to create directory junction "%DST%\cache" -^> "%SRC%".
    exit /b 1
)
echo %INFO% Profile pip cache dir is linked: "%DST%\cache".

set "SRC=%UV_CACHE_DIR%"
set "DST=%LOCALAPPDATA%\uv"
if not exist "%DST%" (
    mkdir "%DST%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%DST%".
        exit /b 1
    )
)
if exist "%DST%\cache" (
    rmdir /S /Q "%DST%\cache"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to remove existing "%DST%\cache".
        exit /b 1
    )
)
mklink /j "%DST%\cache" "%SRC%" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Failed to create directory junction "%DST%\cache" -^> "%SRC%".
    exit /b 1
)
echo %INFO% Profile uv cache dir is linked: "%DST%\cache".

:: --------------------------------------------------------
:: Git
:: --------------------------------------------------------
set "GIT_CACHE=H:\GitHub"
if not exist "%GIT_CACHE%" (
    set "GIT_CACHE=%~d0\GitHub"
)
if not exist "%GIT_CACHE%" (
    set "GIT_CACHE=%_CACHE%\GitHub"
)
if not exist "%GIT_CACHE%" (
    mkdir "%GIT_CACHE%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%GIT_CACHE%".
        exit /b 1
    )
)
echo %INFO% GIT_CACHE                directory: "%GIT_CACHE%".

:: --------------------------------------------------------
:: Node, npm, pnpm, Electron, etc.
:: --------------------------------------------------------
set "NPM_CONFIG_CACHE=%_CACHE%\npm"
if not exist "%NPM_CONFIG_CACHE%" (
    mkdir "%NPM_CONFIG_CACHE%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%NPM_CONFIG_CACHE%".
        exit /b 1
    )
)
echo %INFO% NPM_CONFIG_CACHE         directory: "%NPM_CONFIG_CACHE%".

set "ELECTRON_CACHE=%_CACHE%\electron"
if not exist "%ELECTRON_CACHE%" (
    mkdir "%ELECTRON_CACHE%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%ELECTRON_CACHE%".
        exit /b 1
    )
)
echo %INFO% ELECTRON_CACHE           directory: "%ELECTRON_CACHE%".

set "ELECTRON_BUILDER_CACHE=%_CACHE%\electron-builder"
if not exist "%ELECTRON_BUILDER_CACHE%" (
    mkdir "%ELECTRON_BUILDER_CACHE%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%ELECTRON_BUILDER_CACHE%".
        exit /b 1
    )
)
echo %INFO% ELECTRON_BUILDER_CACHE   directory: "%ELECTRON_BUILDER_CACHE%".

set "PLAYWRIGHT_BROWSERS_PATH=%_CACHE%\playwright"
if not exist "%PLAYWRIGHT_BROWSERS_PATH%" (
    mkdir "%PLAYWRIGHT_BROWSERS_PATH%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%PLAYWRIGHT_BROWSERS_PATH%".
        exit /b 1
    )
)
echo %INFO% PLAYWRIGHT_BROWSERS_PATH directory: "%PLAYWRIGHT_BROWSERS_PATH%".

set "PNPM_HOME=%_CACHE%\pnpm"
if not exist "%PNPM_HOME%" (
    mkdir "%PNPM_HOME%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%PNPM_HOME%".
        exit /b 1
    )
)
echo %INFO% PNPM_HOME                directory: "%PNPM_HOME%".

set "XDG_CACHE_HOME=%_CACHE%\pnpm-cache"
if not exist "%XDG_CACHE_HOME%" (
    mkdir "%XDG_CACHE_HOME%"
    if not "!ERRORLEVEL!"=="0" (
        echo %ERROR% Failed to create "%XDG_CACHE_HOME%".
        exit /b 1
    )
)
echo %INFO% XDG_CACHE_HOME           directory: "%XDG_CACHE_HOME%".

exit /b 0
:: ============================================================================
:: ============================================================================ CACHE_DIR END


:: ============================================================================ CHECK_DELAYED_EXPANSION BEGIN
:: ============================================================================
:CHECK_DELAYED_EXPANSION
::
:: Set DELAYED_EXPANSION to 1 when CMD expands !ComSpec! and to 0 otherwise.
:: Return 0 when delayed expansion is enabled or 1 when disabled.

echo:
echo %WARN% Checking cmd.exe delayed expansion availability
echo %INFO%
echo %INFO% When running with any arguments, Delayed Expansion feature must be
echo %INFO% enabled by the caller.
echo %INFO% When running without arguments, the script is supposed to spawn
echo %INFO% an activated shell, so Delayed Expansion can be enabled locally.
echo:
if "!ComSpec!"=="%ComSpec%" (
    set "DELAYED_EXPANSION=1"
    echo %INFO% --------------------------
    echo %OKOK% CHECK PASSED
    echo %INFO% Delayed Expansion enabled.
    echo %INFO% --------------------------
    echo:
    exit /b 0
) else (
    set "DELAYED_EXPANSION=0"
)

echo:
echo %INFO% ------------------------------------------------------------------------
echo %ERROR% CHECK FAILED
echo %WARN% Delayed Expansion disabled.
echo %INFO% This script should be generally called with Delayed Expansion enabled
echo %INFO% by the caller. When used interactively without any arguments, this
echo %INFO% script will activate Conda environment and spawn an activated shell.
echo %INFO% In this mode, Delayed Expansion mode can be activated by this script.
echo %INFO% In batch mode, this script is used to activate caller's environment,
echo %INFO% and, therefore this script will be unable to activate both Delayed
echo %INFO% Expansion and the caller's environment. Use one of the following
echo %INFO% options, then rerun this script with "/batch" switch to verify that the
echo %INFO% test passes.
echo %INFO%
echo %INFO% 1. "setlocal EnableDelayedExpansion EnableExtensions"
echo %INFO%    Use this command in the parent script before calling this script.
echo %INFO%
echo %INFO% 2. Start a new cmd.exe shell as "cmd.exe /E:ON /V:ON".
echo %INFO%
echo %INFO% 3. Enable Delayed Expansion permanently via the following registry
echo %INFO%    setting (either variant should do), start a new shell:
echo %INFO% ------------------------------------------------------------------------
echo:
echo %INFO% Delayed expansion activation settings.
echo:
echo %INFO% ------------------------------------------------------------------------
echo %INFO% [HKEY_CURRENT_USER\Software\Microsoft\Command Processor]
echo %INFO% "DelayedExpansion"=dword:00000001
echo %INFO% "EnableExtensions"=dword:00000001
echo %INFO%
echo %INFO% --- OR ---
echo %INFO%
echo %INFO% [HKEY_LOCAL_MACHINE\Software\Microsoft\Command Processor]
echo %INFO% "DelayedExpansion"=dword:00000001
echo %INFO% "EnableExtensions"=dword:00000001
echo %INFO% ------------------------------------------------------------------------
echo:

exit /b 1
:: ============================================================================
:: ============================================================================ CHECK_DELAYED_EXPANSION END


:: ============================================================================ NO_ROOT_ENVIRONMENT BEGIN
:: ============================================================================
:: --------------------------------------------------------
:: NO_ROOT_ENVIRONMENT
::
:: Return 1 if CONDA_PREFIX is set or WHERE finds python.exe or conda.bat.
:: WHERE checks the working directory and PATH. Return 0 if none is found.
:: --------------------------------------------------------
:NO_ROOT_ENVIRONMENT

echo:
echo ====================================================================================
echo ====================================================================================
echo == %WARN%                                                            %WARN% ==
echo == %WARN%         Checking for activated Conda environment           %WARN% ==
echo == %WARN%                                                            %WARN% ==
echo ====================================================================================
echo ====================================================================================
echo:

:: --- Check if Conda or Python is active or on the Path ---

set "_CONDA="
set "_PYTHON="
if defined CONDA_PREFIX (
    set "_CONDA=%CONDA_PREFIX%"
)
echo %INFO% Checking if Python is on the Path
where.exe python.exe 2>nul
if "%ERRORLEVEL%"=="0" (
    set "_PYTHON=python.exe"
)
echo %INFO% Checking if Conda is on the Path
where.exe conda.bat 2>nul
if "%ERRORLEVEL%"=="0" (
    set "_CONDA=conda.bat"
)
if not defined _CONDA if not defined _PYTHON (
    echo %OKOK% Python/Conda not detected.
    exit /b 0
)

echo:
if defined CONDA_PREFIX (
    echo %WARN% Detected active CONDA_PREFIX="%CONDA_PREFIX%".
)
if defined _PYTHON (
    echo %WARN% Detected "python.exe" in Path.
)
if defined _CONDA (
    echo %WARN% Detected "conda.bat" in Path.
)

echo %WARN% It is strongly recommended to start this script from a clean
echo %WARN% environment. No Conda or Python variables should be in Path.

set "_CONDA="
set "_PYTHON="
exit /b 1
:: ============================================================================
:: ============================================================================ NO_ROOT_ENVIRONMENT END
