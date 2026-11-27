/// Informacion economica publica de un profesional consultada por el paciente.
/// Representa los importes en centavos enteros exactos (int) para evitar
/// imprecisiones de punto flotante al restar o formatear montos en USD.
/// No almacena ni expone QR, rutas privadas de Storage ni datos bancarios.
class InfoEconomicaProfesional {
  static const int centavosMinimosUsd = 1; // $0.01
  static const int centavosMaximosUsd =
      9999999999; // $99,999,999.99 (NUMERIC(10,2))

  final bool profesionalVisible;
  final bool tieneConfiguracion;
  final String moneda;
  final int? precioConsultaCentavos;
  final bool requiereAdelanto;
  final int? montoAdelantoExigibleCentavos;
  final int? saldoDespuesAdelantoCentavos;
  final String? versionOferta;
  final String? condicionesTexto;

  const InfoEconomicaProfesional({
    required this.profesionalVisible,
    required this.tieneConfiguracion,
    this.moneda = 'USD',
    this.precioConsultaCentavos,
    this.requiereAdelanto = false,
    this.montoAdelantoExigibleCentavos,
    this.saldoDespuesAdelantoCentavos,
    this.versionOferta,
    this.condicionesTexto,
  });

  /// Representa un profesional no visible, no aprobado o inexistente.
  const InfoEconomicaProfesional.noDisponible()
    : profesionalVisible = false,
      tieneConfiguracion = false,
      moneda = 'USD',
      precioConsultaCentavos = null,
      requiereAdelanto = false,
      montoAdelantoExigibleCentavos = null,
      saldoDespuesAdelantoCentavos = null,
      versionOferta = null,
      condicionesTexto = null;

  /// Representa un profesional visible que aun no tiene precio configurado.
  const InfoEconomicaProfesional.sinConfiguracion({this.moneda = 'USD'})
    : profesionalVisible = true,
      tieneConfiguracion = false,
      precioConsultaCentavos = null,
      requiereAdelanto = false,
      montoAdelantoExigibleCentavos = null,
      saldoDespuesAdelantoCentavos = null,
      versionOferta = null,
      condicionesTexto = null;

  bool get tienePrecioConfigurado =>
      profesionalVisible &&
      tieneConfiguracion &&
      precioConsultaCentavos != null &&
      precioConsultaCentavos! >= centavosMinimosUsd;

  bool get exigeAdelanto =>
      tienePrecioConfigurado &&
      requiereAdelanto &&
      montoAdelantoExigibleCentavos != null &&
      montoAdelantoExigibleCentavos! >= centavosMinimosUsd;

  String? get textoPrecioConsulta => precioConsultaCentavos != null
      ? formatearCentavosUsd(precioConsultaCentavos!)
      : null;

  String? get textoMontoAdelanto => montoAdelantoExigibleCentavos != null
      ? formatearCentavosUsd(montoAdelantoExigibleCentavos!)
      : null;

  String? get textoSaldoDespuesAdelanto => saldoDespuesAdelantoCentavos != null
      ? formatearCentavosUsd(saldoDespuesAdelantoCentavos!)
      : null;

  /// Formatea centavos enteros exactos a `$XX.XX` sin pasar por `double`.
  static String formatearCentavosUsd(int centavos) {
    final esNegativo = centavos < 0;
    final absoluto = centavos.abs();
    final dolares = absoluto ~/ 100;
    final restoCentavos = (absoluto % 100).toString().padLeft(2, '0');
    return '${esNegativo ? '-' : ''}\$$dolares.$restoCentavos';
  }

