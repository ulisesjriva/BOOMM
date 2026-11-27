<#
.SYNOPSIS
    Verificación manual por HTTP de permisos en Supabase Storage API para los
    buckets privados de PsicoBloom (`qr-cobro-profesionales` y `comprobantes-adelantos`).

.DESCRIPTION
    Compatible con Windows PowerShell 5.1 y PowerShell 7+.
    - Usa únicamente `SUPABASE_ANON_KEY` (rechaza `service_role` y claves secretas)
      y cuentas de prueba autenticadas cuya sesión e identidad se validan con `/auth/v1/user`.
    - Sobre `RUTA_COMPROBANTE_EXISTENTE` y `RUTA_QR_EXISTENTE` ejecuta EXCLUSIVAMENTE
      operaciones de lectura (`GET`).
    - Las pruebas de sobrescritura (`POST x-upsert: true`, `PUT`) y borrado (`DELETE` batch)
      se ejecutan ÚNICAMENTE sobre archivos desechables con nombre UUID creados por
      esta misma ejecución con imágenes PNG completas y válidas.
    - Comprueba que `ID_CITA_PRUEBA_CARGA` pertenezca al paciente titular y permita
      subir comprobantes en ese momento; si no cumple, registra PENDIENTE sin modificar
      estados ni seleccionar otra cita.
    - Tras cada intento de mutación verifica mediante descarga autenticada sin caché
      que el archivo siga existiendo y mantenga su SHA-256 intacto.
    - Nunca imprime claves, contraseñas, tokens JWT, URLs firmadas ni cuerpos sensibles.
    - Emite un resumen final por prueba con estados: APROBADA, FALLIDA, PENDIENTE o INCONCLUSA.

.PARAMETER SoloCargarFunciones
    Carga únicamente las funciones puras del script (útil para pruebas locales simuladas
    sin realizar ninguna petición HTTP remota).
