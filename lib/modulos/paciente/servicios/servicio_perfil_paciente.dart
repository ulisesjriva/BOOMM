import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorPerfilPaciente implements Exception {
  final String mensaje;
  const ErrorPerfilPaciente(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Servicio encargado de consultar y actualizar el perfil basico del paciente autenticado.
/// Reutiliza las funciones RPC seguras `perfil_del_usuario_actual` y `actualizar_nombre_apellido`.
class ServicioPerfilPaciente {
  const ServicioPerfilPaciente();

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorPerfilPaciente(
        'Falta la configuración de Supabase. Ejecuta la aplicación con la URL y la clave pública.',
      );
    }
    return Supabase.instance.client;
  }

  /// Obtiene el perfil del paciente autenticado desde el backend.
  Future<PerfilUsuario> obtenerPerfilPropio() async {
    final cliente = _cliente;
    final sesion = cliente.auth.currentSession;
    if (sesion == null) {
      throw const ErrorPerfilPaciente(
        'No hay una sesión activa. Inicia sesión nuevamente.',
      );
    }

    final datos = await cliente.rpc('perfil_del_usuario_actual');
    if (datos is! List || datos.length != 1 || datos.first is! Map) {
      throw const ErrorPerfilPaciente(
        'No se encontró el perfil del paciente en el servidor.',
      );
    }

    final perfil = PerfilUsuario.desdeMapa(
      Map<String, dynamic>.from(datos.first as Map),
    );
    if (!perfil.cuentaActiva) {
      throw const ErrorPerfilPaciente(
        'Tu cuenta está inactiva y no puede realizar modificaciones.',
      );
    }
    return perfil;
  }

  /// Actualiza el nombre y apellido del paciente autenticado y devuelve el perfil actualizado.
  Future<PerfilUsuario> actualizarDatosBasicos({
    required String nombre,
    required String apellido,
  }) async {
    final nombreLimpio = nombre.trim();
    final apellidoLimpio = apellido.trim();

    if (nombreLimpio.length < 2) {
      throw const ErrorPerfilPaciente(
        'El nombre debe contener al menos 2 caracteres.',
      );
    }
    if (apellidoLimpio.length < 2) {
      throw const ErrorPerfilPaciente(
        'El apellido debe contener al menos 2 caracteres.',
      );
    }

    await _cliente.rpc(
      'actualizar_nombre_apellido',
      params: {'p_nombre': nombreLimpio, 'p_apellido': apellidoLimpio},
    );

    return obtenerPerfilPropio();
  }

  /// Solicita el cambio del correo de autenticacion en Supabase Auth.
  /// El trigger `sincronizar_correo` actualiza `perfiles.correo` tras confirmarse en Auth.
  Future<void> solicitarCambioCorreo(String nuevoCorreo) async {
    final correoLimpio = nuevoCorreo.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correoLimpio)) {
      throw const ErrorPerfilPaciente('Ingresa un correo electrónico válido.');
    }

    await _cliente.auth.updateUser(UserAttributes(email: correoLimpio));
  }

  static String explicarError(Object error) {
    if (error is ErrorPerfilPaciente) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'No tienes permiso para modificar este perfil o tu cuenta está inactiva.';
      }
      if (error.code == '22023') {
        return 'El nombre y el apellido requieren al menos 2 caracteres.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto:
            'No se pudo guardar el perfil en este momento. Inténtalo de nuevo.',
      );
    }
    if (error is AuthException) {
      return TraductorErroresSupabase.traducirErrorAutenticacion(
        error,
        accionPorDefecto: 'No se pudo actualizar la cuenta en este momento. Inténtalo de nuevo.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto: 'Ocurrió un problema de conexión al procesar tu perfil. Inténtalo de nuevo.',
    );
  }
}
