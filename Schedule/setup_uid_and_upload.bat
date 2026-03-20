@echo off
setlocal EnableDelayedExpansion
title Samantha - Fix UID and Upload

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "LOG=%ROOT%\samantha_uid_setup_log.txt"
set "SA=%ROOT%\firebase-service-account.json"
set "JSON=%ROOT%\schedule_firestore.json"
set "UID_FILE=%ROOT%\samantha_uid.txt"
set "PY=%ROOT%\_uid_setup.py"
set "B64TXT=%ROOT%\_b64.txt"

echo. > "%LOG%"
echo ======================================================= >> "%LOG%"
echo   SAMANTHA UID SETUP LOG  %DATE% %TIME% >> "%LOG%"
echo ======================================================= >> "%LOG%"
echo.
echo  Samantha - UID Setup and Schedule Upload
echo  Log: %LOG%
echo.

if not exist "%SA%" (
    echo [FAIL] firebase-service-account.json missing >> "%LOG%"
    echo  ERROR: firebase-service-account.json not found in %ROOT%
    pause & exit /b 1
)
if not exist "%JSON%" (
    echo [FAIL] schedule_firestore.json missing >> "%LOG%"
    echo  ERROR: schedule_firestore.json not found. Run upload_schedule_to_firestore.bat first.
    pause & exit /b 1
)
echo [OK] Files found >> "%LOG%"

echo  Installing packages...
python -m pip install firebase-admin >> "%LOG%" 2>&1

