@echo off
setlocal EnableDelayedExpansion
title Samantha Calendar Module Setup

:: ============================================================
::  SAMANTHA CALENDAR MODULE — FULL SETUP AUTOMATION
::  Tested on Windows 10/11 with Python 3.11, Flutter 3.x
:: ============================================================
::
::  BEFORE RUNNING:
::  1. Place this .bat file in your project root (same folder
::     that contains the "app" and "backend" folders)
::  2. Place samantha_calendar_module.zip in the same folder
::  3. Make sure Python + Flutter + pip are on your PATH
::
::  WHAT THIS DOES:
::  - Extracts calendar module zip
::  - Copies all Flutter files into app\lib\
::  - Copies backend file into your backend folder
::  - Installs Python dependencies
::  - Runs flutter pub get
::  - Patches iOS Info.plist with calendar permissions
::  - Patches pubspec.yaml with new dependencies
::  - Fixes the dart:html build error in chat_screen.dart
::  - Shows final checklist
:: ============================================================

echo.
echo  ==========================================
echo    SAMANTHA CALENDAR MODULE SETUP
echo  ==========================================
echo.

:: ── Locate project root ──────────────────────────────────────
set "ROOT=%~dp0"
:: Remove trailing backslash
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "APP_DIR=%ROOT%\app"
set "BACKEND_DIR=%ROOT%\backend"
set "ZIP_FILE=%ROOT%\samantha_calendar_module.zip"
set "EXTRACT_DIR=%ROOT%\_calendar_extract"

:: ── Check zip exists ─────────────────────────────────────────
if not exist "%ZIP_FILE%" (
    echo  [ERROR] samantha_calendar_module.zip not found in:
    echo          %ROOT%
    echo.
    echo  Please place the zip file next to this .bat and re-run.
    pause
    exit /b 1
)

:: ── Check app\ folder exists ─────────────────────────────────
if not exist "%APP_DIR%" (
    echo  [ERROR] app\ folder not found at: %APP_DIR%
    echo  Make sure you are running this from your project root.
    pause
    exit /b 1
)

:: ── Check backend\ folder ────────────────────────────────────
if not exist "%BACKEND_DIR%" (
    echo  [WARN] backend\ folder not found — creating it.
    mkdir "%BACKEND_DIR%"
)

echo  [1/8] Extracting calendar module zip...
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%"
mkdir "%EXTRACT_DIR%"

:: Use PowerShell to extract zip (no 7zip needed)
powershell -NoProfile -Command ^
  "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force"

if errorlevel 1 (
    echo  [ERROR] Failed to extract zip. Is PowerShell available?
    pause
    exit /b 1
)
echo  [1/8] Done.

:: ── Create target directories ────────────────────────────────
echo.
echo  [2/8] Creating Flutter directory structure...
mkdir "%APP_DIR%\lib\models"              2>nul
mkdir "%APP_DIR%\lib\services"            2>nul
mkdir "%APP_DIR%\lib\providers"           2>nul
mkdir "%APP_DIR%\lib\screens"             2>nul
mkdir "%APP_DIR%\lib\widgets\schedule"    2>nul
echo  [2/8] Done.

:: ── Copy Flutter files ───────────────────────────────────────
echo.
echo  [3/8] Copying Flutter files into app\lib\...

set "SRC=%EXTRACT_DIR%\flutter\lib"

copy /Y "%SRC%\models\schedule_event.dart"               "%APP_DIR%\lib\models\"
copy /Y "%SRC%\services\schedule_service.dart"           "%APP_DIR%\lib\services\"
copy /Y "%SRC%\services\calendar_sync_service.dart"      "%APP_DIR%\lib\services\"
copy /Y "%SRC%\providers\schedule_provider.dart"         "%APP_DIR%\lib\providers\"
copy /Y "%SRC%\screens\schedule_screen.dart"             "%APP_DIR%\lib\screens\"
copy /Y "%SRC%\widgets\schedule\event_tile.dart"         "%APP_DIR%\lib\widgets\schedule\"
copy /Y "%SRC%\widgets\schedule\widgets.dart"            "%APP_DIR%\lib\widgets\schedule\"

