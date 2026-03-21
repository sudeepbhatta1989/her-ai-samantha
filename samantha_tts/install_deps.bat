@echo off
title Samantha TTS - Installing Dependencies
echo.
echo  Installing Samantha TTS dependencies...
echo  This may take 5-10 minutes on first run.
echo.

SET PYTHON=C:\Users\sudee\AppData\Local\Programs\Python\Python311\python.exe
SET PIP=C:\Users\sudee\AppData\Local\Programs\Python\Python311\Scripts\pip.exe

REM Step 1: Core packages
echo [1/4] Installing Flask and base packages...
"%PIP%" install flask soundfile numpy^<2 --quiet
if errorlevel 1 goto :error

REM Step 2: PyTorch with CUDA 11.8 (pre-compiled, no build needed)
echo [2/4] Installing PyTorch CUDA 11.8...
"%PIP%" install torch==2.1.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu118 --quiet
if errorlevel 1 (
    echo PyTorch CUDA install failed. Trying CPU version...
    "%PIP%" install torch torchaudio --quiet
)

REM Step 3: Try installing TTS (Coqui) - pre-built binary preferred
echo [3/4] Installing Coqui TTS...
"%PIP%" install TTS --prefer-binary --quiet
if errorlevel 1 (
    echo.
    echo  Standard TTS install failed. Trying alternative...
    REM Try with no-build-isolation to skip compilation
    "%PIP%" install TTS --no-build-isolation --prefer-binary --quiet
    if errorlevel 1 (
        echo.
        echo  WARNING: TTS install failed. Trying minimal install...
        REM Install just the core XTTS v2 deps without full TTS package
        "%PIP%" install transformers accelerate sentencepiece --quiet
        echo  Will use transformers-based fallback for TTS.
    )
)

REM Step 4: Verify
echo [4/4] Verifying installation...
"%PYTHON%" -c "import flask; print('  flask OK')"
"%PYTHON%" -c "import torch; print('  torch OK, CUDA:', torch.cuda.is_available())"
"%PYTHON%" -c "import soundfile; print('  soundfile OK')"
"%PYTHON%" -c "from TTS.api import TTS; print('  Coqui TTS OK')" 2>nul || echo   Coqui TTS: NOT available (will use HF fallback)

echo.
echo  Done! Dependencies installed.
echo.
goto :end

:error
echo.
echo  ERROR: Dependency installation failed.
echo  Please run manually:
echo    %PIP% install flask soundfile numpy^<2 TTS --prefer-binary
echo.

:end
pause
