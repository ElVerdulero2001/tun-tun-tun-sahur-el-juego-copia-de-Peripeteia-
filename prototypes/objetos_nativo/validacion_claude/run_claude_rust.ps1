# Validacion independiente (Claude), entrega 8: corre mis pruebas Rust claude_*.rs.
# Compila con el mismo entorno que build_object_native.ps1 (caché compartida, sin red) y
# ejecuta cada ejecutable con un limite externo de 8 s. claude_replay corre dos veces (A6).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File run_claude_rust.ps1 [-OutRoot <carpeta>]
param(
    [string]$OutRoot = '',
    [string]$ToolchainBin = 'C:\Users\ElCaido97\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin',
    [string]$CargoCachePath = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $CargoCachePath) { $CargoCachePath = Join-Path $repo '..\implementacion\tmp\native_toolchain\cargo' }
if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_8' }
$cache = (Resolve-Path -LiteralPath $CargoCachePath).Path
$out = Join-Path $OutRoot ('rust_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $out | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false

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
    $rec = [ordered]@{ name = $Name; exit_code = $p.ExitCode; timed_out = $expired; ms = $watch.ElapsedMilliseconds; limit_s = $Seconds }
    $p.Dispose()
    Write-Host ($Name + ': exit=' + $rec.exit_code + ' ' + $rec.ms + ' ms' + $(if ($expired) { ' VENCIDO' } else { '' }))
    return @{ rec = $rec; stdout = $o.Result }
}

$envBuild = @{ CARGO_HOME = $cache; CARGO_TARGET_DIR = (Join-Path $repo 'tmp\native_target'); RUSTC = (Join-Path $ToolchainBin 'rustc.exe'); CARGO_BUILD_JOBS = '2'; CARGO_PROFILE_DEV_DEBUG = '0' }
$manifest = Join-Path $repo 'native\objetos_core\Cargo.toml'
$c = Run-Bounded 'compile' (Join-Path $ToolchainBin 'cargo.exe') @('test', '--no-default-features', '--no-run', '--manifest-path', $manifest, '--locked', '--offline', '--message-format=json-render-diagnostics') 180 $envBuild
if ($c.rec.exit_code -ne 0 -or $c.rec.timed_out) { throw ('Compilacion fallida. Logs: ' + $out) }
$exes = @($c.stdout -split "`n" | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } |
    Where-Object { $_.reason -eq 'compiler-artifact' -and $_.profile.test -and $_.executable -and $_.target.name -like 'claude_*' -and $_.target.name -notlike 'claude_diag_*' } |
    ForEach-Object { [ordered]@{ name = $_.target.name; exe = $_.executable } })
if ($exes.Count -ne 5) { throw ('Se esperaban 5 ejecutables claude_*, hay ' + $exes.Count) }
$records = @()
foreach ($x in $exes) {
    $runs = if ($x.name -eq 'claude_replay') { @('claude_replay_run1', 'claude_replay_run2') } else { @($x.name) }
    foreach ($r in $runs) {
        $res = Run-Bounded $r $x.exe @('--nocapture', '--test-threads=1') 8 @{}
        $res.rec['exe'] = $x.exe
        $res.rec['exe_sha256'] = (Get-FileHash -LiteralPath $x.exe -Algorithm SHA256).Hash.ToLowerInvariant()
        $records += $res.rec
    }
}
$sources = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native\objetos_core\tests') -Recurse -File -Filter '*.rs' | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($repo.Length + 1); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
[ordered]@{ out = $out; repo = $repo; runs = $records; test_sources = $sources } | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $out 'runner.json') -Encoding UTF8
Write-Host ('EVIDENCIA=' + $out)
