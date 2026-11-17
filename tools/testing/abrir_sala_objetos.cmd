@echo off
setlocal
set "SALA_GODOT=%~1"
if not defined SALA_GODOT if exist "%~dp0godot.exe" set "SALA_GODOT=%~dp0godot.exe"
if not defined SALA_GODOT if exist "%USERPROFILE%\Desktop\Godot_v4.7.2.exe" set "SALA_GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2.exe"
if not defined SALA_GODOT goto missing
if not exist "%SALA_GODOT%" goto missing
start "" /wait "%SALA_GODOT%" --headless --path "%~dp0." --import --log-file "%~dp0import.log"
if errorlevel 1 goto import_failed
start "" "%SALA_GODOT%" --path "%~dp0." --log-file "%~dp0sala.log"
exit /b 0

:missing
echo Pone Godot 4.7.2 en esta carpeta con el nombre godot.exe o arrastra el EXE a este lanzador.
pause
exit /b 1

:import_failed
echo Godot no pudo preparar la sala. Revisa import.log.
pause
exit /b 1
