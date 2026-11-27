import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';

/// Secciones de organizacion visual en la pantalla Mis citas del paciente.
enum SeccionMisCitas { proximas, pendientes, historial }

class CitaPaciente {
  const CitaPaciente({
    required this.idCita,
    required this.idPaciente,
    required this.idProfesional,
    required this.idDisponibilidad,
    required this.nombreProfesional,
    required this.especialidadProfesional,
    required this.modalidadProfesional,
    required this.direccionConsultorio,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.fechaSolicitud,
  });

  final String idCita;
  final String idPaciente;
  final String idProfesional;
  final String idDisponibilidad;
  final String nombreProfesional;
  final String especialidadProfesional;
  final String modalidadProfesional;
  final String direccionConsultorio;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;
  final DateTime? fechaSolicitud;

  String get fechaIso => HorarioDisponibilidad.formatearFechaIso(fecha);

  String get fechaLegible => HorarioDisponibilidad.formatearFechaLegible(fecha);

  String get horaInicioNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaInicio);

  String get horaFinNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaFin);

  String get rangoHorarioTexto =>
      '$horaInicioNormalizada - $horaFinNormalizada';

  int get minutosInicio =>
      HorarioDisponibilidad.convertirHoraAMinutos(horaInicio) ?? 0;

  int get minutosFin =>
      HorarioDisponibilidad.convertirHoraAMinutos(horaFin) ?? 0;

  int get duracionMinutos {
    final diferencia = minutosFin - minutosInicio;
    return diferencia > 0 ? diferencia : 0;
  }

  /// Fecha y hora de inicio en hora pared de Ecuador continental (America/Guayaquil).
  DateTime get fechaHoraInicioEcuador {
    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      minutosInicio ~/ 60,
      minutosInicio % 60,
    );
  }

  /// Fecha y hora de finalizacion en hora pared de Ecuador continental (America/Guayaquil).
  DateTime get fechaHoraFinEcuador {
    final minutosCierre = minutosFin > minutosInicio
        ? minutosFin
        : minutosInicio;
    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      minutosCierre ~/ 60,
      minutosCierre % 60,
    );
  }

  bool get esPendiente => estado.trim().toLowerCase() == 'pendiente';

  bool get esConfirmada => estado.trim().toLowerCase() == 'confirmada';

  bool get esRechazada => estado.trim().toLowerCase() == 'rechazada';

  bool get esCancelada => estado.trim().toLowerCase() == 'cancelada';

  bool get esModalidadVirtual =>
      modalidadProfesional.trim().toLowerCase() == 'virtual';

  bool get esModalidadHibrida {
    final limpia = modalidadProfesional.trim().toLowerCase();
    return limpia.contains('híbrid') || limpia.contains('hibrid');
  }

  /// Indica si la direccion fisica debe mostrarse en la tarjeta sin contradecir
  /// la modalidad (en modalidad Virtual no se presenta como lugar de atencion).
  bool get debeMostrarDireccionConsultorio =>
      direccionConsultorio.trim().isNotEmpty && !esModalidadVirtual;

  /// Verdadero cuando la fecha y hora de finalizacion ya pasaron o coinciden con
  /// la hora actual de Ecuador continental (America/Guayaquil).
  bool haFinalizadoEnEcuador({DateTime? referenciaUtc}) {
    final ahoraEcuador = HorarioDisponibilidad.obtenerAhoraEnEcuador(
      referenciaUtc: referenciaUtc,
    );
    return !fechaHoraFinEcuador.isAfter(ahoraEcuador);
  }

  /// Verdadero cuando una cita confirmada se encuentra actualmente en curso
  /// (inicio <= ahora < fin en America/Guayaquil).
  bool estaEnCursoEnEcuador({DateTime? referenciaUtc}) {
    if (!esConfirmada) {
      return false;
    }
    final ahoraEcuador = HorarioDisponibilidad.obtenerAhoraEnEcuador(
      referenciaUtc: referenciaUtc,
    );
    return !ahoraEcuador.isBefore(fechaHoraInicioEcuador) &&
        fechaHoraFinEcuador.isAfter(ahoraEcuador);
  }

  /// Solicitud persistida como 'pendiente' cuyo horario de finalizacion ya vencio.
  /// No altera el estado persistente en Supabase; solo clasificacion visual.
  bool esSolicitudPendienteVencida({DateTime? referenciaUtc}) {
    return esPendiente && haFinalizadoEnEcuador(referenciaUtc: referenciaUtc);
  }

  /// Clasifica la cita en Proximas, Pendientes o Historial segun su estado real
  /// y la hora actual de Ecuador continental (America/Guayaquil).
  SeccionMisCitas clasificarSeccion({DateTime? referenciaUtc}) {
    if (esConfirmada && !haFinalizadoEnEcuador(referenciaUtc: referenciaUtc)) {
      return SeccionMisCitas.proximas;
    }
    if (esPendiente && !haFinalizadoEnEcuador(referenciaUtc: referenciaUtc)) {
      return SeccionMisCitas.pendientes;
    }
    return SeccionMisCitas.historial;
  }

  /// Etiqueta visual del estado considerando vencimiento de solicitudes pendientes
  /// en America/Guayaquil, sin inventar estados como "Completada".
  String etiquetaEstadoEnEcuador({DateTime? referenciaUtc}) {
    if (esSolicitudPendienteVencida(referenciaUtc: referenciaUtc)) {
      return 'Vencida';
    }
    return etiquetaEstado;
  }

  String get etiquetaEstado {
    if (esPendiente) {
      return 'Pendiente de confirmación';
    }
    if (esConfirmada) {
      return 'Confirmada';
    }
    if (esRechazada) {
      return 'Rechazada';
    }
    if (esCancelada) {
      return 'Cancelada';
    }
    return estado;
  }

  String get descripcionEstado {
    if (esPendiente) {
      return 'Tu solicitud fue enviada y está pendiente de revisión del profesional.';
    }
    if (esConfirmada) {
      return 'Cita confirmada por el profesional.';
    }
    if (esRechazada) {
      return 'Esta solicitud no pudo ser atendida por el profesional.';
    }
    if (esCancelada) {
      return 'Esta cita fue cancelada.';
    }
    return '';
  }

  factory CitaPaciente.desdeMapa(Map<String, dynamic> mapa) {
    final fechaCruda = (mapa['fecha'] ?? '').toString().trim();
    final partesFecha = fechaCruda.split('-');
    DateTime fechaParseada;
    if (partesFecha.length >= 3) {
      final anio = int.tryParse(partesFecha[0]) ?? 1970;
      final mes = int.tryParse(partesFecha[1]) ?? 1;
      final dia = int.tryParse(partesFecha[2].substring(0, 2)) ?? 1;
      fechaParseada = DateTime(anio, mes, dia);
    } else {
      final intento = DateTime.tryParse(fechaCruda) ?? DateTime(1970, 1, 1);
      fechaParseada = DateTime(intento.year, intento.month, intento.day);
    }

    final fechaSolicitudCruda = (mapa['fecha_solicitud'] ?? '')
        .toString()
        .trim();
    final fechaSolicitudParseada = fechaSolicitudCruda.isNotEmpty
        ? DateTime.tryParse(fechaSolicitudCruda)
        : null;

    final nombre = (mapa['nombre_profesional'] ?? '').toString().trim();
    final especialidad = (mapa['especialidad_profesional'] ?? '')
        .toString()
        .trim();
    final modalidad = (mapa['modalidad_profesional'] ?? '').toString().trim();
    final direccion = (mapa['direccion_consultorio'] ?? '').toString().trim();

    return CitaPaciente(
      idCita: (mapa['id_cita'] ?? '').toString().trim(),
      idPaciente: (mapa['id_paciente'] ?? '').toString().trim(),
      idProfesional: (mapa['id_profesional'] ?? '').toString().trim(),
      idDisponibilidad: (mapa['id_disponibilidad'] ?? '').toString().trim(),
      nombreProfesional: nombre.isNotEmpty ? nombre : 'Profesional PsicoBloom',
      especialidadProfesional: especialidad.isNotEmpty
          ? especialidad
          : 'Psicología General',
      modalidadProfesional: modalidad.isNotEmpty ? modalidad : 'Presencial',
      direccionConsultorio: direccion,
      fecha: fechaParseada,
      horaInicio: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_inicio'] ?? '').toString(),
      ),
      horaFin: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_fin'] ?? '').toString(),
      ),
      estado: (mapa['estado'] ?? 'pendiente').toString().trim().toLowerCase(),
      fechaSolicitud: fechaSolicitudParseada,
    );
  }
}
