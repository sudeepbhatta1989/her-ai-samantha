@echo off
REM ════════════════════════════════════════════════════════════════
REM  LAMBDA REBUILD v6 — Linux-compatible wheels
REM  Key fix: --platform manylinux2014_x86_64 --only-binary=:all:
REM  This downloads Linux wheels even when running on Windows.
REM  Lambda runs on Amazon Linux 2 (x86_64) — needs Linux binaries.
REM  Lambda source: C:\Projects\her-ai-samantha\backend\lambda\
REM ════════════════════════════════════════════════════════════════

SET REGION=ap-south-1
SET ACCOUNT=966899696144
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
IF NOT EXIST "%LAMBDA_SRC%\her_ai_content.py" (echo ERROR: her_ai_content.py not found & pause & exit /b 1)
IF NOT EXIST "%LAMBDA_SRC%\her_ai_notifier.py" (echo ERROR: her_ai_notifier.py not found & pause & exit /b 1)
IF NOT EXIST "%LAMBDA_SRC%\her_ai_strategy.py" (echo ERROR: her_ai_strategy.py not found & pause & exit /b 1)
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
echo  Phase G Lambdas (content + notifier)
echo ====================================================

REM ── Package and deploy her-ai-content ──
copy "%LAMBDA_SRC%\her_ai_content.py" "%WORK_DIR%\her_ai_content.py" >NUL
cd /d "%WORK_DIR%"
powershell -Command "Compress-Archive -Path 'her_ai_content.py' -DestinationPath 'content.zip' -Force" >NUL
aws lambda create-function --function-name her-ai-content --runtime python3.11 --role arn:aws:iam::%ACCOUNT%:role/her-ai-lambda-role --handler her_ai_content.lambda_handler --zip-file fileb://content.zip --timeout 120 --memory-size 256 --region %REGION% --output text >NUL 2>&1
aws lambda update-function-code --function-name her-ai-content --zip-file fileb://content.zip --region %REGION% --output text >NUL
aws lambda update-function-configuration --function-name her-ai-content --environment "Variables={GROQ_API_KEY=%GROQ_KEY%,SERPER_API_KEY=%SERPER_KEY%}" --timeout 120 --region %REGION% --output text >NUL
echo   her-ai-content deployed

REM ── Package and deploy her-ai-notifier ──
copy "%LAMBDA_SRC%\her_ai_notifier.py" "%WORK_DIR%\her_ai_notifier.py" >NUL
powershell -Command "Compress-Archive -Path 'her_ai_notifier.py' -DestinationPath 'notifier.zip' -Force" >NUL
aws lambda create-function --function-name her-ai-notifier --runtime python3.11 --role arn:aws:iam::%ACCOUNT%:role/her-ai-lambda-role --handler her_ai_notifier.lambda_handler --zip-file fileb://notifier.zip --timeout 60 --memory-size 128 --region %REGION% --output text >NUL 2>&1
aws lambda update-function-code --function-name her-ai-notifier --zip-file fileb://notifier.zip --region %REGION% --output text >NUL
aws lambda update-function-configuration --function-name her-ai-notifier --environment "Variables={GROQ_API_KEY=%GROQ_KEY%}" --timeout 60 --region %REGION% --output text >NUL
echo   her-ai-notifier deployed

REM ── Package and deploy her-ai-strategy ──
copy "%LAMBDA_SRC%\her_ai_strategy.py" "%WORK_DIR%\her_ai_strategy.py" >NUL
powershell -Command "Compress-Archive -Path 'her_ai_strategy.py' -DestinationPath 'strategy.zip' -Force" >NUL
aws lambda create-function --function-name her-ai-strategy --runtime python3.11 --role arn:aws:iam::%ACCOUNT%:role/her-ai-lambda-role --handler her_ai_strategy.lambda_handler --zip-file fileb://strategy.zip --timeout 180 --memory-size 256 --region %REGION% --output text >NUL 2>&1
aws lambda update-function-code --function-name her-ai-strategy --zip-file fileb://strategy.zip --region %REGION% --output text >NUL
aws lambda update-function-configuration --function-name her-ai-strategy --environment "Variables={GROQ_API_KEY=%GROQ_KEY%}" --timeout 180 --region %REGION% --output text >NUL
echo   her-ai-strategy deployed

REM ── EventBridge: strategy on 1st of every month at 8 AM IST (02:30 UTC) ──
aws events put-rule --name her-ai-strategy-monthly --schedule-expression "cron(30 2 1 * ? *)" --state ENABLED --region %REGION% --output text >NUL
aws lambda add-permission --function-name her-ai-strategy --statement-id events-strategy --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn arn:aws:events:%REGION%:%ACCOUNT%:rule/her-ai-strategy-monthly --region %REGION% --output text >NUL 2>&1
aws events put-targets --rule her-ai-strategy-monthly --targets "Id=1,Arn=arn:aws:lambda:%REGION%:%ACCOUNT%:function:her-ai-strategy" --region %REGION% --output text >NUL
echo   EventBridge: her-ai-strategy on 1st of every month 8 AM IST

REM ── EventBridge: daily script at 7 PM IST (13:30 UTC) ──
aws events put-rule --name her-ai-content-daily --schedule-expression "cron(30 13 * * ? *)" --state ENABLED --region %REGION% --output text >NUL
aws lambda add-permission --function-name her-ai-content --statement-id events-content --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn arn:aws:events:%REGION%:%ACCOUNT%:rule/her-ai-content-daily --region %REGION% --output text >NUL 2>&1
aws events put-targets --rule her-ai-content-daily --targets "Id=1,Arn=arn:aws:lambda:%REGION%:%ACCOUNT%:function:her-ai-content" --region %REGION% --output text >NUL
echo   EventBridge: her-ai-content at 7 PM IST

REM ── EventBridge: notifier every 15 min ──
aws events put-rule --name her-ai-notifier-15min --schedule-expression "rate(15 minutes)" --state ENABLED --region %REGION% --output text >NUL
aws lambda add-permission --function-name her-ai-notifier --statement-id events-notifier --action lambda:InvokeFunction --principal events.amazonaws.com --source-arn arn:aws:events:%REGION%:%ACCOUNT%:rule/her-ai-notifier-15min --region %REGION% --output text >NUL 2>&1
aws events put-targets --rule her-ai-notifier-15min --targets "Id=1,Arn=arn:aws:lambda:%REGION%:%ACCOUNT%:function:her-ai-notifier" --region %REGION% --output text >NUL
echo   EventBridge: her-ai-notifier every 15 min

echo.
echo ====================================================
echo  DONE - 6 Lambdas active
echo  Run copy_firebase_key.ps1 to sync Firebase to new Lambdas
echo  (Right-click copy_firebase_key.ps1 -> Run with PowerShell)
echo ====================================================
pause
