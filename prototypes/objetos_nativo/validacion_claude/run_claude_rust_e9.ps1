# Validacion independiente (Claude), entrega 9: corre los verificadores claude_e9_*.
# Compila con el mismo entorno que build_object_native.ps1 y corre cada ejecutable con limite
# externo de 8 s. N3 (claude_e9_step_after) se reanuda salteando el indice si un paso se cuelga.
# N4 compila claude_e9_cost.rs tambien sobre la entrega anterior (worktree temporal, otro
# directorio de compilacion) y alterna las dos mediciones. No copia binarios de implementacion.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_claude_rust_e9.ps1 [-OutRoot <carpeta>]
param(
    [string]$OutRoot = '',
    [string]$ToolchainBin = 'C:\Users\ElCaido97\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin',
    [string]$CargoCachePath = '',
    [string]$BaselineCommit = 'aeee009',
    [int]$CostRounds = 3
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $CargoCachePath) { $CargoCachePath = Join-Path $repo '..\implementacion\tmp\native_toolchain\cargo' }
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_9' }
$cache = (Resolve-Path -LiteralPath $CargoCachePath).Path
$out = Join-Path $OutRoot ('e9_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $out | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$records = @()

function Run-Bounded([string]$Name, [string]$Program, [string[]]$Argv, [int]$Seconds, [hashtable]$Env) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Program
    $psi.Arguments = ($Argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $expired = -not $p.WaitForExit($Seconds * 1000)
    if ($expired) { & taskkill.exe /PID $p.Id /T /F | Out-Null; [void]$p.WaitForExit(3000) }
    [void]$o.Wait(3000); [void]$e.Wait(3000)
    [IO.File]::WriteAllText((Join-Path $out ($Name + '.stdout.log')), $o.Result, $utf8)
    [IO.File]::WriteAllText((Join-Path $out ($Name + '.stderr.log')), $e.Result, $utf8)
    $rec = [ordered]@{ name = $Name; exit_code = $p.ExitCode; timed_out = $expired; ms = $watch.ElapsedMilliseconds; limit_s = $Seconds; program = $Program; env = $Env }
    $p.Dispose()
    $script:records += $rec
    Write-Host ($Name + ': exit=' + $rec.exit_code + ' ' + $rec.ms + ' ms' + $(if ($expired) { ' VENCIDO' } else { '' }))
    return @{ rec = $rec; stdout = $o.Result }
}
function Get-Exes([string]$Json, [string]$Pattern) {
    @($Json -split "`n" | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } |
        Where-Object { $_.reason -eq 'compiler-artifact' -and $_.profile.test -and $_.executable -and $_.target.name -like $Pattern } |
        ForEach-Object { [ordered]@{ name = $_.target.name; exe = $_.executable } })
}

