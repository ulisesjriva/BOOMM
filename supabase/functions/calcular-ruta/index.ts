// Supabase Edge Function: calcular-ruta
// Calcula la ruta vial por calles, la distancia en metros y el tiempo estimado
// en segundos entre la ubicacion del paciente y el consultorio del profesional.
// Mantiene la clave del proveedor vial en el servidor, sin exponer secretos en Flutter.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const TIEMPO_LIMITE_PROVEEDOR_MS = 8000;

export type ProveedorRutas = 'openrouteservice' | 'google_routes';

export interface Coordenada {
  latitud: number;
  longitud: number;
}

function respuestaJson(
  estadoHttp: number,
  cuerpo: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estadoHttp,
    headers: { ...cabecerasCors, 'Content-Type': 'application/json' },
  });
}

export function esLatitudValida(valor: unknown): valor is number {
  return (
    typeof valor === 'number' &&
    Number.isFinite(valor) &&
    valor >= -90 &&
    valor <= 90
  );
}

export function esLongitudValida(valor: unknown): valor is number {
  return (
    typeof valor === 'number' &&
    Number.isFinite(valor) &&
    valor >= -180 &&
    valor <= 180
  );
}

export function esCoordenadaValida(punto: Coordenada): boolean {
  return (
    esLatitudValida(punto.latitud) &&
    esLongitudValida(punto.longitud) &&
    !(punto.latitud === 0 && punto.longitud === 0)
  );
}

export function extraerGeometriaValidaGeoJson(
  coordenadasGeoJson: unknown,
): Coordenada[] | null {
  if (!Array.isArray(coordenadasGeoJson) || coordenadasGeoJson.length < 2) {
    return null;
  }

  const puntos: Coordenada[] = [];
  for (const par of coordenadasGeoJson) {
    if (!Array.isArray(par) || par.length < 2) {
      return null;
    }
    const longitud = Number(par[0]);
    const latitud = Number(par[1]);
    const coordenada: Coordenada = { latitud, longitud };
    if (!esCoordenadaValida(coordenada)) {
      return null;
    }
    puntos.push(coordenada);
  }

  return puntos.length >= 2 ? puntos : null;
}

export function decodificarPolilineaCodificada(
  codificada: string,
): Coordenada[] | null {
  if (typeof codificada !== 'string' || codificada.trim().length === 0) {
    return null;
  }

  const puntos: Coordenada[] = [];
  let indice = 0;
  let lat = 0;
  let lng = 0;

  while (indice < codificada.length) {
    let b = 0;
    let desplazamiento = 0;
    let resultado = 0;
    do {
      if (indice >= codificada.length) {
        return null;
      }
      b = codificada.charCodeAt(indice++) - 63;
      resultado |= (b & 0x1f) << desplazamiento;
      desplazamiento += 5;
    } while (b >= 0x20);
    const deltaLat = (resultado & 1) !== 0 ? ~(resultado >> 1) : resultado >> 1;
    lat += deltaLat;

    desplazamiento = 0;
    resultado = 0;
    do {
      if (indice >= codificada.length) {
        return null;
      }
      b = codificada.charCodeAt(indice++) - 63;
      resultado |= (b & 0x1f) << desplazamiento;
      desplazamiento += 5;
    } while (b >= 0x20);
    const deltaLng = (resultado & 1) !== 0 ? ~(resultado >> 1) : resultado >> 1;
    lng += deltaLng;

    const coordenada: Coordenada = {
      latitud: lat / 1e5,
      longitud: lng / 1e5,
    };
    if (!esCoordenadaValida(coordenada)) {
      return null;
    }
    puntos.push(coordenada);
  }

  return puntos.length >= 2 ? puntos : null;
}

/**
 * Selecciona de forma explicita un unico proveedor configurado.
 * OpenRouteService es el proveedor acordado por defecto y no se exige configurar
 * un segundo proveedor. Solo se utiliza Google Routes si se selecciona
 * explicitamente mediante PROVEEDOR_RUTAS='google_routes' (o si es el unico configurado).
 */
