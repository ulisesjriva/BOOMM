import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';

class DireccionGeoapify {
  final String direccion;
  final double latitud;
  final double longitud;
  const DireccionGeoapify({
    required this.direccion,
    required this.latitud,
    required this.longitud,
  });
}

class ErrorGeoapify implements Exception {
  final String mensaje;
  const ErrorGeoapify(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Ninguna clave de Geoapify se recibe ni se incorpora al cliente Flutter.
class ServicioGeoapify {
  const ServicioGeoapify();

  static SupabaseClient? get clienteActual {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static String get plantillaTeselas =>
      '${ConfiguracionSupabase.url}/functions/v1/geoapify?z={z}&x={x}&y={y}';

  Future<List<DireccionGeoapify>> buscarDireccion(String texto) async {
    final direccion = texto.trim();
    if (direccion.length < 4 || direccion.length > 180) {
      throw const ErrorGeoapify(
        'Escribe una dirección de entre 4 y 180 caracteres.',
      );
    }
    final cliente = clienteActual;
    if (cliente?.auth.currentSession == null) {
      throw const ErrorGeoapify('Inicia sesión para buscar una dirección.');
    }
    try {
      final respuesta = await cliente!.functions
          .invoke('geoapify', body: {'texto': direccion})
          .timeout(const Duration(seconds: 25));
      return interpretarRespuesta(respuesta.data);
    } on FunctionException catch (error) {
      final detalles = error.details;
      final codigo = detalles is Map ? detalles['codigo'] : null;
      throw ErrorGeoapify(mensajeError(error.status, codigo));
    } on ErrorGeoapify {
      rethrow;
    } catch (_) {
      throw const ErrorGeoapify(
        'No se pudo buscar la dirección. Comprueba tu conexión.',
      );
    }
  }

  static List<DireccionGeoapify> interpretarRespuesta(dynamic datos) {
    if (datos is! Map || datos['resultados'] is! List) {
      throw const ErrorGeoapify('No se pudo interpretar la dirección.');
    }
    final resultados = <DireccionGeoapify>[];
    for (final elemento in (datos['resultados'] as List).take(5)) {
      if (elemento is! Map) {
        continue;
      }
      final latitud = elemento['latitud'];
      final longitud = elemento['longitud'];
      final direccion = elemento['direccion'];
      if (latitud is! num ||
          longitud is! num ||
          direccion is! String ||
          direccion.trim().isEmpty ||
          !latitud.isFinite ||
          !longitud.isFinite ||
          latitud < -1.90 ||
          latitud > -1.45 ||
          longitud < -78.85 ||
          longitud > -78.45) {
        continue;
      }
      resultados.add(
        DireccionGeoapify(
          direccion: direccion,
          latitud: latitud.toDouble(),
          longitud: longitud.toDouble(),
        ),
      );
    }
    return resultados;
  }

  static String mensajeError(int estado, [dynamic codigo]) {
    if (estado == 401) {
      return 'Inicia sesión nuevamente para cargar el mapa.';
    }
    if (estado == 403) {
      return 'Tu cuenta no tiene acceso al mapa.';
    }
    if (codigo == 'CUOTA_MAPA') {
      return 'Se alcanzó el límite gratuito del mapa. Inténtalo más tarde.';
    }
    if (estado == 429) {
      return 'Espera unos segundos antes de volver a consultar el mapa.';
    }
    if (estado == 503) {
      return 'El mapa todavía no está disponible. Inténtalo más tarde.';
    }
    return 'No se pudo cargar el mapa. Comprueba tu conexión e inténtalo nuevamente.';
  }
}

class _TeselaGuardada {
  final Uint8List bytes;
  final DateTime guardadaEn = DateTime.now();
  _TeselaGuardada(this.bytes);
}

/// Cache de memoria compartida, acotada a 12 MB/160 teselas y un dia.
/// Serializa inicios a 8 solicitudes/segundo y evita duplicar peticiones activas.
/// Reintenta una sola vez los fallos transitorios; no repite cuotas ni permisos.
/// Los tokens se envian en cabeceras, nunca en URLs.
class ClienteTeselasGeoapify extends http.BaseClient {
  ClienteTeselasGeoapify();
  static final _transporte = http.Client();
  static final _cache = <String, _TeselaGuardada>{};
  final _pendientes = <String, Future<Uint8List>>{};
  static Future<void> _turno = Future<void>.value();
  final aviso = ValueNotifier<String?>(null);
  bool _cerrado = false;
  static int _bytesGuardados = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final identificador = request.url.toString();
    final guardada = _cache[identificador];
    if (guardada != null &&
        DateTime.now().difference(guardada.guardadaEn) <
            const Duration(days: 1)) {
      return http.StreamedResponse(
        Stream.value(guardada.bytes),
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    final pendiente = _pendientes[identificador];
    final Future<Uint8List> carga;
    if (pendiente != null) {
      carga = pendiente;
    } else {
      carga = _cargar(request.url);
      _pendientes[identificador] = carga;
    }
    try {
      final bytes = await carga;
      if (!_cerrado) {
        aviso.value = null;
      }
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        headers: {'content-type': 'image/png'},
      );
    } catch (error) {
      if (!_cerrado) {
        aviso.value = error is ErrorGeoapify
            ? error.mensaje
            : ServicioGeoapify.mensajeError(0);
      }
      rethrow;
    } finally {
      if (identical(_pendientes[identificador], carga)) {
        _pendientes.remove(identificador);
      }
    }
  }

  Future<Uint8List> _cargar(Uri direccion) async {
    final cliente = ServicioGeoapify.clienteActual;
    final token = cliente?.auth.currentSession?.accessToken;
    if (token == null) {
      throw const ErrorGeoapify('Inicia sesión para cargar el mapa.');
    }
    try {
      // Solo nuestro endpoint: nunca reenviar la sesion a un proveedor externo.
      final base = Uri.parse(ConfiguracionSupabase.url);
      if (direccion.origin != base.origin ||
          direccion.path != '/functions/v1/geoapify') {
        throw const ErrorGeoapify('La dirección del mapa no es válida.');
      }
      final respuesta = await _consultarImagen(direccion, token);
      if (respuesta.statusCode != 200) {
        // No mostrar respuestas tecnicas ni URLs que puedan contener credenciales.
        dynamic codigo;
        try {
          final cuerpo = jsonDecode(respuesta.body);
          if (cuerpo is Map) {
            codigo = cuerpo['codigo'];
          }
        } catch (_) {
          /* No mostrar cuerpos de errores externos. */
        }
        throw ErrorGeoapify(
          ServicioGeoapify.mensajeError(respuesta.statusCode, codigo),
        );
      }
      final bytes = respuesta.bodyBytes;
      if (bytes.length > 1024 * 1024 ||
          bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        throw const ErrorGeoapify('No se pudo cargar el mapa.');
      }
      final clave = direccion.toString();
      final antigua = _cache.remove(clave);
      if (antigua != null) {
        _bytesGuardados -= antigua.bytes.length;
      }
      _cache[clave] = _TeselaGuardada(bytes);
      _bytesGuardados += bytes.length;
      while (_cache.length > 160 || _bytesGuardados > 12 * 1024 * 1024) {
        _bytesGuardados -= _cache.remove(_cache.keys.first)!.bytes.length;
      }
      return bytes;
    } catch (error) {
      final mensaje = error is ErrorGeoapify
          ? error.mensaje
          : ServicioGeoapify.mensajeError(0);
      throw ErrorGeoapify(mensaje);
    }
  }

  Future<http.Response> _consultarImagen(Uri direccion, String token) async {
    for (var intento = 0; intento < 2; intento++) {
      if (_cerrado) {
        throw const ErrorGeoapify('La vista del mapa se cerró.');
      }
      final turnoAnterior = _turno;
      _turno = turnoAnterior.then(
        (_) => Future<void>.delayed(const Duration(milliseconds: 125)),
      );
      await turnoAnterior;
      if (_cerrado) {
        throw const ErrorGeoapify('La vista del mapa se cerró.');
      }
      try {
        final respuesta = await _transporte
            .get(
              direccion,
              headers: {
                'Authorization': 'Bearer $token',
                'apikey': ConfiguracionSupabase.claveAnon,
              },
            )
            .timeout(const Duration(seconds: 30));
        // Cada reintento vuelve a pasar por la reserva de presupuesto del servidor.
        // No repetir rechazos de sesion, permisos ni cuotas.
        if (![502, 503, 504].contains(respuesta.statusCode) || intento == 1) {
          return respuesta;
        }
      } catch (_) {
        if (intento == 1) {
          rethrow;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const ErrorGeoapify('No se pudo cargar el mapa.');
  }

  // El transporte y la cache pertenecen a la app; los avisos a esta vista.
  @override
  void close() {
    if (_cerrado) {
      return;
    }
    _cerrado = true;
    aviso.dispose();
  }
}
