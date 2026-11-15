import 'package:flutter/foundation.dart';

import '../modelos/horario_disponibilidad.dart';
import '../servicios/servicio_disponibilidad_profesional.dart';

class ControladorDisponibilidadProfesional extends ChangeNotifier {
  ControladorDisponibilidadProfesional({
    ServicioDisponibilidadProfesional? servicio,
  }) : _servicio = servicio ?? const ServicioDisponibilidadProfesional();

  final ServicioDisponibilidadProfesional _servicio;

  List<HorarioDisponibilidad> _horarios = const <HorarioDisponibilidad>[];
  Map<String, DiaNoLaborableProfesional> _diasNoLaborablesPorFecha =
      const <String, DiaNoLaborableProfesional>{};
  bool _estaCargando = false;
  bool _estaProcesandoAccion = false;
  String? _mensajeError;
  String? _mensajeExito;
  bool _fueDisposed = false;

  List<HorarioDisponibilidad> get horarios =>
      List<HorarioDisponibilidad>.unmodifiable(_horarios);
  List<DiaNoLaborableProfesional> get diasNoLaborables =>
      List<DiaNoLaborableProfesional>.unmodifiable(
        _diasNoLaborablesPorFecha.values,
      );
  bool get estaCargando => _estaCargando;
  bool get estaProcesandoAccion => _estaProcesandoAccion;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;
  bool get tieneHorarios => _horarios.isNotEmpty;

  DateTime get ahoraUtcReferencia => _servicio.obtenerAhoraUtc();

  DateTime get ahoraEnEcuador => HorarioDisponibilidad.obtenerAhoraEnEcuador(
    referenciaUtc: ahoraUtcReferencia,
  );

  /// Devuelve los horarios registrados para [fecha] ordenados por hora de inicio.
  List<HorarioDisponibilidad> horariosPorFecha(DateTime fecha) {
    final fechaIso = HorarioDisponibilidad.formatearFechaIso(fecha);
    return _horarios
        .where((horario) => horario.fechaIso == fechaIso)
        .toList(growable: false);
  }

  bool esDiaNoLaborable(DateTime fecha) {
    final fechaIso = HorarioDisponibilidad.formatearFechaIso(fecha);
    return _diasNoLaborablesPorFecha.containsKey(fechaIso);
  }

  DiaNoLaborableProfesional? obtenerDiaNoLaborable(DateTime fecha) {
    final fechaIso = HorarioDisponibilidad.formatearFechaIso(fecha);
    return _diasNoLaborablesPorFecha[fechaIso];
  }

  int contarDisponiblesEnFecha(DateTime fecha) {
    return horariosPorFecha(fecha)
        .where((horario) => horario.esDisponible)
        .length;
  }

  int contarReservadosEnFecha(DateTime fecha) {
    return horariosPorFecha(fecha)
        .where((horario) => horario.esReservada)
        .length;
  }

  void limpiarMensajes() {
    if (_mensajeError == null && _mensajeExito == null) {
      return;
    }
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();
  }

  /// Previsualiza los intervalos completos que se generarán para una jornada.
  List<IntervaloHorarioPropuesto> previsualizarIntervalosJornada({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
    required int duracionMinutos,
    required int descansoMinutos,
  }) {
    final existentes = horariosPorFecha(fecha);
    return HorarioDisponibilidad.generarIntervalosJornada(
      horaInicioJornada: horaInicio,
      horaFinJornada: horaFin,
      duracionMinutos: duracionMinutos,
      descansoMinutos: descansoMinutos,
      fecha: fecha,
      horariosExistentesEnFecha: existentes,
    );
  }