#>
[CmdletBinding()]
param(
    [switch]$SoloCargarFunciones
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

$script:Resultados = New-Object System.Collections.Generic.List[object]
$script:TimeoutSegundosHttp = 25

function Registrar-EstadoPrueba {
    param(
        [Parameter(Mandatory = $true)][string]$Prueba,
        [Parameter(Mandatory = $true)][ValidateSet('APROBADA', 'FALLIDA', 'PENDIENTE', 'INCONCLUSA')][string]$Estado,
        [Parameter(Mandatory = $true)][string]$Detalle
    )
    $entrada = New-Object PSObject -Property @{
        Prueba  = $Prueba
        Estado  = $Estado
        Detalle = $Detalle
    }
    $script:Resultados.Add($entrada) | Out-Null
    Write-Output "[$Estado] $Prueba — $Detalle"
    return $entrada
}

function Obtener-VariableEntorno {
    param(
        [Parameter(Mandatory = $true)][string]$Nombre,
        [bool]$Obligatoria = $true
    )
    $valor = [Environment]::GetEnvironmentVariable($Nombre)
    if ([string]::IsNullOrWhiteSpace($valor)) {
        if ($Obligatoria) {
            throw "Falta definir la variable de entorno obligatoria: $Nombre"
        }
        return $null
    }
    return $valor.Trim()
}

function Convertir-DesdeBase64Url {
    param([Parameter(Mandatory = $true)][string]$Texto)
    $normalizado = $Texto.Replace('-', '+').Replace('_', '/')
    switch ($normalizado.Length % 4) {
        2 { $normalizado += '==' }
        3 { $normalizado += '=' }
    }
    $bytes = [Convert]::FromBase64String($normalizado)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Validar-ClavePublicaSupabase {
    param([Parameter(Mandatory = $true)][string]$Clave)
    $limpia = $Clave.Trim()
    if ([string]::IsNullOrWhiteSpace($limpia)) {
        throw 'SUPABASE_ANON_KEY está vacía.'
    }
    if ($limpia.StartsWith('sb_secret_', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Se rechazó SUPABASE_ANON_KEY: corresponde a una clave secreta (sb_secret_*), no a la clave pública anon.'
    }
    $partes = $limpia.Split('.')
    if ($partes.Length -eq 3) {
        try {
            $jsonTexto = Convertir-DesdeBase64Url -Texto $partes[1]
            $payload = $jsonTexto | ConvertFrom-Json
            if ($null -ne $payload -and ($payload.PSObject.Properties.Name -contains 'role')) {
                $rol = [string]$payload.role
                if ($rol -ieq 'service_role') {
                    throw 'Se rechazó SUPABASE_ANON_KEY: contiene rol service_role. Usa exclusivamente la clave pública anon.'
                }
                if ($rol -ine 'anon') {
                    throw "Se rechazó SUPABASE_ANON_KEY: rol JWT inesperado ('$rol'). Se requiere rol 'anon'."
                }
            }
        } catch {
            if ($_.Exception.Message -like 'Se rechazó SUPABASE_ANON_KEY*') {
                throw
            }
            throw 'SUPABASE_ANON_KEY tiene formato JWT inválido.'
        }
    }
    return $true
}

function Calcular-Sha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Invocar-HttpSeguro {
    param(
        [Parameter(Mandatory = $true)][string]$Metodo,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Cabeceras,
        [byte[]]$CuerpoBytes = $null,
        [string]$CuerpoTexto = $null,
        [int]$TimeoutSegundos = 25
    )
    $handler = New-Object System.Net.Http.HttpClientHandler
    $cliente = New-Object System.Net.Http.HttpClient($handler)
    $cliente.Timeout = [TimeSpan]::FromSeconds($TimeoutSegundos)
    try {
        $metodoHttp = New-Object System.Net.Http.HttpMethod($Metodo)
        $req = New-Object System.Net.Http.HttpRequestMessage($metodoHttp, $Uri)
        foreach ($k in $Cabeceras.Keys) {
            if ($k -ieq 'Content-Type') { continue }
            $req.Headers.TryAddWithoutValidation($k, [string]$Cabeceras[$k]) | Out-Null
        }
        if ($null -ne $CuerpoBytes) {
            $contenido = New-Object System.Net.Http.ByteArrayContent(,$CuerpoBytes)
            $ct = if ($Cabeceras.ContainsKey('Content-Type')) { [string]$Cabeceras['Content-Type'] } else { 'application/octet-stream' }
            $contenido.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ct)
            $req.Content = $contenido
        } elseif (-not [string]::IsNullOrEmpty($CuerpoTexto)) {
            $ct = if ($Cabeceras.ContainsKey('Content-Type')) { [string]$Cabeceras['Content-Type'] } else { 'application/json' }
            $req.Content = New-Object System.Net.Http.StringContent($CuerpoTexto, [System.Text.Encoding]::UTF8, $ct)
        }

        $resp = $cliente.SendAsync($req).GetAwaiter().GetResult()
        $bytesResp = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $textoResp = [System.Text.Encoding]::UTF8.GetString($bytesResp)
        $jsonResp = $null
        if (-not [string]::IsNullOrWhiteSpace($textoResp)) {
            try { $jsonResp = $textoResp | ConvertFrom-Json } catch { $jsonResp = $null }
        }

        return @{
            StatusCode = [int]$resp.StatusCode
            Bytes      = $bytesResp
            Texto      = $textoResp
            Json       = $jsonResp
        }
    } finally {
        $cliente.Dispose()
        $handler.Dispose()
    }
}

function Construir-CabecerasSinCache {
    param([Parameter(Mandatory = $true)][hashtable]$Base)
    $copia = @{}
    foreach ($k in $Base.Keys) {
        $copia[$k] = $Base[$k]
    }
    $copia['Cache-Control'] = 'no-cache, no-store, max-age=0'
    $copia['Pragma'] = 'no-cache'
    return $copia
}

function Clasificar-RespuestaStorage {
    param([Parameter(Mandatory = $true)]$Respuesta)
    $codigo = [int]$Respuesta.StatusCode
    if ($codigo -ge 200 -and $codigo -lt 300) {
        return 'EXITO'
    }

    $errorCampo = ''
    $mensajeCampo = ''
    if ($null -ne $Respuesta.Json -and -not ($Respuesta.Json -is [System.Array])) {
        if ($Respuesta.Json.PSObject.Properties.Name -contains 'error') {
            $errorCampo = [string]$Respuesta.Json.error
        }
        if ($Respuesta.Json.PSObject.Properties.Name -contains 'message') {
            $mensajeCampo = [string]$Respuesta.Json.message
        }
    }
    $combinado = ($errorCampo + ' ' + $mensajeCampo).ToLowerInvariant()

    if ($combinado -match 'row-level security' -or $combinado -match 'unauthorized' -or $combinado -match 'invalidjwt' -or $combinado -match 'accessdenied' -or $codigo -eq 401 -or $codigo -eq 403) {
        return 'RECHAZO_RLS_O_AUTH'
    }
    if ($codigo -eq 409 -or $combinado -match 'already exists' -or $combinado -match 'duplicate') {
        return 'CONFLICTO_DUPLICADO'
    }
    if ($codigo -eq 404 -or $combinado -match 'not found' -or $combinado -match 'not_found') {
        return 'NO_ENCONTRADO_O_OCULTO_POR_RLS'
    }
    return 'VALIDACION_U_OTRO_ERROR'
}

function Evaluar-ElegibilidadCitaCarga {
    param($DetalleJson)
    if ($null -eq $DetalleJson) {
        return @{ Elegible = $false; Motivo = 'La cita no devolvió detalle de adelanto para el paciente titular.' }
    }
    $estado = if ($DetalleJson.PSObject.Properties.Name -contains 'estado_adelanto') { [string]$DetalleJson.estado_adelanto } else { '' }
    if ($estado -in @('observado', 'incidencia_pago')) {
        return @{ Elegible = $true; Motivo = "Estado '$estado' admite carga de comprobante." }
    }
    if ($estado -eq 'pendiente_adelanto') {
        $limiteTxt = if ($DetalleJson.PSObject.Properties.Name -contains 'limite_pago_en') { [string]$DetalleJson.limite_pago_en } else { '' }
        $ahoraTxt = if ($DetalleJson.PSObject.Properties.Name -contains 'hora_servidor') { [string]$DetalleJson.hora_servidor } else { '' }
        if ([string]::IsNullOrWhiteSpace($limiteTxt)) {
            return @{ Elegible = $true; Motivo = 'Estado pendiente_adelanto sin límite informado.' }
        }
        if ([string]::IsNullOrWhiteSpace($ahoraTxt)) {
            return @{ Elegible = $false; Motivo = 'El servidor no informó hora_servidor para comprobar si el plazo sigue vigente.' }
        }
        $limiteUtc = [DateTimeOffset]::Parse($limiteTxt).ToUniversalTime()
        $ahoraUtc = [DateTimeOffset]::Parse($ahoraTxt).ToUniversalTime()
        if ($ahoraUtc -le $limiteUtc) {
            return @{ Elegible = $true; Motivo = 'Estado pendiente_adelanto dentro del plazo vigente según hora del servidor.' }
        }
        return @{ Elegible = $false; Motivo = 'La cita está en pendiente_adelanto pero su plazo de pago ya venció según hora del servidor.' }
    }
    return @{ Elegible = $false; Motivo = "La cita está en estado '$estado', que no admite subir comprobantes en este momento." }
}

function Evaluar-LecturaPermitida {
    param(
        [Parameter(Mandatory = $true)][string]$Prueba,
        [Parameter(Mandatory = $true)]$Respuesta
    )
    if ([int]$Respuesta.StatusCode -ne 200 -or $null -eq $Respuesta.Bytes -or $Respuesta.Bytes.Length -eq 0) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "HTTP $($Respuesta.StatusCode) (se esperaba 200 con contenido)." | Out-Null
        throw "Falló lectura permitida: $Prueba"
    }
    Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "HTTP 200 ($($Respuesta.Bytes.Length) bytes recibidos)." | Out-Null
}

function Evaluar-RechazoLectura {
    param(
        [Parameter(Mandatory = $true)][string]$Prueba,
        [Parameter(Mandatory = $true)]$Respuesta
    )
    $cat = Clasificar-RespuestaStorage -Respuesta $Respuesta
    if ($cat -eq 'EXITO') {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "Permitió lectura inesperada (HTTP $($Respuesta.StatusCode))." | Out-Null
        throw "Brecha de lectura en: $Prueba"
    }
    if ($cat -in @('RECHAZO_RLS_O_AUTH', 'NO_ENCONTRADO_O_OCULTO_POR_RLS')) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "Acceso denegado ($cat, HTTP $($Respuesta.StatusCode))." | Out-Null
        return
    }
    Registrar-EstadoPrueba -Prueba $Prueba -Estado 'INCONCLUSA' -Detalle "Error no clasificable como rechazo de acceso ($cat, HTTP $($Respuesta.StatusCode))." | Out-Null
}

