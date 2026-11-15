class HorarioDisponibilidad {
  const HorarioDisponibilidad({
    required this.idDisponibilidad,
    required this.idProfesional,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.tieneCitaVinculada = false,
  });

  final String idDisponibilidad;
  final String idProfesional;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;
  final bool tieneCitaVinculada;

  static const Duration desfaseEcuadorUtc = Duration(hours: -5);
  static const int maximoIntervalosPorOperacion = 24;

  /// Obtiene la fecha y hora pared en zona horaria America/Guayaquil (UTC-05:00).
  static DateTime obtenerAhoraEnEcuador({DateTime? referenciaUtc}) {
    final ahoraUtc = (referenciaUtc ?? DateTime.now().toUtc()).toUtc();
    final desplazada = ahoraUtc.add(desfaseEcuadorUtc);
    return DateTime(
      desplazada.year,
      desplazada.month,
      desplazada.day,
      desplazada.hour,
      desplazada.minute,
      desplazada.second,
    );
  }

  static DateTime normalizarFechaSoloDia(DateTime valor) {
    return DateTime(valor.year, valor.month, valor.day);
  }

  static DateTime parsearFechaIso(String fechaCruda) {
    final limpio = fechaCruda.trim();
    final partesFecha = limpio.split('-');
    if (partesFecha.length >= 3) {
      final anio = int.tryParse(partesFecha[0]) ?? 1970;
      final mes = int.tryParse(partesFecha[1]) ?? 1;
      final diaTexto = partesFecha[2].length >= 2
          ? partesFecha[2].substring(0, 2)
          : partesFecha[2];
      final dia = int.tryParse(diaTexto) ?? 1;
      return DateTime(anio, mes, dia);
    }
    final intento = DateTime.tryParse(limpio) ?? DateTime(1970, 1, 1);
    return DateTime(intento.year, intento.month, intento.day);
  }

  /// Devuelve el lunes (inicio de semana) correspondiente a [fecha].
  static DateTime obtenerLunesDeSemana(DateTime fecha) {
    final limpia = normalizarFechaSoloDia(fecha);
    final diasDesdeLunes = limpia.weekday - DateTime.monday;
    return DateTime(limpia.year, limpia.month, limpia.day - diasDesdeLunes);
  }

  /// Devuelve las 7 fechas de la semana de lunes a domingo a partir de [fechaReferencia].
  static List<DateTime> obtenerDiasDeSemana(DateTime fechaReferencia) {
    final lunes = obtenerLunesDeSemana(fechaReferencia);
    return List<DateTime>.generate(
      7,
      (indice) => DateTime(lunes.year, lunes.month, lunes.day + indice),
      growable: false,
    );
  }

  static String formatearFechaIso(DateTime valor) {
    final anio = valor.year.toString().padLeft(4, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final dia = valor.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }

  static String formatearNombreDiaSemana(DateTime valor) {
    const nombresDias = <int, String>{
      DateTime.monday: 'Lunes',
      DateTime.tuesday: 'Martes',
      DateTime.wednesday: 'Miércoles',
      DateTime.thursday: 'Jueves',
      DateTime.friday: 'Viernes',
      DateTime.saturday: 'Sábado',
      DateTime.sunday: 'Domingo',
    };
    return nombresDias[valor.weekday] ?? '';
  }

  static String formatearNombreDiaMinuscula(DateTime valor) {
    return formatearNombreDiaSemana(valor).toLowerCase();
  }

  static String formatearDiaCortoConNumero(DateTime valor) {
    return '${formatearNombreDiaSemana(valor)} ${valor.day}';
  }

  static String formatearFechaLegible(DateTime valor) {
    const nombresMeses = <int, String>{
      1: 'ene',
      2: 'feb',
      3: 'mar',
      4: 'abr',
      5: 'may',
      6: 'jun',
      7: 'jul',
      8: 'ago',
      9: 'sep',
      10: 'oct',
      11: 'nov',
      12: 'dic',
    };
    final diaSemana = formatearNombreDiaSemana(valor);
    final diaMes = valor.day.toString().padLeft(2, '0');
    final mes = nombresMeses[valor.month] ?? '';
    return '$diaSemana $diaMes $mes ${valor.year}';
  }

  /// Formato completo con día y fecha: "Lunes, 16 de noviembre de 2026".
  static String formatearFechaCompletaDia(DateTime valor) {
    const nombresMesesLargos = <int, String>{
      1: 'enero',
      2: 'febrero',
      3: 'marzo',
      4: 'abril',
      5: 'mayo',
      6: 'junio',
      7: 'julio',
      8: 'agosto',
      9: 'septiembre',
      10: 'octubre',
      11: 'noviembre',
      12: 'diciembre',
    };
    final diaSemana = formatearNombreDiaSemana(valor);
    final mes = nombresMesesLargos[valor.month] ?? '';
    return '$diaSemana, ${valor.day} de $mes de ${valor.year}';
  }

  /// Formato para el selector semanal: "16 nov – 22 nov 2026".
  static String formatearRangoSemana(DateTime fechaReferencia) {
    const nombresMesesCortos = <int, String>{
      1: 'ene',
      2: 'feb',
      3: 'mar',
      4: 'abr',
      5: 'may',
      6: 'jun',
      7: 'jul',
      8: 'ago',
      9: 'sep',
      10: 'oct',
      11: 'nov',
      12: 'dic',
    };
    final lunes = obtenerLunesDeSemana(fechaReferencia);
    final domingo = DateTime(lunes.year, lunes.month, lunes.day + 6);
    final mesLunes = nombresMesesCortos[lunes.month] ?? '';
    final mesDomingo = nombresMesesCortos[domingo.month] ?? '';
    if (lunes.year != domingo.year) {
      return '${lunes.day} $mesLunes ${lunes.year} – ${domingo.day} $mesDomingo ${domingo.year}';
    }
    return '${lunes.day} $mesLunes – ${domingo.day} $mesDomingo ${domingo.year}';
  }

  static String normalizarHoraTexto(String valor) {
    final limpio = valor.trim();
    final partes = limpio.split(':');
    if (partes.length < 2) {
      return limpio;
    }
    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return limpio;
    }
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  static int? convertirHoraAMinutos(String valor) {
    final limpio = valor.trim();
    final partes = limpio.split(':');
    if (partes.length < 2) {
      return null;
    }
    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return null;
    }
    return (horas * 60) + minutos;
  }

  static String formatearHoraDesdeMinutos(int totalMinutos) {
    final ajustado = totalMinutos.clamp(0, (23 * 60) + 59);
    final horas = (ajustado ~/ 60).toString().padLeft(2, '0');
    final minutos = (ajustado % 60).toString().padLeft(2, '0');
    return '$horas:$minutos';
  }

  /// Genera la secuencia de intervalos completos dentro de una jornada [horaInicioJornada]..[horaFinJornada]
  /// con duración [duracionMinutos] y descanso [descansoMinutos] entre citas, sin generar intervalos
  /// incompletos en el tiempo sobrante.
  static List<IntervaloHorarioPropuesto> generarIntervalosJornada({
    required String horaInicioJornada,
    required String horaFinJornada,
    required int duracionMinutos,
    required int descansoMinutos,
    DateTime? fecha,
    List<HorarioDisponibilidad> horariosExistentesEnFecha =
        const <HorarioDisponibilidad>[],
  }) {
    final inicioMin = convertirHoraAMinutos(horaInicioJornada);
    final finMin = convertirHoraAMinutos(horaFinJornada);
    if (inicioMin == null ||
        finMin == null ||
        finMin <= inicioMin ||
        duracionMinutos <= 0 ||
        descansoMinutos < 0) {
      return const <IntervaloHorarioPropuesto>[];
    }

    final fechaComparacion = fecha != null
        ? normalizarFechaSoloDia(fecha)
        : null;
    final resultado = <IntervaloHorarioPropuesto>[];
    var cursor = inicioMin;

    while (cursor + duracionMinutos <= finMin) {
      final finIntervalo = cursor + duracionMinutos;
      final inicioTexto = formatearHoraDesdeMinutos(cursor);
      final finTexto = formatearHoraDesdeMinutos(finIntervalo);

      HorarioDisponibilidad? existenteEnConflicto;
      for (final existente in horariosExistentesEnFecha) {
        if (fechaComparacion != null) {
          if (existente.seSuperponeCon(
            otraFecha: fechaComparacion,
            otroInicioMinutos: cursor,
            otroFinMinutos: finIntervalo,
          )) {
            existenteEnConflicto = existente;
            break;
          }
        } else {
          if (existente.minutosInicio < finIntervalo &&
              existente.minutosFin > cursor) {
            existenteEnConflicto = existente;
            break;
          }
        }
      }

      resultado.add(
        IntervaloHorarioPropuesto(
          horaInicio: inicioTexto,
          horaFin: finTexto,
          enConflicto: existenteEnConflicto != null,
          motivoConflicto: existenteEnConflicto != null
              ? 'Se superpone con ${existenteEnConflicto.rangoHorarioCompacto} (${existenteEnConflicto.etiquetaEstado.toLowerCase()})'
              : null,
        ),
      );

      cursor = finIntervalo + descansoMinutos;
    }

    return resultado;
  }

  static bool esIntervaloEnFuturoEcuador({
    required DateTime fecha,
    required String horaInicio,
    DateTime? referenciaUtc,
  }) {
    final minutos = convertirHoraAMinutos(horaInicio);
    if (minutos == null) {
      return false;
    }
    final ahoraEcuador = obtenerAhoraEnEcuador(referenciaUtc: referenciaUtc);
    final inicioIntervalo = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      minutos ~/ 60,
      minutos % 60,
    );
    return inicioIntervalo.isAfter(ahoraEcuador);
  }

  String get fechaIso => formatearFechaIso(fecha);

  String get fechaLegible => formatearFechaLegible(fecha);

  String get fechaCompletaDia => formatearFechaCompletaDia(fecha);

  String get horaInicioNormalizada => normalizarHoraTexto(horaInicio);

  String get horaFinNormalizada => normalizarHoraTexto(horaFin);

  String get rangoHorarioTexto =>
      '$horaInicioNormalizada - $horaFinNormalizada';

  /// Formato compacto solicitado para las tarjetas semanales: "09:00–10:00".
  String get rangoHorarioCompacto =>
      '$horaInicioNormalizada–$horaFinNormalizada';

  int get minutosInicio => convertirHoraAMinutos(horaInicio) ?? 0;

  int get minutosFin => convertirHoraAMinutos(horaFin) ?? 0;

  int get duracionMinutos {
    final diferencia = minutosFin - minutosInicio;
    return diferencia > 0 ? diferencia : 0;
  }

  bool get esDisponible => estado.trim().toLowerCase() == 'disponible';

  bool get esReservada => estado.trim().toLowerCase() == 'reservada';

  bool get esBloqueada => estado.trim().toLowerCase() == 'bloqueada';

  bool get estaProtegidoPorReservaOCita => esReservada || tieneCitaVinculada;

  /// Solo se permite eliminar intervalos propios sin ninguna cita vinculada ni reserva.
  bool get puedeEliminar => !estaProtegidoPorReservaOCita;

  String get etiquetaEstado {
    if (esReservada) {
      return 'Reservado';
    }
    if (esBloqueada) {
      return 'Bloqueado';
    }
    return 'Disponible';
  }

  bool esFuturoEnEcuador({DateTime? referenciaUtc}) {
    return esIntervaloEnFuturoEcuador(
      fecha: fecha,
      horaInicio: horaInicio,
      referenciaUtc: referenciaUtc,
    );
  }

  bool puedeEditar({DateTime? referenciaUtc, bool esDiaNoLaborable = false}) {
    return !esDiaNoLaborable &&
        esDisponible &&
        !tieneCitaVinculada &&
        esFuturoEnEcuador(referenciaUtc: referenciaUtc);
  }

  bool puedeCambiarBloqueo({
    DateTime? referenciaUtc,
    bool esDiaNoLaborable = false,
  }) {
    if (esReservada || !esFuturoEnEcuador(referenciaUtc: referenciaUtc)) {
      return false;
    }
    // En un dia no laborable no se permite desbloquear horarios mientras la excepcion siga activa.
    if (esDiaNoLaborable && esBloqueada) {
      return false;
    }
    return esDisponible || esBloqueada;
  }

  bool seSuperponeCon({
    required DateTime otraFecha,
    required int otroInicioMinutos,
    required int otroFinMinutos,
  }) {
    final mismaFecha =
        fecha.year == otraFecha.year &&
        fecha.month == otraFecha.month &&
        fecha.day == otraFecha.day;
    if (!mismaFecha) {
      return false;
    }
    // Intervalos contiguos (ej. 09:00-10:00 y 10:00-11:00) no se superponen.
    return minutosInicio < otroFinMinutos && minutosFin > otroInicioMinutos;
  }

  HorarioDisponibilidad copiarCon({
    String? idDisponibilidad,
    String? idProfesional,
    DateTime? fecha,
    String? horaInicio,
    String? horaFin,
    String? estado,
    bool? tieneCitaVinculada,
  }) {
    return HorarioDisponibilidad(
      idDisponibilidad: idDisponibilidad ?? this.idDisponibilidad,
      idProfesional: idProfesional ?? this.idProfesional,
      fecha: fecha != null ? normalizarFechaSoloDia(fecha) : this.fecha,
      horaInicio: horaInicio != null
          ? normalizarHoraTexto(horaInicio)
          : this.horaInicio,
      horaFin: horaFin != null ? normalizarHoraTexto(horaFin) : this.horaFin,
      estado: estado ?? this.estado,
      tieneCitaVinculada: tieneCitaVinculada ?? this.tieneCitaVinculada,
    );
  }

  factory HorarioDisponibilidad.desdeMapa(Map<String, dynamic> mapa) {
    final fechaCruda = (mapa['fecha'] ?? '').toString().trim();
    final fechaParseada = parsearFechaIso(fechaCruda);

    return HorarioDisponibilidad(
      idDisponibilidad: (mapa['id_disponibilidad'] ?? '').toString().trim(),
      idProfesional: (mapa['id_profesional'] ?? '').toString().trim(),
      fecha: fechaParseada,
      horaInicio: normalizarHoraTexto((mapa['hora_inicio'] ?? '').toString()),
      horaFin: normalizarHoraTexto((mapa['hora_fin'] ?? '').toString()),
      estado: (mapa['estado'] ?? 'disponible').toString().trim().toLowerCase(),
      tieneCitaVinculada: mapa['tiene_cita_vinculada'] == true,
    );
  }
}

