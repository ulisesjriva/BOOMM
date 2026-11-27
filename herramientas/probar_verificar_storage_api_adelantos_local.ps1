<#
.SYNOPSIS
    Pruebas locales SIMULADAS (sin HTTP remoto) de las funciones de clasificación,
    validación de clave pública, elegibilidad de cita y evaluación de sobrescritura/borrado
    de `herramientas/verificar_storage_api_adelantos.ps1`.
    Compatible con Windows PowerShell 5.1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rutaScript = Join-Path $PSScriptRoot 'verificar_storage_api_adelantos.ps1'
. $rutaScript -SoloCargarFunciones

function Afirmar-Igual {
    param($Actual, $Esperado, [string]$Caso)
    if ($Actual -ne $Esperado) {
        throw "FALLO en '$Caso': esperado='$Esperado', obtenido='$Actual'"
    }
    Write-Output "[OK-LOCAL] $Caso"
}

function Afirmar-Lanza {
    param([scriptblock]$Accion, [string]$Caso)
    $lanzo = $false
    try {
        & $Accion
    } catch {
        $lanzo = $true
    }
    if (-not $lanzo) {
        throw "FALLO en '$Caso': se esperaba excepción y no se lanzó."
    }
    Write-Output "[OK-LOCAL] $Caso"
}

Write-Output '=== PRUEBAS LOCALES SIMULADAS (SIN PETICIONES HTTP REMOTAS) ==='

# 1. Validación de clave pública (rechaza service_role y sb_secret_*, acepta anon)
$jwtAnon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.firma'
$jwtService = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.firma'
Afirmar-Igual (Validar-ClavePublicaSupabase -Clave $jwtAnon) $true 'Acepta JWT con rol anon'
Afirmar-Lanza { Validar-ClavePublicaSupabase -Clave $jwtService } 'Rechaza JWT con rol service_role'
Afirmar-Lanza { Validar-ClavePublicaSupabase -Clave 'sb_secret_prueba123' } 'Rechaza clave sb_secret_*'

# 2. Clasificación de respuestas Storage
Afirmar-Igual (Clasificar-RespuestaStorage -Respuesta @{ StatusCode = 403; Json = ([PSCustomObject]@{ message = 'new row violates row-level security policy' }) }) 'RECHAZO_RLS_O_AUTH' 'Clasifica rechazo RLS 403'
Afirmar-Igual (Clasificar-RespuestaStorage -Respuesta @{ StatusCode = 409; Json = ([PSCustomObject]@{ error = 'Duplicate'; message = 'The resource already exists' }) }) 'CONFLICTO_DUPLICADO' 'Clasifica conflicto 409'
Afirmar-Igual (Clasificar-RespuestaStorage -Respuesta @{ StatusCode = 404; Json = ([PSCustomObject]@{ error = 'not_found'; message = 'Object not found' }) }) 'NO_ENCONTRADO_O_OCULTO_POR_RLS' 'Clasifica 404'
Afirmar-Igual (Clasificar-RespuestaStorage -Respuesta @{ StatusCode = 400; Json = ([PSCustomObject]@{ error = 'InvalidMimeType'; message = 'mime type not supported' }) }) 'VALIDACION_U_OTRO_ERROR' 'Clasifica error de validación 400'

# 3. Evaluación de sobrescritura
[byte[]]$bytesA = @(1, 2, 3, 4)
[byte[]]$bytesB = @(9, 8, 7, 6)
$shaA = Calcular-Sha256 -Bytes $bytesA

$script:Resultados.Clear()
Evaluar-Sobrescritura -Prueba 'Sobrescritura rechazada por RLS' `
    -RespuestaMutacion @{ StatusCode = 403; Json = ([PSCustomObject]@{ message = 'row-level security' }) } `
    -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesA } `
    -ShaEsperado $shaA
Afirmar-Igual $script:Resultados[0].Estado 'APROBADA' 'Sobrescritura rechazada por RLS con SHA intacto -> APROBADA'

$script:Resultados.Clear()
Evaluar-Sobrescritura -Prueba 'Sobrescritura error validación' `
    -RespuestaMutacion @{ StatusCode = 400; Json = ([PSCustomObject]@{ error = 'InvalidMimeType' }) } `
    -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesA } `
    -ShaEsperado $shaA
