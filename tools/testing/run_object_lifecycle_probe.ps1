param([string]$Modes = 'net_future,net_close,net_timeout,net_lease,net_quiet,action_window', [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$dll = Join-Path $repo 'tmp/native_target/debug/sahur_object_world.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Compilar primero la extensión.' }
$nativeSources = @(Get-ChildItem (Join-Path $repo 'native/objetos_core/src') -Filter '*.rs')
$nativeSources += Get-Item (Join-Path $repo 'native/objetos_core/Cargo.toml'), (Join-Path $repo 'native/objetos_core/Cargo.lock')
if (@($nativeSources | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes.' }
$run = Join-Path $repo ('tmp/lifecycle_probe/' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
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
function Start-Probe([string]$name, [string[]]$argv) {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$EnginePath; $psi.Arguments=($argv | ForEach-Object {'"'+$_+'"'}) -join ' '
    $psi.WorkingDirectory=$runtime; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.EnvironmentVariables['APPDATA']=Join-Path $run 'profile/roaming'
    $psi.EnvironmentVariables['LOCALAPPDATA']=Join-Path $run 'profile/local'
    $p=[Diagnostics.Process]::Start($psi)
    return @{name=$name;p=$p;o=$p.StandardOutput.ReadToEndAsync();e=$p.StandardError.ReadToEndAsync();watch=[Diagnostics.Stopwatch]::StartNew()}
}
function Collect-Probe($job, [bool]$importOnly=$false) {
    $p=$job.p; $remaining=[Math]::Max(1,8000-$job.watch.ElapsedMilliseconds)
    $expired=-not $p.WaitForExit([int]$remaining)
    if($expired){$p.Kill(); [void]$p.WaitForExit(2000)}
    if(-not $job.o.Wait(2000) -or -not $job.e.Wait(2000)){throw 'Output not closed'}
    [IO.File]::WriteAllText((Join-Path $run ($job.name+'.stdout.log')),$job.o.Result)
    [IO.File]::WriteAllText((Join-Path $run ($job.name+'.stderr.log')),$job.e.Result)
    $errors=@(($job.o.Result+"`n"+$job.e.Result) -split "`r?`n" | Where-Object {$_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:)' -and $_ -ne 'ERROR: Failed to read the root certificate store.'})
    $resultFile=Join-Path $run ($job.name+'.result.json'); $result=$null
    if(Test-Path -LiteralPath $resultFile){$result=Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json}
    $record=[ordered]@{name=$job.name;exit_code=$p.ExitCode;timed_out=$expired;ms=$job.watch.ElapsedMilliseconds;errors=$errors;status=$(if($importOnly){'IMPORTED'}elseif($result){$result.status}else{'NO_RESULT'})}
    $script:records+=$record
    Write-Host ($job.name+': exit='+$p.ExitCode+' '+$record.status+' '+$record.ms+' ms')
    if($p.ExitCode -ne 0 -or $expired -or $errors.Count -or (-not $importOnly -and $record.status -ne 'PASSED')){
        Write-Host $job.o.Result; Write-Host $job.e.Result
        throw ('Failed '+$job.name+' Evidence='+$run)
    }
}
$owned=@()
$seen=@{}
try {
    $job=Start-Probe 'import' @('--headless','--editor','--path',$runtime,'--quit','--log-file',(Join-Path $run 'import.godot.log')); $owned+=$job
    Collect-Probe $job $true
    foreach($mode in ($Modes -split ',')) {
        $seen[$mode]=1+$(if($seen.ContainsKey($mode)){$seen[$mode]}else{0})
        $tag=if($seen[$mode] -gt 1){$mode+'_'+$seen[$mode]}else{$mode}
        $socket=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
        $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0)); $port=$socket.LocalEndPoint.Port; $socket.Dispose()
        $jobs=@()
        foreach($role in $(if($mode -in @('action_window','host_journal')){@('single')}else{@('host','client')})) {
            $name=$tag+'_'+$role
            $scene=if($mode -eq 'net_play_room'){'res://prototypes/objetos_adaptador/probe_play_room.tscn'}elseif($mode -eq 'host_journal'){'res://prototypes/objetos_adaptador/probe_host_journal.tscn'}elseif($mode -eq 'net_journal'){'res://prototypes/objetos_adaptador/probe_journal_network.tscn'}elseif($mode -eq 'action_window'){'res://prototypes/objetos_adaptador/probe_action_window.tscn'}elseif($mode -eq 'net_quiet'){'res://prototypes/objetos_adaptador/probe_quiet.tscn'}else{'res://prototypes/objetos_adaptador/probe_lifecycle.tscn'}
            $job=Start-Probe $name @('--headless','--path',$runtime,'--scene',$scene,'--log-file',(Join-Path $run ($name+'.godot.log')),'--',('--role='+$role),('--mode='+$mode),('--port='+$port),('--result='+(Join-Path $run ($name+'.result.json'))),('--trace='+(Join-Path $run ($name+'.trace.json'))))
            $owned+=$job; $jobs+=$job
        }
        foreach($job in $jobs){Collect-Probe $job}
    }
} finally {
    foreach($job in $owned){if(-not $job.p.HasExited){$job.p.Kill();[void]$job.p.WaitForExit(2000)};$job.p.Dispose()}
    [ordered]@{run=$run;runtime=$runtime;dll_sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant();stages=$records;production_sources=$sourceManifest} | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $run 'runner.json') -Encoding utf8
}
Write-Host ('EVIDENCE='+$run)
