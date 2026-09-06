<#
.SYNOPSIS
    Corre una o varias escenas de test de Godot en modo headless, con un
    timeout duro, captura confiable del exit code, y validación de que cada
    escena es real ANTES de tocar Godot.

.DESCRIPTION
    Reemplaza el patrón "godot --headless <escena>" corrido a mano: ese
    patrón no tiene límite de tiempo, así que si el proceso no llama a
    SceneTree.quit() por algún bug del arnés (ya nos pasó: un assert()
    fallido ANTES de quit() corta la función y el proceso queda vivo para
    siempre en headless, sin ventana que cerrar), la sesión que lo lanzó
    queda colgada sin ningún aviso.

    Lanza el proceso con [System.Diagnostics.Process] directo (NO
    Start-Process -PassThru: en esta versión de PowerShell su ExitCode
    queda vacío incluso después de HasExited=true y Refresh() — se verificó
    empíricamente con un proceso de prueba que salía con código 3 y
    Start-Process -PassThru lo reportaba vacío; el mismo caso con
    [System.Diagnostics.Process] devuelve 3 correctamente). Process.WaitForExit(timeoutMs)
    es un método .NET que sí bloquea con un límite de tiempo real, a
    diferencia de asumir que "la consola volvió" quiere decir que terminó.

    Si vence el timeout, mata el ÁRBOL COMPLETO del PID que lanzó (nunca
    "todos los Godot que haya") con "taskkill /PID <pid> /T /F" — no alcanza
    con Process.Kill(): Godot_..._console.exe no es el motor, lanza un
    proceso HIJO real (Godot_..._win64.exe, sin "_console") que hace todo
    el trabajo, y Process.Kill() de .NET Framework mata un solo proceso, sin
    overload de árbol completo (ese llegó recién en .NET Core 3+). El
    ExitCode solo se lee después de confirmar que el proceso terminó de
    verdad por sí solo.

    Antes de lanzar nada, valida cada -Scene: tiene que ser UNA escena
    (formato res://..., extensión .tscn) cuyo archivo exista de verdad bajo
    -ProjectPath. Esto existe porque en un incidente real, invocar este
    script anidado dentro de otro "powershell -File" aplanó un array de dos
    escenas en un solo string separado por coma, y Godot terminó intentando
    abrir un path inválido que colgó hasta el timeout sin ningún aviso
    claro de qué había pasado. Si alguna escena no valida, el script NO
    lanza Godot para ninguna: imprime el motivo y sale con código 2.

    Después de que una escena termina (por sí sola, no por timeout) con
    ExitCode 0, igual se confirma que ni el PID lanzado ni ningún hijo suyo
    siga vivo. Si algo sobrevivió, eso NO es un resultado exitoso aunque el
    test en sí haya dado 0 fallas: es un problema de infraestructura (el
    proceso no se desmontó solo) y el resultado global pasa a ser código 2,
    nunca 0. 124 queda reservado EXCLUSIVAMENTE para "hubo que matar por
    timeout"; 1 queda reservado EXCLUSIVAMENTE para "terminó por sí solo
    pero con fallas reales del test".

    A propósito NO usa --quit-after como mecanismo normal de cierre: ese
    flag corta por cantidad de frames, no por tiempo ni por trabajo
    completado, y un corte demasiado temprano podría reportar success con
    fallas ya impresas en el log. El único mecanismo de cierre válido es
    que el propio test llame quit() con su código de fallas.

.PARAMETER Scene
    Una o más escenas de test, en formato res://... y extensión .tscn (ej.
    res://scenes/test/traversal_resolver_test.tscn). Se validan TODAS antes
    de correr NINGUNA (ver DESCRIPTION). Se corren en secuencia, esperando
    que cada proceso (y sus hijos) termine de verdad antes de lanzar la
    siguiente.

.PARAMETER TimeoutSeconds
    Timeout duro por escena, en segundos. Default 60.

.PARAMETER GodotExe
    Ruta al ejecutable de Godot. Default: $env:GODOT_EXE si está seteada,
    si no una ruta fija de esta máquina (ajustar según dónde esté instalado
    Godot en cada equipo, o setear la variable de entorno GODOT_EXE).

.PARAMETER ProjectPath
    Raíz del proyecto Godot (donde está project.godot). Default: dos
    niveles arriba de este script (tools/testing/ -> raíz del repo). Cada
    -Scene se valida convirtiendo "res://algo.tscn" en "<ProjectPath>\algo.tscn"
    y comprobando que el archivo exista ahí.

.PARAMETER LogDir
    Carpeta donde se guardan stdout/stderr de cada corrida. Default:
    tools/testing/logs/ (no versionado, ver .gitignore).

.EXAMPLE
    .\run_headless_test.ps1 -Scene res://scenes/test/traversal_resolver_test.tscn

.EXAMPLE
    # Fase 1 y Fase 2 en secuencia, con timeout de 90s cada una
    & .\run_headless_test.ps1 -Scene `
        res://scenes/test/traversal_resolver_test.tscn, `
        res://scenes/test/player_motor_test.tscn `
        -TimeoutSeconds 90

.OUTPUTS
    Código de salida del proceso de PowerShell:
      0   -> todas las escenas terminaron solas, ExitCode 0, y no quedó
             ningún proceso vivo.
      1   -> todas cerraron limpio (sin procesos vivos), pero al menos una
             con ExitCode != 0 -- fallas reales del test, ver el log.
      2   -> error de configuración/validación (Godot o el proyecto no se
             encontraron, una -Scene es inválida o no existe), O una escena
             reportó ExitCode 0 pero dejó un proceso vivo (wrapper o hijo)
             -- error de infraestructura, NUNCA se reporta como éxito.
      124 -> al menos una escena no terminó sola dentro del timeout y hubo
             que matar su árbol de procesos -- el resultado de ESA corrida
             no es confiable, cualquier ExitCode/línea de log posterior al
             corte se ignora.
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Scene,

    [int]$TimeoutSeconds = 60,

    [string]$GodotExe = $(if ($env:GODOT_EXE) { $env:GODOT_EXE } else { "C:\Godot\4.6.3\Godot_v4.6.3-stable_win64_console.exe" }),

    [string]$ProjectPath,

    [string]$LogDir
)

