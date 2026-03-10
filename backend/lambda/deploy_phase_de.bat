@echo off
REM ════════════════════════════════════════════════════════════════
REM  LAMBDA REBUILD v6 — Linux-compatible wheels
REM  Key fix: --platform manylinux2014_x86_64 --only-binary=:all:
REM  This downloads Linux wheels even when running on Windows.
REM  Lambda runs on Amazon Linux 2 (x86_64) — needs Linux binaries.
REM  Lambda source: C:\Projects\her-ai-samantha\backend\lambda\
REM ════════════════════════════════════════════════════════════════

SET REGION=ap-south-1
SET LAMBDA_SRC=C:\Projects\her-ai-samantha\backend\lambda
SET WORK_DIR=C:\Users\sudee\Downloads\lambda_build
SET REQ=%LAMBDA_SRC%\requirements.txt

echo.
echo ====================================================
echo   Lambda Rebuild v6 - Linux-compatible wheels
echo ====================================================
echo.

IF NOT EXIST "%LAMBDA_SRC%\handler.py" (echo ERROR: handler.py not found & pause & exit /b 1)
IF NOT EXIST "%LAMBDA_SRC%\her_ai_reflection.py" (echo ERROR: her_ai_reflection.py not found & pause & exit /b 1)
IF NOT EXIST "%LAMBDA_SRC%\her_ai_briefing.py" (echo ERROR: her_ai_briefing.py not found & pause & exit /b 1)
IF NOT EXIST "%REQ%" (echo ERROR: requirements.txt not found & pause & exit /b 1)
echo    OK - all files found

FOR /F "tokens=*" %%i IN ('aws lambda get-function-configuration --function-name her-ai-brain --region %REGION% --query "Environment.Variables.GROQ_API_KEY" --output text 2^>NUL') DO SET GROQ_KEY=%%i
FOR /F "tokens=*" %%i IN ('aws lambda get-function-configuration --function-name her-ai-brain --region %REGION% --query "Environment.Variables.SERPER_API_KEY" --output text 2^>NUL') DO SET SERPER_KEY=%%i
IF "%GROQ_KEY%"=="" (echo ERROR: Cannot read GROQ_API_KEY & pause & exit /b 1)
echo    OK - env vars read

IF EXIST "%WORK_DIR%" RMDIR /S /Q "%WORK_DIR%"
MKDIR "%WORK_DIR%\deps"
echo    OK - build dir clean

REM ════════════════════════════════════════════════════════════════
REM  Install Linux-compatible wheels
REM  --platform manylinux2014_x86_64 = Amazon Linux 2 compatible
REM  --python-version 3.11 = match Lambda runtime
REM  --only-binary=:all: = no source compilation (gets prebuilt .so files)
REM  --no-cache-dir = force fresh download
REM ════════════════════════════════════════════════════════════════
echo.
echo [3/6] Installing Linux-compatible wheels...
echo    (downloads manylinux2014_x86_64 binaries - ~2 minutes)
echo.

py -m pip install ^
    --target "%WORK_DIR%\deps" ^
    --platform manylinux2014_x86_64 ^
    --python-version 3.11 ^
    --only-binary=:all: ^
    --no-cache-dir ^
    --upgrade ^
    -r "%REQ%" ^
    --no-warn-script-location ^
    -q

IF ERRORLEVEL 1 (
    echo.
    echo ERROR: pip install failed.
    echo Retrying without --only-binary for packages without Linux wheels...
    py -m pip install ^
        --target "%WORK_DIR%\deps" ^
        --platform manylinux2014_x86_64 ^
        --python-version 3.11 ^
        --no-cache-dir ^
        --upgrade ^
        -r "%REQ%" ^
        --no-warn-script-location ^
        -q
    IF ERRORLEVEL 1 (echo ERROR: pip install failed both ways & pause & exit /b 1)
)

echo    OK - dependencies installed
echo.
echo Verifying key packages:
DIR "%WORK_DIR%\deps" /B | findstr /I "cryptography google_cloud_firestore firebase"
echo.

REM ════════════════════════════════════════════════════════════════
REM  BUILD AND DEPLOY
REM ════════════════════════════════════════════════════════════════

