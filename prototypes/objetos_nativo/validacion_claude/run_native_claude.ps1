# Validacion independiente (Claude), entrega 8: corre mis escenas Godot sobre el nucleo nativo.
# Copia nueva del proyecto de Codex (project.godot, probe.gd, late_action.gd sin cambios), mi DLL,
# AppData aislado y limite externo de 8 s por proceso. Etapas: binding, exchange, late_codex, late_push.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_native_claude.ps1 [-Stages 'binding,late_push']
param(
    [string]$Stages = 'binding,exchange,late_codex,late_push',
    [string]$OutRoot = '',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe'
)
$ErrorActionPreference = 'Stop'
$known = @('binding', 'exchange', 'late_codex', 'late_push')
$list = @($Stages -split '[,\s]+' | Where-Object { $_ })
foreach ($s in $list) { if ($known -notcontains $s) { throw ('Etapa desconocida: ' + $s) } }
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_8' }
$dll = Join-Path $repo 'tmp\native_target\debug\sahur_object_world.dll'
$src = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\src') -Recurse -File -Filter '*.rs')
$src += Get-Item (Join-Path $repo 'native\objetos_core\Cargo.toml'), (Join-Path $repo 'native\objetos_core\Cargo.lock')
if (@($src | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$out = Join-Path $OutRoot ('godot_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
$rt = Join-Path $out 'runtime'
New-Item -ItemType Directory -Force -Path $rt, (Join-Path $rt 'bin'), (Join-Path $rt '.godot'), (Join-Path $out 'profile\roaming'), (Join-Path $out 'profile\local') | Out-Null
$fixture = Join-Path $repo 'prototypes\objetos_nativo'
foreach ($n in @('project.godot', 'main.tscn', 'probe.gd', 'late_action.gd', 'late_action.tscn')) { Copy-Item -LiteralPath (Join-Path $fixture $n) -Destination (Join-Path $rt $n) }
Copy-Item -LiteralPath (Join-Path $fixture 'extension.gdextension.in') -Destination (Join-Path $rt 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $rt 'bin\sahur_object_world.dll')
foreach ($f in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in '.gd', '.tscn' }) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rt $f.Name) }
[IO.File]::WriteAllText((Join-Path $rt '.godot\extension_list.cfg'), "res://extension.gdextension`n", (New-Object Text.UTF8Encoding $false))
$records = @()
$procs = @()
function Start-Stage([string]$Name, [string]$Scene, [string[]]$Extra) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $argv = @('--headless', '--path', $rt, '--scene', $Scene, '--log-file', (Join-Path $out ($Name + '.godot.log')), '--', ('--result=' + (Join-Path $out ($Name + '.result.json')))) + $Extra
    $psi.Arguments = ($argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $rt
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['APPDATA'] = Join-Path $out 'profile\roaming'
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $out 'profile\local'
    $w = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $script:procs += $p
    return @{ p = $p; name = $Name; w = $w; o = $p.StandardOutput.ReadToEndAsync(); e = $p.StandardError.ReadToEndAsync() }
}
function Wait-Stage($s) {
    $left = [Math]::Max(0, 8000 - [int]$s.w.ElapsedMilliseconds)
    $expired = -not $s.p.WaitForExit($left)
    if ($expired) { & taskkill.exe /PID $s.p.Id /T /F | Out-Null; [void]$s.p.WaitForExit(3000) }
    [void]$s.o.Wait(3000); [void]$s.e.Wait(3000)
    $o = $s.o.Result; $e = $s.e.Result
    [IO.File]::WriteAllText((Join-Path $out ($s.name + '.stdout.log')), $o)
    [IO.File]::WriteAllText((Join-Path $out ($s.name + '.stderr.log')), $e)
    $errs = @(($o + "`n" + $e) -split "`r?`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:|WARNING:)' })
    $rec = [ordered]@{ name = $s.name; exit_code = $s.p.ExitCode; timed_out = $expired; ms = $s.w.ElapsedMilliseconds; error_lines = $errs; result = (Test-Path -LiteralPath (Join-Path $out ($s.name + '.result.json'))) }
    $script:records += $rec
    Write-Host ($s.name + ': exit=' + $rec.exit_code + ' ' + $rec.ms + ' ms' + $(if ($expired) { ' VENCIDO' } else { '' }) + ' lineas_de_error=' + $errs.Count)
}
function Run-Pair([string]$Tag, [string]$Variant, [int]$Port) {
    $marker = Join-Path $out ($Tag + '_ready.txt')
    $common = @(('--port=' + $Port), ('--ready=' + $marker), ('--variant=' + $Variant))
    $h = Start-Stage ($Tag + '_host') 'res://cv_late_observer.tscn' (@('--role=late_host', ('--trace=' + (Join-Path $out ($Tag + '_host.trace.json')))) + $common)
    while (-not (Test-Path -LiteralPath $marker) -and -not $h.p.HasExited -and $h.w.ElapsedMilliseconds -lt 3000) { Start-Sleep -Milliseconds 25 }
    $c = Start-Stage ($Tag + '_client') 'res://cv_late_observer.tscn' (@('--role=late_client', ('--trace=' + (Join-Path $out ($Tag + '_client.trace.json')))) + $common)
    Wait-Stage $h
    Wait-Stage $c
}
try {
    foreach ($stage in $list) {
        if ($stage -eq 'binding') {
            Wait-Stage (Start-Stage 'binding' 'res://cv_binding.tscn' @('--role=binding'))
            Wait-Stage (Start-Stage 'control1' 'res://cv_binding.tscn' @('--role=control'))
            Wait-Stage (Start-Stage 'control2' 'res://cv_binding.tscn' @('--role=control'))
        } elseif ($stage -eq 'exchange') {
            $art = Join-Path $out 'exchange_artifact.bin'
            Wait-Stage (Start-Stage 'export' 'res://cv_exchange.tscn' @('--role=export', ('--artifact=' + $art)))
            Wait-Stage (Start-Stage 'import' 'res://cv_exchange.tscn' @('--role=import', ('--artifact=' + $art)))
        } elseif ($stage -eq 'late_codex') {
            Run-Pair 'late_codex' 'codex' 46311
        } else {
            Run-Pair 'late_push' 'push' 46312
        }
    }
} finally {
    foreach ($p in $procs) { if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(2000) } }
    [ordered]@{ out = $out; stages = $list; dll_sha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
        records = $records; own_processes_left = @($procs | Where-Object { -not $_.HasExited }).Count } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCIA=' + $out)
