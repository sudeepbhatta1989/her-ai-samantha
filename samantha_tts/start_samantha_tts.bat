@echo off
title Samantha TTS Server
color 0B
echo.
echo  =============================================
echo   Samantha TTS Server (XTTS v2 Voice Cloning)
echo  =============================================
echo.

cd /d "%~dp0"

REM Install deps if first time
if not exist ".installed" (
    echo Installing dependencies...
    pip install -r requirements.txt
    echo. > .installed
)

echo Starting TTS server on port 8765...
echo Press Ctrl+C to stop.
echo.
python samantha_tts_server.py
pause
