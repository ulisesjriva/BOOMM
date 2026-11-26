import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
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

/// Fotografia seleccionada localmente en el dispositivo del paciente para vista previa.
/// Aun no implica almacenamiento permanente en Supabase ni Cloudinary.
class ArchivoFotoPacienteSeleccionada {
  final Uint8List bytes;
  final String extensionArchivo;
  final String tipoMime;
  final String? nombreArchivo;

  const ArchivoFotoPacienteSeleccionada({
    required this.bytes,
    required this.extensionArchivo,
    required this.tipoMime,
    this.nombreArchivo,
  });

  int get tamanoBytes => bytes.lengthInBytes;
}

/// Resultado crudo de un selector de imagenes (permite inyectar dobles en pruebas).
class ImagenCrudaPaciente {
  final Uint8List bytes;
  final String? nombreArchivo;

  const ImagenCrudaPaciente({required this.bytes, this.nombreArchivo});
}

typedef ProveedorSeleccionFotoPaciente = Future<ImagenCrudaPaciente?> Function(
  ImageSource origen,
);

/// Servicio encargado de consultar y actualizar el perfil basico del paciente autenticado,
/// asi como seleccionar y validar localmente fotografias desde la galeria.
/// Reutiliza las funciones RPC seguras `perfil_del_usuario_actual` y `actualizar_nombre_apellido`.
class ServicioPerfilPaciente {
  final ProveedorSeleccionFotoPaciente? proveedorSeleccionFoto;

  const ServicioPerfilPaciente({this.proveedorSeleccionFoto});

  static const int limiteBytesFotografia = 5 * 1024 * 1024; // 5 MB

  /// Abre la galeria mediante `image_picker` y valida localmente que el archivo
  /// sea JPG o PNG (por firma binaria real) y no supere 5 MB.
  /// Devuelve null si el usuario cancela la seleccion.
  Future<ArchivoFotoPacienteSeleccionada?> seleccionarFotografiaGaleria({
    ImageSource origen = ImageSource.gallery,
  }) async {
    try {
      final ImagenCrudaPaciente? cruda;
      if (proveedorSeleccionFoto != null) {
        cruda = await proveedorSeleccionFoto!(origen);
      } else {
        final selector = ImagePicker();
        final archivo = await selector.pickImage(
          source: origen,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (archivo == null) {
          return null;
        }
        cruda = ImagenCrudaPaciente(
          bytes: await archivo.readAsBytes(),
          nombreArchivo: archivo.name,
        );
      }

      if (cruda == null) {
        return null;
      }

      return validarFotografiaLocal(
        cruda.bytes,
        nombreArchivo: cruda.nombreArchivo,
      );
    } on ErrorPerfilPaciente {
      rethrow;
    } catch (_) {
      throw const ErrorPerfilPaciente(
        'No se pudo acceder a la galería del dispositivo. Verifica los permisos e inténtalo nuevamente.',
      );
    }
  }

  /// Valida localmente tamano (<= 5 MB) y firma binaria real (JPG o PNG).
  static ArchivoFotoPacienteSeleccionada validarFotografiaLocal(
    Uint8List bytes, {
    String? nombreArchivo,
  }) {
    if (bytes.isEmpty) {
      throw const ErrorPerfilPaciente('El archivo seleccionado está vacío.');
    }
    if (bytes.lengthInBytes > limiteBytesFotografia) {
      throw const ErrorPerfilPaciente(
        'La fotografía supera el límite de 5 MB. Elige una imagen más ligera.',
      );
    }

    // Firma JPG: FF D8 FF
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ArchivoFotoPacienteSeleccionada(
        bytes: bytes,
        extensionArchivo: 'jpg',
        tipoMime: 'image/jpeg',
        nombreArchivo: nombreArchivo,
      );
    }

    // Firma PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return ArchivoFotoPacienteSeleccionada(
        bytes: bytes,
        extensionArchivo: 'png',
        tipoMime: 'image/png',
        nombreArchivo: nombreArchivo,
      );
    }

    throw const ErrorPerfilPaciente(
      'Solo se permiten fotografías en formato JPG o PNG.',
    );
  }

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
