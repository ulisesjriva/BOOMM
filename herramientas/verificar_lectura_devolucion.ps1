# PsicoBloom: prueba HTTP de lectura de un comprobante de devolución.
# No sube, reemplaza ni elimina archivos; no usa service_role ni modifica Git.
param(
    [Parameter(Mandatory=$true)][string]$RutaProyecto,
    [string]$IdCita = 'd4e79cf1-91cd-4dec-9803-3d3071c97e36'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Consultar-Http {
    param([ValidateSet('GET','POST')][string]$Metodo,[string]$Uri,[hashtable]$Cabeceras,[string]$Cuerpo='')
    $cliente = New-Object System.Net.Http.HttpClient
    $cliente.Timeout = [TimeSpan]::FromSeconds(25)
    $peticion = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::new($Metodo),$Uri)
    $respuesta = $null
    try {
        foreach ($nombre in $Cabeceras.Keys) {
            [void]$peticion.Headers.TryAddWithoutValidation($nombre,[string]$Cabeceras[$nombre])
        }
        if (-not [string]::IsNullOrEmpty($Cuerpo)) {
            if ($Metodo -eq 'GET') { throw 'La prueba GET no admite cuerpo.' }
            $peticion.Content = New-Object System.Net.Http.StringContent($Cuerpo,[Text.Encoding]::UTF8,'application/json')
        }
        $respuesta = $cliente.SendAsync($peticion).GetAwaiter().GetResult()
        $bytes = $respuesta.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $json = $null
        $texto = [Text.Encoding]::UTF8.GetString($bytes)
        try { $json = ConvertFrom-Json -InputObject $texto } catch { $json = $null }
        $tipo = [string]$respuesta.Content.Headers.ContentType
        return @{ Http=[int]$respuesta.StatusCode; Bytes=$bytes; Json=$json; Tipo=$tipo }
    } finally {
        if ($null -ne $respuesta) { $respuesta.Dispose() }
        $peticion.Dispose()
        $cliente.Dispose()
    }
}

function Iniciar-PruebaSesion {
    param([string]$Etiqueta,[string]$Base,[string]$Clave)
    $correo = (Read-Host "Correo de $Etiqueta").Trim()
    $segura = Read-Host "Contraseña de $Etiqueta" -AsSecureString
    $puntero = [IntPtr]::Zero
    $textoPassword = $null
    $cuerpo = $null
    try {
        $puntero = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura)
        $textoPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($puntero)
        $cuerpo = @{email=$correo;password=$textoPassword} | ConvertTo-Json -Compress
        $r = Consultar-Http -Metodo POST -Uri "$Base/auth/v1/token?grant_type=password" -Cabeceras @{apikey=$Clave} -Cuerpo $cuerpo
    } finally {
        if ($puntero -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($puntero) }
        if ($null -ne $segura) { $segura.Dispose() }
        $textoPassword = $null
        $cuerpo = $null
    }
    if ($r.Http -ne 200 -or $null -eq $r.Json -or $null -eq $r.Json.PSObject.Properties['access_token']) {
        throw "No se pudo iniciar sesión de $Etiqueta (HTTP $($r.Http)). Revisa correo y contraseña en tu terminal."
    }
    $token = [string]$r.Json.access_token
    $usuario = Consultar-Http -Metodo GET -Uri "$Base/auth/v1/user" -Cabeceras @{apikey=$Clave;Authorization="Bearer $token"}
    if ($usuario.Http -ne 200 -or $null -eq $usuario.Json -or $null -eq $usuario.Json.PSObject.Properties['id'] -or
        $null -eq $usuario.Json.PSObject.Properties['email'] -or [string]$usuario.Json.email -ine $correo) {
        throw "No se pudo verificar la identidad de $Etiqueta."
    }
    Write-Host "[OK] Identidad de $Etiqueta verificada."
    return @{ Token=$token;Uid=[string]$usuario.Json.id }
}

