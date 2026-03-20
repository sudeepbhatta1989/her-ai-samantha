@echo off
setlocal EnableDelayedExpansion
title Samantha - Schedule Upload

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "LOG=%ROOT%\samantha_upload_log.txt"
set "XLSX=%ROOT%\My_Schedule.xlsx"
set "SA=%ROOT%\firebase-service-account.json"
set "PY=%ROOT%\_uploader.py"
set "B64TXT=%ROOT%\_b64.txt"
set "JSON=%ROOT%\schedule_firestore.json"

echo. > "%LOG%"
echo ======================================================= >> "%LOG%"
echo   SAMANTHA UPLOAD LOG  %DATE% %TIME% >> "%LOG%"
echo ======================================================= >> "%LOG%"
echo. >> "%LOG%"
echo.
echo  Samantha Schedule Uploader
echo  Log: %LOG%
echo.

where python >> "%LOG%" 2>&1
python --version >> "%LOG%" 2>&1
if errorlevel 1 (
    echo [FAIL] Python not found >> "%LOG%"
    echo  ERROR: Python not found. Install from python.org
    notepad "%LOG%" & pause & exit /b 1
)
echo [OK] Python found >> "%LOG%"

if not exist "%XLSX%" (
    echo [FAIL] My_Schedule.xlsx missing >> "%LOG%"
    echo  ERROR: My_Schedule.xlsx not found in %ROOT%
    notepad "%LOG%" & pause & exit /b 1
)
echo [OK] My_Schedule.xlsx found >> "%LOG%"

if not exist "%SA%" (
    echo [FAIL] firebase-service-account.json missing >> "%LOG%"
    echo  ERROR: firebase-service-account.json not found.
    echo  Get it: Firebase Console ^> Project Settings ^> Service Accounts ^> Generate new private key
    notepad "%LOG%" & pause & exit /b 1
)
echo [OK] firebase-service-account.json found >> "%LOG%"
echo. >> "%LOG%"

echo [STEP 1] pip install >> "%LOG%"
echo  Installing packages...
python -m pip install openpyxl firebase-admin >> "%LOG%" 2>&1
if errorlevel 1 (
    echo [FAIL] pip install failed >> "%LOG%"
    echo  ERROR: pip install failed. See %LOG%
    notepad "%LOG%" & pause & exit /b 1
)
echo [OK] pip install done >> "%LOG%"
echo. >> "%LOG%"

