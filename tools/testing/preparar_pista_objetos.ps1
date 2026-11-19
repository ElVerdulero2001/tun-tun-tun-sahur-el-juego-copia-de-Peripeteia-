param(
    ## Carpeta nueva donde se arma el paquete; al lado queda el ZIP.
    [string]$OutputPath = ''
)
## Arma el paquete de la pista de objetos para las dos PC: el proyecto entero
## (sin .git ni tmp), la DLL de objetos, el lanzador y la guía como LEEME.md.
## Las dos PC tienen que usar el mismo ZIP: la huella del laboratorio compara
## el nivel, y la pista lleva la revisión de su modelo.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path $repo -Parent) 'pista_objetos_piloto' }
$out = [IO.Path]::GetFullPath($OutputPath)
$zip = $out + '.zip'
if (Test-Path -LiteralPath $out) { throw "Usá una carpeta nueva: $out" }
if (Test-Path -LiteralPath $zip) { throw "Ya existe el ZIP: $zip" }
$dll = Join-Path $repo 'bin/sahur_object_world.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Falta bin/sahur_object_world.dll' }
New-Item -ItemType Directory -Path $out | Out-Null
$skip = @('.git', '.godot', 'tmp', 'diagnosticos_pista', 'import.log', 'pista.log', 'scripts.zip', 'scripts.rar')
Get-ChildItem -LiteralPath $repo -Force | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $out -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $repo 'tools/testing/abrir_pista_objetos.cmd') -Destination $out
Copy-Item -LiteralPath (Join-Path $repo 'docs/net/entregas/pista_objetos_piloto.md') -Destination (Join-Path $out 'LEEME.md')
& tar.exe -a -cf $zip -C $out .
if ($LASTEXITCODE -ne 0) { throw "No se pudo armar el ZIP: $zip" }
$size = [Math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
Write-Host "PAQUETE=$out"
Write-Host "ZIP=$zip ($size MB)"
