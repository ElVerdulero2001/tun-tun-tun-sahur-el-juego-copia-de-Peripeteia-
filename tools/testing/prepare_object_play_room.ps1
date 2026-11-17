param(
    [string]$OutputPath = '',
    [string]$EnginePath = '',
    [switch]$Launch
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path $repo 'tmp/sala_objetos_jugable' }
$runtime = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $runtime) { throw "Usá una carpeta nueva: $runtime" }
$dll = Join-Path $repo 'tmp/native_target/debug/sahur_object_world.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Falta la DLL compilada de objetos.' }
$native = @(Get-ChildItem -LiteralPath (Join-Path $repo 'native/objetos_core/src') -Filter '*.rs')
$native += Get-Item (Join-Path $repo 'native/objetos_core/Cargo.toml'), (Join-Path $repo 'native/objetos_core/Cargo.lock')
if (@($native | Where-Object LastWriteTimeUtc -GT (Get-Item -LiteralPath $dll).LastWriteTimeUtc).Count) {
    throw 'La DLL es anterior a las fuentes nativas. Compilala antes de preparar la sala.'
}
New-Item -ItemType Directory -Path $runtime,(Join-Path $runtime 'bin'),(Join-Path $runtime 'scenes/actor'),(Join-Path $runtime 'prototypes/objetos_adaptador') -Force | Out-Null
$project = [IO.File]::ReadAllText((Join-Path $repo 'prototypes/objetos_nativo/project.godot'))
$project = $project.Replace('Sahur native object world probe', 'Sala de objetos').Replace('res://main.tscn','res://prototypes/objetos_adaptador/play_room.tscn')
[IO.File]::WriteAllText((Join-Path $runtime 'project.godot'), $project, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $repo 'prototypes/objetos_nativo/extension.gdextension.in') -Destination (Join-Path $runtime 'extension.gdextension')
Copy-Item -LiteralPath $dll -Destination (Join-Path $runtime 'bin/sahur_object_world.dll')
Copy-Item -LiteralPath (Join-Path $repo 'scenes/actor/actor.tscn') -Destination (Join-Path $runtime 'scenes/actor/actor.tscn')
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination (Join-Path $runtime 'scripts') -Recurse
$modules = @('authority_channel.gd','clock_adapter.gd','history_bridge.gd','host_action_journal.gd','scene_network_bridge.gd','play_room.gd','play_room.tscn')
foreach ($file in $modules) {
    Copy-Item -LiteralPath (Join-Path $repo ('prototypes/objetos_adaptador/' + $file)) -Destination (Join-Path $runtime 'prototypes/objetos_adaptador')
}
Copy-Item -LiteralPath (Join-Path $repo 'tools/testing/abrir_sala_objetos.cmd') -Destination $runtime
Copy-Item -LiteralPath (Join-Path $repo 'docs/net/entregas/sala_objetos_jugable.md') -Destination (Join-Path $runtime 'LEEME.md')
Write-Host "SALA=$runtime"
if ($Launch) {
    if (-not $EnginePath) { $EnginePath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Godot_v4.7.2.exe' }
    & (Join-Path $runtime 'abrir_sala_objetos.cmd') $EnginePath
    if ($LASTEXITCODE) { throw "El lanzador salió con código $LASTEXITCODE" }
}
