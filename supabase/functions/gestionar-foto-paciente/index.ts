import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const LIMITE_BYTES_FOTOGRAFIA = 5 * 1024 * 1024;
const TIEMPO_ESPERA_SUBIDA_MS = 15000;
const TIEMPO_ESPERA_ELIMINACION_MS = 8000;
const MAX_LIMPIEZAS_POR_PETICION = 5;

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, DELETE, OPTIONS',
};

const CAMPOS_PROHIBIDOS_CLIENTE = [
  'url',
  'fotoUrl',
  'foto_url',
  'archivoUrl',
  'publicId',
  'fotoPublicId',
  'foto_public_id',
  'idUsuario',
  'id_usuario',
  'idPaciente',
  'id_paciente',
];

type FormatoImagenPermitido = {
  extension: 'jpg' | 'png';
  tipoMime: 'image/jpeg' | 'image/png';
};

type PeticionFotoPaciente =
  | { accion: 'eliminar' }
  | { accion: 'reintentar_limpieza' }
  | { accion: 'subir'; bytes: Uint8Array };

type ResultadoEliminacionCloudinary = {
  ok: boolean;
  error?: string;
};

class ErrorGestionFotoPaciente extends Error {
  readonly status: number;
  readonly codigo: string;

  constructor(status: number, codigo: string, mensaje: string) {
    super(mensaje);
    this.status = status;
    this.codigo = codigo;
  }
}

function respuestaJson(status: number, cuerpo: Record<string, unknown>) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      ...cabecerasCors,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function detectarFormatoPorFirma(
  bytes: Uint8Array,
): FormatoImagenPermitido | null {
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return { extension: 'jpg', tipoMime: 'image/jpeg' };
  }

  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return { extension: 'png', tipoMime: 'image/png' };
  }

  return null;
}

function decodificarBase64(base64Crudo: string): Uint8Array {
  const limpio = base64Crudo.trim();
  if (!limpio) {
    throw new ErrorGestionFotoPaciente(
      400,
      'ARCHIVO_VACIO',
      'Debes adjuntar una imagen JPG o PNG válida.',
    );
  }
  if (limpio.startsWith('http://') || limpio.startsWith('https://')) {
    throw new ErrorGestionFotoPaciente(
      400,
      'URL_NO_PERMITIDA',
      'No se aceptan enlaces externos; debes subir el archivo de imagen.',
    );
  }
  if (limpio.startsWith('data:')) {
    throw new ErrorGestionFotoPaciente(
      400,
      'FORMATO_PAYLOAD_INVALIDO',
      'Envía los bytes de la imagen en base64 sin prefijo data URI.',
    );
  }

  // Rechaza cargas sobredimensionadas antes de decodificar.
  if (limpio.length > Math.ceil((LIMITE_BYTES_FOTOGRAFIA * 4) / 3) + 16) {
    throw new ErrorGestionFotoPaciente(
      400,
      'ARCHIVO_SUPERA_LIMITE',
      'La fotografía supera el límite de 5 MB.',
    );
  }

  try {
    const binario = atob(limpio);
    const bytes = new Uint8Array(binario.length);
    for (let i = 0; i < binario.length; i++) {
      bytes[i] = binario.charCodeAt(i);
    }
    return bytes;
  } catch {
    throw new ErrorGestionFotoPaciente(
      400,
      'BASE64_INVALIDO',
      'El archivo de imagen enviado no tiene un formato válido.',
    );
  }
}

function rechazarCamposProhibidosCliente(cuerpo: Record<string, unknown>) {
  for (const campo of CAMPOS_PROHIBIDOS_CLIENTE) {
    if (cuerpo[campo] !== undefined && cuerpo[campo] !== null) {
      throw new ErrorGestionFotoPaciente(
        400,
        'PARAMETRO_NO_PERMITIDO',
        'La operación no acepta URLs, identificadores de Cloudinary ni identificadores de usuario desde el cliente.',
      );
    }
  }
}

