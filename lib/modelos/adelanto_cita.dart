import 'package:boom/modulos/paciente/modelos/info_economica_profesional.dart';

/// Conjunto cerrado de estados validos del flujo de adelantos.
const Set<String> estadosAdelantoValidos = {
  'pendiente_aceptacion',
  'pendiente_adelanto',
  'comprobante_en_revision',
  'observado',
  'verificado',
  'vencido_sin_pago',
  'incidencia_pago',
  'rechazado_sin_pago',
  'cancelado',
};

/// Formatea una fecha/hora UTC a texto legible en zona horaria de Ecuador
/// continental (America/Guayaquil, UTC-05:00).
String formatearFechaHoraEcuador(DateTime fechaUtc) {
  final ecuador = fechaUtc.toUtc().subtract(const Duration(hours: 5));
  final dia = ecuador.day.toString().padLeft(2, '0');
  final mes = ecuador.month.toString().padLeft(2, '0');
  final anio = ecuador.year.toString();
  final hora = ecuador.hour.toString().padLeft(2, '0');
  final minuto = ecuador.minute.toString().padLeft(2, '0');
  return '$dia/$mes/$anio $hora:$minuto (Ecuador)';
}

/// Etiqueta visible en español para el estado del adelanto.
String etiquetaVisibleEstadoAdelanto(
  String estadoAdelanto, {
  bool revisionDemorada = false,
}) {
  if (estadoAdelanto == 'comprobante_en_revision' && revisionDemorada) {
    return 'Revisión demorada';
  }
  switch (estadoAdelanto) {
    case 'pendiente_aceptacion':
      return 'Pendiente de aceptación';
    case 'pendiente_adelanto':
      return 'Pendiente de adelanto';
    case 'comprobante_en_revision':
      return 'Comprobante en revisión';
    case 'observado':
      return 'Comprobante observado';
    case 'verificado':
      return 'Adelanto verificado';
    case 'vencido_sin_pago':
      return 'Vencida sin pago';
    case 'incidencia_pago':
      return 'Incidencia de pago en revisión';
    case 'cancelado':
      return 'Cita cancelada · consultar devolución';
    case 'rechazado_sin_pago':
      return 'Solicitud rechazada';
    default:
      return estadoAdelanto;
  }
}

/// Valida estrictamente los campos monetarios e identificadores de un adelanto.
/// Nunca convierte importes invalidos en 0 ni reconstruye un saldo faltante.
({
  String idCita,
  String estadoAdelanto,
  String moneda,
  int precioCentavos,
  int adelantoCentavos,
  int saldoCentavos,
})
_validarCabeceraAdelanto(Map<String, dynamic> datos) {
  final idCita = (datos['id_cita'] as String?)?.trim() ?? '';
  if (idCita.isEmpty) {
    throw const FormatException('Falta el identificador de la cita.');
  }

  final estado = (datos['estado_adelanto'] as String?)?.trim() ?? '';
  if (!estadosAdelantoValidos.contains(estado)) {
    throw FormatException('Estado de adelanto no reconocido: $estado.');
  }

  final moneda = (datos['moneda'] as String?)?.trim() ?? '';
  if (moneda != 'USD') {
    throw const FormatException('La moneda del adelanto debe ser USD.');
  }

  final precio = InfoEconomicaProfesional.parsearCentavos(
    datos['precio_consulta'],
  );
  if (precio == null ||
      precio < InfoEconomicaProfesional.centavosMinimosUsd ||
      precio > InfoEconomicaProfesional.centavosMaximosUsd) {
    throw const FormatException('El precio de la consulta es inválido.');
  }

  final adelanto = InfoEconomicaProfesional.parsearCentavos(
    datos['monto_adelanto'],
  );
  if (adelanto == null ||
      adelanto < InfoEconomicaProfesional.centavosMinimosUsd ||
      adelanto > InfoEconomicaProfesional.centavosMaximosUsd ||
      adelanto > precio) {
    throw const FormatException('El monto del adelanto es inválido.');
  }

  final saldo = InfoEconomicaProfesional.parsearCentavos(
    datos['saldo_despues_adelanto'],
  );
  if (saldo == null || saldo != (precio - adelanto)) {
    throw const FormatException(
      'El saldo informado no coincide con el precio menos el adelanto.',
    );
  }

  return (
    idCita: idCita,
    estadoAdelanto: estado,
    moneda: moneda,
    precioCentavos: precio,
    adelantoCentavos: adelanto,
    saldoCentavos: saldo,
  );
}

