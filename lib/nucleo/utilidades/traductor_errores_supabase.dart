import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduce excepciones técnicas de autenticación, base de datos, almacenamiento
/// y red en mensajes claros y naturales en español para las personas usuarias.
/// Nunca expone nombres internos de tablas, funciones SQL, códigos HTTP ni
/// mensajes crudos en inglés.
class TraductorErroresSupabase {
  const TraductorErroresSupabase._();

  static final RegExp _patronCorreo = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _patronMinuscula = RegExp(r'[a-z]');
  static final RegExp _patronMayuscula = RegExp(r'[A-Z]');
  static final RegExp _patronNumero = RegExp(r'[0-9]');
  static final RegExp _patronSimbolo = RegExp(r'[!-/:-@\[-`{-~]');

  /// Valida el formato de un correo electrónico en formularios.
  static String? validarCorreo(String? valor) {
    final correo = valor?.trim() ?? '';
    if (correo.isEmpty) {
      return 'Ingresa tu correo electrónico para continuar.';
    }
    if (!_patronCorreo.hasMatch(correo)) {
      return 'Revisa tu correo electrónico. Parece que tiene un formato incorrecto.';
    }
    return null;
  }

  /// Verifica si una contraseña cumple la política real del proyecto:
  /// mínimo 11 caracteres, mayúscula, minúscula, número y símbolo.
  static bool cumpleRequisitosClave(String clave) {
    if (clave.length < 11) return false;
    return _patronMinuscula.hasMatch(clave) &&
        _patronMayuscula.hasMatch(clave) &&
        _patronNumero.hasMatch(clave) &&
        _patronSimbolo.hasMatch(clave);
  }