function Evaluar-Sobrescritura {
    param(
        [Parameter(Mandatory = $true)][string]$Prueba,
        [Parameter(Mandatory = $true)]$RespuestaMutacion,
        [Parameter(Mandatory = $true)]$RespuestaVerificacion,
        [Parameter(Mandatory = $true)][string]$ShaEsperado
    )
    # Verificar integridad posterior primero: si desapareció o cambió, es FALLIDA inmediata
    if ([int]$RespuestaVerificacion.StatusCode -ne 200 -or $null -eq $RespuestaVerificacion.Bytes) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "El archivo desapareció tras el intento de sobrescritura (verificación HTTP $($RespuestaVerificacion.StatusCode))." | Out-Null
        throw "Integridad rota tras sobrescritura: $Prueba"
    }
    $shaActual = Calcular-Sha256 -Bytes $RespuestaVerificacion.Bytes
    if ($shaActual -ne $ShaEsperado) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle 'El contenido del archivo cambió (SHA-256 distinto). Sobrescritura efectiva no permitida.' | Out-Null
        throw "Sobrescritura efectiva detectada en: $Prueba"
    }

    $cat = Clasificar-RespuestaStorage -Respuesta $RespuestaMutacion
    if ($cat -eq 'EXITO') {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "El endpoint devolvió HTTP $($RespuestaMutacion.StatusCode) en un intento de sobrescritura prohibido." | Out-Null
        throw "Mutación permitida inesperadamente en: $Prueba"
    }
    if ($cat -in @('RECHAZO_RLS_O_AUTH', 'CONFLICTO_DUPLICADO')) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "Rechazo explícito ($cat, HTTP $($RespuestaMutacion.StatusCode)) y SHA-256 intacto." | Out-Null
        return
    }
    Registrar-EstadoPrueba -Prueba $Prueba -Estado 'INCONCLUSA' -Detalle "Respuesta ambigua ($cat, HTTP $($RespuestaMutacion.StatusCode)); aunque el SHA-256 sigue intacto, no se confirma rechazo por política/conflicto." | Out-Null
}

