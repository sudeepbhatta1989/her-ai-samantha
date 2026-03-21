@echo off
title Samantha TTS Server
color 0B
echo.
echo  =============================================
echo   Samantha TTS Server (XTTS v2 Voice Cloning)
echo  =============================================
echo.

cd /d "%~dp0"

SET PYTHON=C:\Users\sudee\AppData\Local\Programs\Python\Python311\python.exe
SET PIP=C:\Users\sudee\AppData\Local\Programs\Python\Python311\Scripts\pip.exe

REM Install deps if first time
if not exist ".installed" (
    echo Installing dependencies...
    call "%~dp0install_deps.bat"
    echo. > .installed
)

echo Starting TTS server on port 8765...
echo Press Ctrl+C to stop.
echo.
"%PYTHON%" samantha_tts_server.py
pause
