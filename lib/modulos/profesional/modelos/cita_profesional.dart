import 'horario_disponibilidad.dart';

enum FiltroEstadoCitaProfesional {
  pendientes('pendiente', 'Pendientes'),
  confirmadas('confirmada', 'Confirmadas'),
  rechazadas('rechazada', 'Rechazadas');

  const FiltroEstadoCitaProfesional(this.valorEstado, this.etiqueta);

  final String valorEstado;
  final String etiqueta;
}

class CitaProfesional {
  const CitaProfesional({
    required this.idCita,
    required this.idPaciente,
    required this.idProfesional,
    required this.idDisponibilidad,
    required this.nombrePaciente,
    required this.modalidadProfesional,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.estadoDisponibilidad = 'reservada',
    this.fechaSolicitud,
  });

  final String idCita;
  final String idPaciente;
  final String idProfesional;
  final String idDisponibilidad;
  final String nombrePaciente;
  final String modalidadProfesional;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;
  final String estadoDisponibilidad;
  final DateTime? fechaSolicitud;

  String get fechaIso => HorarioDisponibilidad.formatearFechaIso(fecha);

  String get fechaLegible => HorarioDisponibilidad.formatearFechaLegible(fecha);

  String get horaInicioNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaInicio);

  String get horaFinNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaFin);

  String get rangoHorarioTexto =>
      '$horaInicioNormalizada - $horaFinNormalizada';

  /// Formato compacto de intervalo: "09:00–10:00".
  String get rangoHorarioCompacto =>
      '$horaInicioNormalizada–$horaFinNormalizada';

  int get minutosInicio =>
      HorarioDisponibilidad.convertirHoraAMinutos(horaInicio) ?? 0;

  int get minutosFin =>
      HorarioDisponibilidad.convertirHoraAMinutos(horaFin) ?? 0;

  int get duracionMinutos {
    final diferencia = minutosFin - minutosInicio;
    return diferencia > 0 ? diferencia : 0;
  }

  bool get esPendiente => estado.trim().toLowerCase() == 'pendiente';

  bool get esConfirmada => estado.trim().toLowerCase() == 'confirmada';

  bool get esRechazada => estado.trim().toLowerCase() == 'rechazada';

  bool get esCancelada => estado.trim().toLowerCase() == 'cancelada';

  String get etiquetaEstado {
    if (esPendiente) {
      return 'Pendiente';
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

  bool esFuturoEnEcuador({DateTime? referenciaUtc}) {
    return HorarioDisponibilidad.esIntervaloEnFuturoEcuador(
      fecha: fecha,
      horaInicio: horaInicio,
      referenciaUtc: referenciaUtc,
    );
  }

  bool puedeResponder({DateTime? referenciaUtc}) {
    return esPendiente && esFuturoEnEcuador(referenciaUtc: referenciaUtc);
  }

  factory CitaProfesional.desdeMapa(Map<String, dynamic> mapa) {
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

    final nombre = (mapa['nombre_paciente'] ?? '').toString().trim();
    final modalidad = (mapa['modalidad_profesional'] ?? '').toString().trim();
    final estadoDisp = (mapa['estado_disponibilidad'] ?? 'reservada')
        .toString()
        .trim()
        .toLowerCase();

    return CitaProfesional(
      idCita: (mapa['id_cita'] ?? '').toString().trim(),
      idPaciente: (mapa['id_paciente'] ?? '').toString().trim(),
      idProfesional: (mapa['id_profesional'] ?? '').toString().trim(),
      idDisponibilidad: (mapa['id_disponibilidad'] ?? '').toString().trim(),
      nombrePaciente: nombre.isNotEmpty ? nombre : 'Paciente PsicoBloom',
      modalidadProfesional: modalidad.isNotEmpty ? modalidad : 'Presencial',
      fecha: fechaParseada,
      horaInicio: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_inicio'] ?? '').toString(),
      ),
      horaFin: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_fin'] ?? '').toString(),
      ),
      estado: (mapa['estado'] ?? 'pendiente').toString().trim().toLowerCase(),
      estadoDisponibilidad: estadoDisp.isNotEmpty ? estadoDisp : 'reservada',
      fechaSolicitud: fechaSolicitudParseada,
    );
  }
}
