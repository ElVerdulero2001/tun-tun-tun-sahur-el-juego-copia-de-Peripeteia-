# Actualiza el laboratorio de red en la notebook y lo abre en Godot.
#
# 1. Espera a que Godot esté cerrado.
# 2. Trae de la PC host, por la carpeta compartida, solo lo que cambió. No
#    toca la carpeta .godot de la copia, así Godot solo vuelve a preparar lo
#    nuevo.
# 3. Godot prepara el proyecto sin ventana (registra las clases e importa).
# 4. Abre el editor con net_lab.tscn.
#
# Lo lanza actualizar_lab.bat con doble clic. -Origen, -Destino y -Prueba
# sirven para probarlo en la PC host: -Prueba no espera a que Godot esté
# cerrado.

param(
	[string]$Origen = '',
	[string]$Destino = '',
	[switch]$Prueba
)

$origenes = @('\\DESKTOP-N3JTNMU\tun-lab', '\\192.168.1.212\tun-lab')
if ($Origen -ne '') { $origenes = @($Origen) }
if ($Destino -eq '') {
	$Destino = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'tun-tun-tun-sahur-lab'
}
$escena = 'res://scenes/net_lab/net_lab.tscn'

function Terminar([string]$texto) {
	Write-Host ''
	Write-Host $texto -ForegroundColor Red
	Read-Host 'Apretá Enter para cerrar'
	exit 1
}

if (-not $Prueba) {
	while (Get-Process | Where-Object { $_.ProcessName -like 'Godot*' }) {
		Read-Host 'Godot está abierto. Cerralo y apretá Enter'
	}
}

$origen = $origenes | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'project.godot') } | Select-Object -First 1
if (-not $origen) {
	Terminar 'No encuentro la carpeta compartida de la PC host. ¿Está prendida y en la misma red?'
}

$carpetas = @(
	[Environment]::GetFolderPath('Desktop'),
	(Join-Path $env:USERPROFILE 'Downloads'),
	[Environment]::GetFolderPath('MyDocuments')
)
$godot = Get-ChildItem -Path $carpetas -Filter 'Godot_v4.7.2*.exe' -File -ErrorAction SilentlyContinue |
	Where-Object { $_.Name -notlike '*console*' } | Select-Object -First 1
if (-not $godot) {
	Terminar 'No encuentro Godot_v4.7.2 en el Escritorio, en Descargas ni en Documentos.'
}

Write-Host "Trayendo los cambios desde $origen ..."
robocopy $origen $Destino /MIR /XD .godot .git /R:2 /W:2 /NFL /NDL /NJH /NP
if ($LASTEXITCODE -ge 8) {
	Terminar "La copia falló (robocopy terminó con el código $LASTEXITCODE)."
}

Write-Host ''
Write-Host 'Godot está preparando el proyecto (la primera vez tarda más)...'
$importar = Start-Process -FilePath $godot.FullName -PassThru -Wait -WindowStyle Hidden `
	-ArgumentList @('--headless', '--path', "`"$Destino`"", '--import')
if ($importar.ExitCode -ne 0) {
	Terminar "Godot no pudo preparar el proyecto (código $($importar.ExitCode))."
}

Write-Host 'Abriendo el editor con net_lab.tscn...'
Start-Process -FilePath $godot.FullName -ArgumentList @('-e', '--path', "`"$Destino`"", $escena)