function Evaluar-Borrado {
    param(
        [Parameter(Mandatory = $true)][string]$Prueba,
        [Parameter(Mandatory = $true)]$RespuestaBorrado,
        [Parameter(Mandatory = $true)]$RespuestaVerificacion,
        [Parameter(Mandatory = $true)][string]$ShaEsperado,
        [Parameter(Mandatory = $true)][string]$RutaObjetivo
    )
    # 1. Comprobar existencia posterior y SHA-256 sin caché
    if ([int]$RespuestaVerificacion.StatusCode -ne 200 -or $null -eq $RespuestaVerificacion.Bytes) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "El archivo desapareció tras DELETE (verificación HTTP $($RespuestaVerificacion.StatusCode)). Eliminación no permitida." | Out-Null
        throw "Borrado efectivo detectado en: $Prueba"
    }
    $shaActual = Calcular-Sha256 -Bytes $RespuestaVerificacion.Bytes
    if ($shaActual -ne $ShaEsperado) {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle 'El contenido del archivo cambió tras DELETE (SHA-256 distinto).' | Out-Null
        throw "Integridad rota tras DELETE en: $Prueba"
    }

    # 2. Analizar respuesta HTTP y cuerpo JSON de DELETE
    $cat = Clasificar-RespuestaStorage -Respuesta $RespuestaBorrado
    if ($cat -eq 'RECHAZO_RLS_O_AUTH') {
        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "Rechazo explícito ($cat, HTTP $($RespuestaBorrado.StatusCode)) y archivo intacto (SHA-256 verificado)." | Out-Null
        return
    }

    if ($cat -eq 'EXITO') {
        $textoTrim = if ($null -ne $RespuestaBorrado.Texto) { $RespuestaBorrado.Texto.Trim() } else { '' }
        if ($textoTrim -eq '[]') {
            Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "Sin eliminación efectiva (HTTP $($RespuestaBorrado.StatusCode) con lista JSON vacía []; archivo existente con SHA-256 intacto)." | Out-Null
            return
        }
        $eliminados = @()
        if ($null -ne $RespuestaBorrado.Json) {
            if ($RespuestaBorrado.Json -is [System.Array]) {
                $eliminados = $RespuestaBorrado.Json
            } else {
                # Respuesta 200 con objeto JSON no-lista: resultado ambiguo -> INCONCLUSA
                Registrar-EstadoPrueba -Prueba $Prueba -Estado 'INCONCLUSA' -Detalle "HTTP $($RespuestaBorrado.StatusCode) con respuesta JSON ambigua (no es lista); archivo intacto pero resultado no concluyente." | Out-Null
                return
            }
        } else {
            Registrar-EstadoPrueba -Prueba $Prueba -Estado 'INCONCLUSA' -Detalle "HTTP $($RespuestaBorrado.StatusCode) sin cuerpo JSON interpretable; archivo intacto pero resultado no concluyente." | Out-Null
            return
        }

        if ($eliminados.Count -eq 0) {
            Registrar-EstadoPrueba -Prueba $Prueba -Estado 'APROBADA' -Detalle "Sin eliminación efectiva (HTTP $($RespuestaBorrado.StatusCode) con lista vacía; archivo existente con SHA-256 intacto)." | Out-Null
            return
        }

        Registrar-EstadoPrueba -Prueba $Prueba -Estado 'FALLIDA' -Detalle "DELETE devolvió elementos eliminados en JSON ($($eliminados.Count)) para un objeto protegido." | Out-Null
        throw "DELETE reportó eliminación en: $Prueba"
    }

    Registrar-EstadoPrueba -Prueba $Prueba -Estado 'INCONCLUSA' -Detalle "Respuesta ambigua en DELETE ($cat, HTTP $($RespuestaBorrado.StatusCode)); archivo intacto pero no es rechazo explícito ni lista vacía." | Out-Null
}