class IntervaloHorarioPropuesto {
  const IntervaloHorarioPropuesto({
    required this.horaInicio,
    required this.horaFin,
    this.enConflicto = false,
    this.motivoConflicto,
  });

  final String horaInicio;
  final String horaFin;
  final bool enConflicto;
  final String? motivoConflicto;

  String get horaInicioNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaInicio);

  String get horaFinNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaFin);

  String get rangoCompacto => '$horaInicioNormalizada–$horaFinNormalizada';

  String get rangoTexto => '$horaInicioNormalizada - $horaFinNormalizada';

  int get duracionMinutos {
    final inicio =
        HorarioDisponibilidad.convertirHoraAMinutos(horaInicioNormalizada) ?? 0;
    final fin =
        HorarioDisponibilidad.convertirHoraAMinutos(horaFinNormalizada) ?? 0;
    return fin > inicio ? fin - inicio : 0;
  }
}

class DiaNoLaborableProfesional {
  const DiaNoLaborableProfesional({
    required this.idDiaNoLaborable,
    required this.idProfesional,
    required this.fecha,
    required this.motivo,
    this.intervalosBloqueados = 0,
    this.citasPendientes = 0,
    this.citasConfirmadas = 0,
  });

  final String idDiaNoLaborable;
  final String idProfesional;
  final DateTime fecha;
  final String motivo;
  final int intervalosBloqueados;
  final int citasPendientes;
  final int citasConfirmadas;