function rechazarCamposProhibidosFormData(formData: FormData) {
  for (const campo of CAMPOS_PROHIBIDOS_CLIENTE) {
    if (formData.has(campo)) {
      throw new ErrorGestionFotoPaciente(
        400,
        'PARAMETRO_NO_PERMITIDO',
        'La operación no acepta URLs, identificadores de Cloudinary ni identificadores de usuario desde el cliente.',
      );
    }
  }
}

async function analizarPeticion(req: Request): Promise<PeticionFotoPaciente> {
  if (req.method === 'DELETE') {
    return { accion: 'eliminar' };
  }

  const contentType = (req.headers.get('content-type') ?? '').toLowerCase();

  if (contentType.includes('multipart/form-data')) {
    let formData: FormData;
    try {
      formData = await req.formData();
    } catch {
      throw new ErrorGestionFotoPaciente(
        400,
        'FORMULARIO_INVALIDO',
        'No se pudo leer el archivo enviado.',
      );
    }

    rechazarCamposProhibidosFormData(formData);

    const accionCruda = formData.get('accion');
    const accion =
      typeof accionCruda === 'string' && accionCruda.trim().length > 0
        ? accionCruda.trim().toLowerCase()
        : 'subir';

    if (accion === 'eliminar') {
      return { accion: 'eliminar' };
    }
    if (accion === 'reintentar_limpieza') {
      return { accion: 'reintentar_limpieza' };
    }
    if (accion !== 'subir') {
      throw new ErrorGestionFotoPaciente(
        400,
        'ACCION_NO_VALIDA',
        'La acción solicitada no es válida.',
      );
    }

    const entradaArchivo = formData.get('archivo');
    if (!(entradaArchivo instanceof File)) {
      throw new ErrorGestionFotoPaciente(
        400,
        'ARCHIVO_REQUERIDO',
        'Debes adjuntar un archivo de imagen en el campo archivo.',
      );
    }

    if (entradaArchivo.size <= 0) {
      throw new ErrorGestionFotoPaciente(
        400,
        'ARCHIVO_VACIO',
        'El archivo de imagen está vacío.',
      );
    }
    if (entradaArchivo.size > LIMITE_BYTES_FOTOGRAFIA) {
      throw new ErrorGestionFotoPaciente(
        400,
        'ARCHIVO_SUPERA_LIMITE',
        'La fotografía supera el límite de 5 MB.',
      );
    }

    return {
      accion: 'subir',
      bytes: new Uint8Array(await entradaArchivo.arrayBuffer()),
    };
  }

  if (contentType.includes('application/json')) {
    let cuerpo: Record<string, unknown>;
    try {
      const parseado = await req.json();
      if (
        !parseado ||
        typeof parseado !== 'object' ||
        Array.isArray(parseado)
      ) {
        throw new Error('JSON inválido');
      }
      cuerpo = parseado as Record<string, unknown>;
    } catch {
      throw new ErrorGestionFotoPaciente(
        400,
        'JSON_INVALIDO',
        'El cuerpo de la solicitud no es válido.',
      );
    }

    rechazarCamposProhibidosCliente(cuerpo);

    const accion =
      typeof cuerpo.accion === 'string'
        ? cuerpo.accion.trim().toLowerCase()
        : 'subir';

    if (accion === 'eliminar') {
      return { accion: 'eliminar' };
    }

    if (accion === 'reintentar_limpieza') {
      return { accion: 'reintentar_limpieza' };
    }

    if (accion !== 'subir') {
      throw new ErrorGestionFotoPaciente(
        400,
        'ACCION_NO_VALIDA',
        'La acción solicitada no es válida.',
      );
    }

    if (typeof cuerpo.archivoBase64 !== 'string') {
      throw new ErrorGestionFotoPaciente(
        400,
        'ARCHIVO_REQUERIDO',
        'Debes enviar la imagen en formato JPG o PNG.',
      );
    }

    return {
      accion: 'subir',
      bytes: decodificarBase64(cuerpo.archivoBase64),
    };
  }

  throw new ErrorGestionFotoPaciente(
    415,
    'CONTENIDO_NO_SOPORTADO',
    'Tipo de contenido no soportado para gestionar la fotografía.',
  );
}