$cargo = Join-Path $ToolchainBin 'cargo.exe'
$envNew = @{ CARGO_HOME = $cache; CARGO_TARGET_DIR = (Join-Path $repo 'tmp\native_target'); RUSTC = (Join-Path $ToolchainBin 'rustc.exe'); CARGO_BUILD_JOBS = '2'; CARGO_PROFILE_DEV_DEBUG = '0' }
$c = Run-Bounded 'compile' $cargo @('test', '--no-default-features', '--no-run', '--manifest-path', (Join-Path $repo 'native\objetos_core\Cargo.toml'), '--locked', '--offline', '--message-format=json-render-diagnostics') 180 $envNew
if ($c.rec.exit_code -ne 0) { throw ('Compilacion fallida. Logs: ' + $out) }
$exes = Get-Exes $c.stdout 'claude_e9_*'
if ($exes.Count -ne 6) { throw ('Se esperaban 6 ejecutables claude_e9_*, hay ' + $exes.Count) }
$wt = Join-Path $repo 'tmp\wt_baseline'
$baseline = $null
# git escribe avisos por stderr: con Stop, PowerShell 5.1 los convierte en error. Se mira el codigo.
function Invoke-Git([string[]]$GitArgs) {
    $ErrorActionPreference = 'Continue'
    $o = & git -c 'safe.directory=*' @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('git ' + ($GitArgs -join ' ') + ' fallo: ' + ($o -join ' ')) }
    return (($o | Where-Object { $_ -is [string] }) -join "`n").Trim()
}
try {
    if (Test-Path -LiteralPath $wt) { throw ('Ya existe ' + $wt) }
    [void](Invoke-Git @('-C', $repo, 'worktree', 'add', '--detach', $wt, $BaselineCommit))
    $baseCommit = Invoke-Git @('-C', $wt, 'rev-parse', 'HEAD')
    $tests = Join-Path $wt 'native\objetos_core\tests'
    foreach ($d in @('claude_common', 'claude_e9_common')) { Copy-Item -Recurse -LiteralPath (Join-Path $repo ('native\objetos_core\tests\' + $d)) -Destination (Join-Path $tests $d) }
    Copy-Item -LiteralPath (Join-Path $repo 'native\objetos_core\tests\claude_e9_cost.rs') -Destination $tests
    $envOld = $envNew.Clone(); $envOld['CARGO_TARGET_DIR'] = Join-Path $repo 'tmp\native_target_baseline'
    $cb = Run-Bounded 'compile_baseline' $cargo @('test', '--no-default-features', '--no-run', '--manifest-path', (Join-Path $wt 'native\objetos_core\Cargo.toml'), '--locked', '--offline', '--test', 'claude_e9_cost', '--message-format=json-render-diagnostics') 180 $envOld
    if ($cb.rec.exit_code -ne 0) { throw ('Compilacion de la base fallida. Logs: ' + $out) }
    $baseline = @(Get-Exes $cb.stdout 'claude_e9_cost')[0].exe
    if (-not $baseline) { throw 'Sin ejecutable de costo de la base' }
    $baseSha = (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant()
    foreach ($x in $exes) {
        if ($x.name -in @('claude_e9_cost', 'claude_e9_step_after')) { continue }
        [void](Run-Bounded $x.name $x.exe @('--nocapture', '--test-threads=1') 8 @{})
    }
    $step = ($exes | Where-Object { $_.name -eq 'claude_e9_step_after' }).exe
    $skip = @()
    for ($k = 1; $k -le 6; $k++) {
        $r = Run-Bounded ('claude_e9_step_after_' + $k) $step @('--ignored', '--nocapture', '--test-threads=1') 8 @{ CLAUDE_STEP_SKIP = ($skip -join ',') }
        if (-not $r.rec.timed_out) { break }
        $at = @($r.stdout -split "`r?`n" | Where-Object { $_ -match '^CLAUDE_STEP_AT\t(\d+)' } | ForEach-Object { [int]($_ -split "`t")[1] })
        if ($at.Count -eq 0) { break }
        $skip += $at[-1]
    }
    $cost = ($exes | Where-Object { $_.name -eq 'claude_e9_cost' }).exe
    for ($k = 1; $k -le $CostRounds; $k++) {
        [void](Run-Bounded ('cost_actual_' + $k) $cost @('--nocapture', '--test-threads=1') 8 @{})
        [void](Run-Bounded ('cost_base_' + $k) $baseline @('--nocapture', '--test-threads=1') 8 @{})
    }
} finally {
    if (Test-Path -LiteralPath $wt) { try { [void](Invoke-Git @('-C', $repo, 'worktree', 'remove', '--force', $wt)) } catch { Write-Host $_ } }
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\tests') -Recurse -File -Filter 'claude_e9*' | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($repo.Length + 1); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
    [ordered]@{ out = $out; repo = $repo; head = (Invoke-Git @('-C', $repo, 'rev-parse', 'HEAD')); baseline_commit = $baseCommit; baseline_exe_sha256 = $baseSha
        step_after_skipped = $skip; worktree_removed = (-not (Test-Path -LiteralPath $wt)); runs = $records; sources = $sources } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCIA=' + $out)