/// Resumen liviano del estado de adelanto de una cita (apto para listados de
/// paciente, profesional y supervision del administrador sin datos bancarios ni QR).
class ResumenAdelantoCita {
  final String idCita;
  final String estadoAdelanto;
  final String moneda;
  final int precioConsultaCentavos;
  final int montoAdelantoCentavos;
  final int saldoDespuesAdelantoCentavos;
  final DateTime? limitePagoEn;
  final DateTime? comprobanteEnviadoEn;
  final DateTime? limiteRevisionEn;
  final bool revisionDemorada;
  final DateTime? verificadoEn;
  final bool tieneIncidencia;
  final int totalComprobantes;

  const ResumenAdelantoCita({
    required this.idCita,
    required this.estadoAdelanto,
    this.moneda = 'USD',
    required this.precioConsultaCentavos,
    required this.montoAdelantoCentavos,
    required this.saldoDespuesAdelantoCentavos,
    this.limitePagoEn,
    this.comprobanteEnviadoEn,
    this.limiteRevisionEn,
    this.revisionDemorada = false,
    this.verificadoEn,
    this.tieneIncidencia = false,
    this.totalComprobantes = 0,
  });

  String get etiquetaEstado => etiquetaVisibleEstadoAdelanto(
    estadoAdelanto,
    revisionDemorada: revisionDemorada,
  );

  String get textoPrecioConsulta =>
      InfoEconomicaProfesional.formatearCentavosUsd(precioConsultaCentavos);

  String get textoMontoAdelanto =>
      InfoEconomicaProfesional.formatearCentavosUsd(montoAdelantoCentavos);

  String get textoSaldo => InfoEconomicaProfesional.formatearCentavosUsd(
    saldoDespuesAdelantoCentavos,
  );

  String? get textoLimitePagoEcuador =>
      limitePagoEn != null ? formatearFechaHoraEcuador(limitePagoEn!) : null;

  bool get requiereAccionPaciente =>
      estadoAdelanto == 'pendiente_adelanto' || estadoAdelanto == 'observado';

  bool get requiereRevisionProfesional =>
      estadoAdelanto == 'comprobante_en_revision' ||
      estadoAdelanto == 'incidencia_pago';

  factory ResumenAdelantoCita.desdeMapa(Map<String, dynamic> datos) {
    final base = _validarCabeceraAdelanto(datos);
    final revisionDemoradaRaw = datos['revision_demorada'];
    final tieneIncidenciaRaw = datos['tiene_incidencia'];
    final totalCompRaw = datos['total_comprobantes'];

    if (revisionDemoradaRaw != null && revisionDemoradaRaw is! bool) {
      throw const FormatException('Indicador revision_demorada inválido.');
    }
    if (tieneIncidenciaRaw != null && tieneIncidenciaRaw is! bool) {
      throw const FormatException('Indicador tiene_incidencia inválido.');
    }
    if (totalCompRaw != null && (totalCompRaw is! num || totalCompRaw < 0)) {
      throw const FormatException('Total de comprobantes inválido.');
    }

    return ResumenAdelantoCita(
      idCita: base.idCita,
      estadoAdelanto: base.estadoAdelanto,
      moneda: base.moneda,
      precioConsultaCentavos: base.precioCentavos,
      montoAdelantoCentavos: base.adelantoCentavos,
      saldoDespuesAdelantoCentavos: base.saldoCentavos,
      limitePagoEn: _parsearFecha(datos['limite_pago_en']),
      comprobanteEnviadoEn: _parsearFecha(datos['comprobante_enviado_en']),
      limiteRevisionEn: _parsearFecha(datos['limite_revision_en']),
      revisionDemorada: revisionDemoradaRaw as bool? ?? false,
      verificadoEn: _parsearFecha(datos['verificado_en']),
      tieneIncidencia: tieneIncidenciaRaw as bool? ?? false,
      totalComprobantes: (totalCompRaw as num?)?.toInt() ?? 0,
    );
  }
}

class ComprobanteAdelanto {
  final String idComprobante;
  final String rutaStorage;
  final String? notaPaciente;
  final DateTime? creadoEn;

  const ComprobanteAdelanto({
    required this.idComprobante,
    required this.rutaStorage,
    this.notaPaciente,
    this.creadoEn,
  });