  /// Valida la contraseña en el formulario de registro.
  static String? validarClaveRegistro(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa una contraseña para continuar.';
    }
    if (valor.length < 11) {
      return 'La contraseña debe contener al menos 11 caracteres';
    }
    if (!cumpleRequisitosClave(valor)) {
      return 'Tu contraseña aún no cumple los requisitos: incluye mayúscula, minúscula, número y símbolo.';
    }
    return null;
  }

  /// Valida que la confirmación coincida exactamente con la contraseña ingresada.
  static String? validarConfirmacionClave(
    String? confirmacion,
    String claveOriginal,
  ) {
    if (confirmacion == null || confirmacion.isEmpty) {
      return 'Confirma tu contraseña para continuar.';
    }
    if (confirmacion != claveOriginal) {
      return 'Las contraseñas no coinciden. Revísalas e inténtalo nuevamente.';
    }
    return null;
  }

  /// Determina si una excepción corresponde a un fallo de red o falta de Internet.
  static bool esErrorDeConexion(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException) {
      return true;
    }
    final texto = error.toString().toLowerCase();
    return texto.contains('socketexception') ||
        texto.contains('failed host lookup') ||
        texto.contains('network is unreachable') ||
        texto.contains('connection refused') ||
        texto.contains('connection timed out') ||
        texto.contains('software caused connection abort') ||
        texto.contains('clientexception') ||
        texto.contains('xmlhttprequest error');
  }

  /// Traduce errores de autenticación (`AuthException`, `PostgrestException`, red)
  /// a un mensaje comprensible para la persona usuaria.
  static String traducirErrorAutenticacion(
    Object error, {
    String accionPorDefecto = 'No pudimos completar tu solicitud en este momento. Inténtalo nuevamente en unos minutos.',
  }) {
    if (esErrorDeConexion(error)) {
      return 'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.';
    }

    if (error is AuthWeakPasswordException) {
      return 'Tu contraseña aún no cumple los requisitos. Usa al menos 11 caracteres e incluye mayúsculas, minúsculas, números y un símbolo.';
    }

    if (error is AuthException) {
      final codigo = (error.code ?? '').trim().toLowerCase();
      final estado = (error.statusCode ?? '').trim();
      final mensaje = error.message.toLowerCase();

      if (estado == '429' ||
          codigo.contains('rate_limit') ||
          codigo.contains('over_email_send_rate_limit') ||
          codigo.contains('over_request_rate_limit') ||
          mensaje.contains('rate limit') ||
          mensaje.contains('too many requests') ||
          mensaje.contains('for security purposes, you can only request')) {
        return 'Has realizado varios intentos. Espera un momento antes de volver a intentarlo.';
      }

      if (codigo == 'invalid_credentials' ||
          mensaje.contains('invalid login credentials') ||
          mensaje.contains('invalid credentials')) {
        return 'El correo o la contraseña son incorrectos. Revísalos e inténtalo nuevamente.';
      }

      if (codigo == 'email_not_confirmed' ||
          mensaje.contains('email not confirmed')) {
        return 'Confirma tu correo electrónico mediante el enlace enviado antes de iniciar sesión.';
      }

      if (codigo == 'user_already_exists' ||
          codigo == 'email_exists' ||
          mensaje.contains('user already registered') ||
          mensaje.contains('already been registered')) {
        return 'Este correo electrónico ya está registrado. Intenta iniciar sesión o recupera tu contraseña.';
      }

      if (codigo == 'same_password' ||
          mensaje.contains('same password') ||
          mensaje.contains('different from the old password') ||
          (mensaje.contains('different') && mensaje.contains('password'))) {
        return 'Elige una contraseña diferente de la anterior.';
      }

      if (codigo == 'weak_password' ||
          mensaje.contains('password should') ||
          mensaje.contains('password must') ||
          mensaje.contains('weak password') ||
          mensaje.contains('at least one character') ||
          mensaje.contains('password is known to be weak')) {
        return 'Tu contraseña aún no cumple los requisitos. Usa al menos 11 caracteres e incluye mayúsculas, minúsculas, números y un símbolo.';
      }

      if (codigo == 'otp_expired' ||
          codigo == 'bad_jwt' ||
          codigo == 'flow_state_expired' ||
          codigo == 'flow_state_not_found' ||
          mensaje.contains('expired') ||
          mensaje.contains('invalid token') ||
          mensaje.contains('token has expired')) {
        return 'Este enlace ya no es válido o ha expirado. Solicita uno nuevo para continuar.';
      }

      if (codigo == 'email_address_invalid' ||
          (codigo == 'validation_failed' && mensaje.contains('email')) ||
          mensaje.contains('invalid email') ||
          mensaje.contains('unable to validate email')) {
        return 'Revisa tu correo electrónico. Parece que tiene un formato incorrecto.';
      }

      if (codigo == 'user_banned' ||
          mensaje.contains('banned') ||
          mensaje.contains('user is disabled')) {
        return 'Tu cuenta no se encuentra activa en este momento. Si necesitas ayuda, comunícate con soporte.';
      }

      if (mensaje.contains('password')) {
        return 'Tu contraseña aún no cumple los requisitos. Usa al menos 11 caracteres e incluye mayúsculas, minúsculas, números y un símbolo.';
      }

      if (mensaje.contains('network') ||
          mensaje.contains('connection') ||
          mensaje.contains('socket') ||
          mensaje.contains('fetch')) {
        return 'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.';
      }

      return accionPorDefecto;
    }

    if (error is PostgrestException) {
      return traducirErrorBaseDatos(error, accionPorDefecto: accionPorDefecto);
    }

    return accionPorDefecto;
  }

  /// Traduce excepciones de base de datos (`PostgrestException`) sin revelar
  /// nombres de funciones RPC, tablas ni consultas internas.
  static String traducirErrorBaseDatos(
    Object error, {
    String accionPorDefecto = 'No pudimos completar la operación en este momento. Inténtalo nuevamente.',
  }) {
    if (esErrorDeConexion(error)) {
      return 'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.';
    }

    if (error is PostgrestException) {
      final codigo = (error.code ?? '').trim();
      if (codigo == '42501') {
        return 'No tienes permisos para realizar esta acción o tu cuenta no se encuentra activa.';
      }
      if (codigo == '23505') {
        return 'Esta información ya se encuentra registrada. Revisa los datos e inténtalo nuevamente.';
      }
      if (codigo == '22023' || codigo == '23514') {
        return 'Algunos de los datos ingresados no son válidos. Revísalos e inténtalo nuevamente.';
      }
      if (codigo == 'PGRST301' || codigo == '401') {
        return 'Tu sesión ha expirado. Inicia sesión nuevamente para continuar.';
      }
      return accionPorDefecto;
    }

    return accionPorDefecto;
  }

  /// Traduce excepciones de almacenamiento de archivos (`StorageException`).
  static String traducirErrorAlmacenamiento(
    Object error, {
    String accionPorDefecto = 'No pudimos guardar la fotografía en este momento. Inténtalo nuevamente.',
  }) {
    if (esErrorDeConexion(error)) {
      return 'No pudimos conectarnos. Revisa tu conexión a Internet e inténtalo nuevamente.';
    }

    if (error is StorageException) {
      final estado = (error.statusCode ?? '').trim();
      final mensaje = error.message.toLowerCase();

      if (estado == '413' ||
          mensaje.contains('payload too large') ||
          mensaje.contains('exceeded the maximum allowed size')) {
        return 'La fotografía supera el límite de 5 MB. Elige una imagen más ligera.';
      }
      if (estado == '401' ||
          estado == '403' ||
          mensaje.contains('row-level security') ||
          mensaje.contains('not authorized') ||
          mensaje.contains('permission')) {
        return 'No tienes permisos para actualizar esta fotografía. Inicia sesión nuevamente e inténtalo de nuevo.';
      }
      if (mensaje.contains('mime') ||
          mensaje.contains('invalid_mime_type') ||
          mensaje.contains('format')) {
        return 'El formato de la imagen no es compatible. Usa una fotografía en formato JPG, PNG o WebP.';
      }
      return accionPorDefecto;
    }

    return accionPorDefecto;
  }
}
