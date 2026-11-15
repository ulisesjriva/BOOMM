import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const MINUTOS_CADUCIDAD_CODIGO = 10;

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function respuestaJson(status: number, cuerpo: Record<string, unknown>) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      ...cabecerasCors,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function generarCodigoAleatorioSeguro(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  let binario = '';
  for (const byte of bytes) {
    binario += String.fromCharCode(byte);
  }
  return btoa(binario)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

async function calcularHashSha256Hex(texto: string): Promise<string> {
  const datos = new TextEncoder().encode(texto);
  const resumen = await crypto.subtle.digest('SHA-256', datos);
  return Array.from(new Uint8Array(resumen))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
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
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const botUsername = (Deno.env.get('TELEGRAM_BOT_USERNAME') ?? '')
    .trim()
    .replace(/^@/, '');

  if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceKey || !botUsername) {
    return respuestaJson(500, {
      codigo: 'CONFIGURACION_INCOMPLETA',
      mensaje: 'Los avisos por Telegram no están configurados en el servidor.',
    });
  }

  const encabezadoAuth = req.headers.get('Authorization') ?? '';
  if (!encabezadoAuth.startsWith('Bearer ')) {
    return respuestaJson(401, {
      codigo: 'NO_AUTENTICADO',
      mensaje: 'Debes iniciar sesión para conectar Telegram.',
    });
  }

  // Autentica y resuelve la identidad exclusivamente desde la sesión del usuario.
  const clienteUsuario = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: { Authorization: encabezadoAuth },
    },
  });

  const {
    data: { user: usuario },
    error: errorUsuario,
  } = await clienteUsuario.auth.getUser();

  if (errorUsuario || !usuario) {
    return respuestaJson(401, {
      codigo: 'SESION_INVALIDA',
      mensaje: 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.',
    });
  }

  const { data: filasPerfil, error: errorPerfil } = await clienteUsuario.rpc(
    'perfil_del_usuario_actual',
  );
  const perfilActual = Array.isArray(filasPerfil) ? filasPerfil[0] : null;

  if (errorPerfil || !perfilActual) {
    return respuestaJson(403, {
      codigo: 'PERFIL_NO_ENCONTRADO',
      mensaje: 'No se pudo verificar tu perfil de usuario.',
    });
  }

  if (perfilActual.cuenta_activa !== true || perfilActual.rol !== 'profesional') {
    return respuestaJson(403, {
      codigo: 'ROL_NO_AUTORIZADO',
      mensaje: 'Solo los profesionales con cuenta activa pueden conectar Telegram.',
    });
  }

  const { data: filasProfesional, error: errorProfesional } =
    await clienteUsuario.rpc('obtener_perfil_profesional_propio');
  const profesional = Array.isArray(filasProfesional)
    ? filasProfesional[0]
    : null;
  const idProfesional =
    typeof profesional?.id_profesional === 'string'
      ? profesional.id_profesional
      : '';

  if (errorProfesional || !idProfesional) {
    return respuestaJson(403, {
      codigo: 'PROFESIONAL_NO_ENCONTRADO',
      mensaje: 'No se encontró un perfil profesional asociado a tu cuenta.',
    });
  }

  const codigo = generarCodigoAleatorioSeguro();
  const hashCodigo = await calcularHashSha256Hex(codigo);
  const expiraEn = new Date(
    Date.now() + MINUTOS_CADUCIDAD_CODIGO * 60 * 1000,
  ).toISOString();

  const clienteAdmin = createClient(supabaseUrl, supabaseServiceKey);
  const { error: errorRegistro } = await clienteAdmin.rpc(
    'crear_codigo_vinculacion_telegram',
    {
      p_id_profesional: idProfesional,
      p_hash_codigo: hashCodigo,
      p_expira_en: expiraEn,
    },
  );

  if (errorRegistro) {
    return respuestaJson(500, {
      codigo: 'ERROR_GENERACION_CODIGO',
      mensaje: 'No se pudo generar el enlace de vinculación. Inténtalo nuevamente.',
    });
  }

  return respuestaJson(200, {
    enlaceTelegram: `https://t.me/${botUsername}?start=${codigo}`,
    expiraEn,
  });
});
