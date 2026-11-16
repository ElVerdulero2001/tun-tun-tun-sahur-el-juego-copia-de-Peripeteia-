# Validación independiente (Claude): corre un caso host + invitado con límite externo.
# No modifica runtime/, main.gd ni el runner de carga. Ejemplo:
#   powershell -ExecutionPolicy Bypass -File prototypes\objetos_red\validation\run_case.ps1 -Case drop050 -Net clean
# Perfiles de red:
#   clean      sin degradación
#   degraded   --one-way-ms=100 --jitter-ms=40 --loss=0.05 en ambos procesos (semilla de aplicación 12345, fija en main.gd)
#   asym       invitado --one-way-ms=150, host 0, sin jitter ni pérdida (demora dirigida del evento de salida)
#   mismatch   invitado --slow=0.5 contra host --slow=1 (huella distinta)
param(
    [Parameter(Mandatory = $true)][string]$Case,
    [ValidateSet('clean', 'degraded', 'asym', 'mismatch')][string]$Net = 'clean',
    [ValidateRange(0.01, 1.0)][double]$Slow = 1.0,
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [ValidateRange(1024, 65535)][int]$Port = 43211,
    [ValidateRange(5, 20)][int]$LimitSeconds = 20,
    [string]$OutRoot = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$proto = Join-Path $repo 'prototypes\objetos_red'
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos' }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$culture = [Globalization.CultureInfo]::InvariantCulture
$stamp = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
$runName = '{0}_{1}_{2}' -f $stamp, $Case, $Net
if ($Slow -ne 1.0) { $runName += '_slow' + $Slow.ToString($culture) }
$dir = Join-Path $OutRoot $runName
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$d = $dir.Replace('\', '/')

# Ojo: dentro de @() la coma tiene más precedencia que +; cada elemento va entre paréntesis.
$common = @(('--port=' + $Port), ('--case=' + $Case))
$hostNet = @(); $clientNet = @()
switch ($Net) {
    'degraded' { $hostNet = @('--one-way-ms=100', '--jitter-ms=40', '--loss=0.05'); $clientNet = $hostNet }
    'asym' { $clientNet = @('--one-way-ms=150') }
}
$hostSlow = $Slow; $clientSlow = $Slow
if ($Net -eq 'mismatch') { $hostSlow = 1.0; $clientSlow = 0.5 }

function Build-Args([string]$role, [string[]]$net, [double]$slowValue, [int]$durationMs) {
    $a = @('--headless', '--path', $proto, '--log-file', ($d + '/' + $role + '.godot.log'),
        '--scene', 'res://validation/driver.tscn', '--')
    if ($role -eq 'host') { $a += '--host' } else { $a += '--join=127.0.0.1' }
    $a += $common
    $a += @(('--trace=' + $d + '/' + $role + '.jsonl'), ('--dlog=' + $d + '/' + $role + '.driver.jsonl'),
        ('--duration-ms=' + $durationMs), ('--slow=' + $slowValue.ToString($culture)))
    $a += $net
    return ,$a
}
function Quote([string[]]$a) { ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' }
function Start-Godot([string[]]$a) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = Quote $a
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    return @{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}

$hostArgs = Build-Args 'host' $hostNet $hostSlow (($LimitSeconds - 1) * 1000)
$clientArgs = Build-Args 'client' $clientNet $clientSlow (($LimitSeconds - 2) * 1000)
$watch = [Diagnostics.Stopwatch]::StartNew()
$h = Start-Godot $hostArgs
$c = $null
$failure = @()
# Preparación del host: su driver escribe driver_boot al arrancar.
$hostDriver = Join-Path $dir 'host.driver.jsonl'
while ($watch.Elapsed.TotalSeconds -lt 4) {
    if ((Test-Path -LiteralPath $hostDriver) -and ((Get-Content -LiteralPath $hostDriver -TotalCount 1) -match 'driver_boot')) { break }
    if ($h.p.HasExited) { break }
    Start-Sleep -Milliseconds 50
}
$hostBootSeconds = $watch.Elapsed.TotalSeconds
if ($h.p.HasExited -or -not (Test-Path -LiteralPath $hostDriver)) {
    $failure += 'host_no_arranco'
} else {
    $c = Start-Godot $clientArgs
}
$clientStart = $watch.Elapsed.TotalSeconds
$killed = @()
while ($true) {
    $alive = @($h.p) + $(if ($c) { @($c.p) } else { @() }) | Where-Object { -not $_.HasExited }
    if ($alive.Count -eq 0) { break }
    if ($watch.Elapsed.TotalSeconds -gt $LimitSeconds) {
        foreach ($p in $alive) { & taskkill /PID $p.Id /T /F | Out-Null; $killed += $p.Id }
        $failure += 'limite_externo_vencido'
        break
    }
    Start-Sleep -Milliseconds 50
}
foreach ($x in @($h, $c)) { if ($x) { [void]$x.p.WaitForExit(2000) } }
$total = $watch.Elapsed.TotalSeconds

$result = [ordered]@{
    case = $Case; net = $Net; slow = $Slow; port = $Port; limit_s = $LimitSeconds
    engine = $EnginePath; run_dir = $dir
    host_cmd = '"' + $EnginePath + '" ' + (Quote $hostArgs)
    client_cmd = '"' + $EnginePath + '" ' + (Quote $clientArgs)
    host_boot_s = [math]::Round($hostBootSeconds, 3); client_start_s = [math]::Round($clientStart, 3)
    total_s = [math]::Round($total, 3); killed = $killed
}
$ignore = '^ERROR: Failed to read the root certificate store\.$'
foreach ($pair in @(@('host', $h), @('client', $c))) {
    $role = $pair[0]; $x = $pair[1]
    if (-not $x) { $result[$role + '_exit'] = $null; continue }
    $out = $x.out.Result; $err = $x.err.Result
    [IO.File]::WriteAllText((Join-Path $dir ($role + '.stdout.log')), $out)
    [IO.File]::WriteAllText((Join-Path $dir ($role + '.stderr.log')), $err)
    $result[$role + '_exit'] = $(if ($x.p.HasExited) { $x.p.ExitCode } else { $null })
    $errs = @(($out + "`n" + $err) -split "`r?`n" | Where-Object { ($_ -match '^(SCRIPT ERROR|ERROR|USER ERROR)') -and ($_ -notmatch $ignore) })
    $result[$role + '_errors'] = $errs
}
$result['failures'] = $failure
$json = $result | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $dir 'run.json'), $json, (New-Object Text.UTF8Encoding $false))
$left = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" | Where-Object { $_.ProcessId -in @($h.p.Id) + $(if ($c) { @($c.p.Id) } else { @() }) })
Write-Output ('RUN {0} host_exit={1} client_exit={2} total={3}s killed={4} errors={5}/{6} leftover={7}' -f $runName,
    $result.host_exit, $result.client_exit, $result.total_s, $killed.Count, @($result.host_errors).Count, @($result.client_errors).Count, $left.Count)
foreach ($e in @($result.host_errors)) { if ($e) { Write-Output ('  host: ' + $e) } }
foreach ($e in @($result.client_errors)) { if ($e) { Write-Output ('  client: ' + $e) } }
$analyzer = Join-Path $PSScriptRoot 'analyze.mjs'
if (Test-Path -LiteralPath $analyzer) { & node $analyzer $dir }
