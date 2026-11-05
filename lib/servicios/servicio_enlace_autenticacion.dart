import 'package:supabase_flutter/supabase_flutter.dart';

import '../configuracion/configuracion_supabase.dart';
import '../modelos/enlace_autenticacion.dart';

class ErrorEnlaceAutenticacion implements Exception {
  final String mensaje;
  const ErrorEnlaceAutenticacion(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Cliente temporal separado del cliente global de Flutter.
/// No usa SupabaseAuth/LocalStorage: la sesion del enlace queda solo en memoria.
/// Sus eventos de recuperacion nunca autentican al usuario en el panel principal.
class ServicioEnlaceAutenticacion {
  SupabaseClient? _cliente;
  String? _idRecuperacion;
  bool _cerrado = false;

  SupabaseClient get _conexion {
    if (_cerrado) {
      throw const ErrorEnlaceAutenticacion('Abre nuevamente el enlace del correo.');
    }
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorEnlaceAutenticacion(
        'Falta la configuracion de Supabase. Ejecuta la app con su URL y clave publica.',
      );
    }
    return _cliente ??= SupabaseClient(
      ConfiguracionSupabase.url,
      ConfiguracionSupabase.claveAnon,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  Future<String> confirmarCorreo(EnlaceAutenticacion enlace) async {
    if (enlace.tipo != TipoEnlaceAutenticacion.confirmacion || enlace.tokenHash == null) {
      throw const ErrorEnlaceAutenticacion('El enlace de confirmacion no es valido.');
    }
    final respuesta = await _conexion.auth.verifyOTP(
      tokenHash: enlace.tokenHash,
      type: OtpType.email,
    );
    final usuario = respuesta.user;
    if (usuario == null || usuario.emailConfirmedAt == null || respuesta.session == null) {
      throw const ErrorEnlaceAutenticacion('No se pudo comprobar la confirmacion del correo.');
    }
    final correo = usuario.email ?? '';
    await cerrar();
    return correo;
  }

  Future<void> validarRecuperacion(EnlaceAutenticacion enlace) async {
    _idRecuperacion = null;
    if (enlace.tipo != TipoEnlaceAutenticacion.recuperacion || enlace.tokenHash == null) {
      throw const ErrorEnlaceAutenticacion('Abre un enlace de recuperacion valido desde tu correo.');
    }
    final respuesta = await _conexion.auth.verifyOTP(
      tokenHash: enlace.tokenHash,
      type: OtpType.recovery,
    );
    if (respuesta.user == null || respuesta.session == null ||
        respuesta.session!.user.id != respuesta.user!.id) {
      throw const ErrorEnlaceAutenticacion('No se obtuvo una sesion de recuperacion valida.');
    }
    _idRecuperacion = respuesta.user!.id;
  }

  static String? validarClave(String? clave) {
    if (clave == null || clave.length < 11) {
      return 'Usa al menos 11 caracteres.';
    }
    if (!RegExp(r'[a-z]').hasMatch(clave) ||
        !RegExp(r'[A-Z]').hasMatch(clave) ||
        !RegExp(r'[0-9]').hasMatch(clave) ||
        !RegExp(r'[!-/:-@\[-`{-~]').hasMatch(clave)) {
      return 'Incluye mayuscula, minuscula, numero y simbolo.';
    }
    return null;
  }

  Future<void> guardarClave(String clave) async {
    final errorClave = validarClave(clave);
    if (errorClave != null) throw ErrorEnlaceAutenticacion(errorClave);
    final cliente = _cliente;
    final id = _idRecuperacion;
    if (_cerrado || cliente == null || id == null ||
        cliente.auth.currentSession?.user.id != id) {
      throw const ErrorEnlaceAutenticacion('Primero valida el enlace de recuperacion.');
    }
    final usuario = (await cliente.auth.getUser()).user;
    if (usuario?.id != id) {
      throw const ErrorEnlaceAutenticacion('La sesion de recuperacion ya no es valida. Solicita otro enlace.');
    }
    final respuesta = await cliente.auth.updateUser(UserAttributes(password: clave));
    if (respuesta.user?.id != id) {
      throw const ErrorEnlaceAutenticacion('No se pudo comprobar el cambio de contrasena.');
    }
    await cerrar();
  }

  Future<void> cerrar() async {
    if (_cerrado) return;
    _cerrado = true;
    _idRecuperacion = null;
    final cliente = _cliente;
    _cliente = null;
    if (cliente == null) return;
    try {
      await cliente.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // El cliente no persiste la sesion; su disposicion elimina la copia local.
    } finally {
      await cliente.dispose();
    }
  }

  static String explicarError(Object error) {
    if (error is ErrorEnlaceAutenticacion) return error.mensaje;
    if (error is AuthException) {
      final mensaje = error.message.toLowerCase();
      if (error.statusCode == '429') return 'Demasiados intentos. Espera antes de continuar.';
      if (mensaje.contains('expired') || mensaje.contains('invalid token') ||
          mensaje.contains('token has expired or is invalid')) {
        return 'El enlace vencio, ya fue utilizado o no es valido. Solicita uno nuevo.';
      }
      if (mensaje.contains('same password') || mensaje.contains('different')) {
        return 'Elige una contrasena diferente de la anterior.';
      }
      if (mensaje.contains('password')) {
        return 'La contrasena debe cumplir los requisitos de seguridad de tu cuenta.';
      }
      return 'Supabase no pudo validar la solicitud. Comprueba tu conexion y el enlace del correo.';
    }
    return 'No se pudo completar la solicitud. Comprueba tu conexion e intentalo nuevamente.';
  }
}