Afirmar-Igual $script:Resultados[0].Estado 'INCONCLUSA' 'Sobrescritura con error validación -> INCONCLUSA'

Afirmar-Lanza {
    Evaluar-Sobrescritura -Prueba 'Sobrescritura efectiva cambia SHA' `
        -RespuestaMutacion @{ StatusCode = 200; Json = $null } `
        -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesB } `
        -ShaEsperado $shaA
} 'Sobrescritura que cambia SHA -> FALLIDA y detiene'

# 4. Evaluación de borrado (rechazo explícito vs HTTP 200 lista vacía vs ambiguo vs borrado efectivo)
$script:Resultados.Clear()
Evaluar-Borrado -Prueba 'DELETE rechazo explícito' `
    -RespuestaBorrado @{ StatusCode = 403; Texto = '{"message":"Unauthorized"}'; Json = ([PSCustomObject]@{ message = 'Unauthorized' }) } `
    -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesA } `
    -ShaEsperado $shaA -RutaObjetivo 'ruta/x.png'
Afirmar-Igual $script:Resultados[0].Estado 'APROBADA' 'DELETE 403 con SHA intacto -> APROBADA (rechazo explícito)'

$script:Resultados.Clear()
Evaluar-Borrado -Prueba 'DELETE 200 lista vacía' `
    -RespuestaBorrado @{ StatusCode = 200; Texto = '[]'; Json = @() } `
    -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesA } `
    -ShaEsperado $shaA -RutaObjetivo 'ruta/x.png'
Afirmar-Igual $script:Resultados[0].Estado 'APROBADA' 'DELETE 200 con [] y SHA intacto -> APROBADA (sin eliminación efectiva)'
Afirmar-Igual ($script:Resultados[0].Detalle -like '*Sin eliminación efectiva*') $true 'Distingue sin eliminación efectiva en el detalle'

$script:Resultados.Clear()
Evaluar-Borrado -Prueba 'DELETE 200 cuerpo ambiguo' `
    -RespuestaBorrado @{ StatusCode = 200; Texto = '{"ok":true}'; Json = ([PSCustomObject]@{ ok = $true }) } `
    -RespuestaVerificacion @{ StatusCode = 200; Bytes = $bytesA } `
    -ShaEsperado $shaA -RutaObjetivo 'ruta/x.png'
Afirmar-Igual $script:Resultados[0].Estado 'INCONCLUSA' 'DELETE 200 con JSON ambiguo -> INCONCLUSA'

