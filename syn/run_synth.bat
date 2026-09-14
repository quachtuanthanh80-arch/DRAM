@echo off
setlocal
echo ========================================================
echo [VIVADO SYNTH] Synthesizing Secure DDR5 Controller...
echo ========================================================
call C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -nolog -nojournal -source D:\RAM\syn\run_synth.tcl
if %ERRORLEVEL% equ 0 (
    echo ========================================================
    echo [VIVADO SYNTH] Synthesis & Timing Closure SUCCESS!
    echo ========================================================
) else (
    echo ========================================================
    echo [VIVADO SYNTH] ERROR during synthesis. Check logs.
    echo ========================================================
)
endlocal
