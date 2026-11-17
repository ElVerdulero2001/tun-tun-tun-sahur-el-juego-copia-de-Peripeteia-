# Validacion independiente (Claude), entrega 11: corre cv11_probe (hereda de cv10_probe) en sus 5 modos.
# Copia de run_adapter_claude.ps1 (entrega 10), que queda sin cambios.
# Arma un proyecto temporal como run_object_clock_probe.ps1 de Codex (copia de scripts/,
# scenes/actor/actor.tscn, project.godot del prototipo nativo, extension y MI DLL), agrega el
# adaptador de Codex sin cambios y mis archivos, importa para el registro de clases y corre
# cada modo con --fixed-fps 60 y limite externo de 8 s. Guarda los hashes de cada copia.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_adapter_claude.ps1 [-Modes 'replay,slow']
param(
    [string]$Modes = 'scope,late,time,actor,resync11',
    [string]$OutRoot = '',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$known = @('scope', 'late', 'time', 'actor', 'resync11')
$list = @($Modes -split '[,\s]+' | Where-Object { $_ })
foreach ($m in $list) { if ($known -notcontains $m) { throw ('Modo desconocido: ' + $m) } }
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_10' }
$dll = Join-Path $repo 'tmp\native_target\debug\sahur_object_world.dll'
$src = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\src') -Recurse -File -Filter '*.rs')
if (@($src | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$out = Join-Path $OutRoot ($(if ($CheckOnly) { 'check_' } else { 'adapter11_' }) + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
$rt = Join-Path $out 'runtime'
New-Item -ItemType Directory -Force -Path $rt, (Join-Path $rt 'bin'), (Join-Path $rt '.godot'), (Join-Path $rt 'scenes\actor'), (Join-Path $rt 'prototypes\objetos_adaptador\validacion_claude'), (Join-Path $out 'profile\roaming'), (Join-Path $out 'profile\local') | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$proj = [IO.File]::ReadAllText((Join-Path $repo 'prototypes\objetos_nativo\project.godot')).Replace('res://main.tscn', 'res://prototypes/objetos_adaptador/validacion_claude/cv11_probe.tscn')
[IO.File]::WriteAllText((Join-Path $rt 'project.godot'), $proj, $utf8)
Copy-Item -LiteralPath (Join-Path $repo 'prototypes\objetos_nativo\extension.gdextension.in') -Destination (Join-Path $rt 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $rt 'bin\sahur_object_world.dll')
Copy-Item -LiteralPath (Join-Path $repo 'scenes\actor\actor.tscn') -Destination (Join-Path $rt 'scenes\actor\actor.tscn')
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination (Join-Path $rt 'scripts') -Recurse
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'prototypes\objetos_adaptador') -File) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rt ('prototypes\objetos_adaptador\' + $f.Name)) }
foreach ($f in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in '.gd', '.tscn' }) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rt ('prototypes\objetos_adaptador\validacion_claude\' + $f.Name)) }
[IO.File]::WriteAllText((Join-Path $rt '.godot\extension_list.cfg'), "res://extension.gdextension`n", $utf8)
# Hashes de cada copia contra su original del repositorio.
$copies = @()
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $rt 'scripts'), (Join-Path $rt 'scenes'), (Join-Path $rt 'prototypes') -Recurse -File) {
    $rel = $f.FullName.Substring($rt.Length + 1)
    $orig = Join-Path $repo $rel
    $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $b = if (Test-Path -LiteralPath $orig) { (Get-FileHash -LiteralPath $orig -Algorithm SHA256).Hash.ToLowerInvariant() } elseif ($rel -like 'prototypes\objetos_adaptador\validacion_claude\*') { (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $f.Name) -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
    $copies += [ordered]@{ path = $rel; sha256 = $a; repo_sha256 = $b; equal = ($a -eq $b) }
}
$records = @()
function Run-Bounded([string]$Name, [string[]]$Argv) {
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
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $expired = -not $p.WaitForExit(8000)
    if ($expired) { & taskkill.exe /PID $p.Id /T /F | Out-Null; [void]$p.WaitForExit(3000) }
    [void]$o.Wait(3000); [void]$e.Wait(3000)
    [IO.File]::WriteAllText((Join-Path $out ($Name + '.stdout.log')), $o.Result)
    [IO.File]::WriteAllText((Join-Path $out ($Name + '.stderr.log')), $e.Result)
    $errs = @(($o.Result + "`n" + $e.Result) -split "`r?`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:|WARNING:)' })
    $rec = [ordered]@{ name = $Name; exit_code = $p.ExitCode; timed_out = $expired; ms = $w.ElapsedMilliseconds; error_lines = $errs; result = (Test-Path -LiteralPath (Join-Path $out ($Name + '.result.json'))) }
    $script:records += $rec
    Write-Host ($Name + ': exit=' + $rec.exit_code + ' ' + $rec.ms + ' ms' + $(if ($expired) { ' VENCIDO' } else { '' }) + ' lineas=' + $errs.Count)
    $p.Dispose()
}
try {
    Run-Bounded 'import' @('--headless', '--editor', '--path', $rt, '--quit', '--log-file', (Join-Path $out 'import.godot.log'))
    if ($CheckOnly) {
        Run-Bounded 'check_only' @('--headless', '--path', $rt, '--check-only', '--script', 'res://prototypes/objetos_adaptador/validacion_claude/cv11_probe.gd')
        $list = @()
    }
    foreach ($m in $list) {
        Run-Bounded $m @('--headless', '--fixed-fps', '60', '--path', $rt, '--scene', 'res://prototypes/objetos_adaptador/validacion_claude/cv11_probe.tscn', '--log-file', (Join-Path $out ($m + '.godot.log')), '--', ('--mode=' + $m), ('--result=' + (Join-Path $out ($m + '.result.json'))), ('--trace=' + (Join-Path $out ($m + '.trace.json'))))
    }
} finally {
    $left = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue).Count
    [ordered]@{ out = $out; modes = $list; dll_sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant(); records = $records; godot_left = $left; copies = $copies } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCIA=' + $out)
