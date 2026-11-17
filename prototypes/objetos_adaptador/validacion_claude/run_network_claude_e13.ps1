# Validacion independiente (Claude), entrega 13: corre cv13_probe en pares host/cliente por ENet
# (loopback, ritmo real, como run_object_network_probe.ps1 de Codex) y el modo de un proceso
# 'capacity' con --fixed-fps 60. Arma un proyecto temporal igual que mis runners anteriores
# (scripts/, scenes/actor/actor.tscn, project.godot del prototipo nativo, extension y MI DLL),
# agrega el adaptador de Codex sin cambios y mis archivos, importa y guarda los hashes de cada copia.
# Limite externo de 8 s por proceso, contado desde que arranca. Solo termina procesos propios.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_network_claude_e13.ps1 [-Modes 'base,rpc'] [-CheckOnly]
param(
    [string]$Modes = 'base,delay,time_order,time_old,conflict_pause,future,big,rpc,capacity',
    [string]$OutRoot = '',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$pairs = @('base', 'delay', 'time_order', 'time_old', 'conflict_pause', 'future', 'big', 'rpc', 'quiet')
$known = $pairs + @('capacity')
$list = @($Modes -split '[,\s]+' | Where-Object { $_ })
foreach ($m in $list) { if ($known -notcontains $m) { throw ('Modo desconocido: ' + $m) } }
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_13' }
$dll = Join-Path $repo 'tmp\native_target\debug\sahur_object_world.dll'
$src = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\src') -Recurse -File -Filter '*.rs')
if (@($src | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$out = Join-Path $OutRoot ($(if ($CheckOnly) { 'check13_' } else { 'network13_' }) + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
$rt = Join-Path $out 'runtime'
New-Item -ItemType Directory -Force -Path $rt, (Join-Path $rt 'bin'), (Join-Path $rt '.godot'), (Join-Path $rt 'scenes\actor'), (Join-Path $rt 'prototypes\objetos_adaptador\validacion_claude'), (Join-Path $out 'profile\roaming'), (Join-Path $out 'profile\local') | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$proj = [IO.File]::ReadAllText((Join-Path $repo 'prototypes\objetos_nativo\project.godot')).Replace('res://main.tscn', 'res://prototypes/objetos_adaptador/validacion_claude/cv13_probe.tscn')
[IO.File]::WriteAllText((Join-Path $rt 'project.godot'), $proj, $utf8)
Copy-Item -LiteralPath (Join-Path $repo 'prototypes\objetos_nativo\extension.gdextension.in') -Destination (Join-Path $rt 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $rt 'bin\sahur_object_world.dll')
Copy-Item -LiteralPath (Join-Path $repo 'scenes\actor\actor.tscn') -Destination (Join-Path $rt 'scenes\actor\actor.tscn')
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination (Join-Path $rt 'scripts') -Recurse
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'prototypes\objetos_adaptador') -File) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rt ('prototypes\objetos_adaptador\' + $f.Name)) }
foreach ($f in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in '.gd', '.tscn' }) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rt ('prototypes\objetos_adaptador\validacion_claude\' + $f.Name)) }
[IO.File]::WriteAllText((Join-Path $rt '.godot\extension_list.cfg'), "res://extension.gdextension`n", $utf8)
$copies = @()
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $rt 'scripts'), (Join-Path $rt 'scenes'), (Join-Path $rt 'prototypes') -Recurse -File) {
    $rel = $f.FullName.Substring($rt.Length + 1)
    $orig = Join-Path $repo $rel
    $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $b = if (Test-Path -LiteralPath $orig) { (Get-FileHash -LiteralPath $orig -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    $copies += [ordered]@{ path = $rel; sha256 = $a; repo_sha256 = $b; equal = ($a -eq $b) }
}
$records = @()
function Start-Bounded([string]$Name, [string[]]$Argv) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = ($Argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $rt
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['APPDATA'] = Join-Path $out 'profile\roaming'
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $out 'profile\local'
    $w = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    return @{ name = $Name; p = $p; w = $w; o = $p.StandardOutput.ReadToEndAsync(); e = $p.StandardError.ReadToEndAsync() }
}
function Collect-Bounded($job) {
    $p = $job.p
    $left = [Math]::Max(1, 8000 - $job.w.ElapsedMilliseconds)
    $expired = -not $p.WaitForExit([int]$left)
    if ($expired) { & taskkill.exe /PID $p.Id /T /F | Out-Null; [void]$p.WaitForExit(3000) }
    [void]$job.o.Wait(3000); [void]$job.e.Wait(3000)
    [IO.File]::WriteAllText((Join-Path $out ($job.name + '.stdout.log')), $job.o.Result)
    [IO.File]::WriteAllText((Join-Path $out ($job.name + '.stderr.log')), $job.e.Result)
    $errs = @(($job.o.Result + "`n" + $job.e.Result) -split "`r?`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:|WARNING:)' })
    $rec = [ordered]@{ name = $job.name; exit_code = $p.ExitCode; timed_out = $expired; ms = $job.w.ElapsedMilliseconds; error_lines = $errs; result = (Test-Path -LiteralPath (Join-Path $out ($job.name + '.result.json'))) }
    $script:records += $rec
    Write-Host ($job.name + ': exit=' + $rec.exit_code + ' ' + $rec.ms + ' ms' + $(if ($expired) { ' VENCIDO' } else { '' }) + ' lineas=' + $errs.Count)
}
$owned = @()
try {
    $job = Start-Bounded 'import' @('--headless', '--editor', '--path', $rt, '--quit', '--log-file', (Join-Path $out 'import.godot.log')); $owned += $job
    Collect-Bounded $job
    if ($CheckOnly) {
        foreach ($s in @('cv13_tap_link.gd', 'cv13_probe.gd')) {
            $job = Start-Bounded ('check_' + $s) @('--headless', '--path', $rt, '--check-only', '--script', ('res://prototypes/objetos_adaptador/validacion_claude/' + $s)); $owned += $job
            Collect-Bounded $job
        }
        $list = @()
    }
    foreach ($m in $list) {
        $common = @('--path', $rt, '--scene', 'res://prototypes/objetos_adaptador/validacion_claude/cv13_probe.tscn')
        if ($m -eq 'capacity') {
            $job = Start-Bounded $m (@('--headless', '--fixed-fps', '60') + $common + @('--log-file', (Join-Path $out ($m + '.godot.log')), '--', '--role=solo', ('--mode=' + $m), ('--result=' + (Join-Path $out ($m + '.result.json')))))
            $owned += $job
            Collect-Bounded $job
            continue
        }
        $socket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
        $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0)); $port = $socket.LocalEndPoint.Port; $socket.Dispose()
        $jobs = @()
        foreach ($role in @('host', 'client')) {
            $name = $m + '_' + $role
            $job = Start-Bounded $name (@('--headless') + $common + @('--log-file', (Join-Path $out ($name + '.godot.log')), '--', ('--role=' + $role), ('--mode=' + $m), ('--port=' + $port), ('--result=' + (Join-Path $out ($name + '.result.json'))), ('--trace=' + (Join-Path $out ($name + '.trace.json')))))
            $owned += $job; $jobs += $job
        }
        foreach ($job in $jobs) { Collect-Bounded $job }
    }
} finally {
    foreach ($job in $owned) { if (-not $job.p.HasExited) { & taskkill.exe /PID $job.p.Id /T /F | Out-Null }; $job.p.Dispose() }
    $left = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count
    [ordered]@{ out = $out; modes = $list; dll_sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant(); records = $records; godot_left = $left; copies = $copies } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCIA=' + $out)