  String get fechaIso => HorarioDisponibilidad.formatearFechaIso(fecha);

  String get fechaCompletaDia =>
      HorarioDisponibilidad.formatearFechaCompletaDia(fecha);

  int get citasActivasPorGestionar => citasPendientes + citasConfirmadas;

  bool get tieneCitasPorGestionar => citasActivasPorGestionar > 0;

  factory DiaNoLaborableProfesional.desdeMapa(Map<String, dynamic> mapa) {
    final fechaCruda = (mapa['fecha'] ?? '').toString().trim();
    return DiaNoLaborableProfesional(
      idDiaNoLaborable: (mapa['id_dia_no_laborable'] ?? '').toString().trim(),
      idProfesional: (mapa['id_profesional'] ?? '').toString().trim(),
      fecha: HorarioDisponibilidad.parsearFechaIso(fechaCruda),
      motivo: (mapa['motivo'] ?? '').toString().trim(),
      intervalosBloqueados:
          int.tryParse((mapa['intervalos_bloqueados'] ?? '0').toString()) ?? 0,
      citasPendientes:
          int.tryParse((mapa['citas_pendientes'] ?? '0').toString()) ?? 0,
      citasConfirmadas:
          int.tryParse((mapa['citas_confirmadas'] ?? '0').toString()) ?? 0,
    );
  }
}

