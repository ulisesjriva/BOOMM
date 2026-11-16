import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';

/// Estados posibles al calcular la ruta hacia el consultorio del profesional.
enum EstadoCalculoRuta {
  inicial,
  calculando,
  rutaObtenida,
  sinUbicacionOrigen,
  coordenadasDestinoIncompletas,
  sinRutaDisponible,
  cuentaInactiva,
  tiempoAgotado,
  errorProveedor,
}

/// Resultado tipado del calculo de ruta, distancia y tiempo estimado.
class ResultadoCalculoRuta {
  final EstadoCalculoRuta estado;
  final RutaConsultorio? ruta;
  final String? mensaje;

  const ResultadoCalculoRuta._({required this.estado, this.ruta, this.mensaje});

  const ResultadoCalculoRuta.exito(RutaConsultorio rutaCalculada)
    : this._(estado: EstadoCalculoRuta.rutaObtenida, ruta: rutaCalculada);

  const ResultadoCalculoRuta.fallo(
    EstadoCalculoRuta estadoFallo,
    String mensajeExplicativo,
  ) : this._(estado: estadoFallo, mensaje: mensajeExplicativo);

  bool get fueExitoso =>
      estado == EstadoCalculoRuta.rutaObtenida && ruta != null;
}

typedef InvocadorFuncionRuta = Future<Map<String, dynamic>> Function({
  required double origenLatitud,
  required double origenLongitud,
  required double destinoLatitud,
  required double destinoLongitud,
});

/// Permite simular el contrato nuevo sin romper las pruebas anteriores de auto.
typedef InvocadorRutaPorTransporte = Future<Map<String, dynamic>> Function({
  required double origenLatitud,
  required double origenLongitud,
  required double destinoLatitud,
  required double destinoLongitud,
  required String medioTransporte,
});

/// Servicio encargado de consultar la ruta vial por calles, distancia y tiempo
/// estimado mediante la Edge Function `calcular-ruta` de Supabase (acordada en E05).
/// Nunca inventa distancias, tiempos ni presenta una linea recta como ruta por calles.
class ServicioRutasConsultorio {
  final InvocadorFuncionRuta? invocadorFuncionRuta;
  final InvocadorRutaPorTransporte? invocadorPorTransporte;
  final Duration tiempoLimiteSolicitud;

  const ServicioRutasConsultorio({
    this.invocadorFuncionRuta,
    this.invocadorPorTransporte,
    this.tiempoLimiteSolicitud = const Duration(seconds: 20),
  });

  static const String nombreFuncionEdge = 'calcular-ruta';