function Iniciar-SesionYVerificarIdentidad {
    param(
        [Parameter(Mandatory = $true)][string]$UrlBase,
        [Parameter(Mandatory = $true)][string]$AnonKey,
        [Parameter(Mandatory = $true)][string]$CorreoEsperado,
        [Parameter(Mandatory = $true)][string]$Etiqueta
    )
    $segura = Read-Host "Contraseña para $Etiqueta ($CorreoEsperado)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura)
    try {
        $clave = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    $cuerpo = (@{ email = $CorreoEsperado; password = $clave } | ConvertTo-Json -Compress)
    $clave = $null

    $resLogin = Invocar-HttpSeguro -Metodo 'POST' -Uri "$UrlBase/auth/v1/token?grant_type=password" `
        -Cabeceras @{ apikey = $AnonKey; 'Content-Type' = 'application/json' } `
        -CuerpoTexto $cuerpo -TimeoutSegundos $script:TimeoutSegundosHttp

    if ([int]$resLogin.StatusCode -ne 200 -or $null -eq $resLogin.Json -or -not ($resLogin.Json.PSObject.Properties.Name -contains 'access_token')) {
        throw "No se pudo autenticar $Etiqueta (HTTP $($resLogin.StatusCode))."
    }

    $token = [string]$resLogin.Json.access_token
    $resUser = Invocar-HttpSeguro -Metodo 'GET' -Uri "$UrlBase/auth/v1/user" `
        -Cabeceras (Construir-CabecerasSinCache -Base @{ apikey = $AnonKey; Authorization = "Bearer $token" }) `
        -TimeoutSegundos $script:TimeoutSegundosHttp

    if ([int]$resUser.StatusCode -ne 200 -or $null -eq $resUser.Json -or [string]::IsNullOrWhiteSpace([string]$resUser.Json.id)) {
        throw "No se pudo verificar la identidad de $Etiqueta mediante /auth/v1/user (HTTP $($resUser.StatusCode))."
    }

    $correoReal = [string]$resUser.Json.email
    if ($correoReal -ine $CorreoEsperado) {
        throw "La identidad autenticada para $Etiqueta no coincide con el correo configurado."
    }

    Write-Host "[OK] Sesión verificada para $Etiqueta (identidad confirmada sin mostrar credenciales)."
    return @{
        Token = $token
        Uid   = [string]$resUser.Json.id
        Email = $correoReal
    }
}

if ($SoloCargarFunciones) {
    return
}

# =============================================================================
# EJECUCIÓN PRINCIPAL (CONTRA SUPABASE STORAGE API CON CUENTAS DE PRUEBA)
# =============================================================================

# Dos imágenes PNG 1x1 completas y válidas con contenido distinto
[byte[]]$pngOriginal = @(
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
    0x89,0x00,0x00,0x00,0x0A,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
    0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
    0x42,0x60,0x82
)
[byte[]]$pngDistinto = @(
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,
    0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,
    0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
    0x44,0xAE,0x42,0x60,0x82
)

$urlBase = (Obtener-VariableEntorno -Nombre 'SUPABASE_URL').TrimEnd('/')
$anonKey = Obtener-VariableEntorno -Nombre 'SUPABASE_ANON_KEY'
Validar-ClavePublicaSupabase -Clave $anonKey | Out-Null

$rutaCompExistente = (Obtener-VariableEntorno -Nombre 'RUTA_COMPROBANTE_EXISTENTE').TrimStart('/')
$rutaQrExistente = (Obtener-VariableEntorno -Nombre 'RUTA_QR_EXISTENTE').TrimStart('/')
$idCitaPruebaCarga = Obtener-VariableEntorno -Nombre 'ID_CITA_PRUEBA_CARGA' -Obligatoria $false

$sesPac = Iniciar-SesionYVerificarIdentidad -UrlBase $urlBase -AnonKey $anonKey -CorreoEsperado (Obtener-VariableEntorno -Nombre 'CORREO_PACIENTE_TITULAR') -Etiqueta 'Paciente titular'
$sesProf = Iniciar-SesionYVerificarIdentidad -UrlBase $urlBase -AnonKey $anonKey -CorreoEsperado (Obtener-VariableEntorno -Nombre 'CORREO_PROFESIONAL_TITULAR') -Etiqueta 'Profesional titular'
$sesAjeno = Iniciar-SesionYVerificarIdentidad -UrlBase $urlBase -AnonKey $anonKey -CorreoEsperado (Obtener-VariableEntorno -Nombre 'CORREO_USUARIO_AJENO') -Etiqueta 'Usuario ajeno'

if ($sesPac.Uid -eq $sesProf.Uid -or $sesPac.Uid -eq $sesAjeno.Uid -or $sesProf.Uid -eq $sesAjeno.Uid) {
    throw 'Las tres cuentas de prueba (paciente titular, profesional titular y usuario ajeno) deben ser usuarios distintos.'
}

$cabPac = Construir-CabecerasSinCache -Base @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)" }
$cabProf = Construir-CabecerasSinCache -Base @{ apikey = $anonKey; Authorization = "Bearer $($sesProf.Token)" }
$cabAjeno = Construir-CabecerasSinCache -Base @{ apikey = $anonKey; Authorization = "Bearer $($sesAjeno.Token)" }
$cabAnon = Construir-CabecerasSinCache -Base @{ apikey = $anonKey; Authorization = "Bearer $anonKey" }