echo. > "%B64TXT%"
echo CmltcG9ydCBzeXMsIGpzb24KU0FfS0VZICA9IHN5cy5hcmd2WzFdCkpTT05fSU4gPSBzeXMuYXJn >> "%B64TXT%"
echo dlsyXQpVSURfT1VUID0gc3lzLmFyZ3ZbM10KCnByaW50KCJbMV0gSW5pdGlhbGlzaW5nIEZpcmVi >> "%B64TXT%"
echo YXNlLi4uIiwgZmx1c2g9VHJ1ZSkKaW1wb3J0IGZpcmViYXNlX2FkbWluCmZyb20gZmlyZWJhc2Vf >> "%B64TXT%"
echo YWRtaW4gaW1wb3J0IGNyZWRlbnRpYWxzLCBmaXJlc3RvcmUgYXMgZnN0b3JlLCBhdXRoCgpjcmVk >> "%B64TXT%"
echo ID0gY3JlZGVudGlhbHMuQ2VydGlmaWNhdGUoU0FfS0VZKQpmaXJlYmFzZV9hZG1pbi5pbml0aWFs >> "%B64TXT%"
echo aXplX2FwcChjcmVkKQpkYiA9IGZzdG9yZS5jbGllbnQoKQpwcmludCgiWzFdIEZpcmViYXNlIGNv >> "%B64TXT%"
echo bm5lY3RlZCBPSyIsIGZsdXNoPVRydWUpCgojIE9wdGlvbiBBOiBVc2UgYSBmaXhlZCBwZXJzb25h >> "%B64TXT%"
echo bCBVSUQgKGp1c3QgY3JlYXRlIHVzZXIgb25jZSwgcmV1c2UgZm9yZXZlcikKcHJpbnQoIlsyXSBT >> "%B64TXT%"
echo ZXR0aW5nIHVwIHBlcnNvbmFsIHVzZXIuLi4iLCBmbHVzaD1UcnVlKQoKUEVSU09OQUxfRU1BSUwg >> "%B64TXT%"
echo PSAic2FtYW50aGFAcGVyc29uYWwubG9jYWwiClBFUlNPTkFMX1VJRCAgID0gInNhbWFudGhhX3Bl >> "%B64TXT%"
echo cnNvbmFsX3VzZXIiCgp0cnk6CiAgICB1c2VyID0gYXV0aC5nZXRfdXNlcihQRVJTT05BTF9VSUQp >> "%B64TXT%"
echo CiAgICBwcmludChmIlsyXSBVc2VyIGFscmVhZHkgZXhpc3RzOiB7dXNlci51aWR9IiwgZmx1c2g9 >> "%B64TXT%"
echo VHJ1ZSkKICAgIHVpZCA9IHVzZXIudWlkCmV4Y2VwdCBhdXRoLlVzZXJOb3RGb3VuZEVycm9yOgog >> "%B64TXT%"
echo ICAgdHJ5OgogICAgICAgICMgVHJ5IHRvIGNyZWF0ZSB3aXRoIGZpeGVkIFVJRAogICAgICAgIHVz >> "%B64TXT%"
echo ZXIgPSBhdXRoLmNyZWF0ZV91c2VyKAogICAgICAgICAgICB1aWQ9UEVSU09OQUxfVUlELAogICAg >> "%B64TXT%"
echo ICAgICAgICBkaXNwbGF5X25hbWU9IlN1ZGVlcCAoU2FtYW50aGEgT3duZXIpIiwKICAgICAgICAp >> "%B64TXT%"
echo CiAgICAgICAgcHJpbnQoZiJbMl0gQ3JlYXRlZCB1c2VyIHdpdGggVUlEOiB7dXNlci51aWR9Iiwg >> "%B64TXT%"
echo Zmx1c2g9VHJ1ZSkKICAgICAgICB1aWQgPSB1c2VyLnVpZAogICAgZXhjZXB0IEV4Y2VwdGlvbiBh >> "%B64TXT%"
echo cyBlOgogICAgICAgICMgRmFsbCBiYWNrIHRvIGVtYWlsL3Bhc3N3b3JkIHVzZXIKICAgICAgICB0 >> "%B64TXT%"
echo cnk6CiAgICAgICAgICAgIHVzZXIgPSBhdXRoLmdldF91c2VyX2J5X2VtYWlsKFBFUlNPTkFMX0VN >> "%B64TXT%"
echo QUlMKQogICAgICAgICAgICB1aWQgPSB1c2VyLnVpZAogICAgICAgICAgICBwcmludChmIlsyXSBV >> "%B64TXT%"
echo c2luZyBleGlzdGluZyBlbWFpbCB1c2VyOiB7dWlkfSIsIGZsdXNoPVRydWUpCiAgICAgICAgZXhj >> "%B64TXT%"
echo ZXB0IGF1dGguVXNlck5vdEZvdW5kRXJyb3I6CiAgICAgICAgICAgIHVzZXIgPSBhdXRoLmNyZWF0 >> "%B64TXT%"
echo ZV91c2VyKAogICAgICAgICAgICAgICAgZW1haWw9UEVSU09OQUxfRU1BSUwsCiAgICAgICAgICAg >> "%B64TXT%"
echo ICAgICBkaXNwbGF5X25hbWU9IlN1ZGVlcCAoU2FtYW50aGEgT3duZXIpIiwKICAgICAgICAgICAg >> "%B64TXT%"
echo KQogICAgICAgICAgICB1aWQgPSB1c2VyLnVpZAogICAgICAgICAgICBwcmludChmIlsyXSBDcmVh >> "%B64TXT%"
echo dGVkIGVtYWlsIHVzZXI6IHt1aWR9IiwgZmx1c2g9VHJ1ZSkKCiMgU2F2ZSBVSUQgdG8gZmlsZQp3 >> "%B64TXT%"
echo aXRoIG9wZW4oVUlEX09VVCwgInciKSBhcyBmOgogICAgZi53cml0ZSh1aWQpCnByaW50KGYiWzJd >> "%B64TXT%"
echo IFVJRCBzYXZlZDoge3VpZH0iLCBmbHVzaD1UcnVlKQoKIyBVcGxvYWQgc2NoZWR1bGUKcHJpbnQo >> "%B64TXT%"
echo ZiJbM10gVXBsb2FkaW5nIHNjaGVkdWxlIHRvIHVzZXJzL3t1aWR9L3NjaGVkdWxlIC4uLiIsIGZs >> "%B64TXT%"
echo dXNoPVRydWUpCndpdGggb3BlbihKU09OX0lOLCBlbmNvZGluZz0idXRmLTgiKSBhcyBmOgogICAg >> "%B64TXT%"
echo ZGF0YSA9IGpzb24ubG9hZChmKQoKZG9jcyA9IGRhdGEuZ2V0KCJldmVudHMiLCBkYXRhKSBpZiBp >> "%B64TXT%"
echo c2luc3RhbmNlKGRhdGEsIGRpY3QpIGVsc2UgZGF0YQppZiBpc2luc3RhbmNlKGRvY3MsIGRpY3Qp >> "%B64TXT%"
echo OgogICAgZG9jcyA9IGRvY3MuZ2V0KCJldmVudHMiLCBbXSkKCmNvbCA9IGRiLmNvbGxlY3Rpb24o >> "%B64TXT%"
echo InVzZXJzIikuZG9jdW1lbnQodWlkKS5jb2xsZWN0aW9uKCJzY2hlZHVsZSIpCmJhdCA9IGRiLmJh >> "%B64TXT%"
echo dGNoKCkKbiA9IDA7IHVwID0gMDsgZXJyID0gMAoKIyBDbGVhciBleGlzdGluZyBkb2NzIGZpcnN0 >> "%B64TXT%"
echo IHRvIGF2b2lkIGR1cGxpY2F0ZXMKcHJpbnQoIlszXSBDbGVhcmluZyBleGlzdGluZyBzY2hlZHVs >> "%B64TXT%"
echo ZS4uLiIsIGZsdXNoPVRydWUpCmV4aXN0aW5nID0gY29sLnN0cmVhbSgpCmRlbF9iYXRjaCA9IGRi >> "%B64TXT%"
echo LmJhdGNoKCkKZGVsX2NvdW50ID0gMApmb3IgZG9jIGluIGV4aXN0aW5nOgogICAgZGVsX2JhdGNo >> "%B64TXT%"
echo LmRlbGV0ZShkb2MucmVmZXJlbmNlKQogICAgZGVsX2NvdW50ICs9IDEKICAgIGlmIGRlbF9jb3Vu >> "%B64TXT%"
echo dCA9PSA0OTk6CiAgICAgICAgZGVsX2JhdGNoLmNvbW1pdCgpCiAgICAgICAgZGVsX2JhdGNoID0g >> "%B64TXT%"
echo ZGIuYmF0Y2goKQogICAgICAgIGRlbF9jb3VudCA9IDAKaWYgZGVsX2NvdW50ID4gMDoKICAgIGRl >> "%B64TXT%"
echo bF9iYXRjaC5jb21taXQoKQpwcmludChmIlszXSBDbGVhcmVkIGV4aXN0aW5nIGRvY3MiLCBmbHVz >> "%B64TXT%"
echo aD1UcnVlKQoKZm9yIGRvYyBpbiBkb2NzOgogICAgdHJ5OgogICAgICAgIGJhdC5zZXQoY29sLmRv >> "%B64TXT%"
echo Y3VtZW50KCksIGRvYykKICAgICAgICBuICs9IDE7IHVwICs9IDEKICAgICAgICBpZiBuID09IDQ5 >> "%B64TXT%"
echo OToKICAgICAgICAgICAgYmF0LmNvbW1pdCgpCiAgICAgICAgICAgIHByaW50KGYiICBiYXRjaCB7 >> "%B64TXT%"
echo dXB9IGNvbW1pdHRlZCIsIGZsdXNoPVRydWUpCiAgICAgICAgICAgIGJhdCA9IGRiLmJhdGNoKCk7 >> "%B64TXT%"
echo IG4gPSAwCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGV4OgogICAgICAgIHByaW50KGYiICBbV0FS >> "%B64TXT%"
echo Tl0ge2RvYy5nZXQoJ3RpdGxlJywnPycpfToge2V4fSIsIGZsdXNoPVRydWUpCiAgICAgICAgZXJy >> "%B64TXT%"
echo ICs9IDEKCmlmIG4gPiAwOgogICAgYmF0LmNvbW1pdCgpCgpwcmludChmIltET05FXSBVcGxvYWRl >> "%B64TXT%"
echo ZD17dXB9ICBFcnJvcnM9e2Vycn0iLCBmbHVzaD1UcnVlKQpwcmludChmIltET05FXSBZb3VyIFVJ >> "%B64TXT%"
echo RCBpczoge3VpZH0iLCBmbHVzaD1UcnVlKQpwcmludChmIltET05FXSBDb3B5IHRoaXMgVUlEIGlu >> "%B64TXT%"
echo dG8geW91ciBGbHV0dGVyIGFwcCEiLCBmbHVzaD1UcnVlKQpwcmludChmIlZpZXc6IGh0dHBzOi8v >> "%B64TXT%"
echo Y29uc29sZS5maXJlYmFzZS5nb29nbGUuY29tIiwgZmx1c2g9VHJ1ZSkK >> "%B64TXT%"

