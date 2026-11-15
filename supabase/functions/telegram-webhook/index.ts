// Edge Function externa para recibir actualizaciones del webhook de Telegram.
// Requiere verify_jwt = false en supabase/config.toml (o al desplegar con
// --no-verify-jwt) porque Telegram no envía JWT de Supabase; en su lugar se
// autentica validando X-Telegram-Bot-Api-Secret-Token contra TELEGRAM_WEBHOOK_SECRET.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TIEMPO_ESPERA_TELEGRAM_MS = 8000;

function compararTiempoConstante(a: string, b: string): boolean {
  const bytesA = new TextEncoder().encode(a);
  const bytesB = new TextEncoder().encode(b);
  if (bytesA.length !== bytesB.length) {
    return false;
  }
  let diferencia = 0;
  for (let i = 0; i < bytesA.length; i++) {
    diferencia |= bytesA[i] ^ bytesB[i];
  }
  return diferencia === 0;
}

async function calcularHashSha256Hex(texto: string): Promise<string> {
  const datos = new TextEncoder().encode(texto);
  const resumen = await crypto.subtle.digest('SHA-256', datos);
  return Array.from(new Uint8Array(resumen))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function enviarMensajeTelegram(
  botToken: string,
  chatId: number,
  texto: string,
): Promise<void> {
  const controlador = new AbortController();
  const temporizador = setTimeout(
    () => controlador.abort(),
    TIEMPO_ESPERA_TELEGRAM_MS,
  );
  try {
    await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: texto,
      }),
      signal: controlador.signal,
    });
  } catch {
    // Respuesta informativa al chat; no debe provocar reintentos infinitos del webhook.
  } finally {
    clearTimeout(temporizador);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Método no permitido.', { status: 405 });
  }

  const webhookSecret = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '';
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!webhookSecret || !botToken || !supabaseUrl || !supabaseServiceKey) {
    return new Response('Configuración incompleta.', { status: 500 });
  }

  const secretoRecibido =
    req.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '';
  if (!secretoRecibido || !compararTiempoConstante(secretoRecibido, webhookSecret)) {
    return new Response('No autorizado.', { status: 401 });
  }

  let actualizacion: Record<string, unknown>;
  try {
    const cuerpo = await req.json();
    if (!cuerpo || typeof cuerpo !== 'object' || Array.isArray(cuerpo)) {
      return new Response('OK', { status: 200 });
    }
    actualizacion = cuerpo as Record<string, unknown>;
  } catch {
    return new Response('Solicitud inválida.', { status: 400 });
  }

  const mensaje = actualizacion.message as Record<string, unknown> | undefined;
  if (!mensaje || typeof mensaje !== 'object') {
    return new Response('OK', { status: 200 });
  }

  const chat = mensaje.chat as Record<string, unknown> | undefined;
  const chatId = typeof chat?.id === 'number' ? chat.id : null;
  const tipoChat = typeof chat?.type === 'string' ? chat.type : '';
  const texto = typeof mensaje.text === 'string' ? mensaje.text.trim() : '';

  if (chatId === null || !texto) {
    return new Response('OK', { status: 200 });
  }

  // Detecta /start o /start@nombre_bot con parámetro opcional.
  const coincidenciaStart = /^\/start(?:@[A-Za-z0-9_]+)?(?:\s+(\S+))?$/i.exec(
    texto,
  );
  if (!coincidenciaStart) {
    return new Response('OK', { status: 200 });
  }

  if (tipoChat !== 'private') {
    await enviarMensajeTelegram(
      botToken,
      chatId,
      'Solo puedes vincular un chat privado para recibir avisos de PsicoBloom.',
    );
    return new Response('OK', { status: 200 });
  }

  const codigo = (coincidenciaStart[1] ?? '').trim();
  if (!codigo) {
    await enviarMensajeTelegram(
      botToken,
      chatId,
      'Para conectar tus avisos, abre tu Perfil en PsicoBloom y toca «Conectar Telegram».',
    );
    return new Response('OK', { status: 200 });
  }

  if (!Number.isSafeInteger(chatId) || chatId <= 0 || !/^[A-Za-z0-9_-]{32}$/.test(codigo)) {
    await enviarMensajeTelegram(botToken, chatId,
      'El enlace no es válido. Genera uno nuevo desde tu Perfil en PsicoBloom.');
    return new Response('OK', { status: 200 });
  }
  const hashCodigo = await calcularHashSha256Hex(codigo);
  const clienteAdmin = createClient(supabaseUrl, supabaseServiceKey);

  const { data: resultado, error } = await clienteAdmin.rpc(
    'consumir_codigo_vinculacion_telegram',
    {
      p_hash_codigo: hashCodigo,
      p_chat_id: chatId,
    },
  );

  if (error) {
    await enviarMensajeTelegram(
      botToken,
      chatId,
      'No se pudo completar la vinculación en este momento. Inténtalo nuevamente desde PsicoBloom.',
    );
    return new Response('OK', { status: 200 });
  }

  switch (resultado) {
    case 'ya_vinculado':
      // Un update repetido no cambia la vinculación ni reenvía la confirmación.
      break;
    case 'vinculado':
      await enviarMensajeTelegram(
        botToken,
        chatId,
        '¡Listo! Tu Telegram quedó conectado a PsicoBloom. Aquí recibirás un aviso cuando tengas una nueva solicitud de cita.',
      );
      break;
    case 'chat_en_uso_por_otro':
      await enviarMensajeTelegram(
        botToken,
        chatId,
        'Este chat de Telegram ya está vinculado a otro profesional en PsicoBloom.',
      );
      break;
    case 'codigo_expirado':
    case 'codigo_usado':
    case 'codigo_anulado':
      await enviarMensajeTelegram(
        botToken,
        chatId,
        'Este enlace ya venció o fue utilizado. Genera uno nuevo desde tu Perfil en PsicoBloom.',
      );
      break;
    case 'profesional_inactivo':
      await enviarMensajeTelegram(
        botToken,
        chatId,
        'Tu cuenta profesional no se encuentra activa en PsicoBloom.',
      );
      break;
    default:
      await enviarMensajeTelegram(
        botToken,
        chatId,
        'El código no es válido. Entra a tu Perfil en PsicoBloom y toca «Conectar Telegram».',
      );
      break;
  }

  return new Response('OK', { status: 200 });
});
