param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$implementation = Join-Path $repo 'tmp/colaboracion_objetos_20261116/implementacion'
if (Test-Path -LiteralPath (Join-Path $implementation 'native/objetos_core/Cargo.toml')) {
    $workRoot = (Resolve-Path -LiteralPath $implementation).Path
} else { $workRoot = $repo }
$manifest = Join-Path $workRoot 'native/objetos_core/Cargo.toml'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Falta Cargo.toml del nucleo de objetos.' }
$toolchainBin = Join-Path $env:USERPROFILE '.rustup/toolchains/stable-x86_64-pc-windows-msvc/bin'
$cargo = Join-Path $toolchainBin 'cargo.exe'
$rustc = Join-Path $toolchainBin 'rustc.exe'
if (-not (Test-Path -LiteralPath $cargo) -or -not (Test-Path -LiteralPath $rustc)) {
    throw 'Falta la toolchain estable Rust x64 MSVC. Revisar la instalacion de Rust.'
}
$toolRoot = Join-Path $workRoot 'tmp/native_toolchain'
$cache = Join-Path $toolRoot 'cargo'
$target = Join-Path $workRoot 'tmp/native_target'
$lock = Join-Path (Split-Path $manifest -Parent) 'Cargo.lock'
$fetchArgs = 'fetch --manifest-path "' + $manifest + '"'
if (Test-Path -LiteralPath $lock) { $fetchArgs += ' --locked' }
Write-Host ('Proyecto: ' + $manifest)
Write-Host ('Cache local: ' + $cache)
Write-Host 'Solo descarga dependencias. Limite total: 180 segundos.'
if ($CheckOnly) {
    Write-Output ('CHECK_ONLY: "' + $cargo + '" ' + $fetchArgs)
    exit 0
}

$run = Join-Path $toolRoot ('downloads/' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $run, $cache -Force | Out-Null
$tmpRoot = Join-Path $workRoot 'tmp'
if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot '.gdignore'))) { [IO.File]::WriteAllText((Join-Path $tmpRoot '.gdignore'), '') }
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $cargo
$start.Arguments = $fetchArgs
$start.WorkingDirectory = $workRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.EnvironmentVariables['CARGO_HOME'] = $cache
$start.EnvironmentVariables['CARGO_TARGET_DIR'] = $target
$start.EnvironmentVariables['RUSTC'] = $rustc
$start.EnvironmentVariables['CARGO_NET_RETRY'] = '1'
$start.EnvironmentVariables['CARGO_HTTP_TIMEOUT'] = '20'
$proc = $null
$timer = [Diagnostics.Stopwatch]::StartNew()
$timedOut = $false
$lastReport = 0
try {
    $proc = [Diagnostics.Process]::Start($start)
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    while (-not $proc.WaitForExit(1000)) {
        if ($timer.Elapsed.TotalSeconds -ge 180) { $timedOut = $true; break }
        $elapsed = [int]$timer.Elapsed.TotalSeconds
        if ($elapsed -ge $lastReport + 5) {
            Write-Host ('Cargo esta descargando las bibliotecas... ' + $elapsed + ' s')
            $lastReport = $elapsed
        }
    }
    if ($timedOut) { $proc.Kill(); [void]$proc.WaitForExit(2000) }
    if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000)) { throw 'No se pudieron cerrar los canales de salida de Cargo.' }
    $outText = $stdout.Result
    $errText = $stderr.Result
    [IO.File]::WriteAllText((Join-Path $run 'stdout.log'), $outText)
    [IO.File]::WriteAllText((Join-Path $run 'stderr.log'), $errText)
    if ($outText) { Write-Host $outText }
    if ($errText) { Write-Host $errText }
    $ok = -not $timedOut -and $proc.HasExited -and $proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $lock)
    $result = [ordered]@{
        status = $(if ($ok) { 'READY' } else { 'FAILED' })
        scope = 'dependency_download_only'
        manifest = $manifest
        manifest_sha256 = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
        lock_sha256 = $(if (Test-Path -LiteralPath $lock) { (Get-FileHash -LiteralPath $lock -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null })
        cache = $cache
        exit_code = $(if ($proc.HasExited) { $proc.ExitCode } else { $null })
        timed_out = $timedOut
        seconds = $timer.Elapsed.TotalSeconds
        native_core_compiled = $false
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding UTF8
    Write-Host ('Resultado y logs: ' + $run)
    if (-not $ok) { throw 'Cargo no completo la descarga. Los logs quedaron guardados.' }
} finally {
    if ($null -ne $proc -and -not $proc.HasExited) { $proc.Kill(); [void]$proc.WaitForExit(2000) }
    if ($null -ne $proc) { $proc.Dispose() }
}
