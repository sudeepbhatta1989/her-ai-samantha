@echo off
REM ══════════════════════════════════════════════════
REM  HER AI — Health Check Runner
REM  Run after every phase deploy
REM  Usage: Double-click OR run from Windows Terminal
REM ══════════════════════════════════════════════════

SET SCRIPT=C:\Projects\her-ai-samantha\health_check.py

IF NOT EXIST "%SCRIPT%" (
    echo ERROR: health_check.py not found at %SCRIPT%
    echo Copy health_check.py to C:\Projects\her-ai-samantha\ first
    pause & exit /b 1
)

echo.
echo Running full health check...
echo Results will appear below:
echo.

py "%SCRIPT%" %*

echo.
pause
