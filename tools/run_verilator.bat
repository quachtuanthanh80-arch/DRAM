@echo off
setlocal enabledelayedexpansion

set ARGS=
:parse_loop
if "%~1"=="" goto run_verilator
set "ITEM=%~1"
set "ITEM=!ITEM:\=/!"
set "ITEM=!ITEM:D:=/mnt/d!"
set "ITEM=!ITEM:d:=/mnt/d!"
set "ITEM=!ITEM:C:=/mnt/c!"
set "ITEM=!ITEM:c:=/mnt/c!"
set "ARGS=!ARGS! !ITEM!"
shift
goto parse_loop

:run_verilator
echo ========================================================
echo [VERILATOR RUNNER] Linting and Verifying with Verilator...
echo ========================================================
wsl verilator --lint-only -Wall -Wno-MULTITOP -Wno-UNUSEDPARAM -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY !ARGS!
if !ERRORLEVEL! equ 0 (
    echo ========================================================
    echo [VERILATOR] PASSED: Clean SystemVerilog verification!
    echo ========================================================
) else (
    echo [VERILATOR] FAILED: Please check warnings above.
)
endlocal