  factory ComprobanteAdelanto.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id_comprobante'] as String?)?.trim() ?? '';
    final ruta = (datos['ruta_storage'] as String?)?.trim() ?? '';
    if (id.isEmpty || ruta.isEmpty) {
      throw const FormatException('Registro de comprobante incompleto.');
    }
    return ComprobanteAdelanto(
      idComprobante: id,
      rutaStorage: ruta,
      notaPaciente: (datos['nota_paciente'] as String?)?.trim(),
      creadoEn: _parsearFecha(datos['creado_en']),
    );
  }
}

class ObservacionAdelanto {
  final String idObservacion;
  final String tipoActor;
  final String mensaje;
  final DateTime? creadoEn;

  const ObservacionAdelanto({
    required this.idObservacion,
    required this.tipoActor,
    required this.mensaje,
    this.creadoEn,
  });

  factory ObservacionAdelanto.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id_observacion'] as String?)?.trim() ?? '';
    final actor = (datos['tipo_actor'] as String?)?.trim() ?? '';
    final mensaje = (datos['mensaje'] as String?)?.trim() ?? '';
    if (id.isEmpty ||
        (actor != 'profesional' && actor != 'paciente') ||
        mensaje.isEmpty) {
      throw const FormatException('Registro de observación inválido.');
    }
    return ObservacionAdelanto(
      idObservacion: id,
      tipoActor: actor,
      mensaje: mensaje,
      creadoEn: _parsearFecha(datos['creado_en']),
    );
  }
}

/// Etiqueta visible en español para el estado de una incidencia de carga.
/// Evita exponer códigos internos como `pendiente_revision`.
String etiquetaVisibleEstadoIncidencia(String estadoIncidencia) {
  switch (estadoIncidencia.trim()) {
    case 'pendiente_revision':
      return 'Pendiente de revisión';
    case 'en_revision':
      return 'En revisión';
    case 'resuelta':
      return 'Resuelta';
    default:
      return 'Pendiente de revisión';
  }
}

class IncidenciaAdelanto {
  final String idIncidencia;
  final String detalle;
  final bool horarioYaLiberado;
  final String estadoIncidencia;
  final DateTime? creadoEn;
  final String? motivoResolucion;
  final String? resueltoPor;
  final DateTime? resueltoEn;

  const IncidenciaAdelanto({
    required this.idIncidencia,
    required this.detalle,
    required this.horarioYaLiberado,
    required this.estadoIncidencia,
    this.creadoEn,
    this.motivoResolucion,
    this.resueltoPor,
    this.resueltoEn,
  });

  bool get estaResuelta => estadoIncidencia == 'resuelta';

  bool get estaAbierta => !estaResuelta;

  String get etiquetaEstado =>
      etiquetaVisibleEstadoIncidencia(estadoIncidencia);

  String? get textoResueltoEnEcuador =>
      resueltoEn != null ? formatearFechaHoraEcuador(resueltoEn!) : null;

  factory IncidenciaAdelanto.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id_incidencia'] as String?)?.trim() ?? '';
    final detalle = (datos['detalle'] as String?)?.trim() ?? '';
    final estado = (datos['estado_incidencia'] as String?)?.trim() ?? '';
    const estadosValidos = {'pendiente_revision', 'en_revision', 'resuelta'};
    if (id.isEmpty || detalle.isEmpty || !estadosValidos.contains(estado)) {
      throw const FormatException('Registro de incidencia inválido.');
    }
    final motivo = (datos['motivo_resolucion'] as String?)?.trim();
    final resueltoPor = (datos['resuelto_por'] as String?)?.trim();
    return IncidenciaAdelanto(
      idIncidencia: id,
      detalle: detalle,
      horarioYaLiberado: datos['horario_ya_liberado'] as bool? ?? false,
      estadoIncidencia: estado,
      creadoEn: _parsearFecha(datos['creado_en']),
      motivoResolucion: (motivo != null && motivo.isNotEmpty) ? motivo : null,
      resueltoPor: (resueltoPor != null && resueltoPor.isNotEmpty)
          ? resueltoPor
          : null,
      resueltoEn: _parsearFecha(datos['resuelto_en']),
    );
  }
}

