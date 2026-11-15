import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/horario_disponibilidad.dart';

typedef EjecutorRpcDisponibilidad = Future<dynamic> Function(
  String nombreFuncion, [
  Map<String, dynamic>? parametros,
]);
typedef LectorUsuarioActualIdDisponibilidad = String? Function();
typedef ProveedorAhoraUtcDisponibilidad = DateTime Function();

class ErrorDisponibilidadProfesional implements Exception {
  const ErrorDisponibilidadProfesional(this.mensaje, {this.codigo});

  final String mensaje;
  final String? codigo;

  @override
  String toString() => mensaje;
}

class ServicioDisponibilidadProfesional {
  const ServicioDisponibilidadProfesional({
    this.cliente,
    this.ejecutorRpc,
    this.lectorUsuarioActualId,
    this.proveedorAhoraUtc,
  });

  final SupabaseClient? cliente;
  final EjecutorRpcDisponibilidad? ejecutorRpc;
  final LectorUsuarioActualIdDisponibilidad? lectorUsuarioActualId;
  final ProveedorAhoraUtcDisponibilidad? proveedorAhoraUtc;

  SupabaseClient get _supabase => cliente ?? Supabase.instance.client;

  DateTime obtenerAhoraUtc() {
    if (proveedorAhoraUtc != null) {
      return proveedorAhoraUtc!().toUtc();
    }
    return DateTime.now().toUtc();
  }

  String _obtenerIdUsuarioActualExigido() {
    final idInyectado = lectorUsuarioActualId?.call()?.trim();
    if (idInyectado != null && idInyectado.isNotEmpty) {
      return idInyectado;
    }
    final idSesion = _supabase.auth.currentUser?.id.trim();
    if (idSesion == null || idSesion.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'Debes iniciar sesión como profesional para gestionar tus horarios.',
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
    } on ErrorDisponibilidadProfesional {
      rethrow;
    } on PostgrestException catch (error) {
      throw _traducirErrorPostgrest(error, nombreFuncion: nombreFuncion);
    } catch (error) {
      final texto = error.toString().toLowerCase();
      if (texto.contains('socketexception') ||
          texto.contains('failed host lookup') ||
          texto.contains('network')) {
        throw const ErrorDisponibilidadProfesional(
          'No se pudo conectar con el servidor. Revisa tu conexión a internet e inténtalo de nuevo.',
        );
      }
      throw const ErrorDisponibilidadProfesional(
        'No se pudo procesar la operación de disponibilidad. Inténtalo nuevamente.',
      );
    }
  }

  static const Set<String> _funcionesMigracionAgendaSemanal = <String>{
    'crear_intervalos_jornada_profesional_propia',
    'listar_dias_no_laborables_profesional_propios',
    'registrar_dia_no_laborable_profesional_propio',
    'retirar_dia_no_laborable_profesional_propio',
    'previsualizar_repeticion_semana_profesional_propia',
    'confirmar_repeticion_semana_profesional_propia',
  };

