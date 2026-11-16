param(
    [string]$ArchivePath = 'C:\Users\ElCaido97\Downloads\godot-rapier-3d-single.zip',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe'
)

$ErrorActionPreference = 'Stop'
$expectedArchiveHash = '9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a'
$downloadUrl = 'https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-3d-single.zip'
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Falta el paquete fijado v0.36.0. Descargar sin extraer: $downloadUrl . Ruta esperada: $ArchivePath"
}
$actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedArchiveHash) { throw 'El SHA-256 del paquete no coincide con la publicación oficial fijada.' }
$engine = (Resolve-Path -LiteralPath $EnginePath).Path
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $repo 'prototypes\rollback_rapier'
$tempRoot = Join-Path $repo 'tmp'
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$ignorePath = Join-Path $tempRoot '.gdignore'
if (-not (Test-Path -LiteralPath $ignorePath)) { [IO.File]::WriteAllText($ignorePath, '') }
$runtime = Join-Path $tempRoot ('rapier_probe_' + [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $runtime | Out-Null
foreach ($relative in @('project.godot', 'main.tscn', 'probe.gd', 'exchange_probe.gd', 'exchange.tscn')) {
    Copy-Item -LiteralPath (Join-Path $source $relative) -Destination (Join-Path $runtime $relative)
}
$settingsPath = Join-Path $runtime 'project.godot'
$settings = [IO.File]::ReadAllText($settingsPath)
if (-not $settings.Contains('config/name="Tun-tun: rollback capability probe"')) { throw 'La fuente no corresponde al ensayo aislado.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
$extracted = @()
try {
    $suffix = 'addons/godot-rapier3d/godot-rapier3d.gdextension'
    $roots = @($archive.Entries | Where-Object { $_.FullName.Replace('\','/').EndsWith($suffix) })
    if ($roots.Count -ne 1) { throw 'El paquete no contiene una única extensión 3D esperada.' }
    $entryRoot = $roots[0].FullName.Replace('\','/')
    $prefix = $entryRoot.Substring(0, $entryRoot.Length - $suffix.Length)
    $addonPrefix = $prefix + 'addons/godot-rapier3d/'
    $runtimePrefix = [IO.Path]::GetFullPath($runtime).TrimEnd('\') + '\'
    $dllName = 'libgodot_rapier.windows.x86_64-pc-windows-msvc.dll'
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\','/')
        if (-not $name.StartsWith($addonPrefix) -or $name.EndsWith('/')) { continue }
        $relative = $name.Substring($prefix.Length)
        if ($relative.Contains('/bin/') -and -not $relative.EndsWith('/' + $dllName)) { continue }
        $destination = [IO.Path]::GetFullPath((Join-Path $runtime $relative))
        if (-not $destination.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta de archivo fuera de la carpeta del ensayo.' }
        if ($entry.Length -gt 128MB) { throw 'Tamaño descomprimido inesperado.' }
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        $entryStream = $entry.Open()
        $destinationStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew)
        try { $entryStream.CopyTo($destinationStream) } finally { $entryStream.Dispose(); $destinationStream.Dispose() }
        $extracted += [pscustomobject]@{ path=$relative; sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $runtime ('addons/godot-rapier3d/bin/' + $dllName)))) { throw 'No se encontró el binario Windows x64 fijado.' }
} finally { $archive.Dispose() }

function Invoke-ProbeEngine([string]$Stage, [string[]]$Arguments, [int]$LimitSeconds) {
    $stdout = Join-Path $runtime ($Stage + '.stdout.log')
    $stderr = Join-Path $runtime ($Stage + '.stderr.log')
    # Godot reads these at startup. Keep editor settings and user:// inside
    # this run too, without changing the user's environment persistently.
    $savedAppData = $env:APPDATA
    $savedLocalAppData = $env:LOCALAPPDATA
    try {
        $env:APPDATA = Join-Path $runtime 'profile/roaming'
        $env:LOCALAPPDATA = Join-Path $runtime 'profile/local'
        New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
        $p = Start-Process -FilePath $engine -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Retain the handle before a fast process exits (PowerShell otherwise
        # may lose ExitCode when Start-Process is used without -Wait).
        $processHandle = $p.Handle
    } finally {
        $env:APPDATA = $savedAppData
        $env:LOCALAPPDATA = $savedLocalAppData
    }
    try {
        if (-not $p.WaitForExit($LimitSeconds * 1000)) { throw ("Venció el límite de " + $Stage) }
        $errors = @(Get-Content -LiteralPath $stderr -Encoding UTF8 | Where-Object {
            $_ -match '^(ERROR:|SCRIPT ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$'
        })
        if ($null -eq $p.ExitCode -or $p.ExitCode -ne 0 -or $errors.Count) { throw ("Falló " + $Stage + " (exit=" + $p.ExitCode + "): " + ($errors -join ' ') + '. Logs: ' + $runtime) }
    } finally {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; [void]$p.WaitForExit(1000) }
    }
}

$utf8 = New-Object Text.UTF8Encoding $false
# This fixture has no imported assets. Register the pinned extension before
# the first game startup, keeping Rapier selected throughout. Loading Rapier
# in a Jolt editor process caused a native access violation at editor exit.
$cache = Join-Path $runtime '.godot'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $cache 'extension_list.cfg'), "res://addons/godot-rapier3d/godot-rapier3d.gdextension`n", $utf8)

$manifest = [pscustomobject]@{ version='v0.36.0'; source=$downloadUrl; archive_sha256=$actualHash; runtime_project=$runtime; files=$extracted }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runtime 'dependency.json') -Encoding UTF8
$resultPath = Join-Path $runtime 'probe_result.json'
Invoke-ProbeEngine 'probe' @('--headless','--path',('"'+$runtime+'"'),'--log-file',('"'+(Join-Path $runtime 'probe.godot.log')+'"'),'--',('--result="'+$resultPath+'"')) 8
if (-not (Test-Path -LiteralPath $resultPath)) { throw ('No se produjo el resultado: ' + $runtime) }
$probeResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($probeResult.status -ne 'PASSED' -or $probeResult.backend_class -ne 'RapierPhysicsServer3D' -or $probeResult.dependency -ne 'v0.36.0') { throw 'El resultado no acredita el ensayo fijado.' }
Get-Content -LiteralPath $resultPath -Encoding UTF8
$checkpointPath = Join-Path $runtime 'trusted_checkpoint.bin'
foreach ($role in @('export', 'import')) {
    $exchangeResult = Join-Path $runtime ($role + '_result.json')
    $exchangeArgs = @('--headless','--path',('"'+$runtime+'"'),'--scene','res://exchange.tscn','--log-file',('"'+(Join-Path $runtime ($role + '.godot.log'))+'"'),'--',('--result="'+$exchangeResult+'"'))
    if ($role -eq 'export') { $exchangeArgs += '--export-checkpoint="'+$checkpointPath+'"' }
    else { $exchangeArgs += @('--import-checkpoint="'+$checkpointPath+'"', '--identity-noise') }
    Invoke-ProbeEngine $role $exchangeArgs 8
    if (-not (Test-Path -LiteralPath $exchangeResult)) { throw ('Falta el resultado de ' + $role) }
    $exchangeData = Get-Content -LiteralPath $exchangeResult -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($exchangeData.status -ne 'PASSED' -or $exchangeData.exchange_role -ne $role -or $exchangeData.backend_class -ne 'RapierPhysicsServer3D') { throw ('No se aprobó ' + $role) }
    Get-Content -LiteralPath $exchangeResult -Encoding UTF8
}
Write-Output ('RUNTIME_PROJECT=' + $runtime)