$uriCompExist = "$urlBase/storage/v1/object/authenticated/comprobantes-adelantos/$rutaCompExistente"
$uriQrExist = "$urlBase/storage/v1/object/authenticated/qr-cobro-profesionales/$rutaQrExistente"

Write-Output '--- 1. Lectura por titulares (SOLO LECTURA sobre archivos existentes) ---'
Evaluar-LecturaPermitida -Prueba 'Paciente titular lee comprobante existente' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompExist -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-LecturaPermitida -Prueba 'Profesional titular lee comprobante existente' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompExist -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-LecturaPermitida -Prueba 'Paciente titular lee QR vigente' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrExist -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-LecturaPermitida -Prueba 'Profesional titular lee QR vigente' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrExist -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp)

Write-Output '--- 2. Rechazo ajeno y anónimo (SOLO LECTURA sobre archivos existentes) ---'
Evaluar-RechazoLectura -Prueba 'Anónimo NO puede leer comprobante privado' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompExist -Cabeceras $cabAnon -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-RechazoLectura -Prueba 'Anónimo NO puede leer QR privado' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrExist -Cabeceras $cabAnon -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-RechazoLectura -Prueba 'Usuario ajeno NO puede leer comprobante privado' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompExist -Cabeceras $cabAjeno -TimeoutSegundos $script:TimeoutSegundosHttp)
Evaluar-RechazoLectura -Prueba 'Usuario ajeno NO puede leer QR privado' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrExist -Cabeceras $cabAjeno -TimeoutSegundos $script:TimeoutSegundosHttp)

Write-Output '--- 3. Sobrescritura y borrado EXCLUSIVAMENTE sobre QR desechable UUID ---'
$uuidQr = [Guid]::NewGuid().ToString()
$rutaQrTemp = "$($sesProf.Uid)/prueba_storage_$uuidQr.png"
$uriQrTempObj = "$urlBase/storage/v1/object/qr-cobro-profesionales/$rutaQrTemp"
$uriQrTempAuth = "$urlBase/storage/v1/object/authenticated/qr-cobro-profesionales/$rutaQrTemp"

$subQr = Invocar-HttpSeguro -Metodo 'POST' -Uri $uriQrTempObj `
    -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesProf.Token)"; 'Content-Type' = 'image/png'; 'x-upsert' = 'false' } `
    -CuerpoBytes $pngOriginal -TimeoutSegundos $script:TimeoutSegundosHttp

