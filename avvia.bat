@echo off
REM Launcher per normalizza.ps1 - doppio click su Windows
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0normalizza.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Lo script e terminato con codice errore %ERRORLEVEL%.
    pause
)
endlocal
