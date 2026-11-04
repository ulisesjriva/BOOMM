import 'package:supabase_flutter/supabase_flutter.dart';

import '../configuracion/configuracion_supabase.dart';
import '../modelos/perfil_usuario.dart';

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
        'Falta la configuración de Supabase. Inicia la aplicación con la URL y la clave pública.',
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
        'Supabase no devolvió una respuesta de registro válida.',
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
        'El correo está confirmado, pero no se encontró el perfil. Debemos revisar el trigger y los permisos.',
      );
    }
    final perfil = PerfilUsuario.desdeMapa(
      Map<String, dynamic>.from(datos.first as Map),
    );
    if (perfil.id != usuario.id) {
      throw const ErrorRegistro(
        'El perfil recibido no corresponde a la sesión actual.',
      );
    }
    return perfil;
  }

  /// Traduce errores sin escribir tokens, claves ni contrasenas en consola.
  static String explicarError(Object error) {
    if (error is ErrorRegistro) return error.mensaje;
    if (error is AuthException) {
      if (error.statusCode == '429') {
        return 'Se alcanzó el límite de solicitudes o correos. Espera antes de volver a intentarlo.';
      }
      return 'Supabase Auth: ${error.message}';
    }
    if (error is PostgrestException) {
      return 'No se pudo consultar el perfil: ${error.message}';
    }
    if (error is FormatException) return error.message;
    return 'No se pudo completar la solicitud. Comprueba la conexión y revisa el correo antes de repetir el registro.';
  }
}
