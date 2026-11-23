@echo off

:: ============================================================================
:: Activate the MSVC build environment for an x64 target in the current CMD.
:: Reuse a verified environment or find and call vcvars64.bat.
:: Set NOCOLOR for plain output. Caller delayed expansion is optional.
:: Returns 0 for a verified environment or 1 on failure.
:: When USE_ICU=1, the check Conda ICU DLL architecture.
:: See msbuild.md for configuration, discovery, and troubleshooting.
:: ============================================================================

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

setlocal EnableExtensions EnableDelayedExpansion

set "EXIT_STATUS=0"

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

set "EXIT_STATUS=0"
set "_VCVARS="
set "VCVARS64=VC\Auxiliary\Build\vcvars64.bat"

:: --- 1. Check if already activated ---

echo %INFO% MSBuild: Checking if MSBuild environment is already activated...
if defined VSINSTALLDIR (
    echo %INFO% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
    echo %OKOK% MSBuild: MSBuild environment already active. Skipping activation.
    call :VERIFY_ACTIVATION
    set "EXIT_STATUS=!ERRORLEVEL!"
    goto :MAIN_EXIT
)

:: --- 2. Check explicit environment variable VCVARS ---

call :VCVARS_CHECK      && call :MSBUILD_ACTIVATION && call :VERIFY_ACTIVATION && goto :MAIN_EXIT

:: --- 3. Check default and custom MSVS locations ---

call :MSVS_LOCATIONS    && call :MSBUILD_ACTIVATION && call :VERIFY_ACTIVATION && goto :MAIN_EXIT

:: --- 4. Check BuildTools locations ---

call :MSBUILD_LOCATIONS && call :MSBUILD_ACTIVATION && call :VERIFY_ACTIVATION && goto :MAIN_EXIT

:MAIN_EXIT

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal && exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ VCVARS_CHECK BEGIN
:: ============================================================================
:VCVARS_CHECK

set "_EXIT_STATUS=0"

echo %INFO% MSBuild: Checking if VCVARS points to vcvarsall.bat or vcvars64.bat.
if not defined VCVARS (
    call :WHERE_CLI "vcvars64.bat" "VCVARS64_BAT" || (exit /b 1)
    set "VCVARS=%CLIPATH%"
)

set "VCVARS=%VCVARS:"=%"
echo %INFO% MSBuild: VCVARS = "%VCVARS%".

set "_VCVARS=%VCVARS:vcvarsall.bat=vcvars64.bat%"
if not "%_VCVARS:~-12%"=="vcvars64.bat" (set "_VCVARS=")