  /// Convierte un monto proveniente del servidor (String exacto o num) a
  /// centavos enteros exactos, rechazando valores invalidos o con mas de 2 decimales.
  static int? parsearCentavos(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) {
      if (valor < 0) return null;
      return valor * 100;
    }
    if (valor is String) {
      final limpio = valor.trim().replaceAll(',', '.');
      if (limpio.isEmpty) return null;
      final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(limpio);
      if (match == null) return null;
      final enteros = int.tryParse(match.group(1)!);
      if (enteros == null) return null;
      final decimalesRaw = match.group(2) ?? '';
      final centavos = int.tryParse(decimalesRaw.padRight(2, '0'));
      if (centavos == null) return null;
      return enteros * 100 + centavos;
    }
    if (valor is double) {
      if (valor.isNaN || valor.isInfinite || valor < 0) return null;
      final escalado = valor * 100;
      final redondeado = escalado.round();
      if ((escalado - redondeado).abs() >= 1e-6) return null;
      return redondeado;
    }
    return null;
  }

  /// Construye la instancia leyendo UNICAMENTE los campos economicos permitidos
  /// y valida estrictamente la integridad de la respuesta:
  /// - Exige moneda `'USD'`.
  /// - Si `tiene_configuracion` es `false`, conserva el estado sin precio.
  /// - Si `requiere_adelanto` es `true`, exige adelanto valido, positivo y <= precio
  ///   (nunca lo convierte silenciosamente en "no requiere adelanto").
  /// - Exige que `saldo_despues_adelanto` exista y coincida exactamente con
  ///   `precio_consulta - monto_adelanto_exigible` (nunca lo sustituye silenciosamente).
  factory InfoEconomicaProfesional.desdeMapa(Map<String, dynamic> datos) {
    final tieneConfigRaw = datos['tiene_configuracion'];
    if (tieneConfigRaw is! bool) {
      throw const FormatException(
        'La respuesta económica no indica si existe configuración válida.',
      );
    }

    final monedaRaw = datos['moneda'];
    if (monedaRaw is! String || monedaRaw.trim() != 'USD') {
      throw const FormatException(
        'La moneda informada no es compatible con USD.',
      );
    }

    final requiereRaw = datos['requiere_adelanto'];
    if (requiereRaw is! bool) {
      throw const FormatException(
        'La respuesta económica no indica correctamente si requiere adelanto.',
      );
    }

    if (!tieneConfigRaw) {
      if (requiereRaw || datos['precio_consulta'] != null) {
        throw const FormatException(
          'La respuesta económica sin configuración contiene datos inconsistentes.',
        );
      }
      return const InfoEconomicaProfesional.sinConfiguracion(moneda: 'USD');
    }

    final precioCentavos = parsearCentavos(datos['precio_consulta']);
    if (precioCentavos == null ||
        precioCentavos < centavosMinimosUsd ||
        precioCentavos > centavosMaximosUsd) {
      throw const FormatException(
        'El precio de consulta recibido está fuera del rango admitido.',
      );
    }

    final int adelantoCentavos;
    if (requiereRaw) {
      final adelantoParseado = parsearCentavos(
        datos['monto_adelanto_exigible'],
      );
      if (adelantoParseado == null ||
          adelantoParseado < centavosMinimosUsd ||
          adelantoParseado > centavosMaximosUsd ||
          adelantoParseado > precioCentavos) {
        throw const FormatException(
          'El monto de adelanto recibido no es válido para la consulta.',
        );
      }
      adelantoCentavos = adelantoParseado;
    } else {
      // Cuando requiere_adelanto es falso, el adelanto exigible debe ser 0.
      final adelantoRaw = datos['monto_adelanto_exigible'];
      if (adelantoRaw != null) {
        final adelantoParseado = parsearCentavos(adelantoRaw);
        if (adelantoParseado == null || adelantoParseado > centavosMaximosUsd) {
          throw const FormatException(
            'El monto de adelanto recibido tiene un formato inválido.',
          );
        }
      }
      adelantoCentavos = 0;
    }

    final saldoServidor = parsearCentavos(datos['saldo_despues_adelanto']);
    final saldoEsperado = precioCentavos - adelantoCentavos;
    if (saldoServidor == null ||
        saldoServidor < 0 ||
        saldoServidor > centavosMaximosUsd ||
        saldoServidor != saldoEsperado) {
      throw const FormatException(
        'El saldo informado no coincide con el valor de la consulta menos el adelanto.',
      );
    }

    final versionOferta = (datos['version_oferta'] as String?)?.trim();
    final condicionesTexto = (datos['condiciones_texto'] as String?)?.trim();

    return InfoEconomicaProfesional(
      profesionalVisible: true,
      tieneConfiguracion: true,
      moneda: 'USD',
      precioConsultaCentavos: precioCentavos,
      requiereAdelanto: requiereRaw,
      montoAdelantoExigibleCentavos: adelantoCentavos,
      saldoDespuesAdelantoCentavos: saldoServidor,
      versionOferta: (versionOferta != null && versionOferta.isNotEmpty)
          ? versionOferta
          : null,
      condicionesTexto:
          (condicionesTexto != null && condicionesTexto.isNotEmpty)
          ? condicionesTexto
          : null,
    );
  }
}
