@echo off
cd /d "C:\Projects\her-ai-samantha\backend"
for /f "usebackq tokens=1,* delims==" %%A in (.env) do if not "%%A"=="" if not "%%A:~0,1%"=="#" set "%%A=%%B"
echo Starting Samantha backend on http://localhost:8000
python main.py
pause
