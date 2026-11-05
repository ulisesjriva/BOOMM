import 'package:supabase_flutter/supabase_flutter.dart';

import '../configuracion/configuracion_supabase.dart';

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
        'Falta la configuracion de Supabase. Ejecuta la app con la URL y la clave publica.',
      );
    }
    final correoLimpio = correo.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correoLimpio)) {
      throw const ErrorRecuperacionClave('Ingresa un correo valido.');
    }
    await Supabase.instance.client.auth.resetPasswordForEmail(
      correoLimpio,
      redirectTo: direccionRetorno,
    );
  }

  static String explicarError(Object error) {
    if (error is ErrorRecuperacionClave) return error.mensaje;
    if (error is AuthException) {
      if (error.statusCode == '429') {
        return 'Se alcanzo el limite de solicitudes. Espera antes de pedir otro enlace.';
      }
      return 'Supabase no pudo aceptar la solicitud de recuperacion. Comprueba tu conexion y vuelve a intentarlo.';
    }
    return 'No se pudo solicitar el enlace. Comprueba tu conexion a Internet.';
  }
}
