@echo off
setlocal enabledelayedexpansion
set VIVADO_BIN=C:\AMDDesignTools\2026.1\Vivado\bin
set XVLOG=%VIVADO_BIN%\xvlog.bat
set XELAB=%VIVADO_BIN%\xelab.bat
set XSIM=%VIVADO_BIN%\xsim.bat

if "%~1"=="" (
    echo [ERROR] Usage: run_xsim.bat ^<top_module^> ^<source_files...^>
    exit /b 1
)

set TOP_MOD=%~1
set FILES=

shift
:loop
if "%~1"=="" goto endloop
set FILES=!FILES! "%~1"
shift
goto loop
:endloop

echo ========================================================
echo [XSIM RUNNER] 1. Compiling SystemVerilog files with xvlog...
echo ========================================================
call "%XVLOG%" -sv -nolog !FILES!
if !ERRORLEVEL! neq 0 (
    echo [ERROR] xvlog compilation failed.
    exit /b 1
)

echo ========================================================
echo [XSIM RUNNER] 2. Elaborating design snapshot with xelab...
echo ========================================================
call "%XELAB%" -debug typical -nolog !TOP_MOD! -s "!TOP_MOD!_sim"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] xelab elaboration failed.
    exit /b 1
)

echo ========================================================
echo [XSIM RUNNER] 3. Running headless simulation with xsim...
echo ========================================================
call "%XSIM%" "!TOP_MOD!_sim" -R -nolog
if !ERRORLEVEL! neq 0 (
    echo [ERROR] xsim simulation failed.
    exit /b 1
)

echo ========================================================
echo [XSIM RUNNER] SUCCESS: All simulation tests finished!
echo ========================================================
endlocal