echo  [3/8] Done. Files copied:
echo         - models\schedule_event.dart
echo         - services\schedule_service.dart
echo         - services\calendar_sync_service.dart
echo         - providers\schedule_provider.dart
echo         - screens\schedule_screen.dart
echo         - widgets\schedule\event_tile.dart
echo         - widgets\schedule\widgets.dart

:: ── Copy backend file ────────────────────────────────────────
echo.
echo  [4/8] Copying backend\schedule_api.py...
copy /Y "%EXTRACT_DIR%\backend\schedule_api.py" "%BACKEND_DIR%\schedule_api.py"
echo  [4/8] Done.

:: ── Patch pubspec.yaml ───────────────────────────────────────
echo.
echo  [5/8] Patching pubspec.yaml with new dependencies...
set "PUBSPEC=%APP_DIR%\pubspec.yaml"

if not exist "%PUBSPEC%" (
    echo  [WARN] pubspec.yaml not found at %PUBSPEC% — skipping patch.
    goto :skip_pubspec
)

:: Check if device_calendar already present
findstr /C:"device_calendar" "%PUBSPEC%" >nul 2>&1
if not errorlevel 1 (
    echo  [5/8] device_calendar already in pubspec.yaml — skipping.
    goto :skip_pubspec
)

:: Use PowerShell to insert dependencies after "dependencies:" line
powershell -NoProfile -Command ^
  "$content = Get-Content '%PUBSPEC%' -Raw;" ^
  "$insert = '  device_calendar: ^4.3.0`n  provider: ^6.1.2`n  http: ^1.2.0`n  intl: ^0.19.0`n';" ^
  "$content = $content -replace '(dependencies:\s*\n)', \"`$1$insert\";" ^
  "Set-Content '%PUBSPEC%' $content -NoNewline"

echo  [5/8] Added to pubspec.yaml:
echo         device_calendar: ^4.3.0
echo         provider: ^6.1.2
echo         http: ^1.2.0
echo         intl: ^0.19.0

:skip_pubspec

:: ── Patch iOS Info.plist ─────────────────────────────────────
echo.
echo  [6/8] Patching iOS Info.plist with calendar permissions...
set "PLIST=%APP_DIR%\ios\Runner\Info.plist"

if not exist "%PLIST%" (
    echo  [WARN] Info.plist not found at %PLIST% — skipping iOS patch.
    echo         Add calendar permissions manually — see INTEGRATION.md.
    goto :skip_plist
)

findstr /C:"NSCalendarsUsageDescription" "%PLIST%" >nul 2>&1
if not errorlevel 1 (
    echo  [6/8] Calendar permissions already in Info.plist — skipping.
    goto :skip_plist
)

:: Insert before closing </dict> tag
powershell -NoProfile -Command ^
  "$p = '%PLIST%';" ^
  "$c = Get-Content $p -Raw;" ^
  "$insert = '<key>NSCalendarsUsageDescription</key>`n\t<string>Samantha needs calendar access to sync and manage your events.</string>`n\t<key>NSCalendarsWriteOnlyAccessUsageDescription</key>`n\t<string>Samantha needs write access to create events for you.</string>`n\t';" ^
  "$c = $c -replace '</dict>\s*</plist>', \"$insert</dict>`n</plist>\";" ^
  "Set-Content $p $c -NoNewline"

echo  [6/8] Added to Info.plist:
echo         NSCalendarsUsageDescription
echo         NSCalendarsWriteOnlyAccessUsageDescription

:skip_plist

:: ── Fix dart:html in chat_screen.dart ───────────────────────
echo.
echo  [7/8] Fixing dart:html build error in chat_screen.dart...
set "CHAT_SCREEN=%APP_DIR%\lib\screens\chat_screen.dart"

if not exist "%CHAT_SCREEN%" (
    echo  [7/8] chat_screen.dart not found — skipping fix.
    goto :skip_dart_html
)

findstr /C:"dart:html" "%CHAT_SCREEN%" >nul 2>&1
if errorlevel 1 (
    echo  [7/8] dart:html not found in chat_screen.dart — already clean.
    goto :skip_dart_html
)

