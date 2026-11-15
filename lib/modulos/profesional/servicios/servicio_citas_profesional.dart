import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/cita_profesional.dart';

typedef EjecutorRpcCitasProfesional = Future<dynamic> Function(
  String nombreFuncion, [
  Map<String, dynamic>? parametros,
]);
typedef LectorUsuarioActualIdCitasProfesional = String? Function();
typedef ProveedorAhoraUtcCitasProfesional = DateTime Function();

class ErrorCitasProfesional implements Exception {
  const ErrorCitasProfesional(
    this.mensaje, {
    this.codigo,
    this.esSolicitudYaRespondida = false,
  });

  final String mensaje;
  final String? codigo;
  final bool esSolicitudYaRespondida;

  @override
  String toString() => mensaje;
}

class ServicioCitasProfesional {
  const ServicioCitasProfesional({
    this.cliente,
    this.ejecutorRpc,
    this.lectorUsuarioActualId,
    this.proveedorAhoraUtc,
  });

  final SupabaseClient? cliente;
  final EjecutorRpcCitasProfesional? ejecutorRpc;
  final LectorUsuarioActualIdCitasProfesional? lectorUsuarioActualId;
  final ProveedorAhoraUtcCitasProfesional? proveedorAhoraUtc;

  SupabaseClient get _supabase => cliente ?? Supabase.instance.client;

  DateTime obtenerAhoraUtc() {
    if (proveedorAhoraUtc != null) {
      return proveedorAhoraUtc!().toUtc();
    }
    return DateTime.now().toUtc();
  }

  String _obtenerIdUsuarioActualExigido() {
    if (lectorUsuarioActualId != null) {
      final idInyectado = lectorUsuarioActualId!()?.trim();
      if (idInyectado != null && idInyectado.isNotEmpty) {
        return idInyectado;
      }
      throw const ErrorCitasProfesional(
        'Debes iniciar sesión como profesional para gestionar tus solicitudes de citas.',
        codigo: '42501',
      );
    }
    final idSesion = _supabase.auth.currentUser?.id.trim();
    if (idSesion == null || idSesion.isEmpty) {
      throw const ErrorCitasProfesional(
        'Debes iniciar sesión como profesional para gestionar tus solicitudes de citas.',
        codigo: '42501',
      );
    }
    return idSesion;
  }

  Future<dynamic> _invocarRpc(
    String nombreFuncion, [
    Map<String, dynamic>? parametros,
  ]) async {
    try {
      if (ejecutorRpc != null) {
        return await ejecutorRpc!(nombreFuncion, parametros);
      }
      return await _supabase.rpc(nombreFuncion, params: parametros);
    } on ErrorCitasProfesional {
      rethrow;
    } on PostgrestException catch (error) {
      throw _traducirErrorPostgrest(error);
    } catch (error) {
      final texto = error.toString().toLowerCase();
      if (texto.contains('socketexception') ||
          texto.contains('failed host lookup') ||
          texto.contains('network')) {
        throw const ErrorCitasProfesional(
          'No se pudo conectar con el servidor. Revisa tu conexión a internet e inténtalo de nuevo.',
        );
      }
      throw const ErrorCitasProfesional(
        'No se pudo procesar la operación sobre las solicitudes de citas. Inténtalo nuevamente.',
      );
    }
  }

  ErrorCitasProfesional _traducirErrorPostgrest(PostgrestException error) {
    final codigo = (error.code ?? '').trim();
    final mensajeOriginal = error.message.trim();
    final mensajeMinusculas = mensajeOriginal.toLowerCase();

    if (codigo == 'PGRST202' ||
        codigo == '42883' ||
        mensajeMinusculas.contains('could not find the function')) {
      return ErrorCitasProfesional(
        'El servidor aún no tiene configuradas las funciones de gestión de citas del profesional (migración 10_respuesta_citas_profesional.sql pendiente). No se guardaron cambios.',
        codigo: codigo.isEmpty ? 'PGRST202' : codigo,
      );
    }

    if (codigo == '23P01' ||
        mensajeMinusculas.contains('ya fue respondida') ||
        mensajeMinusculas.contains('estado pendiente')) {
      return ErrorCitasProfesional(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'Esta solicitud ya fue respondida anteriormente y su estado no puede modificarse.',
        codigo: '23P01',
        esSolicitudYaRespondida: true,
      );
    }

    if (codigo == '42501') {
      return ErrorCitasProfesional(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'No tienes permisos activos de profesional aprobado para realizar esta operación.',
        codigo: codigo,
      );
    }

    if (codigo == '22023' || codigo == '23514' || codigo == 'P0002') {
      return ErrorCitasProfesional(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'La solicitud no puede responderse porque ya inició o no cumple las condiciones requeridas.',
        codigo: codigo,
      );
    }

    return ErrorCitasProfesional(
      mensajeOriginal.isNotEmpty
          ? mensajeOriginal
          : 'No se pudo completar la operación en la solicitud de cita.',
      codigo: codigo.isEmpty ? null : codigo,
    );
  }

  List<CitaProfesional> _ordenarCitas(List<CitaProfesional> citas) {
    final copia = List<CitaProfesional>.from(citas);
    copia.sort((a, b) {
      final comparacionFecha = a.fechaIso.compareTo(b.fechaIso);
      if (comparacionFecha != 0) {
        return comparacionFecha;
      }
      return a.minutosInicio.compareTo(b.minutosInicio);
    });
    return copia;
  }

  Future<List<CitaProfesional>> listarCitasPropias() async {
    _obtenerIdUsuarioActualExigido();
    final respuesta = await _invocarRpc('listar_citas_profesional_propias');
    if (respuesta is! List) {
      return const <CitaProfesional>[];
    }

    final citas = respuesta
        .whereType<Map>()
        .map(
          (fila) => CitaProfesional.desdeMapa(Map<String, dynamic>.from(fila)),
        )
        .where((cita) => cita.idCita.isNotEmpty)
        .toList();

    return _ordenarCitas(citas);
  }

  Future<CitaProfesional> responderSolicitudCita({
    required String idCita,
    required String decision,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final idCitaLimpio = idCita.trim();
    if (idCitaLimpio.isEmpty) {
      throw const ErrorCitasProfesional(
        'Debes indicar la solicitud de cita que deseas responder.',
        codigo: '22023',
      );
    }

    final decisionNormalizada = decision.trim().toLowerCase();
    final String estadoDestino;
    if (decisionNormalizada == 'confirmada' ||
        decisionNormalizada == 'aceptar' ||
        decisionNormalizada == 'aceptada') {
      estadoDestino = 'confirmada';
    } else if (decisionNormalizada == 'rechazada' ||
        decisionNormalizada == 'rechazar') {
      estadoDestino = 'rechazada';
    } else {
      throw const ErrorCitasProfesional(
        'La decisión indicada no es válida. Selecciona aceptar o rechazar.',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'responder_solicitud_cita_profesional',
      <String, dynamic>{'p_id_cita': idCitaLimpio, 'p_decision': estadoDestino},
    );

    if (respuesta is List && respuesta.isNotEmpty) {
      final primero = respuesta.first;
      if (primero is Map) {
        return CitaProfesional.desdeMapa(Map<String, dynamic>.from(primero));
      }
    }
    if (respuesta is Map) {
      return CitaProfesional.desdeMapa(Map<String, dynamic>.from(respuesta));
    }

    throw const ErrorCitasProfesional(
      'El servidor devolvió una respuesta incompleta al procesar la solicitud de cita.',
    );
  }
}