export function seleccionarProveedorConfigurado(entorno: {
  proveedorExplicito?: string;
  claveOrs?: string;
  claveGoogleRoutes?: string;
}): { proveedor: ProveedorRutas; claveApi: string } | null {
  const seleccion = entorno.proveedorExplicito?.trim().toLowerCase() ?? '';
  const claveOrs = entorno.claveOrs?.trim() ?? '';
  const claveGoogle = entorno.claveGoogleRoutes?.trim() ?? '';

  if (seleccion === 'openrouteservice') {
    return claveOrs.length > 0
      ? { proveedor: 'openrouteservice', claveApi: claveOrs }
      : null;
  }

  if (seleccion === 'google_routes') {
    return claveGoogle.length > 0
      ? { proveedor: 'google_routes', claveApi: claveGoogle }
      : null;
  }

  if (claveOrs.length > 0) {
    return { proveedor: 'openrouteservice', claveApi: claveOrs };
  }

  if (claveGoogle.length > 0) {
    return { proveedor: 'google_routes', claveApi: claveGoogle };
  }

  return null;
}

async function consultarConTiempoLimite(
  url: string,
  opciones: RequestInit,
  tiempoLimiteMs = TIEMPO_LIMITE_PROVEEDOR_MS,
): Promise<Response> {
  const controlador = new AbortController();
  const identificadorTemporizador = setTimeout(
    () => controlador.abort(),
    tiempoLimiteMs,
  );

  try {
    const respuesta = await fetch(url, {
      ...opciones,
      signal: controlador.signal,
    });
    // Mantener el plazo hasta terminar de recibir el cuerpo, no solo las cabeceras.
    const cuerpo = await respuesta.arrayBuffer();
    return new Response(
      [204, 205, 304].includes(respuesta.status) ? null : cuerpo,
      {
        status: respuesta.status,
        statusText: respuesta.statusText,
        headers: respuesta.headers,
      },
    );
  } finally {
    clearTimeout(identificadorTemporizador);
  }
}