function Evaluar-AccesoDenegado {
    param([string]$Nombre,$Respuesta)
    if ($Respuesta.Http -ge 200 -and $Respuesta.Http -lt 300) {
        return [pscustomobject]@{Estado='FALLIDA';Prueba=$Nombre;HTTP=$Respuesta.Http;Detalle='Se permitió descargar el archivo.'}
    }
    $campos = ''
    if ($null -ne $Respuesta.Json) {
        foreach ($campo in @('code','error','message','statusCode')) {
            if ($null -ne $Respuesta.Json.PSObject.Properties[$campo]) {
                $campos += ' ' + [string]$Respuesta.Json.$campo
            }
        }
    }
    $rechazo = $campos -match '(?i)not_found|not found|NoSuchKey|row.level security|AccessDenied|unauthorized|forbidden'
    if ($Respuesta.Http -in @(400,401,403,404) -and $rechazo -and
        $campos -notmatch '(?i)InvalidRequest|InvalidJWT|invalid jwt|expired|missing.*header|invalid.*api.?key') {
        return [pscustomobject]@{Estado='APROBADA';Prueba=$Nombre;HTTP=$Respuesta.Http;Detalle='Acceso denegado u objeto oculto; el titular sí pudo descargarlo.'}
    }
    return [pscustomobject]@{Estado='INCONCLUSA';Prueba=$Nombre;HTTP=$Respuesta.Http;Detalle='Respuesta distinta de un rechazo de acceso reconocido.'}
}

