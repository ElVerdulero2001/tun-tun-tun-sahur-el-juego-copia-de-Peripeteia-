# Validación independiente (Claude), entrega 5: prepara una copia nueva del ensayo
# con Rapier v0.36.0 y corre cada proceso con límite externo de 8 s, guardando su
# código de salida real, stdout, stderr y resultado. No usa prepare_rapier_probe.ps1
# ni modifica probe.gd/exchange_probe.gd: los copia tal cual junto a mis ensayos.
# Criterios: docs/net/validacion_objetos/criterios_entrega_5.md, parte B.
#   powershell -ExecutionPolicy Bypass -File prototypes\rollback_rapier\validacion_claude\run_rapier.ps1 [-CheckOnly] [-Stages a,b]
param(
    [string]$OutRoot = '',
    [string]$ArchivePath = 'C:\Users\ElCaido97\Downloads\godot-rapier-3d-single.zip',
    [string]$EnginePath = 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe',
    [string[]]$Stages = @(),
    [ValidateRange(1024, 65000)][int]$Port = 45731,
    [string[]]$EnetImportExtra = @(),
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$LimitMs = 8000
$pinned = '9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$fixture = Join-Path $repo 'prototypes\rollback_rapier'
if ([string]::IsNullOrWhiteSpace($OutRoot)) { $OutRoot = Join-Path $repo 'tmp\validacion_objetos\entrega_5\rapier' }
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
$tmpRoot = Join-Path $repo 'tmp'
if (-not (Test-Path -LiteralPath (Join-Path $tmpRoot '.gdignore'))) { [IO.File]::WriteAllText((Join-Path $tmpRoot '.gdignore'), '') }

# 1) Paquete: tamaño y SHA-256 propios, antes de abrirlo.
$zip = Get-Item -LiteralPath $ArchivePath
$sha = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $pinned) { throw ('SHA-256 distinto del fijado: ' + $sha) }