  /// Valida localmente un intervalo individual antes de enviarlo al servidor.
  /// Devuelve un mensaje de error en español o `null` si es válido.
  String? validarIntervaloPropuesto({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
    String? idExcluir,
  }) {
    final inicioMinutos = HorarioDisponibilidad.convertirHoraAMinutos(
      horaInicio,
    );
    final finMinutos = HorarioDisponibilidad.convertirHoraAMinutos(horaFin);
    if (inicioMinutos == null || finMinutos == null) {
      return 'Selecciona una hora de inicio y una hora de fin válidas en formato HH:mm.';
    }
    if (finMinutos <= inicioMinutos) {
      return 'La hora de finalización debe ser posterior a la hora de inicio.';
    }

    final fechaSoloDia = HorarioDisponibilidad.normalizarFechaSoloDia(fecha);
    if (esDiaNoLaborable(fechaSoloDia)) {
      return 'La fecha seleccionada está marcada como día no laborable. Retira primero la excepción si deseas habilitar horarios.';
    }

    final esFuturo = HorarioDisponibilidad.esIntervaloEnFuturoEcuador(
      fecha: fechaSoloDia,
      horaInicio: horaInicio,
      referenciaUtc: ahoraUtcReferencia,
    );
    if (!esFuturo) {
      return 'No se pueden registrar ni modificar horarios en fechas u horas pasadas (hora de Ecuador continental).';
    }

    final idIgnorar = idExcluir?.trim();
    for (final existente in _horarios) {
      if (idIgnorar != null &&
          idIgnorar.isNotEmpty &&
          existente.idDisponibilidad == idIgnorar) {
        continue;
      }
      final seSuperpone = existente.seSuperponeCon(
        otraFecha: fechaSoloDia,
        otroInicioMinutos: inicioMinutos,
        otroFinMinutos: finMinutos,
      );
      if (seSuperpone) {
        return 'El horario ${HorarioDisponibilidad.normalizarHoraTexto(horaInicio)} - '
            '${HorarioDisponibilidad.normalizarHoraTexto(horaFin)} se superpone con el intervalo existente '
            '${existente.rangoHorarioTexto} en esa misma fecha.';
      }
    }

    return null;
  }

  /// Valida una jornada de uno o varios intervalos antes de enviarla al servidor.
  String? validarJornadaPropuesta({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
    required int duracionMinutos,
    required int descansoMinutos,
  }) {
    final inicioMinutos = HorarioDisponibilidad.convertirHoraAMinutos(
      horaInicio,
    );
    final finMinutos = HorarioDisponibilidad.convertirHoraAMinutos(horaFin);
    if (inicioMinutos == null || finMinutos == null) {
      return 'Selecciona una hora de inicio y una hora de fin válidas en formato HH:mm.';
    }
    if (finMinutos <= inicioMinutos) {
      return 'La hora de finalización debe ser posterior a la hora de inicio.';
    }
    if (duracionMinutos <= 0) {
      return 'La duración de cada cita debe ser mayor a 0 minutos.';
    }
    if (descansoMinutos < 0) {
      return 'El descanso entre citas no puede ser negativo.';
    }

    final fechaSoloDia = HorarioDisponibilidad.normalizarFechaSoloDia(fecha);
    if (esDiaNoLaborable(fechaSoloDia)) {
      return 'La fecha seleccionada está marcada como día no laborable. Retira primero la excepción si deseas agregar horarios.';
    }

    final esFuturo = HorarioDisponibilidad.esIntervaloEnFuturoEcuador(
      fecha: fechaSoloDia,
      horaInicio: horaInicio,
      referenciaUtc: ahoraUtcReferencia,
    );
    if (!esFuturo) {
      return 'No se pueden registrar ni modificar horarios en fechas u horas pasadas (hora de Ecuador continental).';
    }

    final propuestos = previsualizarIntervalosJornada(
      fecha: fechaSoloDia,
      horaInicio: horaInicio,
      horaFin: horaFin,
      duracionMinutos: duracionMinutos,
      descansoMinutos: descansoMinutos,
    );
    if (propuestos.isEmpty) {
      return 'La duración de la cita ($duracionMinutos min) supera el rango horario seleccionado. Ajusta las horas o la duración.';
    }
    if (propuestos.length >
        HorarioDisponibilidad.maximoIntervalosPorOperacion) {
      return 'La jornada genera ${propuestos.length} intervalos y supera el máximo permitido de '
          '${HorarioDisponibilidad.maximoIntervalosPorOperacion} intervalos por operación.';
    }

    final enConflicto = propuestos
        .where((item) => item.enConflicto)
        .map((item) => item.rangoCompacto)
        .toList(growable: false);
    if (enConflicto.isNotEmpty) {
      return 'No se guardaron horarios porque existen intervalos en conflicto en esa fecha: ${enConflicto.join(', ')}.';
    }

    return null;
  }

