@echo off
rem Doble clic en la notebook: trae el laboratorio de red de la PC host y lo
rem abre en Godot. El trabajo lo hace actualizar_lab.ps1, que se lee desde la
rem carpeta compartida de la PC host.
title Actualizar laboratorio de red
set "PS1=\\DESKTOP-N3JTNMU\tun-lab\tools\net_lab\actualizar_lab.ps1"
if not exist "%PS1%" set "PS1=\\192.168.1.212\tun-lab\tools\net_lab\actualizar_lab.ps1"
if not exist "%PS1%" (
  echo No encuentro la carpeta compartida de la PC host.
  echo Fijate que este prendida y en la misma red.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