/// Detalle privado de adelanto (unicamente paciente o profesional titular).
class DetalleAdelantoCita {
  final String idCita;
  final String estadoAdelanto;
  final String moneda;
  final int precioConsultaCentavos;
  final int montoAdelantoCentavos;
  final int saldoDespuesAdelantoCentavos;
  final String condicionesAceptadas;
  final String? rutaQrStorage;
  final String? bancoBeneficiario;
  final String? titularBeneficiario;
  final String? tipoCuentaBeneficiario;
  final String? numeroCuentaReferencia;
  final DateTime? aceptadoParaPagoEn;
  final DateTime? limitePagoEn;
  final DateTime? comprobanteEnviadoEn;
  final DateTime? limiteRevisionEn;
  final bool revisionDemorada;
  final String? verificadoPor;
  final DateTime? verificadoEn;
  final DateTime? vencidoEn;
  final DateTime? horaServidor;
  final List<ComprobanteAdelanto> comprobantes;
  final List<ObservacionAdelanto> observaciones;
  final List<IncidenciaAdelanto> incidencias;

  const DetalleAdelantoCita({
    required this.idCita,
    required this.estadoAdelanto,
    this.moneda = 'USD',
    required this.precioConsultaCentavos,
    required this.montoAdelantoCentavos,
    required this.saldoDespuesAdelantoCentavos,
    required this.condicionesAceptadas,
    this.rutaQrStorage,
    this.bancoBeneficiario,
    this.titularBeneficiario,
    this.tipoCuentaBeneficiario,
    this.numeroCuentaReferencia,
    this.aceptadoParaPagoEn,
    this.limitePagoEn,
    this.comprobanteEnviadoEn,
    this.limiteRevisionEn,
    this.revisionDemorada = false,
    this.verificadoPor,
    this.verificadoEn,
    this.vencidoEn,
    this.horaServidor,
    this.comprobantes = const [],
    this.observaciones = const [],
    this.incidencias = const [],
  });

  String get etiquetaEstado => etiquetaVisibleEstadoAdelanto(
    estadoAdelanto,
    revisionDemorada: revisionDemorada,
  );

  String get textoPrecioConsulta =>
      InfoEconomicaProfesional.formatearCentavosUsd(precioConsultaCentavos);

  String get textoMontoAdelanto =>
      InfoEconomicaProfesional.formatearCentavosUsd(montoAdelantoCentavos);

  String get textoSaldo => InfoEconomicaProfesional.formatearCentavosUsd(
    saldoDespuesAdelantoCentavos,
  );

  /// Evalúa si el plazo de pago venció en el instante UTC indicado.
  /// Alineado con la regla del servidor SQL: vence estrictamente después de
  /// `limite_pago_en` (`ahora > limite_pago_en`).
  bool estaPlazoPagoVencidoEn(DateTime referenciaUtc) {
    if (estadoAdelanto == 'vencido_sin_pago') {
      return true;
    }
    if (estadoAdelanto != 'pendiente_adelanto' || limitePagoEn == null) {
      return false;
    }
    return referenciaUtc.toUtc().isAfter(limitePagoEn!.toUtc());
  }

  bool get plazoPagoVencido =>
      estaPlazoPagoVencidoEn(horaServidor ?? DateTime.now().toUtc());

  bool tieneDatosPagoVisiblesEn(DateTime referenciaUtc) =>
      !(estadoAdelanto == 'pendiente_adelanto' &&
          estaPlazoPagoVencidoEn(referenciaUtc)) &&
      estadoAdelanto != 'vencido_sin_pago' &&
      estadoAdelanto != 'cancelado' &&
      rutaQrStorage != null &&
      rutaQrStorage!.isNotEmpty &&
      bancoBeneficiario != null &&
      bancoBeneficiario!.isNotEmpty;

  bool puedeEnviarComprobanteEn(DateTime referenciaUtc) {
    if (estadoAdelanto == 'pendiente_adelanto') {
      return !estaPlazoPagoVencidoEn(referenciaUtc);
    }
    return estadoAdelanto == 'observado' || estadoAdelanto == 'incidencia_pago';
  }

  bool get tieneDatosPagoVisibles =>
      tieneDatosPagoVisiblesEn(horaServidor ?? DateTime.now().toUtc());

  bool get puedeEnviarComprobante =>
      puedeEnviarComprobanteEn(horaServidor ?? DateTime.now().toUtc());

  bool get puedeReportarIncidencia =>
      estadoAdelanto == 'pendiente_adelanto' ||
      estadoAdelanto == 'observado' ||
      estadoAdelanto == 'vencido_sin_pago' ||
      estadoAdelanto == 'incidencia_pago';

  bool get puedeRevisarProfesional =>
      estadoAdelanto == 'comprobante_en_revision' ||
      estadoAdelanto == 'incidencia_pago' ||
      estadoAdelanto == 'observado';

