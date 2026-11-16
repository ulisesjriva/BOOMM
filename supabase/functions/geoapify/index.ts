import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Expose-Headers': 'Retry-After',
};
function respuestaJson(estado: number, codigo: string, mensaje: string) {
  return new Response(JSON.stringify({ codigo, mensaje }), {
    status: estado,
    headers: { ...cabecerasCors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
      ...(estado === 429 ? { 'Retry-After': '5' } : {}) },
  });
}
// Sin URL, estilo, pais ni formato arbitrarios aportados por el cliente.
function entero(valor: string | null): number | null {
  return valor !== null && /^\d{1,8}$/.test(valor) ? Number(valor) : null;
}

Deno.serve(async (peticion: Request) => {
  if (peticion.method === 'OPTIONS') return new Response('ok', { headers: cabecerasCors });
  if (!['GET','POST'].includes(peticion.method)) return respuestaJson(405,'METODO','Método no permitido.');
  const urlSupabase = Deno.env.get('SUPABASE_URL');
  const claveServidor = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const claveGeoapify = Deno.env.get('GEOAPIFY_API_KEY');
  if (!urlSupabase || !claveServidor || !claveGeoapify) return respuestaJson(503,'CONFIGURACION','El mapa todavía no está disponible.');
  const autorizacion = peticion.headers.get('Authorization') ?? '';
  if (!/^Bearer \S+$/.test(autorizacion)) return respuestaJson(401,'SESION','Inicia sesión nuevamente.');
  try {
    const servidor = createClient(urlSupabase, claveServidor, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch: (entrada, opciones) => fetch(entrada, { ...opciones, signal: AbortSignal.timeout(10000) }) },
    });
    const { data: sesion, error: errorSesion } = await servidor.auth.getUser(autorizacion.slice(7));
    if (errorSesion || !sesion.user) return respuestaJson(401,'SESION','Inicia sesión nuevamente.');
    let destino: URL;
    let operacion: string;
    if (peticion.method === 'GET') {
      const parametros = new URL(peticion.url).searchParams;
      const nivel = entero(parametros.get('z'));
      const columna = entero(parametros.get('x'));
      const fila = entero(parametros.get('y'));
      if (nivel === null || nivel < 0 || nivel > 19 || columna === null || fila === null ||
          columna >= 2 ** nivel || fila >= 2 ** nivel) {
        return respuestaJson(400,'COORDENADAS','Coordenadas del mapa no válidas.');
      }
      destino = new URL(`https://maps.geoapify.com/v1/tile/osm-carto/${nivel}/${columna}/${fila}.png`);
      operacion = 'tesela';
    } else {
      if (Number(peticion.headers.get('Content-Length') ?? 0) > 2048) return respuestaJson(413,'TAMANO','La dirección es demasiado larga.');
      const textoCuerpo = await peticion.text();
      if (textoCuerpo.length > 2048) return respuestaJson(413,'TAMANO','La dirección es demasiado larga.');
      let cuerpo;
      try { cuerpo = JSON.parse(textoCuerpo); } catch { return respuestaJson(400,'DIRECCION','Escribe una dirección válida.'); }
      const texto = typeof cuerpo?.texto === 'string' ? cuerpo.texto.trim() : '';
      if (texto.length < 4 || texto.length > 180) return respuestaJson(400,'DIRECCION','Escribe una dirección de entre 4 y 180 caracteres.');
      destino = new URL('https://api.geoapify.com/v1/geocode/search');
      destino.searchParams.set('text', texto);
      destino.searchParams.set('filter','countrycode:ec|rect:-78.85,-1.90,-78.45,-1.45');
      destino.searchParams.set('bias','proximity:-78.64712,-1.67098');
      destino.searchParams.set('format','json');
      destino.searchParams.set('lang','es');
      destino.searchParams.set('limit','5');
      operacion = 'buscar';
    }
    const { data: reserva, error: errorReserva } = await servidor.rpc('reservar_consumo_geoapify', {
      p_id_usuario: sesion.user.id, p_operacion: operacion,
    });
    if (errorReserva) return respuestaJson(503,'LIMITE_NO_DISPONIBLE','El mapa todavía no está disponible.');
    if (reserva === 'cuenta_no_activa') return respuestaJson(403,'CUENTA','Tu cuenta no tiene acceso al mapa.');
    if (reserva !== 'ok') return respuestaJson(429, reserva === 'cuota_global' ? 'CUOTA_MAPA' : 'ESPERA',
      reserva === 'cuota_global' ? 'Se alcanzó el límite gratuito del mapa. Inténtalo más tarde.' : 'Espera unos segundos antes de volver a consultar el mapa.');
    destino.searchParams.set('apiKey', claveGeoapify);
    const respuesta = await fetch(destino, { signal: AbortSignal.timeout(18000), redirect: 'error' });
    if (!respuesta.ok) return respuestaJson(respuesta.status === 429 ? 429 : 502,'PROVEEDOR','No se pudo cargar el mapa o la dirección. Inténtalo más tarde.');
    if (operacion === 'tesela') {
      if (!(respuesta.headers.get('Content-Type') ?? '').startsWith('image/png')) return respuestaJson(502,'FORMATO','No se pudo cargar el mapa.');
      return new Response(await respuesta.arrayBuffer(), { headers: {
        ...cabecerasCors, 'Content-Type':'image/png', 'Cache-Control':'private, max-age=86400',
      } });
    }
    const contenido = await respuesta.json();
    if (!Array.isArray(contenido.results)) return respuestaJson(502,'FORMATO','No se pudo consultar la dirección.');
    const resultados = contenido.results.filter((lugar: Record<string,unknown>) =>
      typeof lugar.lat === 'number' && typeof lugar.lon === 'number' &&
      Number.isFinite(lugar.lat) && Number.isFinite(lugar.lon) &&
      lugar.lat >= -1.90 && lugar.lat <= -1.45 && lugar.lon >= -78.85 && lugar.lon <= -78.45
    ).slice(0,5).map((lugar: Record<string,unknown>) => ({
      direccion: String(lugar.formatted ?? '').slice(0,300), latitud: lugar.lat, longitud: lugar.lon,
    }));
    return new Response(JSON.stringify({ resultados }), { headers: {
      ...cabecerasCors, 'Content-Type':'application/json', 'Cache-Control':'no-store',
    } });
  } catch {
    // No registrar URLs del proveedor, tokens ni direcciones de los usuarios.
    return respuestaJson(502,'CONEXION','No se pudo conectar con el mapa. Comprueba tu conexión e inténtalo nuevamente.');
  }
});