python -c "import base64,sys; data=open(sys.argv[1]).read().replace(chr(10),'').replace(chr(13),'').replace(' ',''); open(sys.argv[2],'wb').write(base64.b64decode(data))" "%B64TXT%" "%PY%"
del "%B64TXT%" 2>nul

echo [STEP] Running UID setup and upload >> "%LOG%"
echo.
python "%PY%" "%SA%" "%JSON%" "%UID_FILE%" 2>&1
set "EXIT=!ERRORLEVEL!"
del "%PY%" 2>nul

echo. >> "%LOG%"
echo Exit: !EXIT! >> "%LOG%"

if !EXIT! == 0 (
    echo.
    echo  ====================================
    echo    SETUP COMPLETE
    echo  ====================================
    echo.
    if exist "%UID_FILE%" (
        set /p SAVED_UID=< "%UID_FILE%"
        echo  Your Firebase UID: !SAVED_UID!
        echo  Saved to: %UID_FILE%
        echo.
        echo  NEXT STEP: Put this UID in your Flutter app:
        echo  In schedule_service.dart and calendar_sync_service.dart
        echo  replace: default_user
        echo  with:    !SAVED_UID!
    )
) else (
    echo  ERROR: Setup failed. Exit=!EXIT!
    notepad "%LOG%"
)
pause