echo [STEP 2] Writing Python script >> "%LOG%"
echo. > "%B64TXT%"
echo aW1wb3J0IGpzb24sIHN5cywgcmUKZnJvbSBkYXRldGltZSBpbXBvcnQgZGF0ZXRpbWUsIHRpbWVk >> "%B64TXT%"
echo ZWx0YQoKWExTWF9QQVRIID0gc3lzLmFyZ3ZbMV0KU0FfS0VZICAgID0gc3lzLmFyZ3ZbMl0KSlNP >> "%B64TXT%"
echo Tl9PVVQgID0gc3lzLmFyZ3ZbM10KCnByaW50KCdbMV0gUGFyc2luZyBFeGNlbC4uLicsIGZsdXNo >> "%B64TXT%"
echo PVRydWUpCgppbXBvcnQgb3BlbnB5eGwKCkNBVEVHT1JZX01BUCA9IHsKICAgICdleGVyY2lzZSc6 >> "%B64TXT%"
echo J2V4ZXJjaXNlJywncnVubmluZyc6J2V4ZXJjaXNlJywncGVuY2lsIHNrZXRjaCc6J3BlcnNvbmFs >> "%B64TXT%"
echo JywKICAgICdza2V0Y2gnOidwZXJzb25hbCcsJ3VrdWxlbGUnOidwZXJzb25hbCcsJ3Bob2thdCBr >> "%B64TXT%"
echo YSBneWFuJzonZGVlcFdvcmsnLAogICAgJ2RlYmF0ZSB2aWRlbyc6J2RlZXBXb3JrJywndHJhdmVs >> "%B64TXT%"
echo ZXIgdHJlZSc6J2RlZXBXb3JrJywnc2FwbmEgY2FudmFzJzond29yaycsCiAgICAnb2ZmaWNlJzon >> "%B64TXT%"
echo d29yaycsJ3dvcmsnOid3b3JrJywnZ2l0YSBhcHAnOidkZWVwV29yaycsJ3NhbWFudGhhJzonZGVl >> "%B64TXT%"
echo cFdvcmsnLAogICAgJ2NvbnRlbnQnOid3b3JrJywnc2hvcnQnOid3b3JrJywncmVlbCc6J3dvcmsn >> "%B64TXT%"
echo LCdiYXRjaCByZWNvcmQnOid3b3JrJywKICAgICdwdWJsaXNoJzond29yaycsJ2VkaXRpbmcnOid3 >> "%B64TXT%"
echo b3JrJywncGxhbic6J3dvcmsnLCdtb3JuaW5nIHJvdXRpbmUnOidwZXJzb25hbCcsCiAgICAnYmF0 >> "%B64TXT%"
echo aHJvb20nOidwZXJzb25hbCcsJ2dldCBkcmVzc2VkJzoncGVyc29uYWwnLCdicmVha2Zhc3QnOidw >> "%B64TXT%"
echo ZXJzb25hbCcsCiAgICAnZGlubmVyJzoncGVyc29uYWwnLCdyZXN0JzoncGVyc29uYWwnLCdidXMn >> "%B64TXT%"
echo OidnZW5lcmFsJywncmVhY2ggaG9tZSc6J2dlbmVyYWwnLAogICAgJ2dhbWUgZGV2ZWxvcG1lbnQn >> "%B64TXT%"
echo OidkZWVwV29yaycsJ2xlYXJuaW5nJzonZGVlcFdvcmsnLCdibG9ncyc6J2RlZXBXb3JrJywKICAg >> "%B64TXT%"
echo ICdtYXJrZXRpbmcnOid3b3JrJywnd2Vic2l0ZSc6J2RlZXBXb3JrJywKfQpQUklPUklUWV9NQVAg >> "%B64TXT%"
echo PSB7CiAgICAnb2ZmaWNlJzonY3JpdGljYWwnLCd3b3JrJzonY3JpdGljYWwnLCdjb3Jwb3JhdGUg >> "%B64TXT%"
echo a3VydWtzaGV0cmEnOidjcml0aWNhbCcsCiAgICAncHVibGlzaCc6J2NyaXRpY2FsJywnZXhlcmNp >> "%B64TXT%"
echo c2UnOidoaWdoJywncnVubmluZyc6J2hpZ2gnLAogICAgJ3RyYXZlbGVyIHRyZWUnOidtZWRpdW0n >> "%B64TXT%"
echo LCdzYXBuYSBjYW52YXMnOidtZWRpdW0nLCdwaG9rYXQga2EgZ3lhbic6J21lZGl1bScsCiAgICAn >> "%B64TXT%"
echo Z2l0YSBhcHAnOidtZWRpdW0nLCdzYW1hbnRoYSc6J21lZGl1bScsJ3BlbmNpbCBza2V0Y2gnOidt >> "%B64TXT%"
echo ZWRpdW0nLAogICAgJ3VrdWxlbGUnOidtZWRpdW0nLCdnYW1lIGRldmVsb3BtZW50JzonbWVkaXVt >> "%B64TXT%"
echo JywnZGViYXRlIHZpZGVvJzonbWVkaXVtJywKICAgICdkaW5uZXInOidsb3cnLCdicmVha2Zhc3Qn >> "%B64TXT%"
echo Oidsb3cnLCdyZXN0JzonbG93JywnbW9ybmluZyByb3V0aW5lJzonbG93JywKICAgICdiYXRocm9v >> "%B64TXT%"
echo bSc6J2xvdycsJ2dldCBkcmVzc2VkJzonbG93JywnYnVzJzonbG93JywncmVhY2ggaG9tZSc6J2xv >> "%B64TXT%"
echo dycsJ3BsYW4nOidsb3cnLAp9ClRBR1NfTUFQID0gewogICAgJ2NvcnBvcmF0ZSBrdXJ1a3NoZXRy >> "%B64TXT%"
echo YSc6WydwaG9rYXRrYWd5YW4nLCdjb250ZW50J10sCiAgICAnZGViYXRlIHZpZGVvJzpbJ3Bob2th >> "%B64TXT%"
echo dGthZ3lhbicsJ3ZpZGVvJ10sCiAgICAnc2hvcnQnOlsncGhva2F0a2FneWFuJywnY29udGVudCdd >> "%B64TXT%"
echo LCdyZWVsJzpbJ3Bob2thdGthZ3lhbicsJ2NvbnRlbnQnXSwKICAgICd0cmF2ZWxlciB0cmVlJzpb >> "%B64TXT%"
echo J3RyYXZlbGVydHJlZSddLCdzYXBuYSBjYW52YXMnOlsnc2FwbmFjYW52YXMnXSwKICAgICdnaXRh >> "%B64TXT%"
echo IGFwcCc6WydnaXRhYXBwJ10sJ3NhbWFudGhhJzpbJ3NhbWFudGhhYWknXSwKICAgICdwaG9rYXQg >> "%B64TXT%"
echo a2EgZ3lhbic6WydwaG9rYXRrYWd5YW4nXSwnZXhlcmNpc2UnOlsnaGVhbHRoJywnZml0bmVzcydd >> "%B64TXT%"
echo LAogICAgJ3VrdWxlbGUnOlsnbXVzaWMnLCdjcmVhdGl2ZSddLCdwZW5jaWwgc2tldGNoJzpbJ2Fy >> "%B64TXT%"
echo dCcsJ2NyZWF0aXZlJ10sCn0KUkVDVVJSSU5HID0gewogICAgJ2V4ZXJjaXNlJzooVHJ1ZSwnZGFp >> "%B64TXT%"
echo bHknKSwncnVubmluZyc6KFRydWUsJ2RhaWx5JyksCiAgICAndWt1bGVsZSc6KFRydWUsJ2RhaWx5 >> "%B64TXT%"
echo JyksJ3BlbmNpbCBza2V0Y2gnOihUcnVlLCdkYWlseScpLAogICAgJ3NrZXRjaCc6KFRydWUsJ2Rh >> "%B64TXT%"
echo aWx5JyksJ29mZmljZSB3b3JrJzooVHJ1ZSwnd2Vla2RheXMnKSwKICAgICdidXMgZnJvbSc6KFRy >> "%B64TXT%"
echo dWUsJ3dlZWtkYXlzJyksJ3JlYWNoIGhvbWUnOihUcnVlLCd3ZWVrZGF5cycpLAogICAgJ2JyZWFr >> "%B64TXT%"
echo ZmFzdCc6KFRydWUsJ2RhaWx5JyksJ2JhdGhyb29tJzooVHJ1ZSwnZGFpbHknKSwKICAgICdnZXQg >> "%B64TXT%"
echo ZHJlc3NlZCc6KFRydWUsJ2RhaWx5JyksJ2Rpbm5lcic6KFRydWUsJ2RhaWx5JyksCiAgICAnY29y >> "%B64TXT%"
echo cG9yYXRlIGt1cnVrc2hldHJhIHB1Ymxpc2hlZCc6KFRydWUsJ3dlZWtseScpLAogICAgJ2NvcnBv >> "%B64TXT%"
echo cmF0ZSBrdXJ1a3NoZXRyYSBwcmVwJzooVHJ1ZSwnd2Vla2x5JyksCiAgICAnYmF0Y2ggcmVjb3Jk >> "%B64TXT%"
echo JzooVHJ1ZSwnd2Vla2x5JyksJ3BsYW4gbmV4dCB3ZWVrJzooVHJ1ZSwnd2Vla2x5JyksCiAgICAn >> "%B64TXT%"
echo ZGViYXRlIHZpZGVvJzooVHJ1ZSwnd2Vla2x5JyksCiAgICAneW91dHViZSBzaG9ydCArIGluc3Rh >> "%B64TXT%"
echo Z3JhbSByZWVsIHB1Ymxpc2hlZCc6KFRydWUsJ3dlZWtkYXlzJyksCn0KREFZX09SREVSID0gWydN >> "%B64TXT%"
echo b25kYXknLCdUdWVzZGF5JywnV2VkbmVzZGF5JywnVGh1cnNkYXknLCdGcmlkYXknLCdTYXR1cmRh >> "%B64TXT%"
echo eScsJ1N1bmRheSddCkRBWV9XRCA9IHtkOmkgZm9yIGksZCBpbiBlbnVtZXJhdGUoREFZX09SREVS >> "%B64TXT%"
echo KX0KCmRlZiBjbGFzc2lmeSh0KToKICAgIHQ9dC5sb3dlcigpOyBjYXQscHJpLHRhZ3M9J2dlbmVy >> "%B64TXT%"
echo YWwnLCdtZWRpdW0nLFtdCiAgICBmb3Igayx2IGluIENBVEVHT1JZX01BUC5pdGVtcygpOgogICAg >> "%B64TXT%"
echo ICAgIGlmIGsgaW4gdDogY2F0PXY7IGJyZWFrCiAgICBmb3Igayx2IGluIFBSSU9SSVRZX01BUC5p >> "%B64TXT%"
echo dGVtcygpOgogICAgICAgIGlmIGsgaW4gdDogcHJpPXY7IGJyZWFrCiAgICBmb3Igayx2IGluIFRB >> "%B64TXT%"
echo R1NfTUFQLml0ZW1zKCk6CiAgICAgICAgaWYgayBpbiB0OiB0YWdzPXY7IGJyZWFrCiAgICByZXR1 >> "%B64TXT%"
echo cm4gY2F0LHByaSx0YWdzCgpkZWYgZ2V0X3JlYyh0KToKICAgIHQ9dC5sb3dlcigpCiAgICBmb3Ig >> "%B64TXT%"
echo aywocixydWxlKSBpbiBSRUNVUlJJTkcuaXRlbXMoKToKICAgICAgICBpZiBrIGluIHQ6IHJldHVy >> "%B64TXT%"
echo biByLHJ1bGUKICAgIHJldHVybiBGYWxzZSxOb25lCgpkZWYgcGFyc2VfdHIodHMpOgogICAgaWYg >> "%B64TXT%"
echo bm90IHRzOiByZXR1cm4gTm9uZQogICAgdHM9c3RyKHRzKS5zdHJpcCgpCiAgICBzPXJlLm1hdGNo >> "%B64TXT%"
echo KHInXihcZHsxLDJ9KTooXGR7Mn0pKD86OlxkezJ9KT8kJyx0cykKICAgIGlmIHM6CiAgICAgICAg >> "%B64TXT%"
echo aCxtPWludChzLmdyb3VwKDEpKSxpbnQocy5ncm91cCgyKSk7IHJldHVybiBoLG0saCxtCiAgICB0 >> "%B64TXT%"
echo cz10cy5yZXBsYWNlKGNocig4MjExKSwnLScpLnJlcGxhY2UoY2hyKDgyMTIpLCctJykKICAgIHRz >> "%B64TXT%"
echo PXJlLnN1YihyJyhcZCs6XGQrKS9cZCs6XGQrJyxyJ1wxJyx0cykKICAgIHIyPXJlLm1hdGNoKHIn >> "%B64TXT%"
echo KFxkezEsMn0pOihcZHsyfSlccyotXHMqKFxkezEsMn0pOihcZHsyfSknLHRzKQogICAgaWYgcjI6 >> "%B64TXT%"
echo CiAgICAgICAgc2gsc209aW50KHIyLmdyb3VwKDEpKSxpbnQocjIuZ3JvdXAoMikpCiAgICAgICAg >> "%B64TXT%"
echo ZWgsZW09aW50KHIyLmdyb3VwKDMpKSxpbnQocjIuZ3JvdXAoNCkpCiAgICAgICAgaWYgZWg8c2gg >> "%B64TXT%"
echo YW5kIGVoPDEyOiBlaCs9MTIKICAgICAgICBpZiBlbT49NjA6IGVoKz1lbS8vNjA7IGVtPWVtJTYw >> "%B64TXT%"
echo CiAgICAgICAgcmV0dXJuIHNoLHNtLGVoLGVtCiAgICByZXR1cm4gTm9uZQoKZGVmIG53ZCh3ZCx0 >> "%B64TXT%"
echo b2RheT1Ob25lKToKICAgIHRvZGF5PXRvZGF5IG9yIGRhdGV0aW1lLm5vdygpCiAgICBkPXdkLXRv >> "%B64TXT%"
echo ZGF5LndlZWtkYXkoKQogICAgaWYgZDw9MDogZCs9NwogICAgcmV0dXJuIHRvZGF5K3RpbWVkZWx0 >> "%B64TXT%"
echo YShkYXlzPWQpCgp3Yj1vcGVucHl4bC5sb2FkX3dvcmtib29rKFhMU1hfUEFUSCkKd3M9d2IuYWN0 >> "%B64TXT%"
echo aXZlCnJhdz1bXQpjdXJfZGF5PSdNb25kYXknCgpmb3Igcm93IGluIHdzLml0ZXJfcm93cyh2YWx1 >> "%B64TXT%"
echo ZXNfb25seT1UcnVlKToKICAgIHR2PXN0cihyb3dbMF0pLnN0cmlwKCkgaWYgcm93WzBdIGVsc2Ug >> "%B64TXT%"
echo JycKICAgIGFjdD1zdHIocm93WzFdKS5zdHJpcCgpIGlmIHJvd1sxXSBlbHNlICcnCiAgICBpZiBu >> "%B64TXT%"
echo b3QgdHYgYW5kIG5vdCBhY3Q6IGNvbnRpbnVlCiAgICBjYj0odHYrJyAnK2FjdCkuc3RyaXAoKQog >> "%B64TXT%"
echo ICAgaWYgJ01vbmRheScgaW4gY2IgYW5kICdGcmlkYXknIGluIGNiIGFuZCAnTW9ybmluZycgaW4g >> "%B64TXT%"
echo Y2I6CiAgICAgICAgY3VyX2RheT0nV2Vla2RheSc7IGNvbnRpbnVlCiAgICBpZiAnV29yayBGcm9t >> "%B64TXT%"
echo IEhvbWUnIGluIGNiOiBjb250aW51ZQogICAgZm9yIGRheSBpbiBEQVlfT1JERVI6CiAgICAgICAg >> "%B64TXT%"
echo aWYgY2Iuc3RhcnRzd2l0aChkYXkpIGFuZCAoJ0V2ZW5pbmcnIGluIGNiIG9yICdEYXknIGluIGNi >> "%B64TXT%"
echo KToKICAgICAgICAgICAgY3VyX2RheT1kYXk7IGJyZWFrCiAgICBpZiB0di5sb3dlcigpIGluICgn >> "%B64TXT%"
echo dGltZScsJycpIGFuZCBhY3QubG93ZXIoKSBpbiAoJ2FjdGl2aXR5JywndGFzaycsJycpOiBjb250 >> "%B64TXT%"
echo aW51ZQogICAgcD1wYXJzZV90cih0dikKICAgIGlmIG5vdCBwOiBjb250aW51ZQogICAgc2gsc20s >> "%B64TXT%"
echo ZWgsZW09cAogICAgaWYgc2g9PWVoIGFuZCBzbT09ZW06CiAgICAgICAgaWYgJ2J1cycgaW4gYWN0 >> "%B64TXT%"
echo Lmxvd2VyKCk6IGVoLGVtPXNoKzEsc20rMzAKICAgICAgICBlbGlmICdwdWJsaXNoZWQnIGluIGFj >> "%B64TXT%"
echo dC5sb3dlcigpIG9yICdyZWVsJyBpbiBhY3QubG93ZXIoKTogZWgsZW09c2gsc20rMzAKICAgICAg >> "%B64TXT%"
echo ICBlbHNlOiBlaCxlbT1zaCxzbSszMAogICAgICAgIGlmIGVtPj02MDogZWgrPWVtLy82MDsgZW09 >> "%B64TXT%"
echo ZW0lNjAKICAgIGNhdCxwcmksdGFncz1jbGFzc2lmeShhY3QpCiAgICBpcixycj1nZXRfcmVjKGFj >> "%B64TXT%"
echo dCkKICAgIHJhdy5hcHBlbmQoeyd0aXRsZSc6YWN0LCdkYXknOmN1cl9kYXksJ3NoJzpzaCwnc20n >> "%B64TXT%"
echo OnNtLCdlaCc6ZWgsJ2VtJzplbSwKICAgICAgICAnY2F0JzpjYXQsJ3ByaSc6cHJpLCd0YWdzJzp0 >> "%B64TXT%"
echo YWdzLCdpcic6aXIsJ3JyJzpycn0pCgpwcmludChmJ1sxXSBQYXJzZWQge2xlbihyYXcpfSBhY3Rp >> "%B64TXT%"
echo dml0aWVzJywgZmx1c2g9VHJ1ZSkKCnRvZGF5PWRhdGV0aW1lLm5vdygpCmRvY3M9W10KZm9yIGV2 >> "%B64TXT%"
echo IGluIHJhdzoKICAgIGRuPWV2WydkYXknXQogICAgaWYgZG49PSdXZWVrZGF5JzogYW5jPW53ZCgw >> "%B64TXT%"
echo LHRvZGF5KQogICAgZWxpZiBkbiBpbiBEQVlfV0Q6IGFuYz1ud2QoREFZX1dEW2RuXSx0b2RheSkK >> "%B64TXT%"
echo ICAgIGVsc2U6IGFuYz10b2RheQogICAgcz1kYXRldGltZShhbmMueWVhcixhbmMubW9udGgsYW5j >> "%B64TXT%"
echo LmRheSxldlsnc2gnXSxldlsnc20nXSkKICAgIGU9ZGF0ZXRpbWUoYW5jLnllYXIsYW5jLm1vbnRo >> "%B64TXT%"
echo LGFuYy5kYXksZXZbJ2VoJ10sZXZbJ2VtJ10pCiAgICBpZiBlPHM6IGUrPXRpbWVkZWx0YShkYXlz >> "%B64TXT%"
echo PTEpCiAgICBkb2NzLmFwcGVuZCh7CiAgICAgICAgJ3RpdGxlJzpldlsndGl0bGUnXSwnZGVzY3Jp >> "%B64TXT%"
echo cHRpb24nOk5vbmUsCiAgICAgICAgJ3N0YXJ0VGltZSc6cy5pc29mb3JtYXQoKSwnZW5kVGltZSc6 >> "%B64TXT%"
echo ZS5pc29mb3JtYXQoKSwKICAgICAgICAncHJpb3JpdHknOmV2WydwcmknXSwnY2F0ZWdvcnknOmV2 >> "%B64TXT%"
echo WydjYXQnXSwnc291cmNlJzonc2FtYW50aGEnLAogICAgICAgICd0YWdzJzpldlsndGFncyddLCdp >> "%B64TXT%"
echo c1JlY3VycmluZyc6ZXZbJ2lyJ10sJ3JlY3VycmluZ1J1bGUnOmV2WydyciddLAogICAgICAgICdh >> "%B64TXT%"
echo aUdlbmVyYXRlZCc6VHJ1ZSwnYWlSZWFzb24nOidHZW5lcmF0ZWQgZnJvbSB1c2VyIHdlZWtseSB0 >> "%B64TXT%"
echo ZW1wbGF0ZSBzY2hlZHVsZScsCiAgICAgICAgJ2lzQ29uZmlybWVkJzpUcnVlLAogICAgfSkKCndp >> "%B64TXT%"
echo dGggb3BlbihKU09OX09VVCwndycsZW5jb2Rpbmc9J3V0Zi04JykgYXMgZjoKICAgIGpzb24uZHVt >> "%B64TXT%"
echo cCh7J2V2ZW50cyc6ZG9jcywndG90YWwnOmxlbihkb2NzKX0sZixpbmRlbnQ9MixkZWZhdWx0PXN0 >> "%B64TXT%"
echo cikKcHJpbnQoZidbMl0gU2F2ZWQge2xlbihkb2NzKX0gZXZlbnRzIHRvIHtKU09OX09VVH0nLCBm >> "%B64TXT%"
echo bHVzaD1UcnVlKQoKcHJpbnQoJ1szXSBDb25uZWN0aW5nIHRvIEZpcmViYXNlLi4uJywgZmx1c2g9 >> "%B64TXT%"
echo VHJ1ZSkKaW1wb3J0IGZpcmViYXNlX2FkbWluCmZyb20gZmlyZWJhc2VfYWRtaW4gaW1wb3J0IGNy >> "%B64TXT%"
echo ZWRlbnRpYWxzLCBmaXJlc3RvcmUgYXMgZnN0b3JlCnRyeToKICAgIGNyZWQ9Y3JlZGVudGlhbHMu >> "%B64TXT%"
echo Q2VydGlmaWNhdGUoU0FfS0VZKQogICAgZmlyZWJhc2VfYWRtaW4uaW5pdGlhbGl6ZV9hcHAoY3Jl >> "%B64TXT%"
echo ZCkKICAgIGRiPWZzdG9yZS5jbGllbnQoKQogICAgcHJpbnQoJ1szXSBGaXJlYmFzZSBjb25uZWN0 >> "%B64TXT%"
echo ZWQgT0snLCBmbHVzaD1UcnVlKQpleGNlcHQgRXhjZXB0aW9uIGFzIGV4OgogICAgcHJpbnQoZidb >> "%B64TXT%"
echo RkFJTF0gRmlyZWJhc2UgaW5pdCBlcnJvcjoge2V4fScsIGZsdXNoPVRydWUpCiAgICBzeXMuZXhp >> "%B64TXT%"
echo dCgxKQoKVUlEPWlucHV0KCdFbnRlciB5b3VyIEZpcmViYXNlIFVJRDogJykuc3RyaXAoKQppZiBu >> "%B64TXT%"
echo b3QgVUlEOgogICAgcHJpbnQoJ1tGQUlMXSBObyBVSUQgZW50ZXJlZC4nKTsgc3lzLmV4aXQoMSkK >> "%B64TXT%"
echo cHJpbnQoZidbNF0gVXBsb2FkaW5nIHtsZW4oZG9jcyl9IGV2ZW50cyB0byB1c2Vycy97VUlEfS9z >> "%B64TXT%"
echo Y2hlZHVsZSAuLi4nLCBmbHVzaD1UcnVlKQoKY29sPWRiLmNvbGxlY3Rpb24oJ3VzZXJzJykuZG9j >> "%B64TXT%"
echo dW1lbnQoVUlEKS5jb2xsZWN0aW9uKCdzY2hlZHVsZScpCmJhdD1kYi5iYXRjaCgpOyBuPTA7IHVw >> "%B64TXT%"
echo PTA7IGVycj0wCmZvciBkb2MgaW4gZG9jczoKICAgIHRyeToKICAgICAgICBiYXQuc2V0KGNvbC5k >> "%B64TXT%"
echo b2N1bWVudCgpLGRvYyk7IG4rPTE7IHVwKz0xCiAgICAgICAgaWYgbj09NDk5OgogICAgICAgICAg >> "%B64TXT%"
echo ICBiYXQuY29tbWl0KCkKICAgICAgICAgICAgcHJpbnQoZicgIGJhdGNoIHt1cH0gY29tbWl0dGVk >> "%B64TXT%"
echo JywgZmx1c2g9VHJ1ZSkKICAgICAgICAgICAgYmF0PWRiLmJhdGNoKCk7IG49MAogICAgZXhjZXB0 >> "%B64TXT%"
echo IEV4Y2VwdGlvbiBhcyBleDoKICAgICAgICBwcmludChmJyAgW1dBUk5dIHtkb2NbInRpdGxlIl19 >> "%B64TXT%"
echo OiB7ZXh9JywgZmx1c2g9VHJ1ZSk7IGVycis9MQppZiBuPjA6IGJhdC5jb21taXQoKQpwcmludChm >> "%B64TXT%"
echo J1tET05FXSBVcGxvYWRlZD17dXB9ICBFcnJvcnM9e2Vycn0nLCBmbHVzaD1UcnVlKQpwcmludChm >> "%B64TXT%"
echo J1ZpZXcgYXQ6IGh0dHBzOi8vY29uc29sZS5maXJlYmFzZS5nb29nbGUuY29tJywgZmx1c2g9VHJ1 >> "%B64TXT%"
echo ZSkK >> "%B64TXT%"