async function firmarParametrosCloudinary(
  parametros: Record<string, string>,
  apiSecret: string,
): Promise<string> {
  const cadenaFirma = Object.keys(parametros)
    .filter((clave) => parametros[clave] !== '')
    .sort()
    .map((clave) => `${clave}=${parametros[clave]}`)
    .join('&');

  const datos = new TextEncoder().encode(`${cadenaFirma}${apiSecret}`);
  const resumen = await crypto.subtle.digest('SHA-1', datos);
  return Array.from(new Uint8Array(resumen))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function subirACloudinary({
  cloudName,
  apiKey,
  apiSecret,
  publicId,
  bytes,
  formato,
}: {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
  publicId: string;
  bytes: Uint8Array;
  formato: FormatoImagenPermitido;
}): Promise<string> {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const firma = await firmarParametrosCloudinary(
    {
      public_id: publicId,
      timestamp,
    },
    apiSecret,
  );

  const formulario = new FormData();
  formulario.append(
    'file',
    new Blob([Uint8Array.from(bytes).buffer], { type: formato.tipoMime }),
    `foto_paciente.${formato.extension}`,
  );
  formulario.append('api_key', apiKey);
  formulario.append('timestamp', timestamp);
  formulario.append('public_id', publicId);
  formulario.append('signature', firma);

  const controlador = new AbortController();
  const temporizador = setTimeout(
    () => controlador.abort(),
    TIEMPO_ESPERA_SUBIDA_MS,
  );

  try {
    const respuesta = await fetch(
      `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/upload`,
      {
        method: 'POST',
        body: formulario,
        signal: controlador.signal,
      },
    );

    if (!respuesta.ok) {
      throw new ErrorGestionFotoPaciente(
        502,
        'ERROR_PROVEEDOR_IMAGEN',
        'No se pudo subir la fotografía en este momento. Inténtalo nuevamente.',
      );
    }

    const datos = await respuesta.json();
    const secureUrl =
      typeof datos?.secure_url === 'string' ? datos.secure_url.trim() : '';

    const prefijoCloud = `https://res.cloudinary.com/${cloudName.toLowerCase()}/`;
    if (
      !secureUrl.startsWith('https://') ||
      !secureUrl.toLowerCase().startsWith(prefijoCloud) ||
      !secureUrl.includes(publicId)
    ) {
      throw new ErrorGestionFotoPaciente(
        502,
        'RESPUESTA_PROVEEDOR_INVALIDA',
        'No se recibió una dirección válida al guardar la fotografía.',
      );
    }

    return secureUrl;
  } catch (error) {
    if (error instanceof ErrorGestionFotoPaciente) {
      throw error;
    }
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new ErrorGestionFotoPaciente(
        504,
        'TIEMPO_ESPERA_AGOTADO',
        'La subida de la fotografía tardó demasiado. Inténtalo nuevamente.',
      );
    }
    throw new ErrorGestionFotoPaciente(
      502,
      'ERROR_CONEXION_PROVEEDOR',
      'No se pudo conectar con el servicio de almacenamiento de imágenes.',
    );
  } finally {
    clearTimeout(temporizador);
  }
}

async function eliminarDeCloudinary({
  cloudName,
  apiKey,
  apiSecret,
  publicId,
}: {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
  publicId: string;
}): Promise<ResultadoEliminacionCloudinary> {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const firma = await firmarParametrosCloudinary(
    {
      invalidate: 'true',
      public_id: publicId,
      timestamp,
    },
    apiSecret,
  );

  const formulario = new FormData();
  formulario.append('public_id', publicId);
  formulario.append('invalidate', 'true');
  formulario.append('api_key', apiKey);
  formulario.append('timestamp', timestamp);
  formulario.append('signature', firma);

  const controlador = new AbortController();
  const temporizador = setTimeout(
    () => controlador.abort(),
    TIEMPO_ESPERA_ELIMINACION_MS,
  );

  try {
    const respuesta = await fetch(
      `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/destroy`,
      {
        method: 'POST',
        body: formulario,
        signal: controlador.signal,
      },
    );

    if (!respuesta.ok) {
      return { ok: false, error: `HTTP_${respuesta.status}` };
    }

    const datos = await respuesta.json().catch(() => null);
    const resultado =
      typeof datos?.result === 'string' ? datos.result.toLowerCase() : '';
    if (resultado === 'ok' || resultado === 'not found') {
      return { ok: true };
    }
    return {
      ok: false,
      error: resultado ? `CLOUDINARY_${resultado}` : 'RESPUESTA_INVALIDA',
    };
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      return { ok: false, error: 'TIMEOUT_ELIMINACION' };
    }
    return { ok: false, error: 'ERROR_RED_ELIMINACION' };
  } finally {
    clearTimeout(temporizador);
  }
}