# $PSScriptRoot se evalúa VACÍO dentro de los default values de arriba en
# Windows PowerShell 5.1 cuando el script tiene un parámetro Mandatory (es
# un quirk conocido del pre-pase que hace PowerShell para detectar
# mandatorios antes de terminar de bindear el resto). Por eso estos dos
# defaults se resuelven acá, en el cuerpo, donde $PSScriptRoot sí está
# poblado — no arriba, en el bloque param().
if (-not $ProjectPath) {
    $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
if (-not $LogDir) {
    $LogDir = Join-Path $PSScriptRoot "logs"
}

if (-not (Test-Path $GodotExe)) {
    Write-Error "No se encontró el ejecutable de Godot en '$GodotExe'. Pasá -GodotExe o seteá `$env:GODOT_EXE."
    exit 2
}
if (-not (Test-Path (Join-Path $ProjectPath "project.godot"))) {
    Write-Error "'$ProjectPath' no tiene project.godot. Pasá -ProjectPath explícito."
    exit 2
}
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ── Validación de escenas — ANTES de tocar Godot ──────────────────────
# Cada -Scene debe ser UNA escena real: res://..., termina en .tscn, y el
# archivo existe de verdad bajo ProjectPath. Nada de esto lanza Godot
# todavía: es puramente chequeo de PowerShell/filesystem. Si algo no
# valida, no se corre NADA (ni siquiera las escenas que sí son válidas) —
# una lista mal formada suele significar que el binding de parámetros salió
# mal (ver DESCRIPTION), y correr "a medias" solo agregaría confusión sobre
# qué se ejecutó y qué no.
function Test-EscenaGodot {
    param([string]$Escena, [string]$ProjectPathBase)

    if ($Escena -match ',') {
        return [pscustomobject]@{ Valida = $false; Motivo = "contiene una coma -- probable lista aplanada en un solo string en vez de un array de -Scene" }
    }
    if ($Escena -notmatch '^res://') {
        return [pscustomobject]@{ Valida = $false; Motivo = "no empieza con 'res://'" }
    }
    if ($Escena -notmatch '\.tscn$') {
        return [pscustomobject]@{ Valida = $false; Motivo = "no termina en '.tscn'" }
    }
    $relativo = ($Escena.Substring(6)) -replace '/', '\'
    $rutaReal = Join-Path $ProjectPathBase $relativo
    if (-not (Test-Path -LiteralPath $rutaReal -PathType Leaf)) {
        return [pscustomobject]@{ Valida = $false; Motivo = "el archivo no existe en '$rutaReal'" }
    }
    return [pscustomobject]@{ Valida = $true; Motivo = "" }
}

$escenasInvalidas = @()
foreach ($escena in $Scene) {
    $chequeo = Test-EscenaGodot -Escena $escena -ProjectPathBase $ProjectPath
    if (-not $chequeo.Valida) {
        $escenasInvalidas += [pscustomobject]@{ Escena = $escena; Motivo = $chequeo.Motivo }
    }
}
if ($escenasInvalidas.Count -gt 0) {
    Write-Error "Una o mas escenas de -Scene no son validas -- no se lanza Godot para NINGUNA:"
    foreach ($inv in $escenasInvalidas) {
        Write-Error ("  '{0}' -> {1}" -f $inv.Escena, $inv.Motivo)
    }
    exit 2
}

$resultados = @()
$huboTimeout = $false
$huboFallas = $false
$huboHuerfano = $false

foreach ($escena in $Scene) {
    $nombre = [System.IO.Path]::GetFileNameWithoutExtension($escena)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logOut = Join-Path $LogDir "$nombre.$timestamp.stdout.log"
    $logErr = Join-Path $LogDir "$nombre.$timestamp.stderr.log"

    Write-Output "==> Corriendo '$escena' (timeout ${TimeoutSeconds}s)..."
    $inicio = Get-Date

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GodotExe
    # --scene explícito (no posicional): Godot lo documenta como "Path or
    # UID of a scene in the project that should be started" -- separarlo de
    # --path evita cualquier ambigüedad sobre qué argumento es la escena.
    $psi.Arguments = "--headless --path `"$ProjectPath`" --scene `"$escena`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null
    $pid_lanzado = $proc.Id

    # Lectura asíncrona: si el proceso escribe más de lo que cabe en el
    # buffer del pipe y nadie lo está leyendo, se puede colgar esperando que
    # alguien vacíe el pipe. ReadToEndAsync() evita ese punto muerto aparte
    # del que ya nos ocupa este script (el del propio arnés de Godot).
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $terminoSolo = $proc.WaitForExit($TimeoutSeconds * 1000)
    $duracion = (Get-Date) - $inicio

    if (-not $terminoSolo) {
        # Godot_..._console.exe NO es el motor: lanza un proceso hijo real
        # (Godot_..._win64.exe, sin "_console") que hace todo el trabajo, más
        # un conhost.exe. Se confirmó empíricamente con Get-CimInstance
        # Win32_Process mientras corría una escena. Process.Kill() (.NET
        # Framework, el que usa Windows PowerShell 5.1) mata SOLO el proceso
        # indicado, sin overload de árbol completo (ese llegó recién en .NET
        # Core 3+). Por eso el kill de timeout usa taskkill /T /F: mata el
        # PID lanzado Y todo lo que cuelga de él — nunca "todos los Godot que
        # haya", solo el árbol de ESTE PID puntual.
        try {
            taskkill /PID $pid_lanzado /T /F 2>&1 | Out-Null
        } catch {
            Write-Warning "No se pudo matar el arbol del PID ${pid_lanzado}: $_"
        }

        # Volcar lo que se haya alcanzado a capturar antes del kill —
        # matar el proceso cierra sus pipes, así que los tasks async
        # deberían completar con el contenido parcial acumulado.
        try { $stdoutTask.Result | Set-Content -Path $logOut -Encoding UTF8 } catch {}
        try { $stderrTask.Result | Set-Content -Path $logErr -Encoding UTF8 } catch {}

        Start-Sleep -Milliseconds 300
        $sigueVivo = Get-Process -Id $pid_lanzado -ErrorAction SilentlyContinue
        # También hay que confirmar que no sobrevivió el hijo real (motor
        # Godot sin "_console"): taskkill /T debería haberlo alcanzado, pero
        # se verifica en vez de asumirlo.
        $hijosVivos = Get-CimInstance Win32_Process -Filter "ParentProcessId=$pid_lanzado" -ErrorAction SilentlyContinue
        $huboTimeout = $true

        Write-Warning "TIMEOUT tras ${TimeoutSeconds}s -- PID $pid_lanzado no cerro solo, se mato su arbol de procesos."
        if ($sigueVivo) {
            Write-Error "El PID $pid_lanzado sigue apareciendo en Get-Process despues de taskkill /T /F."
        }
        if ($hijosVivos) {
            Write-Error "Quedaron hijos vivos del PID $pid_lanzado tras el kill: $($hijosVivos.ProcessId -join ', ')"
        }
        $sigueVivo = $sigueVivo -or $hijosVivos

        $resultados += [pscustomobject]@{
            Escena      = $escena
            Pid_        = $pid_lanzado
            ExitCode    = $null
            Timeout     = $true
            DuracionSeg = [math]::Round($duracion.TotalSeconds, 1)
            LogStdout   = $logOut
            LogStderr   = $logErr
            PidLimpio   = -not $sigueVivo
        }
        continue
    }

    # El proceso terminó por sí solo: recién ahora es seguro leer ExitCode.
    $exitCode = $proc.ExitCode
    $stdoutTask.Result | Set-Content -Path $logOut -Encoding UTF8
    $stderrTask.Result | Set-Content -Path $logErr -Encoding UTF8

    # Godot_..._console.exe puede tardar un poco más en cerrar del todo que
    # el trabajo real que reporta en el log (el wrapper + conhost.exe +
    # el hijo real "..._win64.exe" tardan un momento en desmontarse). Se le
    # da un margen razonable antes de declarar huérfano.
    $sigueVivo = $null
    $hijosVivos = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        $sigueVivo = Get-Process -Id $pid_lanzado -ErrorAction SilentlyContinue
        $hijosVivos = Get-CimInstance Win32_Process -Filter "ParentProcessId=$pid_lanzado" -ErrorAction SilentlyContinue
        if (-not $sigueVivo -and -not $hijosVivos) { break }
    }
    $sigueVivo = $sigueVivo -or $hijosVivos

    # ExitCode 0 con un proceso todavía vivo NO es un resultado exitoso: es
    # un problema de infraestructura (algo no se desmontó solo), distinto
    # de "el test tuvo fallas". Se marca aparte y nunca se deja pasar como 0.
    if ($sigueVivo) {
        $huboHuerfano = $true
        $pidsVivos = @($pid_lanzado) + @($hijosVivos | ForEach-Object { $_.ProcessId })
        Write-Error "ExitCode fue $exitCode pero quedaron procesos vivos para '$escena': PID(s) $($pidsVivos -join ', ')."
    } elseif ($exitCode -ne 0) {
        $huboFallas = $true
    }

    $resultados += [pscustomobject]@{
        Escena      = $escena
        Pid_        = $pid_lanzado
        ExitCode    = $exitCode
        Timeout     = $false
        DuracionSeg = [math]::Round($duracion.TotalSeconds, 1)
        LogStdout   = $logOut
        LogStderr   = $logErr
        PidLimpio   = -not $sigueVivo
    }

    Write-Output "    Termino solo. PID=$pid_lanzado ExitCode=$exitCode Duracion=$([math]::Round($duracion.TotalSeconds, 1))s"
}