  Future<ResultadoCalculoRuta> calcularRuta({
    required double? origenLatitud,
    required double? origenLongitud,
    required double? destinoLatitud,
    required double? destinoLongitud,
    MedioTransporte medioTransporte = MedioTransporte.auto,
  }) async {
    if (destinoLatitud == null || destinoLongitud == null) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.coordenadasDestinoIncompletas,
        'El profesional aún no ha registrado las coordenadas completas de su consultorio.',
      );
    }

    final destino = CoordenadaMapa(
      latitud: destinoLatitud,
      longitud: destinoLongitud,
    );
    if (!destino.esValida) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.coordenadasDestinoIncompletas,
        'Las coordenadas registradas del consultorio no son válidas para calcular una ruta.',
      );
    }

    if (origenLatitud == null || origenLongitud == null) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.sinUbicacionOrigen,
        'Necesitamos tu ubicación actual para calcular la ruta hacia el consultorio.',
      );
    }

    final origen = CoordenadaMapa(
      latitud: origenLatitud,
      longitud: origenLongitud,
    );
    if (!origen.esValida) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.sinUbicacionOrigen,
        'No se pudo obtener una ubicación de origen válida desde tu dispositivo.',
      );
    }

    try {
      final Map<String, dynamic> datosRespuesta;
      if (invocadorPorTransporte != null) {
        datosRespuesta = await invocadorPorTransporte!(
          origenLatitud: origen.latitud,
          origenLongitud: origen.longitud,
          destinoLatitud: destino.latitud,
          destinoLongitud: destino.longitud,
          medioTransporte: medioTransporte.valorApi,
        ).timeout(tiempoLimiteSolicitud);
      } else if (invocadorFuncionRuta != null) {
        if (medioTransporte != MedioTransporte.auto) {
          return const ResultadoCalculoRuta.fallo(
            EstadoCalculoRuta.errorProveedor,
            'Este servicio de rutas necesita actualizarse para calcular recorridos caminando.',
          );
        }
        datosRespuesta = await invocadorFuncionRuta!(
          origenLatitud: origen.latitud,
          origenLongitud: origen.longitud,
          destinoLatitud: destino.latitud,
          destinoLongitud: destino.longitud,
        ).timeout(tiempoLimiteSolicitud);
      } else {
        if (!ConfiguracionSupabase.estaConfigurado) {
          return const ResultadoCalculoRuta.fallo(
            EstadoCalculoRuta.errorProveedor,
            'El servicio para calcular cómo llegar al consultorio no está disponible en este momento.',
          );
        }
        final respuesta = await Supabase.instance.client.functions
            .invoke(
              nombreFuncionEdge,
              body: <String, dynamic>{
                'origenLatitud': origen.latitud,
                'origenLongitud': origen.longitud,
                'destinoLatitud': destino.latitud,
                'destinoLongitud': destino.longitud,
                'medioTransporte': medioTransporte.valorApi,
              },
            )
            .timeout(tiempoLimiteSolicitud);
        if (respuesta.status != 200 || respuesta.data is! Map) {
          final mapaError = respuesta.data is Map
              ? Map<String, dynamic>.from(respuesta.data as Map)
              : const <String, dynamic>{};
          return _mapearRespuestaError(respuesta.status, mapaError);
        }
        datosRespuesta = Map<String, dynamic>.from(respuesta.data as Map);
      }

      if (datosRespuesta.containsKey('codigo') &&
          !datosRespuesta.containsKey('puntosRuta') &&
          !datosRespuesta.containsKey('polilineaCodificada')) {
        return _mapearRespuestaError(422, datosRespuesta);
      }

      final transporteRecibido = datosRespuesta['medioTransporte'];
      // Un servidor anterior devuelve solo auto. Nunca mostrarlo como caminata.
      if ((transporteRecibido != null &&
              transporteRecibido != medioTransporte.valorApi) ||
          (medioTransporte == MedioTransporte.caminando &&
              transporteRecibido != 'caminando')) {
        return const ResultadoCalculoRuta.fallo(
          EstadoCalculoRuta.errorProveedor,
          'No se pudo confirmar el medio de transporte de la ruta. Actualiza el servicio de rutas.',
        );
      }

      final puntosExtraidos = _extraerPuntosPolilineaValida(datosRespuesta);
      final distanciaBruta =
          datosRespuesta['distanciaMetros'] ??
          datosRespuesta['distancia_metros'];
      final duracionBruta =
          datosRespuesta['duracionEstimadaSegundos'] ??
          datosRespuesta['duracion_estimada_segundos'] ??
          datosRespuesta['duracionSegundos'];

      final distanciaMetros = distanciaBruta is num
          ? distanciaBruta.toDouble()
          : double.tryParse(distanciaBruta?.toString() ?? '') ?? 0.0;
      final duracionSegundos = duracionBruta is num
          ? duracionBruta.round()
          : int.tryParse(duracionBruta?.toString() ?? '') ?? 0;

      if (puntosExtraidos.length < 2 ||
          distanciaMetros <= 0 ||
          duracionSegundos <= 0) {
        return const ResultadoCalculoRuta.fallo(
          EstadoCalculoRuta.sinRutaDisponible,
          'No se encontró una ruta vial por calles entre tu ubicación y el consultorio.',
        );
      }

      final ruta = RutaConsultorio(
        origen: origen,
        destino: destino,
        medioTransporte: medioTransporte,
        puntosPolilinea: List<CoordenadaMapa>.unmodifiable(puntosExtraidos),
        distanciaMetros: distanciaMetros,
        duracionEstimadaSegundos: duracionSegundos,
        incluyeTraficoTiempoReal:
            datosRespuesta['incluyeTraficoTiempoReal'] == true,
        proveedor:
            (datosRespuesta['proveedor'] as String?)?.trim() ??
            'openrouteservice',
      );

      if (!ruta.esRutaCalleValida) {
        return const ResultadoCalculoRuta.fallo(
          EstadoCalculoRuta.sinRutaDisponible,
          'No se encontró una ruta vial válida entre tu ubicación y el consultorio.',
        );
      }

      return ResultadoCalculoRuta.exito(ruta);
    } on TimeoutException {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.tiempoAgotado,
        'El cálculo de la ruta tardó demasiado en responder. Inténtalo nuevamente en unos momentos.',
      );
    } on FunctionException catch (error) {
      final detalles = error.details;
      final mapaDetalles = detalles is Map
          ? Map<String, dynamic>.from(detalles)
          : const <String, dynamic>{};
      return _mapearRespuestaError(error.status, mapaDetalles);
    } catch (_) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.errorProveedor,
        'No pudimos calcular la ruta en este momento. Verifica tu conexión e inténtalo nuevamente.',
      );
    }
  }

  /// Extrae y valida todas las coordenadas de la geometria devuelta.
  /// Si algun punto de la geometria es invalido, rechaza la geometria completa.
  List<CoordenadaMapa> _extraerPuntosPolilineaValida(
    Map<String, dynamic> datos,
  ) {
    final listaPuntos = datos['puntosRuta'] ?? datos['puntos_ruta'];
    if (listaPuntos is List) {
      if (listaPuntos.length < 2) {
        return const <CoordenadaMapa>[];
      }
      final resultado = <CoordenadaMapa>[];
      for (final item in listaPuntos) {
        if (item is Map) {
          final coord = CoordenadaMapa.desdeMapa(
            Map<String, dynamic>.from(item),
          );
          if (!coord.esValida) {
            return const <CoordenadaMapa>[];
          }
          resultado.add(coord);
        } else if (item is List && item.length >= 2) {
          // GeoJSON estandar [longitud, latitud]
          final lng = item[0] is num
              ? (item[0] as num).toDouble()
              : double.tryParse(item[0].toString()) ?? double.nan;
          final lat = item[1] is num
              ? (item[1] as num).toDouble()
              : double.tryParse(item[1].toString()) ?? double.nan;
          final coord = CoordenadaMapa(latitud: lat, longitud: lng);
          if (!coord.esValida) {
            return const <CoordenadaMapa>[];
          }
          resultado.add(coord);
        } else {
          return const <CoordenadaMapa>[];
        }
      }
      return resultado;
    }

    final polilinea =
        (datos['polilineaCodificada'] ?? datos['encodedPolyline']) as String?;
    if (polilinea != null && polilinea.trim().isNotEmpty) {
      final decodificados = RutaConsultorio.decodificarPolilinea(
        polilinea.trim(),
      );
      if (decodificados.length >= 2 &&
          decodificados.every((punto) => punto.esValida)) {
        return decodificados;
      }
    }

    return const <CoordenadaMapa>[];
  }

  ResultadoCalculoRuta _mapearRespuestaError(
    int codigoHttp,
    Map<String, dynamic> mapa,
  ) {
    final codigo = (mapa['codigo'] as String?)?.trim().toUpperCase() ?? '';
    final mensajeServidor = _sanearMensajeVisible(
      (mapa['mensaje'] as String?)?.trim(),
    );

    if (codigo == 'CUENTA_INACTIVA' || codigoHttp == 403) {
      return ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.cuentaInactiva,
        mensajeServidor ??
            'Tu cuenta está inactiva y no puede utilizar el cálculo de rutas.',
      );
    }

    if (codigo == 'TIEMPO_AGOTADO' || codigoHttp == 504) {
      return ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.tiempoAgotado,
        mensajeServidor ?? 'El cálculo de la ruta tardó demasiado en responder. Inténtalo nuevamente en unos momentos.',
      );
    }

    if (codigo == 'SIN_RUTA_DISPONIBLE' || codigoHttp == 422) {
      return ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.sinRutaDisponible,
        mensajeServidor ?? 'No se encontró una ruta vial disponible entre tu ubicación y el consultorio.',
      );
    }

    if (codigo == 'COORDENADAS_INVALIDAS' ||
        codigo == 'SOLICITUD_INVALIDA' ||
        codigoHttp == 400) {
      return ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.coordenadasDestinoIncompletas,
        mensajeServidor ?? 'Las coordenadas de ubicación están incompletas o no son válidas para calcular la ruta.',
      );
    }

    if (codigo == 'SERVICIO_NO_DISPONIBLE' ||
        codigo == 'PROVEEDOR_NO_CONFIGURADO' ||
        codigoHttp == 404 ||
        codigoHttp == 503) {
      return const ResultadoCalculoRuta.fallo(
        EstadoCalculoRuta.errorProveedor,
        'El servicio para calcular cómo llegar al consultorio no está disponible en este momento. Inténtalo más tarde.',
      );
    }

    return ResultadoCalculoRuta.fallo(
      EstadoCalculoRuta.errorProveedor,
      mensajeServidor ?? 'No pudimos calcular el recorrido hacia el consultorio en este momento. Inténtalo nuevamente.',
    );
  }

  String? _sanearMensajeVisible(String? mensaje) {
    if (mensaje == null || mensaje.isEmpty) {
      return null;
    }
    final mayusculas = mensaje.toUpperCase();
    if (mayusculas.contains('ORS_API_KEY') ||
        mayusculas.contains('GOOGLE_ROUTES_API_KEY') ||
        mayusculas.contains('EDGE FUNCTION') ||
        mayusculas.contains('CALCULAR-RUTA')) {
      return 'El servicio para calcular cómo llegar al consultorio no está disponible en este momento. Inténtalo más tarde.';
    }
    return mensaje;
  }
}
