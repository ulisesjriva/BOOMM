// Despachador de servidor para la cola eventos_avisos_telegram.
// Debe ejecutarse únicamente desde un cron o tarea de servidor autorizada
// con JWT de servidor en Authorization y una clave exclusiva en X-Telegram-Dispatch-Secret.
// Mantener verify_jwt=true en el gateway; TELEGRAM_DISPATCH_SECRET autentica además al programador.
//
// Nota operativa sobre red incierta:
// Si Telegram recibe la petición sendMessage pero la respuesta HTTP se pierde
// o vence por timeout antes de llegar al despachador, el evento se reintentará
// y podría producirse un aviso duplicado excepcionalmente.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TEXTO_AVISO_SOLICITUD =
  'PsicoBloom: tienes una nueva solicitud de cita. Abre la app y revisa Solicitudes.';
const MAXIMO_INTENTOS = 5;
const TIEMPO_ESPERA_ENVIO_MS = 10000;
const LOTE_EVENTOS = 10;

type EventoReclamado = {
  id_evento: string;
  id_cita: string;
  id_profesional: string;
  intentos: number;
  chat_id: number | null;
};

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

function respuestaJson(status: number, cuerpo: Record<string, unknown>) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

function calcularProximoIntentoIso(intentos: number): string {
  const segundos = Math.min(60 * Math.pow(2, Math.max(0, intentos - 1)), 900);
  return new Date(Date.now() + segundos * 1000).toISOString();
}

async function enviarAvisoTelegram(
  botToken: string,
  chatId: number,
): Promise<{ ok: boolean; permanente: boolean; motivo?: string; reintentarTrasSegundos?: number }> {
  const controlador = new AbortController();
  const temporizador = setTimeout(
    () => controlador.abort(),
    TIEMPO_ESPERA_ENVIO_MS,
  );

  try {
    const respuesta = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: TEXTO_AVISO_SOLICITUD,
        }),
        signal: controlador.signal,
      },
    );

    const cuerpo = await respuesta.json().catch(() => null);
    if (respuesta.ok && cuerpo?.ok === true) {
      return { ok: true, permanente: false };
    }
    if (respuesta.status === 429 || cuerpo?.error_code === 429) {
      const segundos = Number(cuerpo?.parameters?.retry_after);
      return { ok: false, permanente: false, motivo: 'LIMITE_TELEGRAM',
        reintentarTrasSegundos: Number.isFinite(segundos)
          ? Math.max(1, Math.min(segundos, 3600)) : 60 };
    }

    const permanente = [400, 401, 403].includes(respuesta.status);
    return {
      ok: false,
      permanente,
      motivo: `HTTP_${respuesta.status}`,
    };
  } catch (error) {
    const esTimeout = error instanceof DOMException && error.name === 'AbortError';
    return {
      ok: false,
      permanente: false,
      motivo: esTimeout ? 'TIMEOUT_RED' : 'ERROR_RED',
    };
  } finally {
    clearTimeout(temporizador);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return respuestaJson(405, { mensaje: 'Método no permitido.' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
  const secretoDespacho = Deno.env.get('TELEGRAM_DISPATCH_SECRET') ?? '';

  if (!supabaseUrl || !supabaseServiceKey || !botToken || !secretoDespacho) {
    return respuestaJson(500, { mensaje: 'Configuración incompleta.' });
  }

  const auth = req.headers.get('Authorization') ?? '';
  const tokenRecibido = req.headers.get('X-Telegram-Dispatch-Secret') ?? '';
  if (!auth.startsWith('Bearer ') || !tokenRecibido || !compararTiempoConstante(tokenRecibido, secretoDespacho)) {
    return respuestaJson(401, { mensaje: 'No autorizado.' });
  }

  // Cada lote se procesa en paralelo: todos los envíos arrancan dentro de su reserva.
  // Acotar también las RPC para no mantener trabajadores vivos sin límite.
  const clienteAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    global: { fetch: (input: RequestInfo | URL, init?: RequestInit) =>
      fetch(input, { ...init, signal: AbortSignal.timeout(12000) }) },
  });
  const { data: eventos, error: errorReclamo } = await clienteAdmin.rpc(
    'reclamar_eventos_avisos_telegram',
    {
      p_limite: LOTE_EVENTOS,
      p_bloqueo_segundos: 60,
    },
  );

  if (errorReclamo) {
    return respuestaJson(500, { mensaje: 'No se pudo consultar la cola de avisos.' });
  }

  const lista = Array.isArray(eventos) ? (eventos as EventoReclamado[]) : [];
  let enviados = 0;
  let omitidos = 0;
  let reintentos = 0;
  let fallidos = 0;
  let erroresConfirmacion = 0;

  async function finalizar(evento: EventoReclamado, parametros: Record<string, unknown>) {
    const { data, error } = await clienteAdmin.rpc('finalizar_evento_aviso_telegram', {
      ...parametros,
      p_id_evento: evento.id_evento,
      p_intento_esperado: evento.intentos,
    });
    if (error || data !== true) {
      erroresConfirmacion++;
      return false;
    }
    return true;
  }

  await Promise.all(lista.map(async (evento) => {
    try {
      if (!evento.chat_id) {
        if (await finalizar(evento, {p_resultado: 'omitido', p_error: 'SIN_VINCULACION_ACTIVA'})) omitidos++;
        return;
      }
      const envio = await enviarAvisoTelegram(botToken, evento.chat_id);
      if (envio.ok) {
        if (await finalizar(evento, {p_resultado: 'enviado'})) enviados++;
      } else if (!envio.permanente && evento.intentos < MAXIMO_INTENTOS) {
        const proximo = envio.reintentarTrasSegundos !== undefined
          ? new Date(Date.now() + envio.reintentarTrasSegundos * 1000).toISOString()
          : calcularProximoIntentoIso(evento.intentos);
        if (await finalizar(evento, {
          p_resultado: 'reintentar', p_error: envio.motivo ?? 'ERROR_TEMPORAL',
          p_reintentar_en: proximo,
        })) reintentos++;
      } else {
        if (await finalizar(evento, {p_resultado: 'fallido', p_error: envio.motivo ?? 'ERROR_PERMANENTE'})) fallidos++;
      }
    } catch {
      // La reserva vence y otro ciclo podrá recuperar este evento; no fingir éxito.
      erroresConfirmacion++;
    }
  }));

  return respuestaJson(erroresConfirmacion ? 500 : 200, {
    erroresConfirmacion,
    procesados: lista.length,
    enviados,
    omitidos,
    reintentos,
    fallidos,
  });
});
