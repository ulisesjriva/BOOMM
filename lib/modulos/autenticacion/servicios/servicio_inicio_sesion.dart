import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

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

  Future<PerfilUsuario> iniciarSesion({
    required String correo,
    required String clave,
  }) async {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorInicioSesion(
        'El servicio de acceso no está disponible en este momento. Inténtalo más tarde.',
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
          'No se pudo iniciar la sesión. Inténtalo nuevamente.',
        );
      }

      // Reutiliza getUser, perfil_del_usuario_actual y la validacion de id
      // implementados en ServicioRegistro.
      final perfil = await const ServicioRegistro().comprobarConfirmacion(
        correo,
      );
      if (perfil == null) {
        throw const ErrorInicioSesion(
          'Confirma tu correo electrónico mediante el enlace enviado antes de iniciar sesión.',
        );
      }
      if (!perfil.cuentaActiva) {
        throw const ErrorInicioSesion(
          'Tu cuenta no se encuentra activa en este momento. Si necesitas ayuda, comunícate con soporte.',
        );
      }
      return perfil;
    } catch (error) {
      // Si Auth funciono pero fallo el perfil o la cuenta esta inactiva,
      // cierra esta sesion sin cerrar las sesiones de otros dispositivos.
      if (sesionCreada) {
        try {
          await cliente.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          throw ErrorInicioSesion(
            '${explicarError(error)} Revisa tu conexión e inténtalo nuevamente.',
          );
        }
      }
      rethrow;
    }
  }

  /// Inicia OAuth de Google y retorna a la app móvil mediante su esquema propio.
  /// En web, Supabase conserva la URL actual como destino de retorno.
  Future<void> iniciarConGoogle() async {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorInicioSesion(
        'El servicio de acceso no está disponible en este momento. Inténtalo más tarde.',
      );
    }

    final inicioCorrecto = await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb
          ? Uri.base.replace(queryParameters: const {}, fragment: '').toString()
          : 'psicobloom://acceso/',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!inicioCorrecto) {
      throw const ErrorInicioSesion(
        'No se pudo abrir el acceso con Google. Inténtalo nuevamente.',
      );
    }
  }

  /// Alias compatible con pruebas existentes.
  Future<PerfilUsuario> iniciarSesionPaciente({
    required String correo,
    required String clave,
  }) => iniciarSesion(correo: correo, clave: clave);

  static String explicarError(Object error) {
    if (error is ErrorInicioSesion) return error.mensaje;
    if (error is ErrorRegistro) return error.mensaje;
    if (error is PostgrestException) {
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto: 'No pudimos cargar la información de tu cuenta en este momento. Inténtalo nuevamente.',
      );
    }
    return TraductorErroresSupabase.traducirErrorAutenticacion(
      error,
      accionPorDefecto:
          'No pudimos iniciar tu sesión en este momento. Inténtalo nuevamente.',
    );
  }
}