if ([int]$subQr.StatusCode -ne 200) {
    Registrar-EstadoPrueba -Prueba 'Subida de QR desechable UUID' -Estado 'FALLIDA' -Detalle "HTTP $($subQr.StatusCode)." | Out-Null
    throw 'No se pudo preparar el archivo QR desechable UUID.'
}
$shaQrOriginal = Calcular-Sha256 -Bytes $pngOriginal
Evaluar-LecturaPermitida -Prueba 'Lectura inicial de QR desechable UUID' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrTempAuth -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp)

$resUpsertQr = Invocar-HttpSeguro -Metodo 'POST' -Uri $uriQrTempObj `
    -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesProf.Token)"; 'Content-Type' = 'image/png'; 'x-upsert' = 'true' } `
    -CuerpoBytes $pngDistinto -TimeoutSegundos $script:TimeoutSegundosHttp
$verifQr1 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrTempAuth -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp
Evaluar-Sobrescritura -Prueba 'Profesional NO puede sobrescribir QR desechable (POST x-upsert=true)' -RespuestaMutacion $resUpsertQr -RespuestaVerificacion $verifQr1 -ShaEsperado $shaQrOriginal

$resPutQr = Invocar-HttpSeguro -Metodo 'PUT' -Uri $uriQrTempObj `
    -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesProf.Token)"; 'Content-Type' = 'image/png' } `
    -CuerpoBytes $pngDistinto -TimeoutSegundos $script:TimeoutSegundosHttp
$verifQr2 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrTempAuth -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp
Evaluar-Sobrescritura -Prueba 'Profesional NO puede sobrescribir QR desechable (PUT)' -RespuestaMutacion $resPutQr -RespuestaVerificacion $verifQr2 -ShaEsperado $shaQrOriginal

$cuerpoDelQr = (@{ prefixes = @($rutaQrTemp) } | ConvertTo-Json -Compress)
$resDelQr = Invocar-HttpSeguro -Metodo 'DELETE' -Uri "$urlBase/storage/v1/object/qr-cobro-profesionales" `
    -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesProf.Token)"; 'Content-Type' = 'application/json' } `
    -CuerpoTexto $cuerpoDelQr -TimeoutSegundos $script:TimeoutSegundosHttp
$verifQr3 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriQrTempAuth -Cabeceras $cabProf -TimeoutSegundos $script:TimeoutSegundosHttp
Evaluar-Borrado -Prueba 'Profesional NO puede borrar QR desechable (DELETE batch)' -RespuestaBorrado $resDelQr -RespuestaVerificacion $verifQr3 -ShaEsperado $shaQrOriginal -RutaObjetivo $rutaQrTemp

