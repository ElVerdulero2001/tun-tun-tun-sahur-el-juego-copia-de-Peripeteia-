@echo off
title Dependencias del nucleo de objetos
set "SAHUR_DEP_SCRIPT=%~dp0prepare_object_native_dependencies.ps1"
if not exist "%SAHUR_DEP_SCRIPT%" set "SAHUR_DEP_SCRIPT=C:\Users\ElCaido97\Documents\tun-tun-tun-sahur\tools\testing\prepare_object_native_dependencies.ps1"
if not exist "%SAHUR_DEP_SCRIPT%" (
  echo No se encontro el preparador dentro del proyecto.
  echo Revisar C:\Users\ElCaido97\Documents\tun-tun-tun-sahur\tools\testing
  pause
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SAHUR_DEP_SCRIPT%" %*
set "SAHUR_DEP_EXIT=%ERRORLEVEL%"
if /i "%~1"=="-CheckOnly" exit /b %SAHUR_DEP_EXIT%
if not "%SAHUR_DEP_EXIT%"=="0" (
  echo.
  echo La descarga no termino correctamente. Conserva el resultado para Codex.
) else (
  echo.
  echo Dependencias descargadas. Ya podes avisarle a Codex.
)
echo.
pause
exit /b %SAHUR_DEP_EXIT%
