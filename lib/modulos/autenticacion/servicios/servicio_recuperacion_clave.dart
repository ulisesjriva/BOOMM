import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorRecuperacionClave implements Exception {
  final String mensaje;
  const ErrorRecuperacionClave(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Solicita el correo real; la plantilla Reset password dirige a la web HTTPS.
/// Una respuesta aceptada no confirma que el correo exista ni que se entrego.
class ServicioRecuperacionClave {
  const ServicioRecuperacionClave();

  static const direccionRetorno =
      'https://psicobloom-7201a.web.app/autenticacion.html';

  Future<void> solicitarEnlace(String correo) async {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorRecuperacionClave(
        'El servicio de recuperación no está disponible en este momento. Inténtalo más tarde.',
      );
    }
    final correoLimpio = correo.trim();
    final errorCorreo = TraductorErroresSupabase.validarCorreo(correoLimpio);
    if (errorCorreo != null) {
      throw ErrorRecuperacionClave(errorCorreo);
    }
    await Supabase.instance.client.auth.resetPasswordForEmail(
      correoLimpio,
      redirectTo: direccionRetorno,
    );
  }

  static String explicarError(Object error) {
    if (error is ErrorRecuperacionClave) return error.mensaje;
    return TraductorErroresSupabase.traducirErrorAutenticacion(
      error,
      accionPorDefecto: 'No pudimos enviar el enlace de recuperación en este momento. Inténtalo nuevamente.',
    );
  }
}
