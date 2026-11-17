# Validacion independiente (Claude), entrega 15. Mismo armado que run_claude_e14.ps1 (proyecto
# temporal con scripts/, actor, project.godot del prototipo nativo, extension y MI DLL, adaptador de
# Codex sin cambios y mis archivos), con los modos nuevos:
#   expiry (cv15_local), lanes15 y lanes15_stress (cv15_lanes, tres procesos),
# y las regresiones con mis instrumentos de la 14 sin cambios:
#   actions y bridge (cv14_local), close_host, close_client, close_both, lease_silent, quiet y future (cv14_net).
# Un modo repetido corre otra vez con sufijo _2, _3... Limite externo de 8 s por proceso.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_claude_e15.ps1 [-Modes 'expiry,lanes15'] [-CheckOnly]
param(
    [string]$Modes = 'expiry,actions,bridge,lanes15,lanes15,lanes15,lanes15,lanes15_stress,lanes15_stress,close_host,close_client,close_both,lease_silent,quiet,quiet,quiet,quiet,future',
    [string]$OutRoot = '',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$local14 = @('actions', 'bridge')
$pairs = @('close_host', 'close_client', 'close_both', 'lease_silent', 'quiet', 'future')
$trios = @('lanes15', 'lanes15_stress')
$known = $local14 + $pairs + $trios + @('expiry')
$list = @($Modes -split '[,\s]+' | Where-Object { $_ })
foreach ($m in $list) { if ($known -notcontains $m) { throw ('Modo desconocido: ' + $m) } }
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_15' }
$dll = Join-Path $repo 'tmp\native_target\debug\sahur_object_world.dll'
$src = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\src') -Recurse -File -Filter '*.rs')
if (@($src | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$out = Join-Path $OutRoot ($(if ($CheckOnly) { 'check15_' } else { 'run15_' }) + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
$rt = Join-Path $out 'runtime'
New-Item -ItemType Directory -Force -Path $rt, (Join-Path $rt 'bin'), (Join-Path $rt '.godot'), (Join-Path $rt 'scenes\actor'), (Join-Path $rt 'prototypes\objetos_adaptador\validacion_claude'), (Join-Path $out 'profile\roaming'), (Join-Path $out 'profile\local') | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$proj = [IO.File]::ReadAllText((Join-Path $repo 'prototypes\objetos_nativo\project.godot')).Replace('res://main.tscn', 'res://prototypes/objetos_adaptador/validacion_claude/cv15_local.tscn')
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
function Free-Port {
    $s = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
    $s.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0)); $port = $s.LocalEndPoint.Port; $s.Dispose()
    return $port
}
$owned = @()
$seen = @{}
try {
    $job = Start-Bounded 'import' @('--headless', '--editor', '--path', $rt, '--quit', '--log-file', (Join-Path $out 'import.godot.log')); $owned += $job
    Collect-Bounded $job
    if ($CheckOnly) {
        foreach ($s in @('cv15_local.gd', 'cv15_lanes.gd', 'cv15_tap_channel.gd')) {
            $job = Start-Bounded ('check_' + $s) @('--headless', '--path', $rt, '--check-only', '--script', ('res://prototypes/objetos_adaptador/validacion_claude/' + $s)); $owned += $job
            Collect-Bounded $job
        }
        $list = @()
    }
    foreach ($m in $list) {
        $seen[$m] = 1 + $(if ($seen.ContainsKey($m)) { $seen[$m] } else { 0 })
        $tag = if ($seen[$m] -gt 1) { $m + '_' + $seen[$m] } else { $m }
        if ($m -eq 'expiry' -or $local14 -contains $m) {
            $scene = if ($m -eq 'expiry') { 'cv15_local.tscn' } else { 'cv14_local.tscn' }
            $job = Start-Bounded $tag @('--headless', '--path', $rt, '--scene', ('res://prototypes/objetos_adaptador/validacion_claude/' + $scene), '--log-file', (Join-Path $out ($tag + '.godot.log')), '--', ('--mode=' + $m), ('--result=' + (Join-Path $out ($tag + '.result.json'))))
            $owned += $job
            Collect-Bounded $job
            continue
        }
        $port = Free-Port
        $isTrio = $trios -contains $m
        $roles = if ($isTrio) { @('host', 'client', 'intruder') } else { @('host', 'client') }
        $scene = if ($isTrio) { 'cv15_lanes.tscn' } else { 'cv14_net.tscn' }
        $jobs = @()
        foreach ($role in $roles) {
            $name = $tag + '_' + $role
            $argv = @('--headless', '--path', $rt, '--scene', ('res://prototypes/objetos_adaptador/validacion_claude/' + $scene), '--log-file', (Join-Path $out ($name + '.godot.log')), '--', ('--role=' + $role), ('--mode=' + $m), ('--port=' + $port), ('--result=' + (Join-Path $out ($name + '.result.json'))))
            if ($m -eq 'lanes15_stress') { $argv += '--stress=1' }
            $job = Start-Bounded $name $argv
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