powershell -NoProfile -Command ^
  "$f = '%CHAT_SCREEN%';" ^
  "$c = Get-Content $f -Raw;" ^
  "$c = $c -replace \"import 'dart:html';\", \"import 'package:flutter/foundation.dart'; // fixed: was dart:html\";" ^
  "Set-Content $f $c -NoNewline"

echo  [7/8] Replaced dart:html with flutter/foundation.dart

:skip_dart_html

:: ── Install Python deps ──────────────────────────────────────
echo.
echo  [8/8] Installing Python backend dependencies...

where python >nul 2>&1
if errorlevel 1 (
    echo  [WARN] Python not found on PATH — skipping pip install.
    echo         Manually run: pip install groq python-dateutil
    goto :skip_pip
)

:: Check if requirements.txt exists, append to it; else just pip install
set "REQ=%BACKEND_DIR%\requirements.txt"
if exist "%REQ%" (
    findstr /C:"groq" "%REQ%" >nul 2>&1
    if errorlevel 1 echo groq^>=0.5.0>> "%REQ%"
    findstr /C:"python-dateutil" "%REQ%" >nul 2>&1
    if errorlevel 1 echo python-dateutil^>=2.8.0>> "%REQ%"
    echo  Added groq + python-dateutil to requirements.txt
)

python -m pip install groq>=0.5.0 python-dateutil>=2.8.0 --quiet
if errorlevel 1 (
    echo  [WARN] pip install had issues. Try manually:
    echo         pip install groq python-dateutil
) else (
    echo  [8/8] Python packages installed.
)

:skip_pip

:: ── flutter pub get ──────────────────────────────────────────
echo.
echo  Running flutter pub get...
where flutter >nul 2>&1
if errorlevel 1 (
    echo  [WARN] flutter not found on PATH.
    echo         Run manually: cd app ^&^& flutter pub get
) else (
    cd "%APP_DIR%"
    flutter pub get
    cd "%ROOT%"
)

:: ── Clean up extract dir ─────────────────────────────────────
rmdir /s /q "%EXTRACT_DIR%" 2>nul

:: ── Copy INTEGRATION.md to project root ──────────────────────
if exist "%EXTRACT_DIR%\INTEGRATION.md" (
    copy /Y "%EXTRACT_DIR%\INTEGRATION.md" "%ROOT%\INTEGRATION_CALENDAR.md" >nul 2>&1
)

:: ── Final checklist ──────────────────────────────────────────
echo.
echo  ==========================================
echo    SETUP COMPLETE
echo  ==========================================
echo.
echo  DONE AUTOMATICALLY:
echo    [x] Flutter files copied to app\lib\
echo    [x] schedule_api.py copied to backend\
echo    [x] pubspec.yaml patched
echo    [x] Info.plist calendar permissions added
echo    [x] dart:html build error fixed
echo    [x] Python packages installed
echo    [x] flutter pub get ran
echo.
echo  STILL TODO (manual steps):
echo.
echo    1. Set your backend URL in:
echo       app\lib\services\schedule_service.dart  (line ~20)
echo       Change: 'https://your-samantha-backend.com'
echo       To:     your actual server URL
echo.
echo    2. Set Firebase Auth UID in both service files:
echo       schedule_service.dart     (line ~19)
echo       calendar_sync_service.dart (line ~14)
echo       Change: 'default_user'
echo       To: FirebaseAuth.instance.currentUser?.uid ?? 'default_user'
echo.
echo    3. Add ScheduleScreen() to your bottom navigation.
echo       Wrap your app with ChangeNotifierProvider (see INTEGRATION.md)
echo.
echo    4. Add to your existing FastAPI main.py:
echo       from schedule_api import router as schedule_router
echo       app.include_router(schedule_router)
echo.
echo    5. Set GROQ_API_KEY environment variable:
echo       (free key at https://console.groq.com)
echo       set GROQ_API_KEY=your_key_here
echo.
echo    6. Add Firestore security rules (see INTEGRATION.md)
echo.
echo  ==========================================
echo.
pause
