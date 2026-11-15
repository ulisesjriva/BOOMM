import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

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
      throw const ErrorEnlaceAutenticacion(
        'Abre nuevamente el enlace del correo.',
      );
    }
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorEnlaceAutenticacion(
        'El servicio de validación no está disponible en este momento. Inténtalo más tarde.',
      );
    }
    return _cliente ??= SupabaseClient(
      ConfiguracionSupabase.url,
      ConfiguracionSupabase.claveAnon,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  Future<String> confirmarCorreo(EnlaceAutenticacion enlace) async {
    if (enlace.tipo != TipoEnlaceAutenticacion.confirmacion ||
        enlace.tokenHash == null) {
      throw const ErrorEnlaceAutenticacion(
        'El enlace de confirmación no es válido.',
      );
    }
    final respuesta = await _conexion.auth.verifyOTP(
      tokenHash: enlace.tokenHash,
      type: OtpType.email,
    );
    final usuario = respuesta.user;
    if (usuario == null ||
        usuario.emailConfirmedAt == null ||
        respuesta.session == null) {
      throw const ErrorEnlaceAutenticacion(
        'No se pudo comprobar la confirmación del correo.',
      );
    }
    final correo = usuario.email ?? '';
    await cerrar();
    return correo;
  }

  Future<void> validarRecuperacion(EnlaceAutenticacion enlace) async {
    _idRecuperacion = null;
    if (enlace.tipo != TipoEnlaceAutenticacion.recuperacion ||
        enlace.tokenHash == null) {
      throw const ErrorEnlaceAutenticacion(
        'Abre un enlace de recuperación válido desde tu correo.',
      );
    }
    final respuesta = await _conexion.auth.verifyOTP(
      tokenHash: enlace.tokenHash,
      type: OtpType.recovery,
    );
    if (respuesta.user == null ||
        respuesta.session == null ||
        respuesta.session!.user.id != respuesta.user!.id) {
      throw const ErrorEnlaceAutenticacion(
        'Este enlace ya no es válido o ha expirado. Solicita uno nuevo para continuar.',
      );
    }
    _idRecuperacion = respuesta.user!.id;
  }

  static String? validarClave(String? clave) {
    if (clave == null || clave.length < 11) {
      return 'Usa al menos 11 caracteres.';
    }
    if (!TraductorErroresSupabase.cumpleRequisitosClave(clave)) {
      return 'Incluye mayúscula, minúscula, número y símbolo.';
    }
    return null;
  }

  Future<void> guardarClave(String clave) async {
    final errorClave = validarClave(clave);
    if (errorClave != null) throw ErrorEnlaceAutenticacion(errorClave);
    final cliente = _cliente;
    final id = _idRecuperacion;
    if (_cerrado ||
        cliente == null ||
        id == null ||
        cliente.auth.currentSession?.user.id != id) {
      throw const ErrorEnlaceAutenticacion(
        'Primero valida el enlace de recuperación.',
      );
    }
    final usuario = (await cliente.auth.getUser()).user;
    if (usuario?.id != id) {
      throw const ErrorEnlaceAutenticacion(
        'La sesión de recuperación ya no es válida. Solicita otro enlace.',
      );
    }
    final respuesta = await cliente.auth.updateUser(
      UserAttributes(password: clave),
    );
    if (respuesta.user?.id != id) {
      throw const ErrorEnlaceAutenticacion(
        'No se pudo comprobar el cambio de contraseña.',
      );
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
    return TraductorErroresSupabase.traducirErrorAutenticacion(
      error,
      accionPorDefecto: 'No pudimos validar tu solicitud en este momento. Comprueba tu conexión o solicita un enlace nuevo.',
    );
  }
}