  ErrorDisponibilidadProfesional _traducirErrorPostgrest(
    PostgrestException error, {
    String? nombreFuncion,
  }) {
    final codigo = (error.code ?? '').trim();
    final mensajeOriginal = error.message.trim();
    final mensajeMinusculas = mensajeOriginal.toLowerCase();

    if (codigo == 'PGRST202' ||
        codigo == '42883' ||
        mensajeMinusculas.contains('could not find the function') ||
        mensajeMinusculas.contains('función no soportada')) {
      final esEliminacion =
          nombreFuncion == 'eliminar_disponibilidad_profesional_propia' ||
          mensajeMinusculas.contains(
            'eliminar_disponibilidad_profesional_propia',
          );
      if (esEliminacion) {
        return ErrorDisponibilidadProfesional(
          'El servidor aún no tiene configurada la función de eliminación de horarios (migración 12_eliminacion_disponibilidad_profesional.sql pendiente). No se eliminó el horario.',
          codigo: codigo.isEmpty ? 'PGRST202' : codigo,
        );
      }
      final esAgendaSemanal =
          (nombreFuncion != null &&
              _funcionesMigracionAgendaSemanal.contains(nombreFuncion)) ||
          _funcionesMigracionAgendaSemanal.any(
            (fn) => mensajeMinusculas.contains(fn),
          );
      if (esAgendaSemanal) {
        return ErrorDisponibilidadProfesional(
          'El servidor aún no tiene configuradas las funciones de la agenda semanal (migración 14_agenda_semanal_profesional.sql pendiente). No se guardaron cambios.',
          codigo: codigo.isEmpty ? 'PGRST202' : codigo,
        );
      }
      return ErrorDisponibilidadProfesional(
        'El servidor aún no tiene configuradas las funciones de disponibilidad (migración 06_disponibilidad_profesional.sql pendiente). No se guardaron cambios.',
        codigo: codigo.isEmpty ? 'PGRST202' : codigo,
      );
    }

    if (codigo == '23P01' ||
        codigo == '23505' ||
        mensajeMinusculas.contains('superpone') ||
        mensajeMinusculas.contains('conflicto') ||
        mensajeMinusculas.contains('duplicate key')) {
      return ErrorDisponibilidadProfesional(
        mensajeOriginal.isNotEmpty &&
                (mensajeMinusculas.contains('superpone') ||
                    mensajeMinusculas.contains('conflicto') ||
                    mensajeMinusculas.contains('vista previa'))
            ? mensajeOriginal
            : 'El horario indicado se superpone con otro intervalo ya registrado en esa misma fecha.',
        codigo: codigo.isEmpty ? '23P01' : codigo,
      );
    }

    if (codigo == '42501') {
      return ErrorDisponibilidadProfesional(
        mensajeOriginal.isNotEmpty ? mensajeOriginal : 'No tienes permisos para consultar o modificar esta disponibilidad.',
        codigo: codigo,
      );
    }

    if (codigo == '22023' || codigo == '23514' || codigo == 'P0002') {
      return ErrorDisponibilidadProfesional(
        mensajeOriginal.isNotEmpty
            ? mensajeOriginal
            : 'Los datos del horario no cumplen las reglas de validación.',
        codigo: codigo,
      );
    }

    return ErrorDisponibilidadProfesional(
      mensajeOriginal.isNotEmpty ? mensajeOriginal : 'No se pudo completar la operación en los horarios de disponibilidad.',
      codigo: codigo.isEmpty ? null : codigo,
    );
  }

