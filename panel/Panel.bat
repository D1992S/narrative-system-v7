@echo off
rem Panel na zywo dla jednego projektu Narrative V2 (tylko odczyt).
rem Uruchom dwuklikiem albo przeciagnij folder projektu na ten plik.
where python >nul 2>nul
if errorlevel 1 goto missing
python -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" >nul 2>nul
if errorlevel 1 goto missing
set "PANEL_PYTHONW="
for /f "delims=" %%P in ('python -c "import sys,pathlib; print(pathlib.Path(sys.executable).with_name('pythonw.exe'))"') do set "PANEL_PYTHONW=%%P"
if not exist "%PANEL_PYTHONW%" goto console
start "" "%PANEL_PYTHONW%" -B -X utf8 "%~dp0panel.py" %*
exit /b
:console
python -B -X utf8 "%~dp0panel.py" %*
if errorlevel 1 pause
exit /b
:missing
echo Panel wymaga dzialajacego Python 3.10 lub nowszego w PATH.
echo Nie uruchomiono panelu. Sprawdz instalacje Pythona.
pause
exit /b 1
