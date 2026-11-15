import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const LIMITE_BYTES_FOTOGRAFIA = 5 * 1024 * 1024;
const TIEMPO_ESPERA_SUBIDA_MS = 15000;
const TIEMPO_ESPERA_LIMPIEZA_MS = 8000;

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type FormatoImagenPermitido = {
  extension: 'jpg' | 'png';
  tipoMime: 'image/jpeg' | 'image/png';
};

class ErrorValidacionFoto extends Error {
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
    throw new ErrorValidacionFoto(
      400,
      'ARCHIVO_VACIO',
      'Debes adjuntar una imagen JPG o PNG válida.',
    );
  }
  if (limpio.startsWith('http://') || limpio.startsWith('https://')) {
    throw new ErrorValidacionFoto(
      400,
      'URL_NO_PERMITIDA',
      'No se aceptan enlaces externos; debes subir el archivo de imagen.',
    );
  }
  if (limpio.startsWith('data:')) {
    throw new ErrorValidacionFoto(
      400,
      'FORMATO_PAYLOAD_INVALIDO',
      'Envía los bytes de la imagen en base64 sin prefijo data URI.',
    );
  }

  // Aproximación previa antes de decodificar para rechazar cargas enormes rápido.
  if (limpio.length > Math.ceil((LIMITE_BYTES_FOTOGRAFIA * 4) / 3) + 16) {
    throw new ErrorValidacionFoto(
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
    throw new ErrorValidacionFoto(
      400,
      'BASE64_INVALIDO',
      'El archivo de imagen enviado no tiene un formato válido.',
    );
  }
}

async function extraerBytesDesdePeticion(req: Request): Promise<Uint8Array> {
  const contentType = (req.headers.get('content-type') ?? '').toLowerCase();

  if (contentType.includes('multipart/form-data')) {
    let formData: FormData;
    try {
      formData = await req.formData();
    } catch {
      throw new ErrorValidacionFoto(
        400,
        'FORMULARIO_INVALIDO',
        'No se pudo leer el archivo enviado.',
      );
    }

    const entradaArchivo = formData.get('archivo');
    if (!(entradaArchivo instanceof File)) {
      throw new ErrorValidacionFoto(
        400,
        'ARCHIVO_REQUERIDO',
        'Debes adjuntar un archivo de imagen en el campo archivo.',
      );
    }

    if (entradaArchivo.size <= 0) {
      throw new ErrorValidacionFoto(
        400,
        'ARCHIVO_VACIO',
        'El archivo de imagen está vacío.',
      );
    }
    if (entradaArchivo.size > LIMITE_BYTES_FOTOGRAFIA) {
      throw new ErrorValidacionFoto(
        400,
        'ARCHIVO_SUPERA_LIMITE',
        'La fotografía supera el límite de 5 MB.',
      );
    }

    return new Uint8Array(await entradaArchivo.arrayBuffer());
  }

  if (contentType.includes('application/json')) {
    let cuerpo: Record<string, unknown>;
    try {
      const parseado = await req.json();
      if (!parseado || typeof parseado !== 'object' || Array.isArray(parseado)) {
        throw new Error('JSON inválido');
      }
      cuerpo = parseado as Record<string, unknown>;
    } catch {
      throw new ErrorValidacionFoto(
        400,
        'JSON_INVALIDO',
        'El cuerpo de la solicitud no es válido.',
      );
    }

    if (
      typeof cuerpo.url === 'string' ||
      typeof cuerpo.fotoUrl === 'string' ||
      typeof cuerpo.foto_url === 'string' ||
      typeof cuerpo.archivoUrl === 'string'
    ) {
      throw new ErrorValidacionFoto(
        400,
        'URL_NO_PERMITIDA',
        'No se aceptan enlaces externos; debes subir el archivo de imagen.',
      );
    }

    if (typeof cuerpo.archivoBase64 !== 'string') {
      throw new ErrorValidacionFoto(
        400,
        'ARCHIVO_REQUERIDO',
        'Debes enviar la imagen en formato JPG o PNG.',
      );
    }

    return decodificarBase64(cuerpo.archivoBase64);
  }

  throw new ErrorValidacionFoto(
    415,
    'CONTENIDO_NO_SOPORTADO',
    'Tipo de contenido no soportado para subir la fotografía.',
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
    `foto_perfil.${formato.extension}`,
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
      throw new ErrorValidacionFoto(
        502,
        'ERROR_PROVEEDOR_IMAGEN',
        'No se pudo subir la fotografía en este momento. Inténtalo nuevamente.',
      );
    }

    const datos = await respuesta.json();
    const secureUrl =
      typeof datos?.secure_url === 'string' ? datos.secure_url.trim() : '';

    if (!secureUrl.startsWith('https://')) {
      throw new ErrorValidacionFoto(
        502,
        'RESPUESTA_PROVEEDOR_INVALIDA',
        'No se recibió una dirección válida al guardar la fotografía.',
      );
    }

    return secureUrl;
  } catch (error) {
    if (error instanceof ErrorValidacionFoto) {
      throw error;
    }
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new ErrorValidacionFoto(
        504,
        'TIEMPO_ESPERA_AGOTADO',
        'La subida de la fotografía tardó demasiado. Inténtalo nuevamente.',
      );
    }
    throw new ErrorValidacionFoto(
      502,
      'ERROR_CONEXION_PROVEEDOR',
      'No se pudo conectar con el servicio de almacenamiento de imágenes.',
    );
  } finally {
    clearTimeout(temporizador);
  }
}

