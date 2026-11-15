import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';

/// Estados posibles al resolver la sesion inicial o activa del usuario.
enum EstadoResolucionSesion {
  sinSesion,
  autenticado,
  cuentaInactiva,
  errorConexion,
}

/// Resultado tipado de comprobar la sesion y el perfil del usuario actual.
class ResultadoResolucionSesion {
  final EstadoResolucionSesion estado;
  final PerfilUsuario? perfil;
  final String? mensaje;

  const ResultadoResolucionSesion({
    required this.estado,
    this.perfil,
    this.mensaje,
  });

  const ResultadoResolucionSesion.sinSesion({this.mensaje})
    : estado = EstadoResolucionSesion.sinSesion,
      perfil = null;

  const ResultadoResolucionSesion.autenticado(PerfilUsuario this.perfil)
    : estado = EstadoResolucionSesion.autenticado,
      mensaje = null;

  const ResultadoResolucionSesion.cuentaInactiva({
    this.perfil,
    this.mensaje =
        'Tu cuenta está inactiva. Contacta al administrador de PsicoBloom.',
  }) : estado = EstadoResolucionSesion.cuentaInactiva;

  const ResultadoResolucionSesion.errorConexion({
    this.mensaje = 'No se pudo comprobar tu sesión por un problema de conexión. Revisa Internet e inténtalo de nuevo.',
  }) : estado = EstadoResolucionSesion.errorConexion,
       perfil = null;
}

/// Servicio encargado de recuperar la sesion persistente, consultar el rol
/// y estado de la cuenta mediante `perfil_del_usuario_actual` y cerrar sesion.
class ServicioSesion {
  const ServicioSesion();

  /// Comprueba si existe una sesion persistente y obtiene el perfil desde el backend.
  /// No confunde un fallo de red con una cuenta inactiva.
  Future<ResultadoResolucionSesion> resolverSesionActual() async {
    if (!ConfiguracionSupabase.estaConfigurado) {
      return const ResultadoResolucionSesion.sinSesion();
    }

    final cliente = Supabase.instance.client;
    final sesion = cliente.auth.currentSession;
    if (sesion == null) {
      return const ResultadoResolucionSesion.sinSesion();
    }

    try {
      final respuestaUsuario = await cliente.auth.getUser();
      final usuario = respuestaUsuario.user;
      if (usuario == null || usuario.emailConfirmedAt == null) {
        await cerrarSesionLocalSilencioso(cliente);
        return const ResultadoResolucionSesion.sinSesion();
      }

      final datos = await cliente.rpc('perfil_del_usuario_actual');
      if (datos is! List || datos.length != 1 || datos.first is! Map) {
        await cerrarSesionLocalSilencioso(cliente);
        return const ResultadoResolucionSesion.sinSesion(
          mensaje: 'No se encontró un perfil válido para la sesión actual.',
        );
      }

      final perfil = PerfilUsuario.desdeMapa(
        Map<String, dynamic>.from(datos.first as Map),
      );
      if (perfil.id != usuario.id) {
        await cerrarSesionLocalSilencioso(cliente);
        return const ResultadoResolucionSesion.sinSesion(
          mensaje: 'El perfil recibido no coincide con la sesión autenticada.',
        );
      }

      if (!perfil.cuentaActiva) {
        await cerrarSesionLocalSilencioso(cliente);
        return ResultadoResolucionSesion.cuentaInactiva(perfil: perfil);
      }

      return ResultadoResolucionSesion.autenticado(perfil);
    } on AuthException catch (error) {
      if (_esSesionExpiradaOInvalida(error)) {
        await cerrarSesionLocalSilencioso(cliente);
        return const ResultadoResolucionSesion.sinSesion(
          mensaje: 'Tu sesión expiró. Vuelve a iniciar sesión para continuar.',
        );
      }
      return const ResultadoResolucionSesion.errorConexion();
    } on PostgrestException catch (_) {
      return const ResultadoResolucionSesion.errorConexion(
        mensaje: 'No se pudo consultar el perfil en el servidor. Comprueba tu conexión e inténtalo nuevamente.',
      );
    } on FormatException catch (error) {
      return ResultadoResolucionSesion.errorConexion(mensaje: error.message);
    } catch (_) {
      return const ResultadoResolucionSesion.errorConexion();
    }
  }

  /// Cierra la sesion del usuario y limpia el estado privado en memoria.
  Future<void> cerrarSesion() async {
    GestorFavoritos.instancia.limpiar();
    if (!ConfiguracionSupabase.estaConfigurado) {
      return;
    }
    final cliente = Supabase.instance.client;
    try {
      await cliente.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Incluso si falla la red, intentamos limpiar la sesion local.
    }
  }

  static Future<void> cerrarSesionLocalSilencioso(
    SupabaseClient cliente,
  ) async {
    GestorFavoritos.instancia.limpiar();
    try {
      await cliente.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  static bool _esSesionExpiradaOInvalida(AuthException error) {
    final codigo = error.statusCode;
    final mensaje = error.message.toLowerCase();
    return codigo == '401' ||
        codigo == '403' ||
        mensaje.contains('invalid_grant') ||
        mensaje.contains('refresh_token') ||
        mensaje.contains('jwt') ||
        mensaje.contains('expired') ||
        mensaje.contains('session_not_found') ||
        mensaje.contains('user_not_found');
  }
}