  Future<bool> cargarHorarios({bool conservarMensajeExito = false}) async {
    if (_estaCargando) {
      return false;
    }
    _estaCargando = true;
    _mensajeError = null;
    if (!conservarMensajeExito) {
      _mensajeExito = null;
    }
    _notificarSeguro();

    try {
      final lista = await _servicio.listarHorariosPropios();
      Map<String, DiaNoLaborableProfesional> mapaNoLaborables =
          _diasNoLaborablesPorFecha;
      try {
        final diasNoLab = await _servicio.listarDiasNoLaborablesPropios();
        mapaNoLaborables = <String, DiaNoLaborableProfesional>{
          for (final dia in diasNoLab) dia.fechaIso: dia,
        };
      } on ErrorDisponibilidadProfesional catch (error) {
        if (error.codigo != 'PGRST202' && error.codigo != '42883') {
          rethrow;
        }
        mapaNoLaborables = const <String, DiaNoLaborableProfesional>{};
      }

      if (_fueDisposed) {
        return false;
      }
      _horarios = _ordenarHorarios(lista);
      _diasNoLaborablesPorFecha = mapaNoLaborables;
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudieron cargar tus horarios de disponibilidad. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaCargando = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> crearHorario({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    final errorValidacion = validarIntervaloPropuesto(
      fecha: fecha,
      horaInicio: horaInicio,
      horaFin: horaFin,
    );
    if (errorValidacion != null) {
      _mensajeError = errorValidacion;
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final nuevo = await _servicio.crearHorarioPropio(
        fecha: fecha,
        horaInicio: horaInicio,
        horaFin: horaFin,
      );
      if (_fueDisposed) {
        return false;
      }
      _horarios = _ordenarHorarios(<HorarioDisponibilidad>[
        ..._horarios.where(
          (item) => item.idDisponibilidad != nuevo.idDisponibilidad,
        ),
        nuevo,
      ]);
      _mensajeExito =
          'Horario ${nuevo.rangoHorarioTexto} registrado correctamente para el ${nuevo.fechaLegible}.';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo registrar el horario de disponibilidad. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  /// Crea varios intervalos dentro de una jornada en una sola transacción.
  /// Si alguno entra en conflicto, no guarda parcialmente la tanda e informa los intervalos afectados.
  Future<bool> crearHorariosEnJornada({
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
    required int duracionMinutos,
    int descansoMinutos = 0,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    final errorValidacion = validarJornadaPropuesta(
      fecha: fecha,
      horaInicio: horaInicio,
      horaFin: horaFin,
      duracionMinutos: duracionMinutos,
      descansoMinutos: descansoMinutos,
    );
    if (errorValidacion != null) {
      _mensajeError = errorValidacion;
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final creados = await _servicio.crearIntervalosJornadaPropia(
        fecha: fecha,
        horaInicio: horaInicio,
        horaFin: horaFin,
        duracionMinutos: duracionMinutos,
        descansoMinutos: descansoMinutos,
      );
      if (_fueDisposed) {
        return false;
      }
      final idsCreados = creados.map((item) => item.idDisponibilidad).toSet();
      _horarios = _ordenarHorarios(<HorarioDisponibilidad>[
        ..._horarios.where(
          (item) => !idsCreados.contains(item.idDisponibilidad),
        ),
        ...creados,
      ]);
      if (creados.length == 1) {
        final unico = creados.first;
        _mensajeExito =
            'Horario ${unico.rangoHorarioTexto} registrado correctamente para el ${unico.fechaLegible}.';
      } else {
        final fechaLegible = HorarioDisponibilidad.formatearFechaLegible(fecha);
        _mensajeExito =
            'Se agregaron ${creados.length} horarios correctamente para el $fechaLegible.';
      }
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudieron registrar los horarios de la jornada. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> editarHorario({
    required String idDisponibilidad,
    required DateTime fecha,
    required String horaInicio,
    required String horaFin,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    final idLimpio = idDisponibilidad.trim();
    final actual = _buscarPorId(idLimpio);
    if (actual != null) {
      if (esDiaNoLaborable(actual.fecha)) {
        _mensajeError = 'No se pueden editar horarios en una fecha marcada como día no laborable.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
      if (actual.estaProtegidoPorReservaOCita) {
        _mensajeError =
            'No se puede editar un horario reservado o vinculado a una cita.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
      if (!actual.esDisponible) {
        _mensajeError = 'Solo se pueden editar horarios futuros que estén en estado disponible.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
      if (!actual.esFuturoEnEcuador(referenciaUtc: ahoraUtcReferencia)) {
        _mensajeError = 'No se puede editar un horario cuya fecha u hora ya pasó en Ecuador continental.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
    }

    final errorValidacion = validarIntervaloPropuesto(
      fecha: fecha,
      horaInicio: horaInicio,
      horaFin: horaFin,
      idExcluir: idLimpio,
    );
    if (errorValidacion != null) {
      _mensajeError = errorValidacion;
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final actualizado = await _servicio.actualizarHorarioPropio(
        idDisponibilidad: idLimpio,
        fecha: fecha,
        horaInicio: horaInicio,
        horaFin: horaFin,
      );
      if (_fueDisposed) {
        return false;
      }
      _reemplazarHorarioEnLista(actualizado);
      _mensajeExito =
          'Horario actualizado a ${actualizado.rangoHorarioTexto} (${actualizado.fechaLegible}).';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo actualizar el horario seleccionado. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> cambiarEstadoHorario({
    required String idDisponibilidad,
    required String nuevoEstado,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    final idLimpio = idDisponibilidad.trim();
    final estadoDestino = nuevoEstado.trim().toLowerCase();

    if (estadoDestino == 'reservada') {
      _mensajeError = 'El estado "reservada" está reservado exclusivamente para el flujo de agendamiento de citas.';
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }
    if (estadoDestino != 'disponible' && estadoDestino != 'bloqueada') {
      _mensajeError = 'Solo puedes cambiar manualmente el horario entre "disponible" y "bloqueada".';
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    final actual = _buscarPorId(idLimpio);
    if (actual != null) {
      if (actual.esReservada) {
        _mensajeError = 'No se puede bloquear ni desbloquear un horario reservado o vinculado a una cita.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
      if (estadoDestino == 'disponible' && esDiaNoLaborable(actual.fecha)) {
        _mensajeError = 'No se puede desbloquear un horario en una fecha marcada como día no laborable. Retira primero la excepción.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
      if (!actual.esFuturoEnEcuador(referenciaUtc: ahoraUtcReferencia)) {
        _mensajeError = 'No se puede cambiar el estado de un horario cuya fecha u hora ya pasó en Ecuador continental.';
        _mensajeExito = null;
        _notificarSeguro();
        return false;
      }
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final actualizado = await _servicio.cambiarEstadoHorarioPropio(
        idDisponibilidad: idLimpio,
        nuevoEstado: estadoDestino,
      );
      if (_fueDisposed) {
        return false;
      }
      _reemplazarHorarioEnLista(actualizado);
      _mensajeExito = actualizado.esBloqueada
          ? 'Horario ${actualizado.rangoHorarioTexto} bloqueado correctamente.'
          : 'Horario ${actualizado.rangoHorarioTexto} habilitado nuevamente como disponible.';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo actualizar el estado del horario. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> alternarBloqueoHorario(HorarioDisponibilidad horario) {
    final destino = horario.esBloqueada ? 'disponible' : 'bloqueada';
    return cambiarEstadoHorario(
      idDisponibilidad: horario.idDisponibilidad,
      nuevoEstado: destino,
    );
  }

  Future<bool> eliminarHorario(HorarioDisponibilidad horario) {
    return eliminarHorarioPorId(
      horario.idDisponibilidad,
      respaldoHorario: horario,
    );
  }

  Future<bool> eliminarHorarioPorId(
    String idDisponibilidad, {
    HorarioDisponibilidad? respaldoHorario,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    final idLimpio = idDisponibilidad.trim();
    if (idLimpio.isEmpty) {
      _mensajeError =
          'Debes indicar el identificador del horario que deseas eliminar.';
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    final actual = _buscarPorId(idLimpio) ?? respaldoHorario;
    if (actual != null && actual.estaProtegidoPorReservaOCita) {
      _mensajeError = 'No se puede eliminar un horario reservado o con historial de citas vinculadas.';
      _mensajeExito = null;
      _notificarSeguro();
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      await _servicio.eliminarHorarioPropio(idLimpio);
      if (_fueDisposed) {
        return false;
      }
      _horarios = _ordenarHorarios(
        _horarios
            .where((item) => item.idDisponibilidad != idLimpio)
            .toList(growable: false),
      );
      _mensajeExito = actual != null
          ? 'Horario ${actual.rangoHorarioTexto} del ${actual.fechaLegible} eliminado correctamente.'
          : 'Horario eliminado correctamente.';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo eliminar el horario seleccionado. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> registrarDiaNoLaborable({
    required DateTime fecha,
    String? motivo,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final registrado = await _servicio.registrarDiaNoLaborablePropio(
        fecha: fecha,
        motivo: motivo,
      );
      if (_fueDisposed) {
        return false;
      }
      final fechaIso = registrado.fechaIso;
      _diasNoLaborablesPorFecha = <String, DiaNoLaborableProfesional>{
        ..._diasNoLaborablesPorFecha,
        fechaIso: registrado,
      };
      // Bloquea los intervalos libres de esa fecha en memoria, conservando los reservados y su historial.
      _horarios = _ordenarHorarios(
        _horarios
            .map((horario) {
              if (horario.fechaIso == fechaIso && horario.esDisponible) {
                return horario.copiarCon(estado: 'bloqueada');
              }
              return horario;
            })
            .toList(growable: false),
      );

      if (registrado.tieneCitasPorGestionar) {
        _mensajeExito =
            'Día no laborable registrado (${registrado.fechaCompletaDia}). '
            'Se bloquearon ${registrado.intervalosBloqueados} horarios libres y tienes '
            '${registrado.citasActivasPorGestionar} cita(s) activa(s) por gestionar en Solicitudes.';
      } else {
        _mensajeExito =
            'Día no laborable registrado (${registrado.fechaCompletaDia}). '
            'Se bloquearon ${registrado.intervalosBloqueados} horario(s) libre(s).';
      }
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError =
            'No se pudo registrar el día no laborable. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<bool> retirarDiaNoLaborable(DateTime fecha) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      await _servicio.retirarDiaNoLaborablePropio(fecha);
      if (_fueDisposed) {
        return false;
      }
      final fechaIso = HorarioDisponibilidad.formatearFechaIso(fecha);
      final copia = Map<String, DiaNoLaborableProfesional>.from(
        _diasNoLaborablesPorFecha,
      )..remove(fechaIso);
      _diasNoLaborablesPorFecha = copia;
      // No se desbloquean automaticamente los intervalos bloqueados para respetar bloqueos manuales.
      _mensajeExito =
          'Se retiró la excepción de día no laborable del ${HorarioDisponibilidad.formatearFechaLegible(fecha)}. '
          'Los horarios bloqueados se conservan hasta que decidas habilitarlos.';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo retirar la excepción de día no laborable. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  Future<VistaPreviaRepeticionSemana?> previsualizarRepeticionSemana({
    required DateTime lunesOrigen,
    required int semanasPosteriores,
  }) async {
    _mensajeError = null;
    _notificarSeguro();

    try {
      final vistaPrevia = await _servicio.previsualizarRepeticionSemanaPropia(
        lunesOrigen: lunesOrigen,
        semanasPosteriores: semanasPosteriores,
      );
      return vistaPrevia;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
        _notificarSeguro();
      }
      return null;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo calcular la vista previa para repetir la semana. Inténtalo nuevamente.';
        _notificarSeguro();
      }
      return null;
    }
  }

  Future<bool> confirmarRepeticionSemana({
    required DateTime lunesOrigen,
    required int semanasPosteriores,
    required String huellaVistaPrevia,
  }) async {
    if (_estaProcesandoAccion) {
      return false;
    }

    _estaProcesandoAccion = true;
    _mensajeError = null;
    _mensajeExito = null;
    _notificarSeguro();

    try {
      final creados = await _servicio.confirmarRepeticionSemanaPropia(
        lunesOrigen: lunesOrigen,
        semanasPosteriores: semanasPosteriores,
        huellaVistaPrevia: huellaVistaPrevia,
      );
      if (_fueDisposed) {
        return false;
      }
      final idsCreados = creados.map((item) => item.idDisponibilidad).toSet();
      _horarios = _ordenarHorarios(<HorarioDisponibilidad>[
        ..._horarios.where(
          (item) => !idsCreados.contains(item.idDisponibilidad),
        ),
        ...creados,
      ]);
      _mensajeExito =
          'Se copiaron ${creados.length} horario(s) disponible(s) en las próximas $semanasPosteriores semana(s).';
      return true;
    } on ErrorDisponibilidadProfesional catch (error) {
      if (!_fueDisposed) {
        _mensajeError = error.mensaje;
      }
      return false;
    } catch (_) {
      if (!_fueDisposed) {
        _mensajeError = 'No se pudo confirmar la repetición de horarios. Inténtalo nuevamente.';
      }
      return false;
    } finally {
      if (!_fueDisposed) {
        _estaProcesandoAccion = false;
        _notificarSeguro();
      }
    }
  }

  HorarioDisponibilidad? _buscarPorId(String idDisponibilidad) {
    for (final horario in _horarios) {
      if (horario.idDisponibilidad == idDisponibilidad) {
        return horario;
      }
    }
    return null;
  }

  void _reemplazarHorarioEnLista(HorarioDisponibilidad actualizado) {
    final reemplazados = <HorarioDisponibilidad>[
      ..._horarios.where(
        (item) => item.idDisponibilidad != actualizado.idDisponibilidad,
      ),
      actualizado,
    ];
    _horarios = _ordenarHorarios(reemplazados);
  }

  List<HorarioDisponibilidad> _ordenarHorarios(
    List<HorarioDisponibilidad> lista,
  ) {
    final copia = List<HorarioDisponibilidad>.from(lista);
    copia.sort((a, b) {
      final comparacionFecha = a.fechaIso.compareTo(b.fechaIso);
      if (comparacionFecha != 0) {
        return comparacionFecha;
      }
      return a.minutosInicio.compareTo(b.minutosInicio);
    });
    return copia;
  }

  void _notificarSeguro() {
    if (!_fueDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _fueDisposed = true;
    super.dispose();
  }
}
