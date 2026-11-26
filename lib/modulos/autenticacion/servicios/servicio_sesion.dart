import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';
import 'package:boom/modulos/paciente/controladores/gestor_resultado_orientacion.dart';

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

  /// Canal ligero en memoria para mantener sincronizados los cambios del perfil
  /// del paciente (nombre, apellido y fotografia) entre Perfil e Inicio.
  static final ValueNotifier<PerfilUsuario?> perfilPacienteSincronizado =
      ValueNotifier<PerfilUsuario?>(null);

  static void notificarPerfilPacienteActualizado(PerfilUsuario perfil) {
    perfilPacienteSincronizado.value = perfil;
  }

  static void limpiarPerfilPacienteSincronizado() {
    perfilPacienteSincronizado.value = null;
  }

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

      var perfilBase = PerfilUsuario.desdeMapa(
        Map<String, dynamic>.from(datos.first as Map),
      );

      // Si el usuario es un paciente activo, consulta su fotografia personalizada
      // almacenada en Supabase cuando la migracion 24 esta aplicada.
      if (perfilBase.rol == 'paciente' && perfilBase.cuentaActiva) {
        try {
          final datosPaciente = await cliente.rpc(
            'obtener_perfil_paciente_propio',
          );
          if (datosPaciente is List &&
              datosPaciente.length == 1 &&
              datosPaciente.first is Map) {
            perfilBase = PerfilUsuario.desdeMapa(
              Map<String, dynamic>.from(datosPaciente.first as Map),
            );
          }
        } catch (_) {
          // Mantiene compatibilidad si la RPC dedicada aun no esta desplegada.
        }
      }

      final fotoSesion = extraerFotoDesdeMetadatos(usuario.userMetadata);
      final perfil =
          !perfilBase.tieneFotoPersonalizada &&
              (perfilBase.fotoUrl == null ||
                  perfilBase.fotoUrl!.trim().isEmpty) &&
              fotoSesion != null
          ? perfilBase.copiarCon(
              fotoUrl: fotoSesion,
              tieneFotoPersonalizada: false,
            )
          : perfilBase;
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

      if (perfil.rol == 'paciente') {
        notificarPerfilPacienteActualizado(perfil);
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

  /// Extrae una URL de foto valida desde los metadatos de sesion (ej. Google OAuth).
  static String? extraerFotoDesdeMetadatos(Map<String, dynamic>? metadatos) {
    if (metadatos == null) return null;
    for (final clave in const ['foto_url', 'avatar_url', 'picture']) {
      final valor = metadatos[clave];
      if (valor is String && valor.trim().isNotEmpty) {
        return valor.trim();
      }
    }
    return null;
  }

  /// Obtiene la foto disponible en la sesion activa (por ejemplo, avatar de Google)
  /// sin realizar llamadas de red ni requerir cambios en el esquema de base de datos.
  String? obtenerFotoUsuarioActual() {
    if (!ConfiguracionSupabase.estaConfigurado) {
      return null;
    }
    try {
      final usuario = Supabase.instance.client.auth.currentUser;
      return extraerFotoDesdeMetadatos(usuario?.userMetadata);
    } catch (_) {
      return null;
    }
  }

  /// Cierra la sesion del usuario y limpia el estado privado en memoria.
  Future<void> cerrarSesion() async {
    GestorFavoritos.instancia.limpiar();
    GestorResultadoOrientacion.instancia.limpiar();
    limpiarPerfilPacienteSincronizado();
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
    GestorResultadoOrientacion.instancia.limpiar();
    limpiarPerfilPacienteSincronizado();
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
