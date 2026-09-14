@echo off
setlocal
set VERIBLE_BIN=%~dp0verible\verible-verilog-lint.exe

if "%~1"=="" (
    echo [ERROR] Usage: run_lint.bat ^<path_to_sv_file^>
    exit /b 1
)

echo [VERIBLE LINT] Checking: %~1
"%VERIBLE_BIN%" --rules_config_search %*
if %ERRORLEVEL% equ 0 (
    echo [VERIBLE LINT] PASSED: Clean SystemVerilog syntax and rules!
) else (
    echo [VERIBLE LINT] FAILED: Please review lint errors above.
)
endlocal
