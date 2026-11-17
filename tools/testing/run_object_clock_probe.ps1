param(
    [string]$Modes = 'normal,slow,pause,resync,budget,tuning,history,api_authority,api_scope,api_time,api_recovery,hist_actor,hist_time,hist_gap,hist_effect,hist_guards',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$dll = Join-Path $repo 'tmp/native_target/debug/sahur_object_world.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Compilar primero la extensión.' }
$nativeSources = @(Get-ChildItem (Join-Path $repo 'native/objetos_core/src') -Filter '*.rs')
$nativeSources += Get-Item (Join-Path $repo 'native/objetos_core/Cargo.toml'), (Join-Path $repo 'native/objetos_core/Cargo.lock')
if (@($nativeSources | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$modeList = @($Modes -split '[,\s]+' | Where-Object { $_ })
foreach ($m in $modeList) { if ($m -notin @('normal','slow','pause','resync','budget','tuning','history','api_authority','api_scope','api_time','api_recovery','hist_actor','hist_time','hist_gap','hist_effect','hist_guards')) { throw ('Modo desconocido '+$m) } }
$run = Join-Path $repo ('tmp/clock_probe/' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
$runtime = Join-Path $run 'runtime'
New-Item -ItemType Directory -Force -Path $runtime,(Join-Path $runtime 'bin'),(Join-Path $runtime '.godot'),(Join-Path $run 'profile/roaming'),(Join-Path $run 'profile/local'),(Join-Path $runtime 'scenes/actor'),(Join-Path $runtime 'prototypes/objetos_adaptador') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'prototypes/objetos_nativo/project.godot') -Destination (Join-Path $runtime 'project.godot')
$projectPath = Join-Path $runtime 'project.godot'
$projectText = [IO.File]::ReadAllText($projectPath).Replace('res://main.tscn','res://prototypes/objetos_adaptador/probe.tscn')
[IO.File]::WriteAllText($projectPath,$projectText,(New-Object Text.UTF8Encoding $false))
Copy-Item -LiteralPath (Join-Path $repo 'prototypes/objetos_nativo/extension.gdextension.in') -Destination (Join-Path $runtime 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $runtime 'bin/sahur_object_world.dll')
Copy-Item -LiteralPath (Join-Path $repo 'scenes/actor/actor.tscn') -Destination (Join-Path $runtime 'scenes/actor/actor.tscn')
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination (Join-Path $runtime 'scripts') -Recurse
foreach ($f in Get-ChildItem (Join-Path $repo 'prototypes/objetos_adaptador') -File) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $runtime ('prototypes/objetos_adaptador/'+$f.Name))
}
[IO.File]::WriteAllText((Join-Path $runtime '.godot/extension_list.cfg'), "res://extension.gdextension`n", (New-Object Text.UTF8Encoding $false))
$sourceManifest = @(Get-ChildItem (Join-Path $runtime 'scripts'),(Join-Path $runtime 'scenes'),(Join-Path $runtime 'prototypes') -File -Recurse | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($runtime.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$records = @()
function Run-Bounded([string]$Name, [string[]]$Argv, [bool]$ImportOnly = $false) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = ($Argv | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $runtime
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['APPDATA'] = Join-Path $run 'profile/roaming'
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $run 'profile/local'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    try {
        $expired = -not $p.WaitForExit(8000)
        if ($expired) { $p.Kill(); [void]$p.WaitForExit(2000) }
        if (-not $o.Wait(2000) -or -not $e.Wait(2000)) { throw 'Salida sin cerrar.' }
        [IO.File]::WriteAllText((Join-Path $run ($Name+'.stdout.log')), $o.Result)
        [IO.File]::WriteAllText((Join-Path $run ($Name+'.stderr.log')), $e.Result)
        $errors = @(($o.Result+"`n"+$e.Result) -split "`r?`n" | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:)' -and $_ -ne 'ERROR: Failed to read the root certificate store.' })
        $result = $null
        $resultFile = Join-Path $run ($Name+'.result.json')
        if (Test-Path -LiteralPath $resultFile) { $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        $rec = [ordered]@{name=$Name;exit_code=$p.ExitCode;timed_out=$expired;ms=$watch.ElapsedMilliseconds;errors=$errors;status=$(if($result){$result.status}elseif($ImportOnly){'IMPORTED'}else{'NO_RESULT'})}
        $script:records += $rec
        Write-Host ($Name+': exit='+$p.ExitCode+' '+$rec.status+' '+$rec.ms+' ms')
        if ($p.ExitCode -ne 0 -or $expired -or $errors.Count -or (-not $ImportOnly -and (-not $result -or $result.status -ne 'PASSED'))) {
            Write-Host $o.Result; Write-Host $e.Result
            throw ('Fallo: '+$Name+'. Evidencia: '+$run)
        }
    } finally {
        if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(2000) }
        $p.Dispose()
    }
}
try {
    # Generate the class registry from exact production sources. No generated
    # stand-ins or edits to ActorInput/ActorMotor/SimClock are used.
    Run-Bounded 'import' @('--headless','--editor','--path',$runtime,'--quit','--log-file',(Join-Path $run 'import.godot.log')) $true
    foreach ($m in $modeList) {
        $scene = if ($m.StartsWith('hist_')) { 'res://prototypes/objetos_adaptador/probe_history.tscn' } elseif ($m.StartsWith('api_')) { 'res://prototypes/objetos_adaptador/probe_authority.tscn' } else { 'res://prototypes/objetos_adaptador/probe.tscn' }
        Run-Bounded $m @('--headless','--path',$runtime,'--scene',$scene,'--log-file',(Join-Path $run ($m+'.godot.log')),'--',('--mode='+$m),('--result='+(Join-Path $run ($m+'.result.json'))),('--trace='+(Join-Path $run ($m+'.trace.json'))))
    }
} finally {
    [ordered]@{run=$run;runtime=$runtime;dll_sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant();stages=$records;production_sources=$sourceManifest} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCE='+$run)
