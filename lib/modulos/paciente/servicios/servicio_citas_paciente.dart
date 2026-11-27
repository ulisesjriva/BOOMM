import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/cita_paciente.dart';

typedef EjecutorRpcCitasPaciente = Future<dynamic> Function(
  String nombreFuncion, [
  Map<String, dynamic>? parametros,
]);
typedef LectorUsuarioActualIdCitasPaciente = String? Function();
typedef ProveedorAhoraUtcCitasPaciente = DateTime Function();

class ErrorCitasPaciente implements Exception {
  const ErrorCitasPaciente(
    this.mensaje, {
    this.codigo,
    this.esConflictoHorarioOcupado = false,
    this.esSolicitudDuplicada = false,
    this.esOfertaDesactualizada = false,
  });

  final String mensaje;
  final String? codigo;
  final bool esConflictoHorarioOcupado;
  final bool esSolicitudDuplicada;
  final bool esOfertaDesactualizada;

  @override
  String toString() => mensaje;
}

class ServicioCitasPaciente {
  const ServicioCitasPaciente({
    this.cliente,
    this.ejecutorRpc,
    this.lectorUsuarioActualId,
    this.proveedorAhoraUtc,
  });

  final SupabaseClient? cliente;
  final EjecutorRpcCitasPaciente? ejecutorRpc;
  final LectorUsuarioActualIdCitasPaciente? lectorUsuarioActualId;
  final ProveedorAhoraUtcCitasPaciente? proveedorAhoraUtc;

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
      throw const ErrorCitasPaciente(
        'Debes iniciar sesión como paciente para consultar horarios o solicitar una cita.',
        codigo: '42501',
      );
    }
    final idSesion = _supabase.auth.currentUser?.id.trim();
    if (idSesion == null || idSesion.isEmpty) {
      throw const ErrorCitasPaciente(
        'Debes iniciar sesión como paciente para consultar horarios o solicitar una cita.',
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
    } on ErrorCitasPaciente {
      rethrow;
    } on PostgrestException catch (error) {
      throw _traducirErrorPostgrest(error);
    } catch (error) {
      final texto = error.toString().toLowerCase();
      if (texto.contains('socketexception') ||
          texto.contains('failed host lookup') ||
          texto.contains('network')) {
        throw const ErrorCitasPaciente(
          'No se pudo conectar con el servidor. Revisa tu conexión a internet e inténtalo de nuevo.',
        );
      }
      throw const ErrorCitasPaciente(
        'No se pudo procesar la operación de citas. Inténtalo nuevamente.',
      );
    }
  }

  ErrorCitasPaciente _traducirErrorPostgrest(PostgrestException error) {
    final codigo = (error.code ?? '').trim();
    final mensajeOriginal = error.message.trim();
    final mensajeMinusculas = mensajeOriginal.toLowerCase();

    if (codigo == 'PGRST202' ||
        codigo == '42883' ||
        mensajeMinusculas.contains('could not find the function')) {
      return ErrorCitasPaciente(
        'El servidor aún no tiene configuradas las funciones de solicitud de citas (migración 08_solicitud_citas_paciente.sql pendiente). No se envió la solicitud.',
        codigo: codigo.isEmpty ? 'PGRST202' : codigo,
      );
    }

    if (codigo == '23505' ||
        mensajeMinusculas.contains('ya enviaste una solicitud') ||
        mensajeMinusculas.contains('duplicate key')) {
      return ErrorCitasPaciente(
        mensajeOriginal.isNotEmpty &&
                mensajeMinusculas.contains('ya enviaste una solicitud')
            ? mensajeOriginal
            : 'Ya enviaste una solicitud para este horario. Puedes revisarla en Mis citas.',
        codigo: '23505',
        esSolicitudDuplicada: true,
      );
    }

    if (codigo == '23P01' ||
        mensajeMinusculas.contains('acaba de ser reservado') ||
        mensajeMinusculas.contains('ya no está disponible') ||
        mensajeMinusculas.contains('bloqueado por el profesional')) {
      return ErrorCitasPaciente(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'Este horario acaba de ser reservado por otro paciente o dejó de estar disponible. Selecciona otro horario de la lista actualizada.',
        codigo: '23P01',
        esConflictoHorarioOcupado: true,
      );
    }

    if (codigo == '40001') {
      return ErrorCitasPaciente(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'Las condiciones o tarifa de adelanto cambiaron recientemente. Revisa el resumen actualizado y vuelve a aceptar.',
        codigo: '40001',
        esOfertaDesactualizada: true,
      );
    }

    if (codigo == '42501') {
      return ErrorCitasPaciente(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'No tienes permisos activos de paciente para realizar esta operación.',
        codigo: codigo,
      );
    }

    if (codigo == '22023' || codigo == '23514' || codigo == 'P0002') {
      return ErrorCitasPaciente(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'El horario seleccionado no es válido o ya no se encuentra disponible.',
        codigo: codigo,
      );
    }

    return ErrorCitasPaciente(
      mensajeOriginal.isNotEmpty
          ? mensajeOriginal
          : 'No se pudo completar la operación de solicitud de cita.',
      codigo: codigo.isEmpty ? null : codigo,
    );
  }

  List<HorarioDisponibilidad> _ordenarHorarios(
    List<HorarioDisponibilidad> horarios,
  ) {
    final copia = List<HorarioDisponibilidad>.from(horarios);
    copia.sort((a, b) {
      final comparacionFecha = a.fechaIso.compareTo(b.fechaIso);
      if (comparacionFecha != 0) {
        return comparacionFecha;
      }
      return a.minutosInicio.compareTo(b.minutosInicio);
    });
    return copia;
  }

  List<CitaPaciente> _ordenarCitas(List<CitaPaciente> citas) {
    final copia = List<CitaPaciente>.from(citas);
    copia.sort((a, b) {
      final comparacionFecha = a.fechaIso.compareTo(b.fechaIso);
      if (comparacionFecha != 0) {
        return comparacionFecha;
      }
      return a.minutosInicio.compareTo(b.minutosInicio);
    });
    return copia;
  }

  Future<List<HorarioDisponibilidad>> listarHorariosDisponiblesProfesional({
    required String idProfesional,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final idLimpio = idProfesional.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorCitasPaciente(
        'Debes indicar el profesional para consultar sus horarios disponibles.',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'listar_horarios_disponibles_profesional',
      <String, dynamic>{'p_id_profesional': idLimpio},
    );
    if (respuesta is! List) {
      return const <HorarioDisponibilidad>[];
    }

    final ahoraUtc = obtenerAhoraUtc();
    final horarios = respuesta
        .whereType<Map>()
        .map(
          (fila) =>
              HorarioDisponibilidad.desdeMapa(Map<String, dynamic>.from(fila)),
        )
        .where(
          (horario) =>
              horario.idDisponibilidad.isNotEmpty &&
              horario.esDisponible &&
              !horario.tieneCitaVinculada &&
              horario.esFuturoEnEcuador(referenciaUtc: ahoraUtc),
        )
        .toList();

    return _ordenarHorarios(horarios);
  }

  Future<CitaPaciente> solicitarCita({
    required String idProfesional,
    required String idDisponibilidad,
    String? claveIdempotencia,
    bool? aceptaCondicionesAdelanto,
    String? versionOfertaAdelanto,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final idProfesionalLimpio = idProfesional.trim();
    final idDisponibilidadLimpio = idDisponibilidad.trim();
    if (idProfesionalLimpio.isEmpty || idDisponibilidadLimpio.isEmpty) {
      throw const ErrorCitasPaciente(
        'Debes seleccionar un horario válido antes de enviar la solicitud.',
        codigo: '22023',
      );
    }

    final parametros = <String, dynamic>{
      'p_id_profesional': idProfesionalLimpio,
      'p_id_disponibilidad': idDisponibilidadLimpio,
    };
    if (claveIdempotencia != null && claveIdempotencia.trim().isNotEmpty) {
      parametros['p_clave_idempotencia'] = claveIdempotencia.trim();
    }
    if (aceptaCondicionesAdelanto != null) {
      parametros['p_acepta_condiciones_adelanto'] = aceptaCondicionesAdelanto;
    }
    if (versionOfertaAdelanto != null &&
        versionOfertaAdelanto.trim().isNotEmpty) {
      parametros['p_version_oferta_adelanto'] = versionOfertaAdelanto.trim();
    }

    final respuesta = await _invocarRpc('solicitar_cita_paciente', parametros);

    if (respuesta is List && respuesta.isNotEmpty) {
      final primero = respuesta.first;
      if (primero is Map) {
        return CitaPaciente.desdeMapa(Map<String, dynamic>.from(primero));
      }
    }
    if (respuesta is Map) {
      return CitaPaciente.desdeMapa(Map<String, dynamic>.from(respuesta));
    }

    throw const ErrorCitasPaciente(
      'El servidor devolvió una respuesta incompleta al registrar la solicitud de cita.',
    );
  }

  Future<List<CitaPaciente>> listarCitasPropias() async {
    _obtenerIdUsuarioActualExigido();
    final respuesta = await _invocarRpc('listar_citas_paciente_propias');
    if (respuesta is! List) {
      return const <CitaPaciente>[];
    }

    final citas = respuesta
        .whereType<Map>()
        .map((fila) => CitaPaciente.desdeMapa(Map<String, dynamic>.from(fila)))
        .where((cita) => cita.idCita.isNotEmpty)
        .toList();

    return _ordenarCitas(citas);
  }
}
