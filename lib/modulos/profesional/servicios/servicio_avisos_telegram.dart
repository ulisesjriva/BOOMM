import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorAvisosTelegram implements Exception {
  final String mensaje;
  const ErrorAvisosTelegram(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Estado actual de la vinculacion opcional de Telegram del profesional.
class EstadoTelegramProfesional {
  final bool conectado;
  final DateTime? conectadoEn;
  final bool tieneCodigoPendiente;
  final DateTime? codigoExpiraEn;

  const EstadoTelegramProfesional({
    required this.conectado,
    this.conectadoEn,
    required this.tieneCodigoPendiente,
    this.codigoExpiraEn,
  });

  factory EstadoTelegramProfesional.desdeMapa(Map<String, dynamic> datos) {
    return EstadoTelegramProfesional(
      conectado: datos['conectado'] as bool? ?? false,
      conectadoEn: _parsearFecha(datos['conectado_en']),
      tieneCodigoPendiente: datos['tiene_codigo_pendiente'] as bool? ?? false,
      codigoExpiraEn: _parsearFecha(datos['codigo_expira_en']),
    );
  }

  static DateTime? _parsearFecha(dynamic valor) {
    if (valor is String && valor.trim().isNotEmpty) {
      return DateTime.tryParse(valor.trim());
    }
    return null;
  }
}

/// Enlace temporal generado por el servidor para iniciar la vinculacion en Telegram.
class EnlaceVinculacionTelegram {
  final String enlaceTelegram;
  final DateTime? expiraEn;

  const EnlaceVinculacionTelegram({
    required this.enlaceTelegram,
    this.expiraEn,
  });
}

class RespuestaEdgeTelegram {
  final int estado;
  final dynamic datos;

  const RespuestaEdgeTelegram({required this.estado, required this.datos});
}

typedef EjecutorRpcTelegram = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

typedef InvocadorEdgeTelegram = Future<RespuestaEdgeTelegram> Function(
  String nombreFuncion,
);

typedef AbridorEnlaceTelegram = Future<bool> Function(Uri enlace);

/// Servicio para gestionar la vinculacion opcional de avisos por Telegram
/// del profesional autenticado. No maneja secretos ni chat_id en Flutter.
class ServicioAvisosTelegram {
  final EjecutorRpcTelegram? ejecutorRpc;
  final InvocadorEdgeTelegram? invocadorEdge;
  final AbridorEnlaceTelegram? abridorEnlace;

  const ServicioAvisosTelegram({
    this.ejecutorRpc,
    this.invocadorEdge,
    this.abridorEnlace,
  });

  static const String nombreFuncionGenerarCodigo = 'generar-codigo-telegram';
  static const Duration tiempoEsperaPeticion = Duration(seconds: 15);

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorAvisosTelegram(
        'Falta la configuración de Supabase para gestionar avisos por Telegram.',
      );
    }
    return Supabase.instance.client;
  }

  Future<dynamic> _invocarRpc(
    String nombreFuncion, {
    Map<String, dynamic>? parametros,
  }) {
    if (ejecutorRpc != null) {
      return ejecutorRpc!(nombreFuncion, parametros: parametros);
    }
    return _cliente.rpc(nombreFuncion, params: parametros);
  }

  /// Consulta el estado de vinculacion de Telegram del profesional actual.
  Future<EstadoTelegramProfesional> obtenerEstado() async {
    try {
      final respuesta = await _invocarRpc('estado_telegram_profesional_propio')
          .timeout(tiempoEsperaPeticion);

      if (respuesta is List && respuesta.isNotEmpty && respuesta.first is Map) {
        return EstadoTelegramProfesional.desdeMapa(
          Map<String, dynamic>.from(respuesta.first as Map),
        );
      }
      return const EstadoTelegramProfesional(
        conectado: false,
        tieneCodigoPendiente: false,
      );
    } on TimeoutException {
      throw const ErrorAvisosTelegram(
        'La consulta de Telegram tardó demasiado. Inténtalo nuevamente.',
      );
    } on PostgrestException catch (error) {
      throw ErrorAvisosTelegram(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto:
              'No se pudo comprobar el estado de Telegram en este momento.',
        ),
      );
    } catch (error) {
      if (error is ErrorAvisosTelegram) rethrow;
      throw const ErrorAvisosTelegram(
        'No se pudo comprobar el estado de Telegram. Revisa tu conexión.',
      );
    }
  }

  /// Solicita a la Edge Function un enlace temporal de un solo uso (10 min).
  Future<EnlaceVinculacionTelegram> generarEnlaceVinculacion() async {
    try {
      final respuesta =
          await (invocadorEdge != null
                  ? invocadorEdge!(nombreFuncionGenerarCodigo)
                  : _invocarEdge(nombreFuncionGenerarCodigo))
              .timeout(tiempoEsperaPeticion);

      if (respuesta.estado != 200) {
        throw ErrorAvisosTelegram(
          _mapearMensajeErrorEdge(respuesta.estado, respuesta.datos),
        );
      }

      final mapa = _normalizarMapa(respuesta.datos);
      final enlace = (mapa?['enlaceTelegram'] as String?)?.trim() ?? '';
      if (!enlace.startsWith('https://t.me/')) {
        throw const ErrorAvisosTelegram(
          'No se recibió un enlace válido para conectar Telegram.',
        );
      }

      final expiraEnRaw = mapa?['expiraEn'] as String?;
      return EnlaceVinculacionTelegram(
        enlaceTelegram: enlace,
        expiraEn: expiraEnRaw != null ? DateTime.tryParse(expiraEnRaw) : null,
      );
    } on TimeoutException {
      throw const ErrorAvisosTelegram(
        'La conexión con el servidor tardó demasiado. Inténtalo nuevamente.',
      );
    } on FunctionException catch (error) {
      throw ErrorAvisosTelegram(
        _mapearMensajeErrorEdge(error.status, error.details),
      );
    } catch (error) {
      if (error is ErrorAvisosTelegram) rethrow;
      throw const ErrorAvisosTelegram(
        'No se pudo generar el enlace de Telegram. Inténtalo nuevamente.',
      );
    }
  }

  /// Abre el enlace https://t.me/... en la app de Telegram o navegador externo.
  Future<void> abrirEnlaceVinculacion(String enlace) async {
    final uri = Uri.tryParse(enlace.trim());
    if (uri == null || !enlace.trim().startsWith('https://t.me/')) {
      throw const ErrorAvisosTelegram(
        'El enlace de Telegram no tiene un formato válido.',
      );
    }

    final abierto = abridorEnlace != null
        ? await abridorEnlace!(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!abierto) {
      throw const ErrorAvisosTelegram(
        'No se pudo abrir Telegram en este dispositivo.',
      );
    }
  }

  /// Elimina la vinculacion de Telegram y anula codigos pendientes del profesional.
  Future<void> desconectar() async {
    try {
      await _invocarRpc('desconectar_telegram_profesional_propio')
          .timeout(tiempoEsperaPeticion);
    } on TimeoutException {
      throw const ErrorAvisosTelegram(
        'La desconexión tardó demasiado. Inténtalo nuevamente.',
      );
    } on PostgrestException catch (error) {
      throw ErrorAvisosTelegram(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo desconectar Telegram en este momento.',
        ),
      );
    } catch (error) {
      if (error is ErrorAvisosTelegram) rethrow;
      throw const ErrorAvisosTelegram(
        'No se pudo desconectar Telegram. Revisa tu conexión.',
      );
    }
  }

  Future<RespuestaEdgeTelegram> _invocarEdge(String nombreFuncion) async {
    final respuesta = await _cliente.functions.invoke(nombreFuncion);
    return RespuestaEdgeTelegram(
      estado: respuesta.status,
      datos: respuesta.data,
    );
  }

  Map<String, dynamic>? _normalizarMapa(dynamic datos) {
    if (datos is Map<String, dynamic>) return datos;
    if (datos is Map) return Map<String, dynamic>.from(datos);
    if (datos is String && datos.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(datos);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _mapearMensajeErrorEdge(int estado, dynamic detalles) {
    final mapa = _normalizarMapa(detalles);
    final mensaje = (mapa?['mensaje'] as String?)?.trim();
    if (mensaje != null && mensaje.isNotEmpty) return mensaje;
    if (estado == 401) {
      return 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.';
    }
    if (estado == 403) {
      return 'Solo los profesionales con cuenta activa pueden conectar Telegram.';
    }
    return 'No se pudo generar el enlace de Telegram en este momento.';
  }

  static String explicarError(Object error) {
    if (error is ErrorAvisosTelegram) return error.mensaje;
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto: 'No se pudo completar la operación de Telegram. Inténtalo nuevamente.',
    );
  }
}