  void _validarIntervaloEnEcuador({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
  }) {
    final inicioMinutos = HorarioDisponibilidad.convertirHoraAMinutos(
      horaInicio,
    );
    final finMinutos = HorarioDisponibilidad.convertirHoraAMinutos(horaFin);
    if (inicioMinutos == null || finMinutos == null) {
      throw const ErrorDisponibilidadProfesional(
        'Selecciona una hora de inicio y una hora de fin válidas en formato HH:mm.',
        codigo: '22023',
      );
    }
    if (finMinutos <= inicioMinutos) {
      throw const ErrorDisponibilidadProfesional(
        'La hora de finalización debe ser posterior a la hora de inicio.',
        codigo: '23514',
      );
    }
    final esFuturo = HorarioDisponibilidad.esIntervaloEnFuturoEcuador(
      fecha: fecha,
      horaInicio: horaInicio,
      referenciaUtc: obtenerAhoraUtc(),
    );
    if (!esFuturo) {
      throw const ErrorDisponibilidadProfesional(
        'No se pueden registrar ni modificar horarios en fechas u horas pasadas (hora de Ecuador continental).',
        codigo: '22023',
      );
    }
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

  Future<List<HorarioDisponibilidad>> listarHorariosPropios() async {
    _obtenerIdUsuarioActualExigido();
    final respuesta = await _invocarRpc(
      'listar_disponibilidad_profesional_propia',
    );
    return _extraerListaHorarios(respuesta);
  }

  Future<HorarioDisponibilidad> crearHorarioPropio({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final fechaNormalizada = HorarioDisponibilidad.normalizarFechaSoloDia(
      fecha,
    );
    final inicioNormalizado = HorarioDisponibilidad.normalizarHoraTexto(
      horaInicio,
    );
    final finNormalizado = HorarioDisponibilidad.normalizarHoraTexto(horaFin);

    _validarIntervaloEnEcuador(
      fecha: fechaNormalizada,
      horaInicio: inicioNormalizado,
      horaFin: finNormalizado,
    );

    final respuesta = await _invocarRpc(
      'crear_disponibilidad_profesional_propia',
      <String, dynamic>{
        'p_fecha': HorarioDisponibilidad.formatearFechaIso(fechaNormalizada),
        'p_hora_inicio': inicioNormalizado,
        'p_hora_fin': finNormalizado,
      },
    );

    return _extraerHorarioUnico(respuesta);
  }

  Future<List<HorarioDisponibilidad>> crearIntervalosJornadaPropia({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
    required int duracionMinutos,
    int descansoMinutos = 0,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final fechaNormalizada = HorarioDisponibilidad.normalizarFechaSoloDia(
      fecha,
    );
    final inicioNormalizado = HorarioDisponibilidad.normalizarHoraTexto(
      horaInicio,
    );
    final finNormalizado = HorarioDisponibilidad.normalizarHoraTexto(horaFin);

    if (duracionMinutos <= 0) {
      throw const ErrorDisponibilidadProfesional(
        'La duración de cada cita debe ser mayor a 0 minutos.',
        codigo: '22023',
      );
    }
    if (descansoMinutos < 0) {
      throw const ErrorDisponibilidadProfesional(
        'El descanso entre citas no puede ser negativo.',
        codigo: '22023',
      );
    }

    _validarIntervaloEnEcuador(
      fecha: fechaNormalizada,
      horaInicio: inicioNormalizado,
      horaFin: finNormalizado,
    );

    final generados = HorarioDisponibilidad.generarIntervalosJornada(
      horaInicioJornada: inicioNormalizado,
      horaFinJornada: finNormalizado,
      duracionMinutos: duracionMinutos,
      descansoMinutos: descansoMinutos,
    );
    if (generados.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'La duración de la cita supera el rango horario seleccionado. No se puede generar ningún intervalo completo.',
        codigo: '22023',
      );
    }
    if (generados.length > HorarioDisponibilidad.maximoIntervalosPorOperacion) {
      throw const ErrorDisponibilidadProfesional(
        'Se supera el límite máximo de ${HorarioDisponibilidad.maximoIntervalosPorOperacion} intervalos por operación.',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'crear_intervalos_jornada_profesional_propia',
      <String, dynamic>{
        'p_fecha': HorarioDisponibilidad.formatearFechaIso(fechaNormalizada),
        'p_hora_inicio': inicioNormalizado,
        'p_hora_fin': finNormalizado,
        'p_duracion_minutos': duracionMinutos,
        'p_descanso_minutos': descansoMinutos,
      },
    );

    final creados = _extraerListaHorarios(respuesta);
    if (creados.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'El servidor no devolvió los horarios creados en la jornada.',
      );
    }
    return creados;
  }

  Future<HorarioDisponibilidad> actualizarHorarioPropio({
    required String idDisponibilidad,
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final idLimpio = idDisponibilidad.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'Debes indicar el identificador del horario que deseas editar.',
        codigo: '22023',
      );
    }

    final fechaNormalizada = HorarioDisponibilidad.normalizarFechaSoloDia(
      fecha,
    );
    final inicioNormalizado = HorarioDisponibilidad.normalizarHoraTexto(
      horaInicio,
    );
    final finNormalizado = HorarioDisponibilidad.normalizarHoraTexto(horaFin);

    _validarIntervaloEnEcuador(
      fecha: fechaNormalizada,
      horaInicio: inicioNormalizado,
      horaFin: finNormalizado,
    );

    final respuesta = await _invocarRpc(
      'actualizar_disponibilidad_profesional_propia',
      <String, dynamic>{
        'p_id_disponibilidad': idLimpio,
        'p_fecha': HorarioDisponibilidad.formatearFechaIso(fechaNormalizada),
        'p_hora_inicio': inicioNormalizado,
        'p_hora_fin': finNormalizado,
      },
    );

    return _extraerHorarioUnico(respuesta);
  }

  Future<HorarioDisponibilidad> cambiarEstadoHorarioPropio({
    required String idDisponibilidad,
    required String nuevoEstado,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final idLimpio = idDisponibilidad.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'Debes indicar el identificador del horario que deseas actualizar.',
        codigo: '22023',
      );
    }

    final estadoNormalizado = nuevoEstado.trim().toLowerCase();
    if (estadoNormalizado == 'reservada') {
      throw const ErrorDisponibilidadProfesional(
        'El estado "reservada" está reservado exclusivamente para el flujo de agendamiento de citas.',
        codigo: '22023',
      );
    }
    if (estadoNormalizado != 'disponible' && estadoNormalizado != 'bloqueada') {
      throw const ErrorDisponibilidadProfesional(
        'Solo puedes cambiar manualmente el horario entre "disponible" y "bloqueada".',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'cambiar_estado_disponibilidad_profesional_propia',
      <String, dynamic>{
        'p_id_disponibilidad': idLimpio,
        'p_nuevo_estado': estadoNormalizado,
      },
    );

    return _extraerHorarioUnico(respuesta);
  }

  Future<void> eliminarHorarioPropio(String idDisponibilidad) async {
    _obtenerIdUsuarioActualExigido();
    final idLimpio = idDisponibilidad.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'Debes indicar el identificador del horario que deseas eliminar.',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'eliminar_disponibilidad_profesional_propia',
      <String, dynamic>{'p_id_disponibilidad': idLimpio},
    );

    final idEliminado = _extraerCampoTextoUnico(respuesta, 'id_disponibilidad');
    if (idEliminado != idLimpio) {
      throw const ErrorDisponibilidadProfesional(
        'El servidor no confirmó la eliminación del horario seleccionado.',
      );
    }
  }