class ItemVistaPreviaRepeticionSemana {
  const ItemVistaPreviaRepeticionSemana({
    required this.semanaOffset,
    required this.fechaOrigen,
    required this.fechaDestino,
    required this.horaInicio,
    required this.horaFin,
    required this.accion,
    required this.motivo,
    required this.huellaVistaPrevia,
  });

  final int semanaOffset;
  final DateTime fechaOrigen;
  final DateTime fechaDestino;
  final String horaInicio;
  final String horaFin;
  final String accion;
  final String motivo;
  final String huellaVistaPrevia;

  bool get esCrear => accion.trim().toLowerCase() == 'crear';

  bool get esOmitido => !esCrear;

  String get fechaDestinoIso =>
      HorarioDisponibilidad.formatearFechaIso(fechaDestino);

  String get fechaDestinoLegible =>
      HorarioDisponibilidad.formatearFechaLegible(fechaDestino);

  String get fechaDestinoCompletaDia =>
      HorarioDisponibilidad.formatearFechaCompletaDia(fechaDestino);

  String get horaInicioNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaInicio);

  String get horaFinNormalizada =>
      HorarioDisponibilidad.normalizarHoraTexto(horaFin);

  String get rangoHorarioCompacto =>
      '$horaInicioNormalizada–$horaFinNormalizada';

  factory ItemVistaPreviaRepeticionSemana.desdeMapa(Map<String, dynamic> mapa) {
    return ItemVistaPreviaRepeticionSemana(
      semanaOffset:
          int.tryParse((mapa['semana_offset'] ?? '1').toString()) ?? 1,
      fechaOrigen: HorarioDisponibilidad.parsearFechaIso(
        (mapa['fecha_origen'] ?? '').toString(),
      ),
      fechaDestino: HorarioDisponibilidad.parsearFechaIso(
        (mapa['fecha_destino'] ?? '').toString(),
      ),
      horaInicio: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_inicio'] ?? '').toString(),
      ),
      horaFin: HorarioDisponibilidad.normalizarHoraTexto(
        (mapa['hora_fin'] ?? '').toString(),
      ),
      accion: (mapa['accion'] ?? 'omitido').toString().trim().toLowerCase(),
      motivo: (mapa['motivo'] ?? '').toString().trim(),
      huellaVistaPrevia: (mapa['huella_vista_previa'] ?? '').toString().trim(),
    );
  }
}

class VistaPreviaRepeticionSemana {
  const VistaPreviaRepeticionSemana({
    required this.lunesOrigen,
    required this.semanasPosteriores,
    required this.huellaVistaPrevia,
    required this.items,
  });

  final DateTime lunesOrigen;
  final int semanasPosteriores;
  final String huellaVistaPrevia;
  final List<ItemVistaPreviaRepeticionSemana> items;

  List<ItemVistaPreviaRepeticionSemana> get itemsACrear =>
      items.where((item) => item.esCrear).toList(growable: false);

  List<ItemVistaPreviaRepeticionSemana> get itemsOmitidos =>
      items.where((item) => item.esOmitido).toList(growable: false);

  int get totalCrear => itemsACrear.length;

  int get totalOmitidos => itemsOmitidos.length;

  bool get tieneIntervalosParaCrear => totalCrear > 0;
}
