import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';

class ErrorInicioSesion implements Exception {
  final String mensaje;
  const ErrorInicioSesion(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Autentica con correo y clave y consulta el perfil propio en el servidor.
/// El rol procede de la RPC existente, nunca de los metadatos del formulario.
class ServicioInicioSesion {
  const ServicioInicioSesion();

  Future<PerfilUsuario> iniciarSesionPaciente({
    required String correo,
    required String clave,
  }) async {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorInicioSesion(
        'Falta la configuracion de Supabase. Ejecuta la app con la URL y la clave publica.',
      );
    }

    final cliente = Supabase.instance.client;
    var sesionCreada = false;
    try {
      final respuesta = await cliente.auth.signInWithPassword(
        email: correo.trim(),
        password: clave,
      );
      sesionCreada = respuesta.session != null;
      if (!sesionCreada || respuesta.user == null) {
        throw const ErrorInicioSesion(
          'No se obtuvo una sesion valida. Vuelve a iniciar sesion.',
        );
      }

      // Reutiliza getUser, perfil_del_usuario_actual y la validacion de id
      // implementados en ServicioRegistro.
      final perfil = await const ServicioRegistro().comprobarConfirmacion(
        correo,
      );
      if (perfil == null) {
        throw const ErrorInicioSesion(
          'No se pudo comprobar la cuenta y su correo confirmado.',
        );
      }
      if (!perfil.cuentaActiva) {
        throw const ErrorInicioSesion(
          'Tu cuenta esta inactiva. Contacta al administrador.',
        );
      }
      if (perfil.rol != 'paciente') {
        if (perfil.rol == 'profesional' && perfil.aprobacion == 'pendiente') {
          throw const ErrorInicioSesion(
            'Tu cuenta profesional esta pendiente de aprobacion. Su panel aun no esta conectado.',
          );
        }
        if (perfil.rol == 'profesional' && perfil.aprobacion == 'rechazado') {
          throw const ErrorInicioSesion(
            'Tu solicitud profesional fue rechazada. Contacta al administrador.',
          );
        }
        throw const ErrorInicioSesion(
          'Las credenciales son correctas, pero el panel de tu rol aun no esta conectado. Por ahora solo esta disponible el acceso del paciente.',
        );
      }
      return perfil;
    } catch (error) {
      // Si Auth funciono pero fallo el perfil o el acceso a este panel,
      // cierra esta sesion sin cerrar las sesiones de otros dispositivos.
      if (sesionCreada) {
        try {
          await cliente.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          throw ErrorInicioSesion(
            '${explicarError(error)} No se pudo cerrar la sesion local. Comprueba la conexion y vuelve a intentarlo.',
          );
        }
      }
      rethrow;
    }
  }

  static String explicarError(Object error) {
    if (error is ErrorInicioSesion) return error.mensaje;
    if (error is AuthException) {
      final mensaje = error.message.toLowerCase();
      if (error.statusCode == '429') {
        return 'Demasiados intentos. Espera antes de volver a iniciar sesion.';
      }
      if (mensaje.contains('invalid login credentials')) {
        return 'El correo o la contrasena son incorrectos.';
      }
      if (mensaje.contains('email not confirmed')) {
        return 'Confirma tu correo mediante el enlace de registro antes de ingresar.';
      }
      return 'No se pudo autenticar la cuenta. Comprueba tu conexion y vuelve a intentarlo.';
    }
    if (error is PostgrestException) {
      return 'No se pudo consultar tu perfil. Revisa la funcion perfil_del_usuario_actual y sus permisos en Supabase.';
    }
    if (error is ErrorRegistro) return error.mensaje;
    if (error is FormatException) return error.message;
    return 'No se pudo iniciar sesion. Comprueba tu conexion e intentalo de nuevo.';
  }
}
