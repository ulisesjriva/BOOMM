import 'package:boom/modelos/adelanto_cita.dart';
import 'package:boom/modulos/paciente/modelos/info_economica_profesional.dart';

/// La devolución registrada representa el reporte del profesional, no una
/// confirmación bancaria automática ni una nueva confirmación de cita.
class GestionCancelacionCita {
  final Map<String, dynamic> _datos;
  const GestionCancelacionCita._(this._datos);

  factory GestionCancelacionCita.desdeMapa(Map<String, dynamic> datos) {
    const pagos = {'no_reportado', 'pendiente_verificacion', 'recibido', 'no_recibido'};
    const devoluciones = {'no_aplica', 'pendiente_verificacion', 'pendiente_devolucion', 'registrada'};
    final centavos = InfoEconomicaProfesional.parsearCentavos(datos['monto_adelanto']);
    if (datos['id_cita'] is! String || (datos['id_cita'] as String).isEmpty ||
        !pagos.contains(datos['estado_pago']) || !devoluciones.contains(datos['estado_devolucion']) ||
        !{'paciente', 'profesional'}.contains(datos['rol']) ||
        centavos == null || centavos < 0 || datos['moneda'] != 'USD') {
      throw const FormatException('Respuesta de cancelación inválida.');
    }
    for (final campo in ['puede_cancelar', 'corresponde_devolucion', 'puede_revisar_pago', 'puede_registrar_devolucion']) {
      if (datos[campo] is! bool) throw FormatException('Indicador inválido: $campo.');
    }
    if (datos['puede_cancelar'] == true && (datos['version_previa'] is! String || (datos['version_previa'] as String).isEmpty)) {
      throw const FormatException('Falta la versión de la confirmación.');
    }
    return GestionCancelacionCita._(Map.unmodifiable(datos));
  }

  String get idCita => _datos['id_cita'] as String;
  String get rol => _datos['rol'] as String;
  String get estadoCita => _datos['estado_cita'] as String;
  String get estadoPago => _datos['estado_pago'] as String;
  String get estadoDevolucion => _datos['estado_devolucion'] as String;
  String get versionPrevia => _datos['version_previa'] as String? ?? '';
  bool get puedeCancelar => _datos['puede_cancelar'] == true;
  bool get correspondeDevolucion => _datos['corresponde_devolucion'] == true;
  bool get puedeRevisarPago => _datos['puede_revisar_pago'] == true;
  bool get puedeRegistrarDevolucion => _datos['puede_registrar_devolucion'] == true;
  bool get estaCancelada => _datos['cancelada_en'] != null;
  int get montoCentavos => InfoEconomicaProfesional.parsearCentavos(_datos['monto_adelanto'])!;
  String get textoMonto => InfoEconomicaProfesional.formatearCentavosUsd(montoCentavos);
  String? get rutaComprobante => _datos['ruta_comprobante_devolucion'] as String?;
  String? get referencia => _datos['referencia_devolucion'] as String?;
  String? get motivo => _datos['motivo'] as String?;
  String? get motivoRevision => _datos['motivo_revision'] as String?;
  String? get fechaCancelacion {
    final fecha = DateTime.tryParse(_datos['cancelada_en'] as String? ?? '');
    return fecha == null ? null : formatearFechaHoraEcuador(fecha);
  }

  String get textoConsecuencia {
    if (montoCentavos == 0) return 'Esta cita no tiene un adelanto registrado. No se genera devolución.';
    final regla = correspondeDevolucion
        ? 'Corresponde devolver $textoMonto si el ingreso está verificado.'
        : 'Según la anticipación o la reprogramación previa, no corresponde devolución del adelanto.';
    if (estadoPago == 'pendiente_verificacion') {
      return 'El ingreso está pendiente de verificación. $regla Cancelar no confirma el pago.';
    }
    if (estadoPago == 'no_recibido') return 'El profesional registró que no recibió el ingreso. No se genera devolución.';
    if (estadoPago == 'no_reportado') return 'No hay un pago reportado. $regla Si ya transferiste, indícalo antes de cancelar.';
    return correspondeDevolucion
        ? 'Corresponde la devolución completa del adelanto recibido: $textoMonto.'
        : 'El adelanto recibido ($textoMonto) no tiene devolución según las condiciones aceptadas.';
  }

  String get etiquetaDevolucion => switch (estadoDevolucion) {
    'pendiente_verificacion' => 'Ingreso pendiente de verificación',
    'pendiente_devolucion' => 'Devolución pendiente',
    'registrada' => 'Devolución registrada por el profesional',
    _ => 'Sin devolución pendiente',
  };
}
