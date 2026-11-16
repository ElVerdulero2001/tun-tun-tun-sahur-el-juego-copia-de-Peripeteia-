param(
    [Parameter(Mandatory = $true)][string]$EnginePath,
    [ValidateSet('solo', 'host', 'client')][string]$Role = 'solo',
    [ValidateSet('prediction', 'reference')][string]$Mode = 'prediction',
    [string]$Address = '127.0.0.1',
    [ValidateRange(1024, 65535)][int]$Port = 43171,
    [ValidateRange(1, 18)][int]$DurationSeconds = 8,
    [ValidateRange(0, 5000)][int]$OneWayMs = 0,
    [ValidateRange(0, 1000)][int]$JitterMs = 0,
    [ValidateRange(0.0, 0.5)][double]$Loss = 0.0,
    [ValidateRange(0.01, 1.0)][double]$Slow = 1.0,
    [string]$LogDirectory = '',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$prototypeRoot = Join-Path $projectRoot 'prototypes\objetos_red'
if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $projectRoot 'tmp\object_prototype_logs'
}
$engineFile = (Resolve-Path -LiteralPath $EnginePath).Path
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$logRoot = (Resolve-Path -LiteralPath $LogDirectory).Path
$runName = '{0}_{1}_{2}' -f [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss_ffff'), $Role, $PID
$stdoutPath = Join-Path $logRoot ($runName + '.stdout.log')
$stderrPath = Join-Path $logRoot ($runName + '.stderr.log')
$godotPath = Join-Path $logRoot ($runName + '.godot.log')
$tracePath = Join-Path $logRoot ($runName + '.jsonl')
foreach ($path in @($prototypeRoot, $godotPath, $tracePath, $Address)) {
    if ($path.Contains('"') -or $path.Contains("`n") -or $path.Contains("`r")) {
        throw 'Las rutas y la dirección no pueden contener comillas ni saltos de línea.'
    }
}
$arguments = @('--headless', '--path', ('"' + $prototypeRoot + '"'), '--log-file', ('"' + $godotPath + '"'))
if ($CheckOnly) {
    $arguments += @('--check-only', '--script', 'res://main.gd')
} else {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $arguments += @('--', ('--duration-ms=' + ($DurationSeconds * 1000)), ('--trace="' + $tracePath + '"'),
        ('--mode=' + $Mode), ('--port=' + $Port), ('--one-way-ms=' + $OneWayMs),
        ('--jitter-ms=' + $JitterMs), ('--loss=' + $Loss.ToString($culture)), ('--slow=' + $Slow.ToString($culture)))
    if ($Role -eq 'host') { $arguments += '--host' }
    if ($Role -eq 'client') { $arguments += ('--join=' + $Address) }
}
$process = $null
$failure = ''
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    $process = Start-Process -FilePath $engineFile -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadlineSeconds = if ($CheckOnly) { 12 } else { $DurationSeconds + 2 }
    while (-not $process.HasExited) {
        $messages = @()
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $path) { $messages += @(Get-Content -LiteralPath $path -Encoding UTF8) }
        }
        $errors = @($messages | Where-Object {
            $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$'
        })
        if ($errors.Count -gt 0) { $failure = $errors -join [Environment]::NewLine; break }
        if ($watch.Elapsed.TotalSeconds -gt $deadlineSeconds) { $failure = 'Venció el límite externo de la corrida.'; break }
        [void]$process.WaitForExit(100)
    }
    if ($process.HasExited) { $process.WaitForExit() }
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        [void]$process.WaitForExit(1000)
    }
}
$messages = @()
foreach ($path in @($stdoutPath, $stderrPath)) {
    if (Test-Path -LiteralPath $path) { $messages += @(Get-Content -LiteralPath $path -Encoding UTF8) }
}
$errors = @($messages | Where-Object {
    $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$'
})
if ($errors.Count -gt 0) { $failure = $errors -join [Environment]::NewLine }
if ($process.ExitCode -ne 0) { $failure += "`nGodot terminó con código $($process.ExitCode)." }
if (-not $CheckOnly -and -not (($messages -join "`n").Contains('OBJECT_PROTO_BOOT'))) {
    $failure += "`nNo se observó el marcador de arranque."
}
[pscustomobject]@{
    Status = $(if ($failure) { 'FAILED' } else { 'LOAD_OK' })
    Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
    Trace = $tracePath
    Stdout = $stdoutPath
    Stderr = $stderrPath
    Note = 'Solo comprueba carga y cierre. No certifica física, red ni trayectorias.'
} | Format-List
if ($failure) { throw $failure }
