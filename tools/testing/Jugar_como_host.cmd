@echo off
setlocal
node "%~dp0publicar_pista.mjs" %*
if errorlevel 1 (
    pause
    exit /b 1
)