  Future<List<DiaNoLaborableProfesional>>
  listarDiasNoLaborablesPropios() async {
    _obtenerIdUsuarioActualExigido();
    final respuesta = await _invocarRpc(
      'listar_dias_no_laborables_profesional_propios',
    );
    if (respuesta is! List) {
      return const <DiaNoLaborableProfesional>[];
    }
    return respuesta
        .whereType<Map>()
        .map(
          (fila) => DiaNoLaborableProfesional.desdeMapa(
            Map<String, dynamic>.from(fila),
          ),
        )
        .where((item) => item.idDiaNoLaborable.isNotEmpty)
        .toList(growable: false);
  }

  Future<DiaNoLaborableProfesional> registrarDiaNoLaborablePropio({
    required DateTime fecha,
    String? motivo,
  }) async {
    _obtenerIdUsuarioActualExigido();
    final fechaNormalizada = HorarioDisponibilidad.normalizarFechaSoloDia(
      fecha,
    );
    final hoyEcuador = HorarioDisponibilidad.normalizarFechaSoloDia(
      HorarioDisponibilidad.obtenerAhoraEnEcuador(
        referenciaUtc: obtenerAhoraUtc(),
      ),
    );
    if (fechaNormalizada.isBefore(hoyEcuador)) {
      throw const ErrorDisponibilidadProfesional(
        'No se pueden marcar como no laborables fechas pasadas en Ecuador continental.',
        codigo: '22023',
      );
    }

    final respuesta = await _invocarRpc(
      'registrar_dia_no_laborable_profesional_propio',
      <String, dynamic>{
        'p_fecha': HorarioDisponibilidad.formatearFechaIso(fechaNormalizada),
        'p_motivo': (motivo ?? '').trim(),
      },
    );

    if (respuesta is List && respuesta.isNotEmpty && respuesta.first is Map) {
      return DiaNoLaborableProfesional.desdeMapa(
        Map<String, dynamic>.from(respuesta.first as Map),
      );
    }
    if (respuesta is Map) {
      return DiaNoLaborableProfesional.desdeMapa(
        Map<String, dynamic>.from(respuesta),
      );
    }
    throw const ErrorDisponibilidadProfesional(
      'El servidor devolvió una respuesta incompleta al registrar el día no laborable.',
    );
  }