python -c "import base64,sys; data=open(sys.argv[1]).read().replace(chr(10),'').replace(chr(13),'').replace(' ',''); open(sys.argv[2],'wb').write(base64.b64decode(data))" "%B64TXT%" "%PY%"
if errorlevel 1 (
    echo [FAIL] Script decode failed >> "%LOG%"
    echo  ERROR: Script decode failed.
    notepad "%LOG%" & pause & exit /b 1
)
del "%B64TXT%" 2>nul
echo [OK] Python script ready >> "%LOG%"
echo. >> "%LOG%"

echo [STEP 3] Running upload >> "%LOG%"
echo.
echo  You will be asked for your Firebase UID.
echo  Find it: Firebase Console ^> Authentication ^> Users ^> copy the UID
echo.

python "%PY%" "%XLSX%" "%SA%" "%JSON%"
set "EXIT=!ERRORLEVEL!"

echo. >> "%LOG%"
echo [STEP 3] Python exit code: !EXIT! >> "%LOG%"

del "%PY%" 2>nul

if !EXIT! == 0 (
    echo ======================================================= >> "%LOG%"
    echo   RESULT: SUCCESS >> "%LOG%"
    echo ======================================================= >> "%LOG%"
    echo.
    echo  ====================================
    echo    UPLOAD COMPLETE
    echo  ====================================
    echo  schedule_firestore.json saved to: %JSON%
    echo  Full log: %LOG%
) else (
    echo ======================================================= >> "%LOG%"
    echo   RESULT: FAILED  exit=!EXIT! >> "%LOG%"
    echo ======================================================= >> "%LOG%"
    echo.
    echo  ERROR occurred - check the messages above.
    echo  Exit code: !EXIT!
    echo  Log: %LOG%
    echo.
    notepad "%LOG%"
)
pause