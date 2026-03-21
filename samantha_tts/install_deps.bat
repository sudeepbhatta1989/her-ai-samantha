@echo off
title Samantha TTS - Installing Dependencies
echo.
echo  Installing Samantha TTS dependencies...
echo  This may take 5-10 minutes on first run.
echo.

SET PYTHON=C:\Users\sudee\AppData\Local\Programs\Python\Python311\python.exe
SET PIP=C:\Users\sudee\AppData\Local\Programs\Python\Python311\Scripts\pip.exe

REM Step 1: Core packages
echo [1/5] Installing Flask and base packages...
"%PIP%" install flask soundfile numpy^<2 --quiet
if errorlevel 1 goto :error

REM Step 2: PyTorch with CUDA 11.8 (pre-compiled, no build needed)
echo [2/5] Installing PyTorch CUDA 11.8...
"%PIP%" install torch==2.1.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu118 --quiet
if errorlevel 1 (
    echo  PyTorch CUDA install failed. Trying CPU version...
    "%PIP%" install torch torchaudio --quiet
)

REM Step 3: Try Coqui TTS with --no-deps to skip problematic sub-deps that need C++ compilation
echo [3/5] Trying Coqui TTS (no-deps mode)...
"%PIP%" install TTS --no-deps --quiet
if not errorlevel 1 (
    REM Install only the XTTS v2 core deps (all pure Python / pre-built wheels)
    "%PIP%" install transformers coqpit trainer librosa inflect pypinyin unidecode num2words langdetect bangla bnnumerizer bnunicodenormalizer --quiet --prefer-binary
    "%PYTHON%" -c "from TTS.api import TTS; print('  Coqui TTS OK')" 2>nul
    if not errorlevel 1 goto :install_kokoro
    echo  Coqui TTS imported but incomplete. Will use Kokoro.
) else (
    echo  Coqui TTS build failed (Windows C++ issue). Using Kokoro TTS instead.
)

REM Step 4: Install Kokoro TTS (pure Python, no compilation, high quality)
:install_kokoro
echo [4/5] Installing Kokoro TTS (high-quality fallback)...
"%PIP%" install kokoro>=0.9.2 --quiet
if errorlevel 1 (
    echo  Kokoro install failed. Installing espeakng dependency...
    "%PIP%" install espeakng-loader --quiet
    "%PIP%" install kokoro>=0.9.2 --quiet
)
REM Also install misaki for better phonemisation
"%PIP%" install misaki[en] --quiet 2>nul

REM Step 5: Verify
echo [5/5] Verifying installation...
"%PYTHON%" -c "import flask; print('  flask        OK')"
"%PYTHON%" -c "import torch; print('  torch        OK, CUDA:', torch.cuda.is_available())"
"%PYTHON%" -c "import soundfile; print('  soundfile    OK')"
"%PYTHON%" -c "from TTS.api import TTS; print('  Coqui TTS    OK (best quality + voice clone)')" 2>nul || echo   Coqui TTS    NOT available
"%PYTHON%" -c "from kokoro import KPipeline; print('  Kokoro TTS   OK (high quality fallback)')" 2>nul || echo   Kokoro TTS   NOT available

echo.
echo  Done! TTS server is ready.
echo.
goto :end

:error
echo.
echo  ERROR: Base dependency installation failed.
echo  Please run manually:
echo    %PIP% install flask soundfile numpy^<2
echo.

:end
pause
