param(
    [ValidateSet('Check','CoreTests','Extension')][string]$Stage = 'CoreTests',
    [ValidateRange(15,300)][int]$BuildLimitSeconds = 180,
    [string]$ToolchainBin = '',
    [string]$CargoCachePath = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$manifest = Join-Path $repo 'native/objetos_core/Cargo.toml'
if ([string]::IsNullOrWhiteSpace($ToolchainBin)) {
    $profileRoot = [Environment]::GetFolderPath('UserProfile')
    if ($env:USERPROFILE) { $profileRoot = $env:USERPROFILE }
    $ToolchainBin = Join-Path $profileRoot '.rustup/toolchains/stable-x86_64-pc-windows-msvc/bin'
}
$bin = (Resolve-Path -LiteralPath $ToolchainBin).Path
$cargo = Join-Path $bin 'cargo.exe'
$rustc = Join-Path $bin 'rustc.exe'
if ([string]::IsNullOrWhiteSpace($CargoCachePath)) { $CargoCachePath = Join-Path $repo 'tmp/native_toolchain/cargo' }
$cache = (Resolve-Path -LiteralPath $CargoCachePath).Path
$target = Join-Path $repo 'tmp/native_target'
$run = Join-Path $repo ('tmp/native_build/' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + $Stage + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
function Invoke-Bounded([string]$Name, [string]$Program, [string[]]$Argv, [int]$Seconds) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Program
    $psi.Arguments = ($Argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['CARGO_HOME'] = $cache
    $psi.EnvironmentVariables['CARGO_TARGET_DIR'] = $target
    $psi.EnvironmentVariables['RUSTC'] = $rustc
    $psi.EnvironmentVariables['CARGO_BUILD_JOBS'] = '2'
    $psi.EnvironmentVariables['CARGO_PROFILE_DEV_DEBUG'] = '0'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $expired = $false
    try {
        $last = 0
        while (-not $p.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -ge $Seconds) { $expired = $true; & taskkill.exe /PID $p.Id /T /F | Out-Null; break }
            $elapsed = [int]$watch.Elapsed.TotalSeconds
            if ($elapsed -ge $last + 15) { Write-Host ($Name + ': ' + $elapsed + ' s / limite ' + $Seconds + ' s'); $last = $elapsed }
        }
        if (-not $p.WaitForExit(2000)) { throw ('No se cerro ' + $Name) }
        if (-not $outTask.Wait(2000) -or -not $errTask.Wait(2000)) { throw ('Salida sin cerrar: ' + $Name) }
        $o = $outTask.Result; $e = $errTask.Result
        [IO.File]::WriteAllText((Join-Path $run ($Name + '.stdout.log')), $o, $utf8)
        [IO.File]::WriteAllText((Join-Path $run ($Name + '.stderr.log')), $e, $utf8)
        [ordered]@{stage=$Name;exit_code=$p.ExitCode;timed_out=$expired;seconds=$watch.Elapsed.TotalSeconds;limit_seconds=$Seconds} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run ($Name + '.result.json')) -Encoding UTF8
        if ($e) { Write-Host (($e -split "`n" | Select-Object -Last 12) -join "`n") }
        if ($p.ExitCode -ne 0 -or $expired) {
            foreach ($line in ($o -split "`n")) {
                try { $msg = $line | ConvertFrom-Json; if ($msg.reason -eq 'compiler-message' -and $msg.message.rendered) { Write-Host $msg.message.rendered } } catch {}
            }
            throw ($Name + ' fallo. Logs: ' + $run)
        }
        Write-Host ($Name + ': exit=0 en ' + [Math]::Round($watch.Elapsed.TotalSeconds,3) + ' s')
        return $o
    } finally {
        if (-not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F | Out-Null; [void]$p.WaitForExit(2000) }
        $p.Dispose()
    }
}
$common = @('--manifest-path',$manifest,'--locked','--offline','--message-format=json-render-diagnostics')
if ($Stage -eq 'Check') {
    [void](Invoke-Bounded 'check' $cargo (@('check','--lib','--no-default-features') + $common) $BuildLimitSeconds)
} elseif ($Stage -eq 'Extension') {
    [void](Invoke-Bounded 'extension' $cargo (@('build','--lib') + $common) $BuildLimitSeconds)
    Write-Host ('DLL=' + (Join-Path $target 'debug/sahur_object_world.dll'))
} else {
    $compiled = Invoke-Bounded 'compile_tests' $cargo (@('test','--no-default-features','--no-run') + $common) $BuildLimitSeconds
    $testBins = @($compiled -split "`n" | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } |
        Where-Object { $_.reason -eq 'compiler-artifact' -and $_.profile.test -and $_.executable } | ForEach-Object { $_.executable } | Select-Object -Unique)
    if ($testBins.Count -eq 0) { throw 'No se genero ningun ejecutable de pruebas.' }
    $i = 0
    foreach ($testBin in $testBins) {
        $output = Invoke-Bounded ('tests_' + $i) $testBin @('--nocapture','--test-threads=1') 8
        Write-Host $output
        $i += 1
    }
}
Write-Host ('EVIDENCE=' + $run)