  Future<void> retirarDiaNoLaborablePropio(DateTime fecha) async {
    _obtenerIdUsuarioActualExigido();
    final fechaNormalizada = HorarioDisponibilidad.normalizarFechaSoloDia(
      fecha,
    );

    final respuesta = await _invocarRpc(
      'retirar_dia_no_laborable_profesional_propio',
      <String, dynamic>{
        'p_fecha': HorarioDisponibilidad.formatearFechaIso(fechaNormalizada),
      },
    );

    final idRetirado = _extraerCampoTextoUnico(
      respuesta,
      'id_dia_no_laborable',
    );
    if (idRetirado.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'El servidor no confirmó el retiro del día no laborable.',
      );
    }
  }

  Future<VistaPreviaRepeticionSemana> previsualizarRepeticionSemanaPropia({
    required DateTime lunesOrigen,
    required int semanasPosteriores,
  }) async {
    _obtenerIdUsuarioActualExigido();
    if (semanasPosteriores < 1 || semanasPosteriores > 4) {
      throw const ErrorDisponibilidadProfesional(
        'Selecciona entre 1 y 4 semanas posteriores para repetir la distribución.',
        codigo: '22023',
      );
    }

    final lunesNormalizado = HorarioDisponibilidad.obtenerLunesDeSemana(
      lunesOrigen,
    );
    final respuesta = await _invocarRpc(
      'previsualizar_repeticion_semana_profesional_propia',
      <String, dynamic>{
        'p_lunes_origen': HorarioDisponibilidad.formatearFechaIso(
          lunesNormalizado,
        ),
        'p_semanas_posteriores': semanasPosteriores,
      },
    );

    if (respuesta is! List) {
      return VistaPreviaRepeticionSemana(
        lunesOrigen: lunesNormalizado,
        semanasPosteriores: semanasPosteriores,
        huellaVistaPrevia: '',
        items: const <ItemVistaPreviaRepeticionSemana>[],
      );
    }

    final items = respuesta
        .whereType<Map>()
        .map(
          (fila) => ItemVistaPreviaRepeticionSemana.desdeMapa(
            Map<String, dynamic>.from(fila),
          ),
        )
        .toList(growable: false);

    final huella = items.isNotEmpty ? items.first.huellaVistaPrevia : '';
    return VistaPreviaRepeticionSemana(
      lunesOrigen: lunesNormalizado,
      semanasPosteriores: semanasPosteriores,
      huellaVistaPrevia: huella,
      items: items,
    );
  }

  Future<List<HorarioDisponibilidad>> confirmarRepeticionSemanaPropia({
    required DateTime lunesOrigen,
    required int semanasPosteriores,
    required String huellaVistaPrevia,
  }) async {
    _obtenerIdUsuarioActualExigido();
    if (semanasPosteriores < 1 || semanasPosteriores > 4) {
      throw const ErrorDisponibilidadProfesional(
        'Selecciona entre 1 y 4 semanas posteriores para repetir la distribución.',
        codigo: '22023',
      );
    }
    final huellaLimpia = huellaVistaPrevia.trim();
    if (huellaLimpia.isEmpty) {
      throw const ErrorDisponibilidadProfesional(
        'Debes previsualizar los intervalos antes de confirmar la repetición semanal.',
        codigo: '22023',
      );
    }

    final lunesNormalizado = HorarioDisponibilidad.obtenerLunesDeSemana(
      lunesOrigen,
    );
    final respuesta = await _invocarRpc(
      'confirmar_repeticion_semana_profesional_propia',
      <String, dynamic>{
        'p_lunes_origen': HorarioDisponibilidad.formatearFechaIso(
          lunesNormalizado,
        ),
        'p_semanas_posteriores': semanasPosteriores,
        'p_huella_vista_previa': huellaLimpia,
      },
    );

    return _extraerListaHorarios(respuesta);
  }

  String _extraerCampoTextoUnico(dynamic respuesta, String nombreCampo) {
    if (respuesta is List && respuesta.isNotEmpty) {
      final primero = respuesta.first;
      if (primero is Map) {
        return (primero[nombreCampo] ?? '').toString().trim();
      }
    }
    if (respuesta is Map) {
      return (respuesta[nombreCampo] ?? '').toString().trim();
    }
    return '';
  }

  List<HorarioDisponibilidad> _extraerListaHorarios(dynamic respuesta) {
    if (respuesta is! List) {
      return const <HorarioDisponibilidad>[];
    }
    final horarios = respuesta
        .whereType<Map>()
        .map(
          (fila) =>
              HorarioDisponibilidad.desdeMapa(Map<String, dynamic>.from(fila)),
        )
        .where((horario) => horario.idDisponibilidad.isNotEmpty)
        .toList();
    return _ordenarHorarios(horarios);
  }

  HorarioDisponibilidad _extraerHorarioUnico(dynamic respuesta) {
    if (respuesta is List && respuesta.isNotEmpty) {
      final primero = respuesta.first;
      if (primero is Map) {
        return HorarioDisponibilidad.desdeMapa(
          Map<String, dynamic>.from(primero),
        );
      }
    }
    if (respuesta is Map) {
      return HorarioDisponibilidad.desdeMapa(
        Map<String, dynamic>.from(respuesta),
      );
    }
    throw const ErrorDisponibilidadProfesional(
      'El servidor devolvió una respuesta incompleta al guardar el horario.',
    );
  }
}
