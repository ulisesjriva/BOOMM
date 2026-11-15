import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorRegistro implements Exception {
  final String mensaje;
  const ErrorRegistro(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Registro, reenvio y comprobacion real del correo y del perfil propio.
/// No guarda contrasenas ni usa claves de administracion.
class ServicioRegistro {
  const ServicioRegistro();

  static const enlaceRetorno = 'psicobloom://acceso/';

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorRegistro(
        'El servicio de registro no está disponible en este momento. Inténtalo más tarde.',
      );
    }
    return Supabase.instance.client;
  }

  Future<void> registrar({
    required String nombre,
    required String apellido,
    required String correo,
    required String clave,
    required bool esProfesional,
  }) async {
    if (clave.length < 11) {
      throw const ErrorRegistro(
        'La contraseña debe contener al menos 11 caracteres.',
      );
    }
    if (!TraductorErroresSupabase.cumpleRequisitosClave(clave)) {
      throw const ErrorRegistro(
        'Tu contraseña aún no cumple los requisitos. Usa al menos 11 caracteres e incluye mayúsculas, minúsculas, números y un símbolo.',
      );
    }
    final respuesta = await _cliente.auth.signUp(
      email: correo.trim(),
      password: clave,
      emailRedirectTo: enlaceRetorno,
      data: {
        'nombre': nombre.trim(),
        'apellido': apellido.trim(),
        'rol': esProfesional ? 'profesional' : 'paciente',
      },
    );
    if (respuesta.user == null) {
      throw const ErrorRegistro(
        'No pudimos completar tu registro en este momento. Inténtalo nuevamente en unos minutos.',
      );
    }
    // Una respuesta aceptada no demuestra entrega de correo ni cuenta nueva:
    // Auth puede ocultar si una direccion ya estaba registrada.
  }

  Future<void> reenviarEnlace(String correo) async {
    await _cliente.auth.resend(
      type: OtpType.signup,
      email: correo.trim(),
      emailRedirectTo: enlaceRetorno,
    );
  }

  /// null significa que esta instancia no tiene una sesion confirmada para ese
  /// correo. No demuestra que el correo siga sin confirmar en otro dispositivo.
  Future<PerfilUsuario?> comprobarConfirmacion(String correo) async {
    final cliente = _cliente;
    if (cliente.auth.currentSession == null) return null;
    final respuesta = await cliente.auth.getUser();
    final usuario = respuesta.user;
    if (usuario == null ||
        usuario.email?.toLowerCase() != correo.trim().toLowerCase() ||
        usuario.emailConfirmedAt == null) {
      return null;
    }
    final datos = await cliente.rpc('perfil_del_usuario_actual');
    if (datos is! List || datos.length != 1 || datos.first is! Map) {
      throw const ErrorRegistro(
        'Tu correo está confirmado, pero aún no pudimos cargar tu perfil. Intenta iniciar sesión en unos instantes.',
      );
    }
    final perfil = PerfilUsuario.desdeMapa(
      Map<String, dynamic>.from(datos.first as Map),
    );
    if (perfil.id != usuario.id) {
      throw const ErrorRegistro(
        'La sesión actual no coincide con la cuenta consultada. Inicia sesión nuevamente.',
      );
    }
    return perfil;
  }

  /// Traduce errores sin escribir tokens, claves ni contrasenas en consola.
  static String explicarError(Object error) {
    if (error is ErrorRegistro) return error.mensaje;
    return TraductorErroresSupabase.traducirErrorAutenticacion(
      error,
      accionPorDefecto: 'No pudimos completar tu registro en este momento. Inténtalo nuevamente en unos minutos.',
    );
  }
}
