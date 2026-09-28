@echo off
rem NETRA live demo - laptop backup. Double-click to start.
rem Prints a public https://....gradio.live link (valid 72 h) that works from any
rem phone or laptop while this window stays open. Close the window to stop.
rem First run only: creates ..\.venv and installs the requirements (~2 min).
cd /d "%~dp0"
set PY=..\.venv\Scripts\python.exe
if not exist "%PY%" (
    echo Setting up Python environment - first run only...
    "%LOCALAPPDATA%\Python\bin\python.exe" -m venv ..\.venv || goto :fail
    "%PY%" -m pip install -q -r requirements.txt || goto :fail
)
echo Starting NETRA... the public link appears below in about 30 seconds.
"%PY%" app.py --share
goto :eof
:fail
echo Setup failed. Is Python installed at %LOCALAPPDATA%\Python\bin\python.exe ?
pause
