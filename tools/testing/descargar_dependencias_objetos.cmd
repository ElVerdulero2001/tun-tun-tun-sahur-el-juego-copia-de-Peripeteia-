@echo off
title Dependencias del nucleo de objetos
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_object_native_dependencies.ps1"
if errorlevel 1 (
  echo.
  echo La descarga no termino correctamente. Conserva el resultado para Codex.
) else (
  echo.
  echo Dependencias descargadas. Ya podes avisarle a Codex.
)
echo.
pause
