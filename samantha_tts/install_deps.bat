@echo off
title Samantha TTS - Installing Dependencies
echo.
echo  Installing Samantha TTS dependencies...
echo  This may take 5-10 minutes on first run.
echo.

SET PYTHON=C:\Users\sudee\AppData\Local\Programs\Python\Python311\python.exe
SET PIP=C:\Users\sudee\AppData\Local\Programs\Python\Python311\Scripts\pip.exe

REM Step 1: Core packages
echo [1/4] Installing Flask, soundfile, numpy...
"%PIP%" install flask soundfile "numpy<2" --quiet
if errorlevel 1 goto :error

REM Step 2: PyTorch >= 2.4 with CUDA 11.8 (Kokoro requires torch >= 2.4)
echo [2/4] Installing PyTorch CUDA 11.8 (torch ^>= 2.4)...
"%PIP%" install "torch>=2.4.0" torchaudio --index-url https://download.pytorch.org/whl/cu118 --quiet
if errorlevel 1 (
    echo  CUDA install failed. Trying CPU version...
    "%PIP%" install "torch>=2.4.0" torchaudio --quiet
)

REM Step 3: Kokoro TTS (pure Python, no C++ compilation needed)
echo [3/4] Installing Kokoro TTS...
"%PIP%" install "kokoro>=0.9.2" --quiet
if errorlevel 1 (
    echo  ERROR: Kokoro install failed.
    goto :error
)

REM Step 4: Verify
echo [4/4] Verifying...
"%PYTHON%" -c "import flask; print('  flask        OK')"
"%PYTHON%" -c "import torch; print('  torch        OK  version:', torch.__version__, ' CUDA:', torch.cuda.is_available())"
"%PYTHON%" -c "import soundfile; print('  soundfile    OK')"
"%PYTHON%" -c "from kokoro import KPipeline; print('  Kokoro TTS   OK')" 2>nul || echo   Kokoro TTS   FAILED - check output above

echo.
echo  All done! Run start_samantha_tts.bat to start the server.
echo.
goto :end

:error
echo.
echo  ERROR: Installation failed. See messages above.
echo.

:end
pause
