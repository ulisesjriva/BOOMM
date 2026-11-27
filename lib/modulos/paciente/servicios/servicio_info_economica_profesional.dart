import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/paciente/modelos/info_economica_profesional.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

typedef EjecutorRpcInfoEconomica = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

class ErrorInfoEconomicaProfesional implements Exception {
  final String mensaje;
  final String? codigo;

  const ErrorInfoEconomicaProfesional(this.mensaje, {this.codigo});

  @override
  String toString() => mensaje;
}

/// Consulta exclusivamente la informacion economica publica de un profesional
/// mediante la RPC `obtener_info_economica_profesional`.
/// No solicita ni procesa QR, rutas privadas de Storage ni datos bancarios.
class ServicioInfoEconomicaProfesional {
  final EjecutorRpcInfoEconomica? ejecutorRpc;
  final String? Function()? lectorUsuarioActualId;

  const ServicioInfoEconomicaProfesional({
    this.ejecutorRpc,
    this.lectorUsuarioActualId,
  });

  String? _obtenerUidActual() {
    if (lectorUsuarioActualId != null) {
      return lectorUsuarioActualId!()?.trim();
    }
    if (!ConfiguracionSupabase.estaConfigurado) {
      return null;
    }
    return Supabase.instance.client.auth.currentUser?.id.trim();
  }

  Future<dynamic> _invocarRpc(
    String nombreFuncion, {
    Map<String, dynamic>? parametros,
  }) async {
    if (ejecutorRpc != null) {
      return ejecutorRpc!(nombreFuncion, parametros: parametros);
    }
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorInfoEconomicaProfesional(
        'No se pudo consultar la información económica en este momento.',
      );
    }
    return Supabase.instance.client.rpc(nombreFuncion, params: parametros);
  }

  Future<InfoEconomicaProfesional> obtenerInfoEconomicaProfesional({
    required String idProfesional,
  }) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.isEmpty) {
      throw const ErrorInfoEconomicaProfesional(
        'Debes iniciar sesión con una cuenta activa para consultar esta información.',
        codigo: '42501',
      );
    }

    final idLimpio = idProfesional.trim();
    if (idLimpio.isEmpty) {
      return const InfoEconomicaProfesional.noDisponible();
    }

    try {
      dynamic respuesta;
      try {
        respuesta = await _invocarRpc(
          'obtener_oferta_adelanto_profesional',
          parametros: <String, dynamic>{'p_id_profesional': idLimpio},
        );
      } on PostgrestException catch (error) {
        if (error.code == 'PGRST202' || error.code == '42883') {
          respuesta = await _invocarRpc(
            'obtener_info_economica_profesional',
            parametros: <String, dynamic>{'p_id_profesional': idLimpio},
          );
        } else {
          rethrow;
        }
      }

      if (respuesta is List) {
        if (respuesta.isEmpty) {
          return const InfoEconomicaProfesional.noDisponible();
        }
        if (respuesta.length == 1 && respuesta.first is Map) {
          return InfoEconomicaProfesional.desdeMapa(
            Map<String, dynamic>.from(respuesta.first as Map),
          );
        }
        throw const ErrorInfoEconomicaProfesional(
          'La información económica recibida tiene un formato inesperado. Inténtalo de nuevo.',
        );
      }

      if (respuesta is Map) {
        return InfoEconomicaProfesional.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }

      throw const ErrorInfoEconomicaProfesional(
        'La información económica recibida tiene un formato inesperado. Inténtalo de nuevo.',
      );
    } on ErrorInfoEconomicaProfesional {
      rethrow;
    } on FormatException {
      throw const ErrorInfoEconomicaProfesional(
        'La información económica recibida no es consistente. Inténtalo de nuevo.',
      );
    } on PostgrestException catch (error) {
      throw ErrorInfoEconomicaProfesional(
        explicarError(error),
        codigo: error.code,
      );
    } catch (_) {
      throw const ErrorInfoEconomicaProfesional(
        'No se pudo cargar la información económica. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  static String explicarError(Object error) {
    if (error is ErrorInfoEconomicaProfesional) {
      return error.mensaje;
    }
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'No tienes permisos activos para consultar esta información económica.';
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'La consulta de información económica aún no está habilitada en el servidor.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto:
            'No se pudo cargar la información económica en este momento.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto:
          'No se pudo cargar la información económica. Inténtalo de nuevo.',
    );
  }
}