# 2) Copia nueva: fixture de Codex sin cambios + mis ensayos.
$stamp = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
$rt = Join-Path $OutRoot ($stamp + $(if ($CheckOnly) { '_check' } else { '' }))
New-Item -ItemType Directory -Path $rt | Out-Null
foreach ($f in @('project.godot', 'main.tscn', 'probe.gd', 'exchange.tscn', 'exchange_probe.gd')) {
    Copy-Item -LiteralPath (Join-Path $fixture $f) -Destination (Join-Path $rt $f)
}
New-Item -ItemType Directory -Path (Join-Path $rt 'validacion_claude') | Out-Null
Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $_.Extension -in '.gd', '.tscn' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $rt ('validacion_claude\' + $_.Name)) }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
$extracted = @()
try {
    $suffix = 'addons/godot-rapier3d/godot-rapier3d.gdextension'
    $roots = @($archive.Entries | Where-Object { $_.FullName.Replace('\', '/').EndsWith($suffix) })
    if ($roots.Count -ne 1) { throw 'El paquete no tiene una única extensión 3D.' }
    $prefix = $roots[0].FullName.Replace('\', '/').Substring(0, $roots[0].FullName.Length - $suffix.Length)
    $rtFull = [IO.Path]::GetFullPath($rt).TrimEnd('\') + '\'
    $dll = 'libgodot_rapier.windows.x86_64-pc-windows-msvc.dll'
    foreach ($e in $archive.Entries) {
        $name = $e.FullName.Replace('\', '/')
        if (-not $name.StartsWith($prefix + 'addons/godot-rapier3d/') -or $name.EndsWith('/')) { continue }
        $rel = $name.Substring($prefix.Length)
        if ($rel.Contains('/bin/') -and -not $rel.EndsWith('/' + $dll)) { continue }
        $dest = [IO.Path]::GetFullPath((Join-Path $rt $rel))
        if (-not $dest.StartsWith($rtFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta fuera de la copia.' }
        if ($e.Length -gt 128MB) { throw 'Tamaño inesperado.' }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
        $in = $e.Open(); $out = [IO.File]::Open($dest, [IO.FileMode]::CreateNew)
        try { $in.CopyTo($out) } finally { $in.Dispose(); $out.Dispose() }
        $extracted += [ordered]@{ path = $rel; sha256 = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
} finally { $archive.Dispose() }
New-Item -ItemType Directory -Force -Path (Join-Path $rt '.godot') | Out-Null
[IO.File]::WriteAllText((Join-Path $rt '.godot\extension_list.cfg'), "res://addons/godot-rapier3d/godot-rapier3d.gdextension`n", (New-Object Text.UTF8Encoding $false))
$profileRoaming = Join-Path $rt 'profile\roaming'; $profileLocal = Join-Path $rt 'profile\local'
New-Item -ItemType Directory -Force -Path $profileRoaming, $profileLocal | Out-Null
$r = $rt.Replace('\', '/')

# 3) Procesos.
function Quote([string[]]$a) { ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' }
function Start-Stage([string]$name, [string[]]$stageArgs) {
    $a = @('--headless', '--path', $r, '--log-file', ($r + '/' + $name + '.godot.log')) + $stageArgs
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $EnginePath
    $psi.Arguments = Quote $a
    $psi.WorkingDirectory = $rt
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['APPDATA'] = $profileRoaming
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $profileLocal
    $w = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $script:allProcs += $p
    return @{ name = $name; p = $p; w = $w; cmd = ('"' + $EnginePath + '" ' + $psi.Arguments)
        out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync() }
}
function Wait-Stage($s) {
    $left = [Math]::Max(0, $LimitMs - [int]$s.w.ElapsedMilliseconds)
    $timedOut = -not $s.p.WaitForExit($left)
    if ($timedOut) { & taskkill /PID $s.p.Id /T /F | Out-Null; [void]$s.p.WaitForExit(2000) } else { $s.p.WaitForExit() }
    $ms = $s.w.ElapsedMilliseconds
    $o = $s.out.Result; $e = $s.err.Result
    [IO.File]::WriteAllText((Join-Path $rt ($s.name + '.stdout.log')), $o)
    [IO.File]::WriteAllText((Join-Path $rt ($s.name + '.stderr.log')), $e)
    $ignore = '^ERROR: Failed to read the root certificate store\.$'
    $lines = ($o + "`n" + $e) -split "`r?`n"
    $errs = @($lines | Where-Object { ($_ -match '^(SCRIPT ERROR|ERROR|USER ERROR)') -and ($_ -notmatch $ignore) })
    $warns = @($lines | Where-Object { $_ -match '^(WARNING|USER WARNING)' })
    $resPath = Join-Path $rt ($s.name + '.result.json')
    $res = $null
    if (Test-Path -LiteralPath $resPath) { $res = Get-Content -LiteralPath $resPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    return [ordered]@{ stage = $s.name; exit_code = $(if ($s.p.HasExited) { $s.p.ExitCode } else { $null }); timed_out = $timedOut
        ms = $ms; limit_ms = $LimitMs; error_lines = $errs; warning_lines = $warns; result_file = (Test-Path -LiteralPath $resPath)
        status = $(if ($res -and $res.status) { $res.status } elseif ($res) { 'passed={0} failed={1}' -f $res.passed, $res.failed } else { $null })
        backend = $(if ($res) { $res.backend_class } else { $null }); cmd = $s.cmd }
}
function Res([string]$name) { return ('--result=' + $r + '/' + $name + '.result.json') }
$art = $r + '/r3_artifact.bin'
$codexCp = $r + '/codex_checkpoint.bin'
$plan = [ordered]@{
    'codex_probe' = @('--scene', 'res://main.tscn', '--', (Res 'codex_probe'))
    'codex_export' = @('--scene', 'res://exchange.tscn', '--', (Res 'codex_export'), ('--export-checkpoint=' + $codexCp))
    'codex_import' = @('--scene', 'res://exchange.tscn', '--', (Res 'codex_import'), ('--import-checkpoint=' + $codexCp), '--identity-noise')
    'r2_contact' = @('--scene', 'res://validacion_claude/rv_contact.tscn', '--', (Res 'r2_contact'))
    'r3_export' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_export'), '--role=export', ('--out-file=' + $art))
    'r3_import_noise_reverse' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_import_noise_reverse'), '--role=import', ('--source=file:' + $art), '--noise=7', '--reverse')
    'r3_import_swap' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_import_swap'), '--role=import', ('--source=file:' + $art), '--swap')
    'r3_import_second' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_import_second'), '--role=import', ('--source=file:' + $art), '--second-first', '--post-create')
    'r3_import_second_control' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_import_second_control'), '--role=import', ('--source=file:' + $art), '--second-first', '--post-create', '--no-import')
    'r3_enet_export' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_enet_export'), '--role=export', ('--serve-port=' + $Port))
    'r3_enet_import' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_enet_import'), '--role=import', ('--source=enet:' + $Port), '--reverse') + $EnetImportExtra
    # Diagnóstico agregado después de la primera corrida (criterios §6): orden invertido sin ruido, por archivo.
    'r3_import_reverse_only' = @('--scene', 'res://validacion_claude/rv_exchange.tscn', '--', (Res 'r3_import_reverse_only'), '--role=import', ('--source=file:' + $art), '--reverse')
    'r4_spaces' = @('--scene', 'res://validacion_claude/rv_spaces.tscn', '--', (Res 'r4_spaces'))
    'r4_spaces_control' = @('--scene', 'res://validacion_claude/rv_spaces.tscn', '--', (Res 'r4_spaces_control'), '--control')
}
$results = @()
$script:allProcs = @()
if ($CheckOnly) {
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $rt 'validacion_claude') -Filter '*.gd')) {
        $s = Start-Stage ('check_' + $f.BaseName) @('--check-only', '--script', ('res://validacion_claude/' + $f.Name))
        $results += Wait-Stage $s
    }
} else {
    # Con powershell -File la lista llega como un solo texto: separarla y rechazar nombres desconocidos.
    $names = @($Stages | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) { $names = @($plan.Keys) }
    foreach ($n in $names) { if (-not $plan.Contains($n)) { throw ('Etapa desconocida: ' + $n) } }
    $i = 0
    while ($i -lt $names.Count) {
        $n = $names[$i]
        if ($n -eq 'r3_enet_export') {
            # Par concurrente: el exportador escucha, el importador se conecta. Cada uno con su límite.
            $a = Start-Stage $n $plan[$n]
            $b = Start-Stage 'r3_enet_import' $plan['r3_enet_import']
            $results += Wait-Stage $a
            $results += Wait-Stage $b
            $i += 1
            if ($i -lt $names.Count -and $names[$i] -eq 'r3_enet_import') { $i += 1 }
            continue
        }
        $results += Wait-Stage (Start-Stage $n $plan[$n])
        $i += 1
    }
}
$left = @($script:allProcs | Where-Object { -not $_.HasExited })
$summary = [ordered]@{ runtime = $rt; archive = $zip.FullName; archive_bytes = $zip.Length; archive_sha256 = $sha
    pinned_sha256 = $pinned; engine = $EnginePath; limit_ms = $LimitMs; check_only = [bool]$CheckOnly
    extracted = $extracted; stages = $results; godot_left_running = $left.Count }
[IO.File]::WriteAllText((Join-Path $rt 'runner.json'), ($summary | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
foreach ($x in $results) {
    Write-Output ('{0,-28} exit={1,-12} {2,5} ms timeout={3} errores={4} {5}' -f $x.stage, $x.exit_code, $x.ms, $x.timed_out, @($x.error_lines).Count, $x.status)
    foreach ($l in @($x.error_lines)) { if ($l) { Write-Output ('    ' + $l) } }
}
Write-Output ('RUNTIME=' + $rt + ' sha_ok=' + ($sha -eq $pinned) + ' godot_abiertos=' + $left.Count)
