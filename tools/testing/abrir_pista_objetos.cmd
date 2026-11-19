@echo off
rem Abre el laboratorio de red con la pista de objetos (piloto).
rem Usa Godot 4.7.2: arrastrale el ejecutable a este archivo, o dejalo en esta
rem carpeta con el nombre godot.exe, o en el Escritorio como Godot_v4.7.2.exe.
setlocal
set "PISTA_GODOT=%~1"
if not defined PISTA_GODOT if exist "%~dp0godot.exe" set "PISTA_GODOT=%~dp0godot.exe"
if not defined PISTA_GODOT if exist "%USERPROFILE%\Desktop\Godot_v4.7.2.exe" set "PISTA_GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2.exe"
if not defined PISTA_GODOT goto missing
if not exist "%PISTA_GODOT%" goto missing
start "" /wait "%PISTA_GODOT%" --headless --path "%~dp0." --import --log-file "%~dp0import.log"
if errorlevel 1 goto import_failed
start "" "%PISTA_GODOT%" --path "%~dp0." --scene res://scenes/net_lab/net_lab.tscn --log-file "%~dp0pista.log" -- --pista-objetos --pista-diagnostico="%~dp0diagnosticos_pista"
exit /b 0

:missing
echo Pone Godot 4.7.2 en esta carpeta con el nombre godot.exe o arrastra el EXE a este lanzador.
pause
exit /b 1

:import_failed
echo Godot no pudo preparar el laboratorio. Revisa import.log.
pause
exit /b 1