if exist "%_VCVARS%" (
    echo %INFO% MSBuild: Attempting activation...
    exit /b 0
) else (
    set "_VCVARS="
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ VCVARS_CHECK END


:: ============================================================================ MSVS_LOCATIONS BEGIN
:: ============================================================================
:MSVS_LOCATIONS

set "_EXIT_STATUS=0"

for %%P in (
    "%ProgramFiles%\Microsoft Visual Studio" 
    "%ProgramFiles(x86)%\Microsoft Visual Studio"
    "%~dp0..\Microsoft Visual Studio"
) do (
    echo %INFO% MSBuild: Checking for VS editions in "%%~P\{VERSION}\{KIND}".
    for /f "usebackq delims=" %%Y in (`dir /b /ad /O:-N "%%~P" 2^>nul`) do (
        for /d %%E in ("%%~P\%%Y\*") do (
            if exist "%%~fE\%VCVARS64%" (
               set "_VCVARS=%%~fE\%VCVARS64%"
               exit /b 0
            )
        )
    )
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSVS_LOCATIONS END


:: ============================================================================ MSBUILD_LOCATIONS BEGIN
:: ============================================================================
:MSBUILD_LOCATIONS

set "_EXIT_STATUS=0"

echo %INFO% MSBuild: Checking if BUILDTOOLS or MSBUILDTOOLS point to the "BuildTools" directory and fallback locations.
for %%D in (
    "%~dp0..\MSBuildTools"
    "%~dp0..\BuildTools"
    "%~d0\dev\MSBuildTools"
    "%~d0\dev\BuildTools"
    "%MSBUILDTOOLS%"
    "%BUILDTOOLS%"
) do (
    if exist "%%~fD\%VCVARS64%" (
        set "_VCVARS=%%~fD\%VCVARS64%"
        exit /b 0
    )
)

set "_EXIT_STATUS=1"

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSBUILD_LOCATIONS END


:: ============================================================================ MSBUILD_ACTIVATION BEGIN
:: ============================================================================
:MSBUILD_ACTIVATION

set "_EXIT_STATUS=0"

set "VSCMD_SKIP_SENDTELEMETRY=1"
echo:
echo %WARN% MSBuild: Activating MS Build Tools.
echo %INFO% MSBuild: Calling "%_VCVARS%"
echo:
call "%_VCVARS%" || (
    echo:
    echo %ERROR% MSBuild: "%_VCVARS%" returned an error.
    exit /b 1
) 

if not exist "%VCINSTALLDIR%" (
    echo %ERROR% MSBuild: MS Build Tools activation failed.
    set "_EXIT_STATUS=1"
) else (
    echo %INFO% MSBuild: MS Build Tools activation succeeded.
    echo %INFO% MSBuild: Staus pending verification.
    set "_EXIT_STATUS=0"
)

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MSBUILD_ACTIVATION END


:: ============================================================================ VERIFY_ACTIVATION BEGIN
:: ============================================================================
:VERIFY_ACTIVATION

setlocal
set "EXIT_STATUS=0"

echo:
echo %WARN% Verifying activation.
echo:

if defined VisualStudioVersion (
    echo %INFO% VisualStudioVersion=%VisualStudioVersion%
    echo:
) else (
    echo %ERROR% VisualStudioVersion is not set.
    set "EXIT_STATUS=1"
)

set "PAD10=          "
set "WIDTH=15"
set "TOOL_LABEL=VCINSTALLDIR=%PAD10%%PAD10%%PAD10%%PAD10%"
set "TOOL_LABEL=!TOOL_LABEL:~0,%WIDTH%!"
if exist "%VCINSTALLDIR%" (
    echo %INFO% %TOOL_LABEL% %VCINSTALLDIR%
) else (
    echo %ERROR% VCINSTALLDIR is not set.
    set "EXIT_STATUS=1"
)

set "EXPECTED_MACHINE="
if /i "%VSCMD_ARG_TGT_ARCH%"=="x86" set "EXPECTED_MACHINE=14C"
if /i "%VSCMD_ARG_TGT_ARCH%"=="x64" set "EXPECTED_MACHINE=8664"
if not defined EXPECTED_MACHINE (
    echo %ERROR% VSCMD_ARG_TGT_ARCH must be x86 or x64; got "!VSCMD_ARG_TGT_ARCH!".
    set "EXIT_STATUS=1"
)

call :WHERE_CLI "nmake.exe"    "NMAKE_EXE"     || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "cl.exe"       "CL_EXE"        || (set "EXIT_STATUS=!ERRORLEVEL!")
set "CL_EXE=%CLIPATH%"
call :WHERE_CLI "link.exe"     "LINK_EXE"      || (set "EXIT_STATUS=!ERRORLEVEL!")
set "LINK_EXE=%CLIPATH%"
call :WHERE_CLI "lib.exe"      "LIB_EXE"       || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "dumpbin.exe"  "DUMPBIN_EXE"   || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "curl.exe"     "CURL_EXE"      || (set "EXIT_STATUS=!ERRORLEVEL!")
call :WHERE_CLI "tclsh.exe"    "TCLSH_EXE"   "True"

if defined CL_EXE call :VERIFY_MS_LINKER "%CL_EXE%" "%LINK_EXE%" || set "EXIT_STATUS=1"

if not exist "%windir%\System32\tar.exe" (
    echo %ERROR% Windows tar is not found at "%windir%\System32\tar.exe".
    set "EXIT_STATUS=1"
)

if "%USE_ICU%"=="1" (
    call :CHECK_ICU_MACHINE || set "EXIT_STATUS=1"
)

echo:

if "%EXIT_STATUS%"=="0" (
    echo %OKOK% MSBuild: MS Build Tools are ready..
    echo %OKOK% MSBuild: VSINSTALLDIR points to "%VSINSTALLDIR%".
) else (
    echo %ERROR% MSBuild: MS Build Tools verification failed.
)

echo:
echo --------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal && exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ VERIFY_ACTIVATION END


:: ============================================================================ WHERE_CLI BEGIN
:: ============================================================================
:WHERE_CLI
:: ---------------------------------------------------------------------
:: %1 - Tool for `where` command, e.g., "link.exe"
:: %2 - Label for stdout message, e.g., "LINK_EXE"
:: %3 - If TRUE, treat as optional dependency {WARN, not ERROR}.
:: ---------------------------------------------------------------------

set "_EXIT_STATUS=0"
set "TOOL=%~1"
set "PAD10=          "
set "WIDTH=15"
set "TOOL_LABEL=%~2=%PAD10%%PAD10%%PAD10%%PAD10%"
set "TOOL_LABEL=!TOOL_LABEL:~0,%WIDTH%!"
if /i "%~3"=="TRUE" (
    set "LEVEL=%WARN%"
) else (
    set "LEVEL=%ERROR%"
)

set "CLIPATH="
set "CLIDIR="
for /f "usebackq delims=" %%I in (`where "%TOOL%" 2^>nul`) do (
    if "!CLIPATH!"=="" (
        set "CLIPATH=%%~I"
        set "CLIDIR=%%~dpI"
    )
)
if defined CLIPATH (
    echo %INFO% %TOOL_LABEL% %CLIPATH%
) else (
    echo %LEVEL% %TOOL_LABEL% is not found.
    set "_EXIT_STATUS=1"
)
if /i "%~3"=="TRUE" (set "_EXIT_STATUS=0")

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ WHERE_CLI END


:: ============================================================================ VERIFY_MS_LINKER BEGIN
:: ============================================================================
:VERIFY_MS_LINKER
:: ---------------------------------------------------------------------
:: %1 - cl.exe path.
:: %2 - link.exe path.
:: ---------------------------------------------------------------------

set "_CL_EXE=%~f1"
set "_CL_DIR=%~dp1"

set "_LINK_EXE=%~f2"
set "_LINK_DIR=%~dp2"

link.exe /? 2>&1 | findstr.exe /i /c:"Microsoft (R) Incremental Linker" /c:"/INCREMENTAL" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% MSBuild: Linker collision detected: link.exe is not the Microsoft Incremental Linker.
    echo %ERROR% MSBuild: Executing link.exe resolved to "%_LINK_EXE%" -- likely MSYS/Git/GNU link.exe.
    echo %ERROR% MSBuild: Expected MSVC toolset directory: "%_CL_DIR%".
    exit /b 1
)

if /i not "%_LINK_DIR%"=="%_CL_DIR%" (
    echo %ERROR% MSBuild: Linker collision detected: link.exe directory does not match active cl.exe directory.
    echo %ERROR% MSBuild: Resolved link.exe: "%_LINK_EXE%"
    echo %ERROR% MSBuild: Active cl.exe:     "%_CL_EXE%"
    exit /b 1
)

echo:
echo %INFO% Verified Microsoft linker.
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ VERIFY_MS_LINKER END


:: ============================================================================ CHECK_ICU_MACHINE BEGIN
:: ============================================================================
:CHECK_ICU_MACHINE

if not defined CONDA_PREFIX (
    echo %ERROR% USE_ICU=1 requires an active Conda environment.
    exit /b 1
)
set "ICU_BIN=!CONDA_PREFIX!\Library\bin"
set "FOUND_ICU="
for /f "usebackq delims=" %%F in (`dir /b /a:-d "!ICU_BIN!\icuuc*.dll" 2^>nul ^| findstr /i /r /x "icuuc[0-9][0-9]*\.dll"`) do (
    set "FOUND_ICU=1"
    set "MACHINE=unknown"
    for /f "usebackq tokens=1,2" %%M in (`dumpbin.exe /nologo /headers "!ICU_BIN!\%%F" ^|^| echo unreadable machine`) do (
        if /i "%%N"=="machine" set "MACHINE=%%M"
    )
    if /i not "!MACHINE!"=="%EXPECTED_MACHINE%" (
        echo %ERROR% "!ICU_BIN!\%%F": expected %VSCMD_ARG_TGT_ARCH% [%EXPECTED_MACHINE%], observed !MACHINE!.
        exit /b 1
    )
    echo %OKOK% "!ICU_BIN!\%%F": PE machine !MACHINE! matches target %VSCMD_ARG_TGT_ARCH%.
)
if not defined FOUND_ICU (
    echo %ERROR% No versioned ICU common DLL found in "!ICU_BIN!".
    exit /b 1
)
exit /b 0
:: ============================================================================
:: ============================================================================ CHECK_ICU_MACHINE END


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME
:: ---------------------------------------------------------------------
:: Color Scheme (with NOCOLOR fallback)
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