/**
 * Reclama y ejecuta de forma segura las limpiezas pendientes en Cloudinary
 * pertenecientes exclusivamente al paciente autenticado. Si alguna falla,
 * queda marcada como 'pendiente' para reintento posterior sin dejar referencias
 * invalidas en Supabase.
 */
async function procesarLimpiezasPendientesPaciente({
  clienteAdmin,
  idUsuario,
  prefijoPropio,
  cloudName,
  apiKey,
  apiSecret,
}: {
  clienteAdmin: SupabaseClient;
  idUsuario: string;
  prefijoPropio: string;
  cloudName: string;
  apiKey: string;
  apiSecret: string;
}): Promise<{ procesadas: number; pendientes: number }> {
  const { data: filasPendientes, error: errorReclamo } = await clienteAdmin.rpc(
    'reclamar_limpiezas_foto_paciente_pendientes_servidor',
    {
      p_id_usuario: idUsuario,
      p_limite: MAX_LIMPIEZAS_POR_PETICION,
    },
  );

  if (errorReclamo || !Array.isArray(filasPendientes)) {
    return { procesadas: 0, pendientes: 0 };
  }

  let procesadas = 0;
  let pendientes = 0;

  for (const fila of filasPendientes) {
    const publicId =
      typeof fila?.foto_public_id === 'string'
        ? fila.foto_public_id.trim()
        : '';

    // Defensa en profundidad: nunca elimina recursos fuera del prefijo del paciente.
    if (!publicId || !publicId.startsWith(prefijoPropio)) {
      continue;
    }

    const resultado = await eliminarDeCloudinary({
      cloudName,
      apiKey,
      apiSecret,
      publicId,
    });

    await clienteAdmin.rpc(
      'registrar_resultado_limpieza_foto_paciente_servidor',
      {
        p_id_usuario: idUsuario,
        p_foto_public_id: publicId,
        p_eliminado: resultado.ok,
        p_error: resultado.error ?? null,
      },
    );

    if (resultado.ok) {
      procesadas++;
    } else {
      pendientes++;
    }
  }

  return { procesadas, pendientes };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cabecerasCors });
  }

  if (req.method !== 'POST' && req.method !== 'DELETE') {
    return respuestaJson(405, {
      codigo: 'METODO_NO_PERMITIDO',
      mensaje: 'Método no permitido.',
    });
  }

  try {
    const supabaseUrl = (Deno.env.get('SUPABASE_URL') ?? '').trim();
    const supabaseAnonKey = (Deno.env.get('SUPABASE_ANON_KEY') ?? '').trim();
    const supabaseServiceRoleKey = (
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    ).trim();
    const cloudName = (Deno.env.get('CLOUDINARY_CLOUD_NAME') ?? '').trim();
    const apiKey = (Deno.env.get('CLOUDINARY_API_KEY') ?? '').trim();
    const apiSecret = (Deno.env.get('CLOUDINARY_API_SECRET') ?? '').trim();

    if (
      !supabaseUrl ||
      !supabaseAnonKey ||
      !supabaseServiceRoleKey ||
      !cloudName ||
      !apiKey ||
      !apiSecret
    ) {
      return respuestaJson(500, {
        codigo: 'CONFIGURACION_INCOMPLETA',
        mensaje: 'El servicio de fotografías no está disponible en este momento.',
      });
    }

    const encabezadoAuth = req.headers.get('Authorization') ?? '';
    if (!encabezadoAuth.startsWith('Bearer ')) {
      return respuestaJson(401, {
        codigo: 'NO_AUTENTICADO',
        mensaje: 'Debes iniciar sesión para gestionar tu fotografía.',
      });
    }

    const tokenJwt = encabezadoAuth.slice('Bearer '.length).trim();
    if (!tokenJwt) {
      return respuestaJson(401, {
        codigo: 'NO_AUTENTICADO',
        mensaje: 'Debes iniciar sesión para gestionar tu fotografía.',
      });
    }

    // 1. Verifica identidad exclusivamente desde el JWT autenticado.
    const clienteUsuario = createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${tokenJwt}`,
        },
      },
    });

    const {
      data: { user: usuario },
      error: errorUsuario,
    } = await clienteUsuario.auth.getUser(tokenJwt);

    if (errorUsuario || !usuario || !usuario.email_confirmed_at) {
      return respuestaJson(401, {
        codigo: 'SESION_INVALIDA',
        mensaje: 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.',
      });
    }

    const { data: filasPerfil, error: errorPerfil } =
      await clienteUsuario.rpc('perfil_del_usuario_actual');
    const perfilActual = Array.isArray(filasPerfil) ? filasPerfil[0] : null;

    if (errorPerfil || !perfilActual || perfilActual.id !== usuario.id) {
      return respuestaJson(403, {
        codigo: 'PERFIL_NO_ENCONTRADO',
        mensaje: 'No se pudo verificar tu perfil de usuario.',
      });
    }

    if (perfilActual.cuenta_activa !== true) {
      return respuestaJson(403, {
        codigo: 'CUENTA_INACTIVA',
        mensaje: 'Tu cuenta no se encuentra activa para realizar esta acción.',
      });
    }

    if (perfilActual.rol !== 'paciente') {
      return respuestaJson(403, {
        codigo: 'ROL_NO_AUTORIZADO',
        mensaje: 'Solo las cuentas de pacientes pueden gestionar esta fotografía.',
      });
    }

    // 2. Cliente administrativo para ejecutar las RPC exclusivas de service_role.
    const clienteAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    });

    const prefijoPropio = `psicobloom/pacientes/${usuario.id}_`;
    const peticion = await analizarPeticion(req);

    // -------------------------------------------------------------------------
    // ACCION: REINTENTAR LIMPIEZAS PENDIENTES EN CLOUDINARY DEL PROPIO PACIENTE
    // -------------------------------------------------------------------------
    if (peticion.accion === 'reintentar_limpieza') {
      const resumenLimpieza = await procesarLimpiezasPendientesPaciente({
        clienteAdmin,
        idUsuario: usuario.id,
        prefijoPropio,
        cloudName,
        apiKey,
        apiSecret,
      });

      return respuestaJson(200, {
        procesadas: resumenLimpieza.procesadas,
        pendientes: resumenLimpieza.pendientes,
      });
    }

    // -------------------------------------------------------------------------
    // ACCION: ELIMINAR FOTOGRAFIA PERSONALIZADA DEL PACIENTE
    //         1) Confirma primero el cambio en Supabase (bajo FOR UPDATE) y
    //            encola atomicamente el public_id en limpieza_fotos_paciente_pendientes.
    //         2) Ejecuta la eliminacion en Cloudinary desde la cola reintentable.
    // -------------------------------------------------------------------------
    if (peticion.accion === 'eliminar') {
      const { data: filasEliminacion, error: errorEliminacion } =
        await clienteAdmin.rpc('eliminar_foto_paciente_servidor', {
          p_id_usuario: usuario.id,
        });

      if (errorEliminacion) {
        const esSinPermiso = errorEliminacion.code === '42501';
        return respuestaJson(esSinPermiso ? 403 : 500, {
          codigo: esSinPermiso ? 'SIN_PERMISO' : 'ERROR_ELIMINACION_BD',
          mensaje: esSinPermiso
            ? 'No tienes permiso para eliminar esta fotografía.'
            : 'No se pudo completar la eliminación de tu fotografía.',
        });
      }

      const resultadoEliminacion = Array.isArray(filasEliminacion)
        ? filasEliminacion[0]
        : null;

      const resumenLimpieza = await procesarLimpiezasPendientesPaciente({
        clienteAdmin,
        idUsuario: usuario.id,
        prefijoPropio,
        cloudName,
        apiKey,
        apiSecret,
      });

      return respuestaJson(200, {
        eliminada: resultadoEliminacion?.eliminada === true,
        fotoUrl: null,
        tieneFotoPersonalizada: false,
        limpiezaAlmacenamientoPendiente: resumenLimpieza.pendientes > 0,
      });
    }

    // -------------------------------------------------------------------------
    // ACCION: SUBIR / REEMPLAZAR FOTOGRAFIA DEL PACIENTE
    // -------------------------------------------------------------------------
    const { bytes } = peticion;
    if (bytes.length <= 0) {
      return respuestaJson(400, {
        codigo: 'ARCHIVO_VACIO',
        mensaje: 'El archivo de imagen está vacío.',
      });
    }

    if (bytes.length > LIMITE_BYTES_FOTOGRAFIA) {
      return respuestaJson(400, {
        codigo: 'ARCHIVO_SUPERA_LIMITE',
        mensaje: 'La fotografía supera el límite de 5 MB.',
      });
    }

    const formatoReal = detectarFormatoPorFirma(bytes);
    if (!formatoReal) {
      return respuestaJson(400, {
        codigo: 'FORMATO_NO_PERMITIDO',
        mensaje: 'Solo se permiten fotografías en formato JPG o PNG.',
      });
    }

    const publicIdNuevo = `${prefijoPropio}${crypto.randomUUID()}`;

    const secureUrl = await subirACloudinary({
      cloudName,
      apiKey,
      apiSecret,
      publicId: publicIdNuevo,
      bytes,
      formato: formatoReal,
    });

    const { error: errorPersistencia } = await clienteAdmin.rpc(
      'establecer_foto_paciente_servidor',
      {
        p_id_usuario: usuario.id,
        p_foto_url: secureUrl,
        p_foto_public_id: publicIdNuevo,
      },
    );

    if (errorPersistencia) {
      // Solo un rechazo SQL confirmado garantiza que la BD no aplico el cambio:
      // limpiamos la imagen recien subida y, si Cloudinary falla, la encolamos
      // para reintento seguro sin tocar nunca la foto anterior del paciente.
      const rechazoSqlConfirmado = /^[0-9A-Z]{5}$/.test(
        errorPersistencia.code ?? '',
      );
      if (rechazoSqlConfirmado) {
        const resultadoLimpieza = await eliminarDeCloudinary({
          cloudName,
          apiKey,
          apiSecret,
          publicId: publicIdNuevo,
        });
        if (!resultadoLimpieza.ok) {
          await clienteAdmin.rpc('encolar_limpieza_foto_paciente_servidor', {
            p_id_usuario: usuario.id,
            p_foto_public_id: publicIdNuevo,
          });
        }
      }

      const esSinPermiso = errorPersistencia.code === '42501';
      return respuestaJson(esSinPermiso ? 403 : 500, {
        codigo: esSinPermiso ? 'SIN_PERMISO' : 'ERROR_PERSISTENCIA_FOTO',
        mensaje: esSinPermiso
          ? 'No tienes permiso para actualizar esta fotografía.'
          : 'No se pudo guardar la fotografía en tu perfil. Se conservó tu foto anterior.',
      });
    }

    // Drena la cola de limpiezas pendientes del paciente (incluye la foto anterior
    // recien sustituida y cualquier eliminacion previa que hubiese fallado).
    const resumenLimpieza = await procesarLimpiezasPendientesPaciente({
      clienteAdmin,
      idUsuario: usuario.id,
      prefijoPropio,
      cloudName,
      apiKey,
      apiSecret,
    });

    return respuestaJson(200, {
      fotoUrl: secureUrl,
      tieneFotoPersonalizada: true,
      limpiezaAlmacenamientoPendiente: resumenLimpieza.pendientes > 0,
    });
  } catch (error) {
    if (error instanceof ErrorGestionFotoPaciente) {
      return respuestaJson(error.status, {
        codigo: error.codigo,
        mensaje: error.message,
      });
    }
    return respuestaJson(500, {
      codigo: 'ERROR_INTERNO',
      mensaje: 'No se pudo procesar la fotografía en este momento.',
    });
  }
});