try {
    $rutaConfig = Join-Path (Resolve-Path -LiteralPath $RutaProyecto).Path 'configuracion_supabase.json'
    $config = Get-Content -LiteralPath $rutaConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    $base = ([string]$config.SUPABASE_URL).TrimEnd('/')
    $clave = [string]$config.SUPABASE_ANON_KEY
    if ($base -notmatch '^https://[a-z0-9-]+\.supabase\.co$' -or [string]::IsNullOrWhiteSpace($clave)) {
        throw 'Falta la URL o clave pública válida en la configuración local.'
    }
    # Esta prueba reutiliza la clave pública anon JWT del proyecto existente.
    # Nunca aceptar claves privadas ni una sesión privilegiada como sustituto.
    if ($clave.StartsWith('sb_secret_')) { throw 'No se admiten claves privadas.' }
    $partes = $clave.Split('.')
    if ($partes.Length -ne 3) { throw 'Esta prueba requiere la clave pública anon JWT usada actualmente por el proyecto.' }
    $payload = $partes[1].Replace('-','+').Replace('_','/')
    while ($payload.Length % 4 -ne 0) { $payload += '=' }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    if ($claims.role -ne 'anon') { throw 'La configuración debe contener una clave pública anon, nunca service_role.' }

    Write-Host 'PRUEBA DE LECTURA DEL COMPROBANTE DE DEVOLUCIÓN'
    Write-Host 'No se subirá, sobrescribirá ni borrará ningún archivo.'
    Write-Host 'Usa primero al paciente John, titular de la cita de demostración.'
    $paciente = Iniciar-PruebaSesion -Etiqueta 'paciente titular' -Base $base -Clave $clave
    $cabPaciente = @{apikey=$clave;Authorization="Bearer $($paciente.Token)";'Cache-Control'='no-cache, no-store';Pragma='no-cache'}
    $gestion = Consultar-Http -Metodo POST -Uri "$base/rest/v1/rpc/obtener_gestion_cancelacion" -Cabeceras $cabPaciente -Cuerpo (@{p_id_cita=$IdCita}|ConvertTo-Json -Compress)
    if ($gestion.Http -ne 200 -or $null -eq $gestion.Json) { throw 'El paciente no pudo consultar esta cancelación. Verifica la cuenta titular.' }
    $g = $gestion.Json
    if ($g.rol -ne 'paciente' -or $g.estado_devolucion -ne 'registrada' -or [string]::IsNullOrWhiteSpace([string]$g.ruta_comprobante_devolucion)) {
        throw 'Esta cuenta/cita no tiene el comprobante de devolución registrado que vamos a probar.'
    }
    $ruta = [string]$g.ruta_comprobante_devolucion
    $segmentos = $ruta.Split('/')
    if ($segmentos.Length -ne 3 -or $segmentos[0] -ne $IdCita -or $ruta.Contains('..')) { throw 'Ruta de comprobante inesperada.' }
    $rutaCodificada = ($segmentos | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $uriArchivo = "$base/storage/v1/object/authenticated/comprobantes-devoluciones/$rutaCodificada"
    $lectura = Consultar-Http -Metodo GET -Uri $uriArchivo -Cabeceras $cabPaciente
    if ($lectura.Http -ne 200 -or $lectura.Bytes.Length -eq 0 -or $lectura.Tipo -notmatch '^image/(jpeg|png)') {
        throw "No pasó el control positivo del titular (HTTP $($lectura.Http)). No se evaluarán falsos rechazos sobre un archivo inexistente."
    }
    $resultados = New-Object 'System.Collections.Generic.List[object]'
    $resultados.Add([pscustomobject]@{Estado='APROBADA';Prueba='Paciente titular puede leer';HTTP=$lectura.Http;Detalle='Imagen descargada correctamente.'})
    Write-Host '[OK] El paciente titular pudo descargar la imagen.'

    $cabAnon = @{apikey=$clave;Authorization="Bearer $clave";'Cache-Control'='no-cache, no-store';Pragma='no-cache'}
    $anon = Consultar-Http -Metodo GET -Uri $uriArchivo -Cabeceras $cabAnon
    $resultados.Add((Evaluar-AccesoDenegado -Nombre 'Sin sesión de usuario no puede leer' -Respuesta $anon))

    Write-Host 'Ahora usa una cuenta distinta del paciente y de la profesional, por ejemplo el administrador de prueba.'
    $ajeno = Iniciar-PruebaSesion -Etiqueta 'cuenta ajena' -Base $base -Clave $clave
    if ($ajeno.Uid -eq $paciente.Uid -or $ajeno.Uid -eq $segmentos[1]) { throw 'La cuenta ajena debe ser distinta del paciente y de la profesional titular.' }
    $cabAjeno = @{apikey=$clave;Authorization="Bearer $($ajeno.Token)";'Cache-Control'='no-cache, no-store';Pragma='no-cache'}
    $respuestaAjeno = Consultar-Http -Metodo GET -Uri $uriArchivo -Cabeceras $cabAjeno
    $resultados.Add((Evaluar-AccesoDenegado -Nombre 'Cuenta ajena no puede leer' -Respuesta $respuestaAjeno))

    Write-Host ''
    Write-Host 'RESULTADOS (lecturas HTTP reales; sin modificaciones de archivos)'
    $resultados | Format-Table -Property @('Estado', 'Prueba', 'HTTP') -AutoSize | Out-Host
    foreach ($fila in $resultados) { Write-Host "$($fila.Estado): $($fila.Prueba). $($fila.Detalle)" }
    $fallidas = @($resultados | Where-Object {$_.Estado -eq 'FALLIDA'}).Count
    $inconclusas = @($resultados | Where-Object {$_.Estado -eq 'INCONCLUSA'}).Count
    Write-Host "Totales: aprobadas $(@($resultados|Where-Object {$_.Estado -eq 'APROBADA'}).Count); fallidas $fallidas; inconclusas $inconclusas."
    if ($fallidas -gt 0 -or $inconclusas -gt 0) { exit 1 }
} catch {
    Write-Host ('PRUEBA DETENIDA: ' + $_.Exception.Message)
    exit 1
} finally {
    # No imprimir ni conservar credenciales en archivos.
    $clave = $null
    $paciente = $null
    $ajeno = $null
}
