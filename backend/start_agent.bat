@echo off
cd /d "C:\Projects\her-ai-samantha\backend"
for /f "usebackq tokens=1,* delims==" %%A in (.env) do if not "%%A"=="" if not "%%A:~0,1%"=="#" set "%%A=%%B"
echo Starting Samantha autonomous agent...
python agent_loop.py
pause