Write-Output ""
Write-Output "===== RESUMEN ====="
foreach ($r in $resultados) {
    $estado = if ($r.Timeout) { "TIMEOUT" } elseif (-not $r.PidLimpio) { "HUERFANO" } elseif ($r.ExitCode -eq 0) { "OK" } else { "FALLAS" }
    Write-Output ("  [{0,-8}] {1} | PID={2} ExitCode={3} Duracion={4}s PidLimpio={5}" -f `
        $estado, $r.Escena, $r.Pid_, $r.ExitCode, $r.DuracionSeg, $r.PidLimpio)
    Write-Output "      stdout: $($r.LogStdout)"
    Write-Output "      stderr: $($r.LogStderr)"
}

# Prioridad del código global: huérfano (2, infraestructura no confiable)
# > timeout (124, exclusivo de "hubo que matar por tiempo") > fallas reales
# (1) > todo OK (0). Un huérfano se considera más grave que un timeout
# porque significa que ni siquiera matando el proceso a tiempo se puede
# garantizar hoy un cierre limpio.
if ($huboHuerfano) {
    Write-Output "RESULTADO GLOBAL: al menos una escena dejo un proceso vivo pese a reportar terminado -- error de infraestructura, NO es un exito. Ver logs."
    exit 2
} elseif ($huboTimeout) {
    Write-Output "RESULTADO GLOBAL: al menos una escena no cerro sola (timeout). Ver logs."
    exit 124
} elseif ($huboFallas) {
    Write-Output "RESULTADO GLOBAL: todas cerraron solas y limpias, pero hubo fallas reales. Ver logs."
    exit 1
} else {
    Write-Output "RESULTADO GLOBAL: todas OK."
    exit 0
}