REM ── her-ai-brain ──────────────────────────────────────────────
echo [4/6] Building her-ai-brain...
MKDIR "%WORK_DIR%\brain"
xcopy "%WORK_DIR%\deps\*" "%WORK_DIR%\brain\" /E /Q /Y >NUL
COPY "%LAMBDA_SRC%\handler.py" "%WORK_DIR%\brain\handler.py" >NUL
powershell -Command "Compress-Archive -Path '%WORK_DIR%\brain\*' -DestinationPath '%WORK_DIR%\brain.zip' -Force"
IF NOT EXIST "%WORK_DIR%\brain.zip" (echo ERROR: brain.zip not created & pause & exit /b 1)
FOR %%F IN ("%WORK_DIR%\brain.zip") DO echo    Zip size: %%~zF bytes
aws lambda update-function-code --function-name her-ai-brain --zip-file "fileb://%WORK_DIR%\brain.zip" --region %REGION% --output text >NUL
IF ERRORLEVEL 1 (echo ERROR updating her-ai-brain & pause & exit /b 1)
:W1
timeout /t 5 /nobreak >NUL
FOR /F "tokens=*" %%s IN ('aws lambda get-function-configuration --function-name her-ai-brain --region %REGION% --query "LastUpdateStatus" --output text 2^>NUL') DO SET S=%%s
IF NOT "%S%"=="Successful" (echo    %S%... & GOTO W1)
echo    OK - her-ai-brain deployed

REM ── her-ai-reflection ─────────────────────────────────────────
echo [5/6] Building her-ai-reflection...
MKDIR "%WORK_DIR%\reflection"
xcopy "%WORK_DIR%\deps\*" "%WORK_DIR%\reflection\" /E /Q /Y >NUL
COPY "%LAMBDA_SRC%\her_ai_reflection.py" "%WORK_DIR%\reflection\handler.py" >NUL
powershell -Command "Compress-Archive -Path '%WORK_DIR%\reflection\*' -DestinationPath '%WORK_DIR%\reflection.zip' -Force"
aws lambda update-function-code --function-name her-ai-reflection --zip-file "fileb://%WORK_DIR%\reflection.zip" --region %REGION% --output text >NUL
:W2
timeout /t 5 /nobreak >NUL
FOR /F "tokens=*" %%s IN ('aws lambda get-function-configuration --function-name her-ai-reflection --region %REGION% --query "LastUpdateStatus" --output text 2^>NUL') DO SET S=%%s
IF NOT "%S%"=="Successful" (echo    %S%... & GOTO W2)
aws lambda update-function-configuration --function-name her-ai-reflection --environment "Variables={GROQ_API_KEY=%GROQ_KEY%,SERPER_API_KEY=%SERPER_KEY%}" --region %REGION% --output text >NUL
echo    OK - her-ai-reflection deployed

REM ── her-ai-briefing ───────────────────────────────────────────
echo [6/6] Building her-ai-briefing...
MKDIR "%WORK_DIR%\briefing"
xcopy "%WORK_DIR%\deps\*" "%WORK_DIR%\briefing\" /E /Q /Y >NUL
COPY "%LAMBDA_SRC%\her_ai_briefing.py" "%WORK_DIR%\briefing\handler.py" >NUL
powershell -Command "Compress-Archive -Path '%WORK_DIR%\briefing\*' -DestinationPath '%WORK_DIR%\briefing.zip' -Force"
aws lambda update-function-code --function-name her-ai-briefing --zip-file "fileb://%WORK_DIR%\briefing.zip" --region %REGION% --output text >NUL
:W3
timeout /t 5 /nobreak >NUL
FOR /F "tokens=*" %%s IN ('aws lambda get-function-configuration --function-name her-ai-briefing --region %REGION% --query "LastUpdateStatus" --output text 2^>NUL') DO SET S=%%s
IF NOT "%S%"=="Successful" (echo    %S%... & GOTO W3)
aws lambda update-function-configuration --function-name her-ai-briefing --environment "Variables={GROQ_API_KEY=%GROQ_KEY%,SERPER_API_KEY=%SERPER_KEY%}" --region %REGION% --output text >NUL
echo    OK - her-ai-briefing deployed

REM ── Smoke test ────────────────────────────────────────────────
echo.
echo Testing her-ai-brain (get_streaks)...
aws lambda invoke --function-name her-ai-brain --region %REGION% --payload "{\"userId\":\"user1\",\"action\":\"get_streaks\"}" --cli-binary-format raw-in-base64-out "%WORK_DIR%\smoke.json" --output text >NUL
type "%WORK_DIR%\smoke.json"
echo.
echo.
echo Testing her-ai-brain (chat)...
aws lambda invoke --function-name her-ai-brain --region %REGION% --payload "{\"userId\":\"user1\",\"message\":\"hi\"}" --cli-binary-format raw-in-base64-out "%WORK_DIR%\smoke2.json" --output text >NUL
type "%WORK_DIR%\smoke2.json"
echo.

echo ====================================================
echo  DONE
echo  SUCCESS = see streaks/reply above, no ImportModuleError
echo  REMINDER: Add FIREBASE_SERVICE_ACCOUNT to:
echo    her-ai-reflection + her-ai-briefing in Lambda Console
echo ====================================================
pause