Afirmar-Lanza {
    Evaluar-Borrado -Prueba 'DELETE elimina realmente el archivo' `
        -RespuestaBorrado @{ StatusCode = 200; Texto = '[{"name":"ruta/x.png"}]'; Json = @([PSCustomObject]@{ name = 'ruta/x.png' }) } `
        -RespuestaVerificacion @{ StatusCode = 404; Bytes = @() } `
        -ShaEsperado $shaA -RutaObjetivo 'ruta/x.png'
} 'DELETE que elimina el archivo -> FALLIDA y detiene'

# 5. Elegibilidad de ID_CITA_PRUEBA_CARGA
$eVigente = Evaluar-ElegibilidadCitaCarga -DetalleJson ([PSCustomObject]@{
    estado_adelanto = 'pendiente_adelanto'
    limite_pago_en  = '2026-11-30T15:00:00Z'
    hora_servidor   = '2026-11-26T21:00:00Z'
})
Afirmar-Igual $eVigente.Elegible $true 'Cita pendiente_adelanto dentro de plazo es elegible'

$eVencida = Evaluar-ElegibilidadCitaCarga -DetalleJson ([PSCustomObject]@{
    estado_adelanto = 'pendiente_adelanto'
    limite_pago_en  = '2026-11-25T15:00:00Z'
    hora_servidor   = '2026-11-26T21:00:00Z'
})
Afirmar-Igual $eVencida.Elegible $false 'Cita pendiente_adelanto vencida no es elegible'

$eVerificada = Evaluar-ElegibilidadCitaCarga -DetalleJson ([PSCustomObject]@{
    estado_adelanto = 'verificado'
})
Afirmar-Igual $eVerificada.Elegible $false 'Cita verificada no es elegible'

# 6. Prueba de la función real Iniciar-SesionYVerificarIdentidad (simulando Read-Host, Write-Host e Invocar-HttpSeguro)
$claveSimulada = 'ClaveSecreta_NoImprimir_987!'
$tokenSimulado = 'jwt_token_simulado_no_imprimir_xyz'
$uidSimulado = '11111111-2222-3333-4444-555555555555'
$correoEsperadoSim = 'paciente.prueba@psicobloom.test'
$script:CorreoUserSimulado = $correoEsperadoSim
$script:MensajesHostCapturados = New-Object System.Collections.Generic.List[string]

function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    return (ConvertTo-SecureString $claveSimulada -AsPlainText -Force)
}

function Write-Host {
    param([Parameter(Position = 0)]$Object)
    $script:MensajesHostCapturados.Add([string]$Object) | Out-Null
}

function Invocar-HttpSeguro {
    param(
        [string]$Metodo,
        [string]$Uri,
        [hashtable]$Cabeceras,
        [byte[]]$CuerpoBytes = $null,
        [string]$CuerpoTexto = $null,
        [int]$TimeoutSegundos = 25
    )
    if ($Metodo -eq 'POST' -and $Uri -like '*/auth/v1/token*') {
        return @{
            StatusCode = 200
            Bytes      = @()
            Texto      = '{"access_token":"..."}'
            Json       = ([PSCustomObject]@{ access_token = $tokenSimulado })
        }
    }
    if ($Metodo -eq 'GET' -and $Uri -like '*/auth/v1/user') {
        return @{
            StatusCode = 200
            Bytes      = @()
            Texto      = '{}'
            Json       = ([PSCustomObject]@{ id = $uidSimulado; email = $script:CorreoUserSimulado })
        }
    }
    throw "Llamada HTTP simulada inesperada: $Metodo $Uri"
}

$resultadoFlujo = @(Iniciar-SesionYVerificarIdentidad -UrlBase 'https://ejemplo.supabase.co' -AnonKey $jwtAnon -CorreoEsperado $correoEsperadoSim -Etiqueta 'Paciente prueba')
Afirmar-Igual $resultadoFlujo.Count 1 'Iniciar-SesionYVerificarIdentidad emite exactamente 1 objeto en el flujo de resultados'

$sesion = $resultadoFlujo[0]
Afirmar-Igual ($sesion -is [hashtable]) $true 'El objeto devuelto por Iniciar-SesionYVerificarIdentidad es un hashtable de sesión'
Afirmar-Igual $sesion.Token $tokenSimulado 'Token devuelto coincide con el simulado'
Afirmar-Igual $sesion.Uid $uidSimulado 'Uid devuelto coincide con el simulado'
Afirmar-Igual $sesion.Email $correoEsperadoSim 'Email devuelto coincide con el simulado'

$textoHostTodo = ($script:MensajesHostCapturados -join "`n")
Afirmar-Igual ($textoHostTodo -like "*$tokenSimulado*") $false 'La salida Write-Host no imprime el token'
Afirmar-Igual ($textoHostTodo -like "*$claveSimulada*") $false 'La salida Write-Host no imprime la contraseña'
Afirmar-Igual ($textoHostTodo -like '*Sesión verificada para Paciente prueba*') $true 'Write-Host conserva el mensaje de confirmación sin credenciales'

$script:CorreoUserSimulado = 'otro.correo@psicobloom.test'
Afirmar-Lanza {
    Iniciar-SesionYVerificarIdentidad -UrlBase 'https://ejemplo.supabase.co' -AnonKey $jwtAnon -CorreoEsperado $correoEsperadoSim -Etiqueta 'Paciente prueba' | Out-Null
} 'Rechaza identidad cuando /auth/v1/user devuelve un correo diferente'

Write-Output 'OK: todas las pruebas locales simuladas pasaron en Windows PowerShell (sin HTTP remoto).'
