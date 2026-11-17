param(
    [ValidateSet('all','local','file','enet','late')][string]$Stages = 'all',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [ValidateRange(1024,65000)][int]$Port = 46231
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$dll = Join-Path $repo 'tmp/native_target/debug/sahur_object_world.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Compilar primero: build_object_native.ps1 -Stage Extension' }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native/objetos_core/src') -Recurse -File -Filter '*.rs')
$sources += Get-Item (Join-Path $repo 'native/objetos_core/Cargo.toml'), (Join-Path $repo 'native/objetos_core/Cargo.lock')
if (@($sources | Where-Object LastWriteTimeUtc -GT (Get-Item $dll).LastWriteTimeUtc).Count) { throw 'La DLL es anterior a las fuentes. Volver a compilar.' }
$runtime = Join-Path $repo ('tmp/native_probe/' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $runtime,(Join-Path $runtime 'bin'),(Join-Path $runtime '.godot'),(Join-Path $runtime 'profile/roaming'),(Join-Path $runtime 'profile/local') -Force | Out-Null
$fixture = Join-Path $repo 'prototypes/objetos_nativo'
foreach ($name in @('project.godot','main.tscn','probe.gd','late_action.gd','late_action.tscn')) { Copy-Item -LiteralPath (Join-Path $fixture $name) -Destination (Join-Path $runtime $name) }
Copy-Item -LiteralPath (Join-Path $fixture 'extension.gdextension.in') -Destination (Join-Path $runtime 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $runtime 'bin/sahur_object_world.dll')
[IO.File]::WriteAllText((Join-Path $runtime '.godot/extension_list.cfg'), "res://extension.gdextension`n", (New-Object Text.UTF8Encoding $false))
$results = @()
$processes = @()
function Start-Stage([string]$Name, [string]$Role) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $scene = if($Role -like 'late_*'){'res://late_action.tscn'}else{'res://main.tscn'}
    $marker = if($Role -like 'late_*'){'late_ready.txt'}else{'server_ready.txt'}
    $stageArgs = @('--headless','--path',$runtime,'--scene',$scene,'--log-file',(Join-Path $runtime ($Name+'.godot.log')),'--',('--role='+$Role),('--port='+$Port),('--result='+(Join-Path $runtime ($Name+'.result.json'))),('--artifact='+(Join-Path $runtime 'trusted_artifact.bin')),('--ready='+(Join-Path $runtime $marker)))
    $psi.Arguments = ($stageArgs | ForEach-Object { '"'+$_+'"' }) -join ' '
    $psi.WorkingDirectory = $runtime
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['APPDATA'] = Join-Path $runtime 'profile/roaming'
    $psi.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $runtime 'profile/local'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $script:processes += $p
    return @{p=$p;name=$Name;watch=$watch;out=$p.StandardOutput.ReadToEndAsync();err=$p.StandardError.ReadToEndAsync()}
}
function Wait-Stage($s) {
    $remaining = [Math]::Max(0,8000-[int]$s.watch.ElapsedMilliseconds)
    $expired = -not $s.p.WaitForExit($remaining)
    if ($expired) { $s.p.Kill(); [void]$s.p.WaitForExit(2000) }
    if (-not $s.out.Wait(2000) -or -not $s.err.Wait(2000)) { throw 'Salida del motor sin cerrar.' }
    $o=$s.out.Result; $e=$s.err.Result
    [IO.File]::WriteAllText((Join-Path $runtime ($s.name+'.stdout.log')),$o)
    [IO.File]::WriteAllText((Join-Path $runtime ($s.name+'.stderr.log')),$e)
    $errors = @(($o+"`n"+$e) -split "`r?`n" | Where-Object {$_ -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:)' -and $_ -ne 'ERROR: Failed to read the root certificate store.'})
    $resultFile=Join-Path $runtime ($s.name+'.result.json')
    $r=$null
    if(Test-Path -LiteralPath $resultFile){$r=Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json}
    $record=[ordered]@{name=$s.name;exit_code=$s.p.ExitCode;timed_out=$expired;ms=$s.watch.ElapsedMilliseconds;errors=$errors;status=$(if($r){$r.status}else{'NO_RESULT'})}
    $script:results += $record
    Write-Host ($s.name+': exit='+$record.exit_code+' '+$record.status+' '+$record.ms+' ms')
    if($record.exit_code -ne 0 -or $expired -or $errors.Count -or -not $r -or $r.status -ne 'PASSED') {
        Write-Host $o;Write-Host $e
        throw ('Fallo del ensayo '+$s.name+'. Logs: '+$runtime)
    }
}
try {
    if($Stages -in @('all','local')) { Wait-Stage (Start-Stage 'local' 'local') }
    if($Stages -in @('all','file')) { Wait-Stage (Start-Stage 'export' 'export'); Wait-Stage (Start-Stage 'import' 'import') }
    if($Stages -in @('all','enet')) {
        $server=Start-Stage 'enet_export' 'enet_export'
        while(-not (Test-Path -LiteralPath (Join-Path $runtime 'server_ready.txt')) -and -not $server.p.HasExited -and $server.watch.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        if(-not (Test-Path -LiteralPath (Join-Path $runtime 'server_ready.txt'))) { Wait-Stage $server; throw 'Servidor sin marca de preparado.' }
        $client=Start-Stage 'enet_import' 'enet_import'
        Wait-Stage $server
        Wait-Stage $client
    }
    if($Stages -in @('all','late')) {
        $server=Start-Stage 'late_host' 'late_host'
        while(-not (Test-Path -LiteralPath (Join-Path $runtime 'late_ready.txt')) -and -not $server.p.HasExited -and $server.watch.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 25 }
        if(-not (Test-Path -LiteralPath (Join-Path $runtime 'late_ready.txt'))) { Wait-Stage $server; throw 'Servidor tardio sin preparar.' }
        $client=Start-Stage 'late_client' 'late_client'
        Wait-Stage $server
        Wait-Stage $client
    }
} finally {
    foreach($p in $processes){if(-not $p.HasExited){$p.Kill();[void]$p.WaitForExit(2000)}}
    [ordered]@{runtime=$runtime;dll_sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant();lock_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'native/objetos_core/Cargo.lock') -Algorithm SHA256).Hash.ToLowerInvariant();stages=$results;remaining_own_processes=@($processes | Where-Object {-not $_.HasExited}).Count} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runtime 'runner.json') -Encoding UTF8
}
Write-Host ('EVIDENCE='+$runtime)
