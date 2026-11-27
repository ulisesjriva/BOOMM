/// Configuracion de cobro y adelanto opcional del profesional en USD.
/// Guarda unicamente la ruta privada del QR en Storage, nunca una URL firmada.
class ConfiguracionCobroProfesional {
  static const double montoMinimoUsd = 0.01;
  static const double montoMaximoUsd = 99999999.99;

  final bool requiereAdelanto;
  final String moneda;
  final double? precioConsulta;
  final double? montoAdelanto;
  final String? rutaQrStorage;
  final String? bancoBeneficiario;
  final String? titularBeneficiario;
  final String? tipoCuentaBeneficiario;
  final String? numeroCuentaReferencia;
  final DateTime? actualizadoEn;

  const ConfiguracionCobroProfesional({
    this.requiereAdelanto = false,
    this.moneda = 'USD',
    this.precioConsulta,
    this.montoAdelanto,
    this.rutaQrStorage,
    this.bancoBeneficiario,
    this.titularBeneficiario,
    this.tipoCuentaBeneficiario,
    this.numeroCuentaReferencia,
    this.actualizadoEn,
  });

  bool get tieneQrGuardado =>
      rutaQrStorage != null && rutaQrStorage!.trim().isNotEmpty;

  ConfiguracionCobroProfesional copiarCon({
    bool? requiereAdelanto,
    double? precioConsulta,
    double? montoAdelanto,
    String? rutaQrStorage,
    String? bancoBeneficiario,
    String? titularBeneficiario,
    String? tipoCuentaBeneficiario,
    String? numeroCuentaReferencia,
    DateTime? actualizadoEn,
  }) {
    return ConfiguracionCobroProfesional(
      requiereAdelanto: requiereAdelanto ?? this.requiereAdelanto,
      moneda: moneda,
      precioConsulta: precioConsulta ?? this.precioConsulta,
      montoAdelanto: montoAdelanto ?? this.montoAdelanto,
      rutaQrStorage: rutaQrStorage ?? this.rutaQrStorage,
      bancoBeneficiario: bancoBeneficiario ?? this.bancoBeneficiario,
      titularBeneficiario: titularBeneficiario ?? this.titularBeneficiario,
      tipoCuentaBeneficiario:
          tipoCuentaBeneficiario ?? this.tipoCuentaBeneficiario,
      numeroCuentaReferencia:
          numeroCuentaReferencia ?? this.numeroCuentaReferencia,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  factory ConfiguracionCobroProfesional.desdeMapa(Map<String, dynamic> datos) {
    final fechaRaw = datos['actualizado_en'];
    DateTime? actualizadoEn;
    if (fechaRaw is String && fechaRaw.trim().isNotEmpty) {
      actualizadoEn = DateTime.tryParse(fechaRaw.trim());
    } else if (fechaRaw is DateTime) {
      actualizadoEn = fechaRaw;
    }

    return ConfiguracionCobroProfesional(
      requiereAdelanto: datos['requiere_adelanto'] as bool? ?? false,
      moneda: (datos['moneda'] as String?)?.trim().isNotEmpty == true
          ? (datos['moneda'] as String).trim()
          : 'USD',
      precioConsulta: _parsearNumero(datos['precio_consulta']),
      montoAdelanto: _parsearNumero(datos['monto_adelanto']),
      rutaQrStorage: (datos['ruta_qr_storage'] as String?)?.trim(),
      bancoBeneficiario: (datos['banco_beneficiario'] as String?)?.trim(),
      titularBeneficiario: (datos['titular_beneficiario'] as String?)?.trim(),
      tipoCuentaBeneficiario: (datos['tipo_cuenta_beneficiario'] as String?)
          ?.trim(),
      numeroCuentaReferencia: (datos['numero_cuenta_referencia'] as String?)
          ?.trim(),
      actualizadoEn: actualizadoEn,
    );
  }

  static double? _parsearNumero(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    if (valor is String && valor.trim().isNotEmpty) {
      return double.tryParse(valor.trim().replaceAll(',', '.'));
    }
    return null;
  }

  /// Valida un monto USD sin redondear silenciosamente:
  /// rechaza NaN, infinitos, <= 0, > 99999999.99 y fracciones menores a 1 centavo.
  static String? validarMontoUsd(double valor, {required String etiqueta}) {
    if (valor.isNaN || valor.isInfinite) {
      return '$etiqueta no es un número válido.';
    }
    if (valor < montoMinimoUsd || valor > montoMaximoUsd) {
      return '$etiqueta debe estar entre 0.01 y 99999999.99 USD.';
    }
    final escalado = valor * 100;
    final centavos = escalado.round();
    if ((escalado - centavos).abs() >= 1e-6) {
      return '$etiqueta admite como máximo dos decimales (centavos exactos).';
    }
    return null;
  }

  /// Parsea un texto monetario en USD con maximo 2 decimales exactos dentro de rango.
  static double? parsearMontoUsd(String texto) {
    final limpio = texto.trim().replaceAll(',', '.');
    if (limpio.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(limpio)) {
      return null;
    }
    final valor = double.tryParse(limpio);
    if (valor == null) return null;
    if (validarMontoUsd(valor, etiqueta: 'El monto') != null) {
      return null;
    }
    return valor;
  }
}