function esErrorTiempoAgotado(error: unknown): boolean {
  if (!error || typeof error !== 'object') {
    return false;
  }
  const nombre = (error as { name?: unknown }).name;
  return nombre === 'AbortError' || nombre === 'TimeoutError';
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cabecerasCors });
  }

  if (req.method !== 'POST') {
    return respuestaJson(405, {
      codigo: 'METODO_NO_PERMITIDO',
      mensaje: 'Esta operación no está permitida.',
    });
  }

  try {
    // 1. Verificar sesion autenticada en Supabase
    const encabezadoAuth = req.headers.get('Authorization');
    const urlSupabase = Deno.env.get('SUPABASE_URL') ?? '';
    const claveAnon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

    if (!encabezadoAuth || !urlSupabase || !claveAnon) {
      return respuestaJson(401, {
        codigo: 'NO_AUTORIZADO',
        mensaje:
          'Debes iniciar sesión para calcular cómo llegar al consultorio.',
      });
    }

    const clienteSupabase = createClient(urlSupabase, claveAnon, {
      global: { headers: { Authorization: encabezadoAuth } },
    });
    const {
      data: { user },
      error: errorUsuario,
    } = await clienteSupabase.auth.getUser();

    if (errorUsuario || !user) {
      return respuestaJson(401, {
        codigo: 'NO_AUTORIZADO',
        mensaje: 'Tu sesión no es válida. Inicia sesión nuevamente.',
      });
    }

    // 2. Comprobar mediante el contrato existente de perfil que la cuenta esta activa
    const { data: filasPerfil, error: errorPerfil } =
      await clienteSupabase.rpc('perfil_del_usuario_actual');

    const perfilActual = Array.isArray(filasPerfil)
      ? filasPerfil[0]
      : filasPerfil;

    if (
      errorPerfil ||
      !perfilActual ||
      typeof perfilActual !== 'object' ||
      typeof (perfilActual as { cuenta_activa?: unknown }).cuenta_activa !== 'boolean'
    ) {
      return respuestaJson(503, {
        codigo: 'SERVICIO_NO_DISPONIBLE',
        mensaje: 'No pudimos comprobar el estado de tu cuenta. Inténtalo nuevamente.',
      });
    }

    if ((perfilActual as { cuenta_activa: boolean }).cuenta_activa === false) {
      return respuestaJson(403, {
        codigo: 'CUENTA_INACTIVA',
        mensaje:
          'Tu cuenta está inactiva y no puede utilizar el cálculo de rutas.',
      });
    }

    // 3. Leer y validar el JSON de entrada como error de solicitud si es invalido
    let cuerpo: Record<string, unknown>;
    try {
      const jsonRecibido = await req.json();
      if (
        typeof jsonRecibido !== 'object' ||
        jsonRecibido === null ||
        Array.isArray(jsonRecibido)
      ) {
        return respuestaJson(400, {
          codigo: 'SOLICITUD_INVALIDA',
          mensaje:
            'Los datos enviados para calcular la ruta no tienen un formato válido.',
        });
      }
      cuerpo = jsonRecibido as Record<string, unknown>;
    } catch (_) {
      return respuestaJson(400, {
        codigo: 'SOLICITUD_INVALIDA',
        mensaje: 'Los datos enviados para calcular la ruta no son válidos.',
      });
    }

    // 4. Validar coordenadas de origen y destino
    const origenLatitud = cuerpo.origenLatitud;
    const origenLongitud = cuerpo.origenLongitud;
    const destinoLatitud = cuerpo.destinoLatitud;
    const destinoLongitud = cuerpo.destinoLongitud;

    if (
      !esLatitudValida(origenLatitud) ||
      !esLongitudValida(origenLongitud) ||
      !esLatitudValida(destinoLatitud) ||
      !esLongitudValida(destinoLongitud) ||
      (origenLatitud === 0 && origenLongitud === 0) ||
      (destinoLatitud === 0 && destinoLongitud === 0)
    ) {
      return respuestaJson(400, {
        codigo: 'COORDENADAS_INVALIDAS',
        mensaje:
          'Las coordenadas de origen o del consultorio están incompletas o fuera de rango.',
      });
    }

    // Solo perfiles admitidos: no aceptar endpoints o valores arbitrarios.
    const medioTransporte = cuerpo.medioTransporte === undefined ? 'auto' : cuerpo.medioTransporte;
    if (medioTransporte !== 'auto' && medioTransporte !== 'caminando') {
      return respuestaJson(400, { codigo: 'TRANSPORTE_INVALIDO',
        mensaje: 'Selecciona En auto o Caminando para calcular la ruta.' });
    }
    const perfilOrs = medioTransporte === 'auto' ? 'driving-car' : 'foot-walking';

    // 5. Seleccion explicita del proveedor de rutas configurado en el servidor
    const proveedorSeleccionado = seleccionarProveedorConfigurado({
      proveedorExplicito: Deno.env.get('PROVEEDOR_RUTAS'),
      claveOrs: Deno.env.get('ORS_API_KEY'),
      claveGoogleRoutes: Deno.env.get('GOOGLE_ROUTES_API_KEY'),
    });

    if (!proveedorSeleccionado) {
      return respuestaJson(503, {
        codigo: 'SERVICIO_NO_DISPONIBLE',
        mensaje:
          'El servicio para calcular cómo llegar al consultorio no está disponible en este momento. Inténtalo más tarde.',
      });
    }

    // 6A. Proveedor primario acordado: OpenRouteService API
    if (proveedorSeleccionado.proveedor === 'openrouteservice') {
      let respuestaOrs: Response;
      try {
        respuestaOrs = await consultarConTiempoLimite(
          `https://api.heigit.org/openrouteservice/v2/directions/${perfilOrs}/geojson`,
          {
            method: 'POST',
            headers: {
              Authorization: proveedorSeleccionado.claveApi,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              coordinates: [
                [origenLongitud, origenLatitud],
                [destinoLongitud, destinoLatitud],
              ],
            }),
          },
        );
      } catch (errorRed) {
        if (esErrorTiempoAgotado(errorRed)) {
          return respuestaJson(504, {
            codigo: 'TIEMPO_AGOTADO',
            mensaje:
              'El cálculo de la ruta tardó demasiado en responder. Inténtalo nuevamente en unos momentos.',
          });
        }
        return respuestaJson(502, {
          codigo: 'ERROR_PROVEEDOR',
          mensaje:
            'No pudimos comunicarnos con el servicio de rutas en este momento. Inténtalo nuevamente.',
        });
      }

      if (!respuestaOrs.ok) {
        if (respuestaOrs.status === 404) {
          return respuestaJson(422, {
            codigo: 'SIN_RUTA_DISPONIBLE',
            mensaje:
              'No se encontró una ruta vial por calles entre tu ubicación y el consultorio.',
          });
        }
        return respuestaJson(502, {
          codigo: 'ERROR_PROVEEDOR',
          mensaje:
            'No se pudo calcular el recorrido hacia el consultorio en este momento. Inténtalo nuevamente.',
        });
      }

      const datosOrs = await respuestaOrs.json();
      const caracteristica = datosOrs?.features?.[0];
      const coordenadasGeoJson = caracteristica?.geometry?.coordinates;
      const segmento = caracteristica?.properties?.summary;

      const distanciaMetros = Number(segmento?.distance ?? 0);
      const duracionEstimadaSegundos = Math.round(
        Number(segmento?.duration ?? 0),
      );
      const puntosRuta = extraerGeometriaValidaGeoJson(coordenadasGeoJson);

      if (
        !puntosRuta ||
        !Number.isFinite(distanciaMetros) ||
        distanciaMetros <= 0 ||
        !Number.isFinite(duracionEstimadaSegundos) ||
        duracionEstimadaSegundos <= 0
      ) {
        return respuestaJson(422, {
          codigo: 'SIN_RUTA_DISPONIBLE',
          mensaje:
            'No se encontró una ruta vial válida entre tu ubicación y el consultorio.',
        });
      }

      return respuestaJson(200, {
        puntosRuta,
        distanciaMetros,
        duracionEstimadaSegundos,
        incluyeTraficoTiempoReal: false,
        proveedor: 'openrouteservice',
        medioTransporte,
      });
    }

    // 6B. Proveedor opcional alternativo (solo cuando se selecciona explicitamente google_routes)
    let respuestaGoogle: Response;
    try {
      respuestaGoogle = await consultarConTiempoLimite(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': proveedorSeleccionado.claveApi,
            'X-Goog-FieldMask':
              'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
          },
          body: JSON.stringify({
            origin: {
              location: {
                latLng: { latitude: origenLatitud, longitude: origenLongitud },
              },
            },
            destination: {
              location: {
                latLng: {
                  latitude: destinoLatitud,
                  longitude: destinoLongitud,
                },
              },
            },
            travelMode: medioTransporte === 'auto' ? 'DRIVE' : 'WALK',
            ...(medioTransporte === 'auto' ? { routingPreference: 'TRAFFIC_UNAWARE' } : {}),
          }),
        },
      );
    } catch (errorRed) {
      if (esErrorTiempoAgotado(errorRed)) {
        return respuestaJson(504, {
          codigo: 'TIEMPO_AGOTADO',
          mensaje:
            'El cálculo de la ruta tardó demasiado en responder. Inténtalo nuevamente en unos momentos.',
        });
      }
      return respuestaJson(502, {
        codigo: 'ERROR_PROVEEDOR',
        mensaje:
          'No pudimos comunicarnos con el servicio de rutas en este momento. Inténtalo nuevamente.',
      });
    }

    if (!respuestaGoogle.ok) {
      return respuestaJson(502, {
        codigo: 'ERROR_PROVEEDOR',
        mensaje:
          'No se pudo calcular el recorrido hacia el consultorio en este momento. Inténtalo nuevamente.',
      });
    }

    const datosGoogle = await respuestaGoogle.json();
    const rutaGoogle = datosGoogle?.routes?.[0];
    const polilineaCodificada =
      rutaGoogle?.polyline?.encodedPolyline as string | undefined;
    const distanciaMetros = Number(rutaGoogle?.distanceMeters ?? 0);
    const duracionTexto = String(rutaGoogle?.duration ?? '0s').replace('s', '');
    const duracionEstimadaSegundos = Math.round(Number(duracionTexto));

    const puntosRuta = polilineaCodificada
      ? decodificarPolilineaCodificada(polilineaCodificada)
      : null;

    if (
      !puntosRuta ||
      !Number.isFinite(distanciaMetros) ||
      distanciaMetros <= 0 ||
      !Number.isFinite(duracionEstimadaSegundos) ||
      duracionEstimadaSegundos <= 0
    ) {
      return respuestaJson(422, {
        codigo: 'SIN_RUTA_DISPONIBLE',
        mensaje:
          'No se encontró una ruta vial disponible entre tu ubicación y el consultorio.',
      });
    }

    return respuestaJson(200, {
      puntosRuta,
      distanciaMetros,
      duracionEstimadaSegundos,
      incluyeTraficoTiempoReal: false,
      proveedor: 'google_routes',
      medioTransporte,
    });
  } catch (_) {
    return respuestaJson(500, {
      codigo: 'ERROR_INTERNO',
      mensaje:
        'No se pudo procesar el cálculo de la ruta hacia el consultorio en este momento.',
    });
  }
});
