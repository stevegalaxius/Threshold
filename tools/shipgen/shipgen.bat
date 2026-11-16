@echo off
rem Runs shipgen on Windows: double-click it, or from a terminal
rem   tools\shipgen\shipgen.bat --role hauler -n 24
rem Finds Python (the "py" launcher first), installs Pillow the first time,
rem and writes ships to the save folders mods\shipyard\data\shipgen\.
setlocal
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY where python >nul 2>nul && set "PY=python"
if not defined PY (
  echo Python 3 isnt installed. Get it from https://www.python.org/downloads/ ^(tick "Add python.exe to PATH"^), or run: winget install Python.Python.3.12
  pause
  exit /b 1
)
%PY% -c "import PIL" 2>nul || (
  echo Installing Pillow ^(one time^)...
  %PY% -m pip install --user pillow || (echo Couldnt install Pillow. & pause & exit /b 1)
)
%PY% "%~dp0shipgen.py" %*
if "%~1"=="" pause