  /// Indica si una incidencia de carga cumple los requisitos para cierre manual
  /// simple por parte del profesional titular: abierta, sin horario liberado,
  /// con comprobante registrado y adelanto en revisión, observado o verificado.
  bool puedeResolverIncidenciaCarga(IncidenciaAdelanto incidencia) {
    if (!incidencia.estaAbierta || incidencia.horarioYaLiberado) {
      return false;
    }
    final estadoPermitido =
        estadoAdelanto == 'comprobante_en_revision' ||
        estadoAdelanto == 'observado' ||
        estadoAdelanto == 'verificado';
    return estadoPermitido && comprobantes.isNotEmpty;
  }

  factory DetalleAdelantoCita.desdeMapa(Map<String, dynamic> datos) {
    final base = _validarCabeceraAdelanto(datos);

    final listaCompRaw = datos['comprobantes'];
    if (listaCompRaw != null && listaCompRaw is! List) {
      throw const FormatException('Lista de comprobantes inválida.');
    }
    final listaObsRaw = datos['observaciones'];
    if (listaObsRaw != null && listaObsRaw is! List) {
      throw const FormatException('Lista de observaciones inválida.');
    }
    final listaIncRaw = datos['incidencias'];
    if (listaIncRaw != null && listaIncRaw is! List) {
      throw const FormatException('Lista de incidencias inválida.');
    }

    final listaComp = (listaCompRaw as List? ?? const []).map((item) {
      if (item is! Map) {
        throw const FormatException('Elemento de comprobante malformado.');
      }
      return ComprobanteAdelanto.desdeMapa(Map<String, dynamic>.from(item));
    }).toList();

    final listaObs = (listaObsRaw as List? ?? const []).map((item) {
      if (item is! Map) {
        throw const FormatException('Elemento de observación malformado.');
      }
      return ObservacionAdelanto.desdeMapa(Map<String, dynamic>.from(item));
    }).toList();

    final listaInc = (listaIncRaw as List? ?? const []).map((item) {
      if (item is! Map) {
        throw const FormatException('Elemento de incidencia malformado.');
      }
      return IncidenciaAdelanto.desdeMapa(Map<String, dynamic>.from(item));
    }).toList();

    return DetalleAdelantoCita(
      idCita: base.idCita,
      estadoAdelanto: base.estadoAdelanto,
      moneda: base.moneda,
      precioConsultaCentavos: base.precioCentavos,
      montoAdelantoCentavos: base.adelantoCentavos,
      saldoDespuesAdelantoCentavos: base.saldoCentavos,
      condicionesAceptadas: (datos['condiciones_aceptadas'] ?? '')
          .toString()
          .trim(),
      rutaQrStorage: (datos['ruta_qr_storage'] as String?)?.trim(),
      bancoBeneficiario: (datos['banco_beneficiario'] as String?)?.trim(),
      titularBeneficiario: (datos['titular_beneficiario'] as String?)?.trim(),
      tipoCuentaBeneficiario: (datos['tipo_cuenta_beneficiario'] as String?)
          ?.trim(),
      numeroCuentaReferencia: (datos['numero_cuenta_referencia'] as String?)
          ?.trim(),
      aceptadoParaPagoEn: _parsearFecha(datos['aceptado_para_pago_en']),
      limitePagoEn: _parsearFecha(datos['limite_pago_en']),
      comprobanteEnviadoEn: _parsearFecha(datos['comprobante_enviado_en']),
      limiteRevisionEn: _parsearFecha(datos['limite_revision_en']),
      revisionDemorada: datos['revision_demorada'] as bool? ?? false,
      verificadoPor: (datos['verificado_por'] as String?)?.trim(),
      verificadoEn: _parsearFecha(datos['verificado_en']),
      vencidoEn: _parsearFecha(datos['vencido_en']),
      horaServidor: _parsearFecha(datos['hora_servidor']),
      comprobantes: List.unmodifiable(listaComp),
      observaciones: List.unmodifiable(listaObs),
      incidencias: List.unmodifiable(listaInc),
    );
  }
}

DateTime? _parsearFecha(dynamic valor) {
  if (valor == null) return null;
  if (valor is DateTime) return valor.toUtc();
  if (valor is String && valor.trim().isNotEmpty) {
    return DateTime.tryParse(valor.trim())?.toUtc();
  }
  return null;
}