Write-Output '--- 4. Sobrescritura y borrado EXCLUSIVAMENTE sobre comprobante desechable UUID ---'
if ([string]::IsNullOrWhiteSpace($idCitaPruebaCarga)) {
    Registrar-EstadoPrueba -Prueba 'Pruebas de mutación en comprobante desechable UUID' -Estado 'PENDIENTE' -Detalle 'No se definió ID_CITA_PRUEBA_CARGA.' | Out-Null
} else {
    $resDetalleCita = Invocar-HttpSeguro -Metodo 'POST' -Uri "$urlBase/rest/v1/rpc/obtener_detalle_adelanto_cita" `
        -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)"; 'Content-Type' = 'application/json' } `
        -CuerpoTexto (@{ p_id_cita = $idCitaPruebaCarga } | ConvertTo-Json -Compress) `
        -TimeoutSegundos $script:TimeoutSegundosHttp

    if ([int]$resDetalleCita.StatusCode -ne 200) {
        Registrar-EstadoPrueba -Prueba 'Pruebas de mutación en comprobante desechable UUID' -Estado 'PENDIENTE' -Detalle "No se pudo validar pertenencia de ID_CITA_PRUEBA_CARGA para el paciente titular (HTTP $($resDetalleCita.StatusCode))." | Out-Null
    } else {
        $eleg = Evaluar-ElegibilidadCitaCarga -DetalleJson $resDetalleCita.Json
        if (-not $eleg.Elegible) {
            Registrar-EstadoPrueba -Prueba 'Pruebas de mutación en comprobante desechable UUID' -Estado 'PENDIENTE' -Detalle $eleg.Motivo | Out-Null
        } else {
            $uuidComp = [Guid]::NewGuid().ToString()
            $rutaCompTemp = "$idCitaPruebaCarga/$($sesPac.Uid)/prueba_storage_$uuidComp.png"
            $uriCompTempObj = "$urlBase/storage/v1/object/comprobantes-adelantos/$rutaCompTemp"
            $uriCompTempAuth = "$urlBase/storage/v1/object/authenticated/comprobantes-adelantos/$rutaCompTemp"

            $subComp = Invocar-HttpSeguro -Metodo 'POST' -Uri $uriCompTempObj `
                -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)"; 'Content-Type' = 'image/png'; 'x-upsert' = 'false' } `
                -CuerpoBytes $pngOriginal -TimeoutSegundos $script:TimeoutSegundosHttp

            if ([int]$subComp.StatusCode -ne 200) {
                Registrar-EstadoPrueba -Prueba 'Subida de comprobante desechable UUID' -Estado 'FALLIDA' -Detalle "HTTP $($subComp.StatusCode)." | Out-Null
                throw 'No se pudo preparar el comprobante desechable UUID.'
            }
            $shaCompOriginal = Calcular-Sha256 -Bytes $pngOriginal
            Evaluar-LecturaPermitida -Prueba 'Lectura inicial de comprobante desechable UUID' -Respuesta (Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompTempAuth -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp)

            $resUpsertComp = Invocar-HttpSeguro -Metodo 'POST' -Uri $uriCompTempObj `
                -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)"; 'Content-Type' = 'image/png'; 'x-upsert' = 'true' } `
                -CuerpoBytes $pngDistinto -TimeoutSegundos $script:TimeoutSegundosHttp
            $verifComp1 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompTempAuth -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp
            Evaluar-Sobrescritura -Prueba 'Paciente NO puede sobrescribir comprobante desechable (POST x-upsert=true)' -RespuestaMutacion $resUpsertComp -RespuestaVerificacion $verifComp1 -ShaEsperado $shaCompOriginal

            $resPutComp = Invocar-HttpSeguro -Metodo 'PUT' -Uri $uriCompTempObj `
                -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)"; 'Content-Type' = 'image/png' } `
                -CuerpoBytes $pngDistinto -TimeoutSegundos $script:TimeoutSegundosHttp
            $verifComp2 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompTempAuth -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp
            Evaluar-Sobrescritura -Prueba 'Paciente NO puede sobrescribir comprobante desechable (PUT)' -RespuestaMutacion $resPutComp -RespuestaVerificacion $verifComp2 -ShaEsperado $shaCompOriginal

            $cuerpoDelComp = (@{ prefixes = @($rutaCompTemp) } | ConvertTo-Json -Compress)
            $resDelComp = Invocar-HttpSeguro -Metodo 'DELETE' -Uri "$urlBase/storage/v1/object/comprobantes-adelantos" `
                -Cabeceras @{ apikey = $anonKey; Authorization = "Bearer $($sesPac.Token)"; 'Content-Type' = 'application/json' } `
                -CuerpoTexto $cuerpoDelComp -TimeoutSegundos $script:TimeoutSegundosHttp
            $verifComp3 = Invocar-HttpSeguro -Metodo 'GET' -Uri $uriCompTempAuth -Cabeceras $cabPac -TimeoutSegundos $script:TimeoutSegundosHttp
            Evaluar-Borrado -Prueba 'Paciente NO puede borrar comprobante desechable (DELETE batch)' -RespuestaBorrado $resDelComp -RespuestaVerificacion $verifComp3 -ShaEsperado $shaCompOriginal -RutaObjetivo $rutaCompTemp
        }
    }
}

Write-Output ''
Write-Output '================ RESUMEN DE VERIFICACIÓN STORAGE API ================'
foreach ($r in $script:Resultados) {
    Write-Output ("{0,-11} | {1} | {2}" -f $r.Estado, $r.Prueba, $r.Detalle)
}
$nAprob = @($script:Resultados | Where-Object { $_.Estado -eq 'APROBADA' }).Count
$nFall  = @($script:Resultados | Where-Object { $_.Estado -eq 'FALLIDA' }).Count
$nPend  = @($script:Resultados | Where-Object { $_.Estado -eq 'PENDIENTE' }).Count
$nInc   = @($script:Resultados | Where-Object { $_.Estado -eq 'INCONCLUSA' }).Count
Write-Output "Totales -> APROBADA: $nAprob | FALLIDA: $nFall | PENDIENTE: $nPend | INCONCLUSA: $nInc"
