param(
    ## Segundos de cada partida (--autoquit). El guion del invitado dura unos 25 s
    ## después de conectarse; con la preparación, 45 s alcanzan.
    [ValidateRange(10,120)][int]$Seconds = 45,
    [int]$Port = 0,
    ## Argumentos extra del invitado, por ejemplo '--sim-rtt=120 --sim-jitter=20'.
    [string]$GuestExtra = '',
    [string]$HostExtra = '',
    [string]$Label = 'base',
    [string]$EnginePath = '',
    [switch]$Import,
    ## Ventanas reales (con dibujo) en vez de --headless.
    [switch]$Windowed,
    ## Solo el invitado con ventana (1280x720), con capturas de algunas fases
    ## guardadas junto al registro (guest_<fase>.png).
    [switch]$WindowedGuest
)
## Prueba de la pista de objetos con un host y un invitado en esta PC.
## El host elige la pista (--pista-objetos) y el invitado corre el guion
## --test-input=pista. Los dos anotan cada cuadro (--pista-log) y al final se
## arma el informe con tools/testing/pista_objetos_report.mjs.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $EnginePath) { $EnginePath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Godot_v4.7.2.exe' }
if (-not (Test-Path -LiteralPath $EnginePath)) { throw "No está Godot en $EnginePath" }
if ($Port -eq 0) { $Port = Get-Random -Minimum 30000 -Maximum 39000 }
$stamp = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
$out = Join-Path $repo ("tmp/pista_objetos/{0}_{1}" -f $stamp, $Label)
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Start-Godot([string]$Name, [string[]]$Argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = ($Argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ Name = $Name; Process = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

function Stop-Tree($run) {
    if (-not $run.Process.HasExited) { & taskkill.exe /PID $run.Process.Id /T /F | Out-Null }
}

if ($Import) {
    $imp = Start-Godot 'import' @('--headless', '--path', $repo, '--import')
    if (-not $imp.Process.WaitForExit(240000)) { Stop-Tree $imp; throw 'La importación no terminó en 240 s' }
    [IO.File]::WriteAllText((Join-Path $out 'import.log'), $imp.Out.Result + "`n" + $imp.Err.Result)
    Write-Host ("import: exit={0}" -f $imp.Process.ExitCode)
}

$common = @('--path', $repo, '--max-fps', '60', '--scene', 'res://scenes/net_lab/net_lab.tscn')
$guestCommon = $common
if ($WindowedGuest) {
    $guestCommon = @('--resolution', '1280x720') + $common
    $GuestExtra = ($GuestExtra + ' --pista-capturas').Trim()
}
if (-not $Windowed) {
    $common = @('--headless') + $common
    if (-not $WindowedGuest) { $guestCommon = @('--headless') + $guestCommon }
}
$hostArgs = $common + @('--', '--host', "--port=$Port", '--pista-objetos', "--autoquit=$Seconds", "--pista-log=$out/host.csv") + ($HostExtra -split ' ' | Where-Object { $_ })
$guestArgs = $guestCommon + @('--', '--client', '--address=127.0.0.1', "--port=$Port", '--test-input=pista', "--autoquit=$($Seconds - 3)", "--pista-log=$out/guest.csv") + ($GuestExtra -split ' ' | Where-Object { $_ })
$hostRun = Start-Godot 'host' $hostArgs
Start-Sleep -Milliseconds 1500
$guestRun = Start-Godot 'guest' $guestArgs
$limit = ($Seconds + 25) * 1000
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    foreach ($run in @($guestRun, $hostRun)) {
        $left = [Math]::Max(1000, $limit - [int]$watch.ElapsedMilliseconds)
        if (-not $run.Process.WaitForExit($left)) { Write-Host ("{0}: no terminó a tiempo; se corta" -f $run.Name); Stop-Tree $run }
    }
} finally {
    foreach ($run in @($guestRun, $hostRun)) {
        Stop-Tree $run
        [void]$run.Process.WaitForExit(3000)
        $text = ''
        if ($run.Out.Wait(3000)) { $text += $run.Out.Result }
        if ($run.Err.Wait(3000)) { $text += "`n--- stderr ---`n" + $run.Err.Result }
        [IO.File]::WriteAllText((Join-Path $out ($run.Name + '.log')), $text)
        $code = if ($run.Process.HasExited) { $run.Process.ExitCode } else { 'vivo' }
        Write-Host ("{0}: exit={1}" -f $run.Name, $code)
    }
}
$left = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.CommandLine -like "*--port=$Port*" })
foreach ($p in $left) { & taskkill.exe /PID $p.ProcessId /T /F | Out-Null }
if ($left.Count) { Write-Host ("Se cerraron {0} procesos que quedaron vivos" -f $left.Count) }
Write-Host "SALIDA=$out"
$report = Join-Path $PSScriptRoot 'pista_objetos_report.mjs'
if ((Test-Path -LiteralPath $report) -and (Test-Path -LiteralPath (Join-Path $out 'guest.csv'))) {
    & node $report $out
}