async function eliminarImagenRecienSubidaBestEffort({
  cloudName,
  apiKey,
  apiSecret,
  publicId,
}: {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
  publicId: string;
}): Promise<void> {
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
    TIEMPO_ESPERA_LIMPIEZA_MS,
  );

  try {
    await fetch(
      `https://api.cloudinary.com/v1_1/${encodeURIComponent(cloudName)}/image/destroy`,
      {
        method: 'POST',
        body: formulario,
        signal: controlador.signal,
      },
    );
  } catch {
    // Limpieza best-effort únicamente de la imagen recién subida.
  } finally {
    clearTimeout(temporizador);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cabecerasCors });
  }

  if (req.method !== 'POST') {
    return respuestaJson(405, {
      codigo: 'METODO_NO_PERMITIDO',
      mensaje: 'Método no permitido.',
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const cloudName = Deno.env.get('CLOUDINARY_CLOUD_NAME') ?? '';
  const apiKey = Deno.env.get('CLOUDINARY_API_KEY') ?? '';
  const apiSecret = Deno.env.get('CLOUDINARY_API_SECRET') ?? '';

  if (
    !supabaseUrl ||
    !supabaseAnonKey ||
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
      mensaje: 'Debes iniciar sesión para actualizar tu fotografía.',
    });
  }

  const clienteSupabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: encabezadoAuth,
      },
    },
  });

  const {
    data: { user: usuario },
    error: errorUsuario,
  } = await clienteSupabase.auth.getUser();

  if (errorUsuario || !usuario) {
    return respuestaJson(401, {
      codigo: 'SESION_INVALIDA',
      mensaje: 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.',
    });
  }

  const { data: filasPerfil, error: errorPerfil } = await clienteSupabase.rpc(
    'perfil_del_usuario_actual',
  );
  const perfilActual = Array.isArray(filasPerfil) ? filasPerfil[0] : null;

  if (errorPerfil || !perfilActual) {
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

  if (perfilActual.rol !== 'profesional') {
    return respuestaJson(403, {
      codigo: 'ROL_NO_AUTORIZADO',
      mensaje: 'Solo las cuentas de profesionales pueden subir esta fotografía.',
    });
  }

  const { data: filasProfesional, error: errorProfesional } =
    await clienteSupabase.rpc('obtener_perfil_profesional_propio');
  const profesionalPropio = Array.isArray(filasProfesional)
    ? filasProfesional[0]
    : null;

  if (errorProfesional || !profesionalPropio) {
    return respuestaJson(403, {
      codigo: 'PROFESIONAL_NO_ENCONTRADO',
      mensaje: 'No se encontró un perfil profesional asociado a tu cuenta.',
    });
  }

  let bytes: Uint8Array;
  try {
    bytes = await extraerBytesDesdePeticion(req);
  } catch (error) {
    if (error instanceof ErrorValidacionFoto) {
      return respuestaJson(error.status, {
        codigo: error.codigo,
        mensaje: error.message,
      });
    }
    return respuestaJson(400, {
      codigo: 'ARCHIVO_INVALIDO',
      mensaje: 'No se pudo procesar la fotografía enviada.',
    });
  }

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

  const publicIdNuevo = `psicobloom/profesionales/${usuario.id}_${crypto.randomUUID()}`;

  let secureUrl: string;
  try {
    secureUrl = await subirACloudinary({
      cloudName,
      apiKey,
      apiSecret,
      publicId: publicIdNuevo,
      bytes,
      formato: formatoReal,
    });
  } catch (error) {
    if (error instanceof ErrorValidacionFoto) {
      return respuestaJson(error.status, {
        codigo: error.codigo,
        mensaje: error.message,
      });
    }
    return respuestaJson(502, {
      codigo: 'ERROR_SUBIDA_IMAGEN',
      mensaje: 'No se pudo subir la fotografía en este momento.',
    });
  }

  const { error: errorPersistencia } = await clienteSupabase.rpc(
    'actualizar_foto_profesional_propia',
    { p_foto_url: secureUrl },
  );

  if (errorPersistencia) {
    // Solo un error SQL explícito confirma que la escritura fue rechazada.
    // Si hubo un fallo de red, la escritura pudo completarse: no borrar la imagen.
    const rechazoSqlConfirmado = /^[0-9A-Z]{5}$/.test(
      errorPersistencia.code ?? '',
    );
    if (rechazoSqlConfirmado) {
      await eliminarImagenRecienSubidaBestEffort({
        cloudName,
        apiKey,
        apiSecret,
        publicId: publicIdNuevo,
      });
    }

    const esSinPermiso = errorPersistencia.code === '42501';
    return respuestaJson(esSinPermiso ? 403 : 500, {
      codigo: esSinPermiso ? 'SIN_PERMISO' : 'ERROR_PERSISTENCIA_FOTO',
      mensaje: esSinPermiso
        ? 'No tienes permiso para actualizar esta fotografía.'
        : rechazoSqlConfirmado
          ? 'No se pudo guardar la fotografía en tu perfil. Se conservó tu foto anterior.'
          : 'No pudimos confirmar si la fotografía se guardó. Vuelve a cargar tu perfil antes de intentarlo otra vez.',
    });
  }

  return respuestaJson(200, {
    fotoUrl: secureUrl,
  });
});
