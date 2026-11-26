import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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

/// Fotografia seleccionada localmente en el dispositivo del paciente.
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

/// Respuesta normalizada de la Edge Function `gestionar-foto-paciente`.
class RespuestaFotoPacienteEdge {
  final int estado;
  final dynamic datos;

  const RespuestaFotoPacienteEdge({required this.estado, required this.datos});
}

typedef ProveedorSeleccionFotoPaciente = Future<ImagenCrudaPaciente?> Function(
  ImageSource origen,
);

typedef InvocadorFotoPacienteEdge = Future<RespuestaFotoPacienteEdge> Function(
  String nombreFuncion, {
  required Map<String, dynamic> cuerpo,
});

typedef EjecutorRpcPerfilPaciente = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

/// Servicio encargado de consultar y actualizar el perfil basico del paciente autenticado,
/// asi como seleccionar, validar, subir y eliminar su fotografia mediante la Edge Function
/// segura `gestionar-foto-paciente` (Cloudinary firmado en servidor + Supabase).
class ServicioPerfilPaciente {
  final ProveedorSeleccionFotoPaciente? proveedorSeleccionFoto;
  final InvocadorFotoPacienteEdge? invocadorFotoEdge;
  final EjecutorRpcPerfilPaciente? ejecutorRpc;
  final String? Function()? lectorUsuarioActualId;

  const ServicioPerfilPaciente({
    this.proveedorSeleccionFoto,
    this.invocadorFotoEdge,
    this.ejecutorRpc,
    this.lectorUsuarioActualId,
  });

  static const String nombreFuncionGestionarFoto = 'gestionar-foto-paciente';
  static const int limiteBytesFotografia = 5 * 1024 * 1024; // 5 MB
  static const Duration tiempoEsperaFoto = Duration(seconds: 25);

  /// Abre la galeria o camara mediante `image_picker` y valida localmente que el archivo
  /// sea JPG o PNG (por firma binaria real) y no supere 5 MB.
  /// Devuelve null si el usuario cancela la seleccion.
  Future<ArchivoFotoPacienteSeleccionada?> seleccionarFotografia({
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
    } on UnimplementedError {
      throw ErrorPerfilPaciente(
        origen == ImageSource.camera
            ? 'La cámara no está disponible en esta plataforma.'
            : 'No se pudo acceder a la galería en esta plataforma.',
      );
    } on UnsupportedError {
      throw ErrorPerfilPaciente(
        origen == ImageSource.camera
            ? 'La cámara no está disponible en este dispositivo.'
            : 'La galería no está disponible en este dispositivo.',
      );
    } on PlatformException catch (error) {
      final codigo = error.code.toLowerCase();
      if (origen == ImageSource.camera) {
        if (codigo.contains('denied') || codigo.contains('permission')) {
          throw const ErrorPerfilPaciente(
            'Permiso de cámara denegado. Habilítalo en la configuración del dispositivo.',
          );
        }
        throw const ErrorPerfilPaciente(
          'La cámara no está disponible en este dispositivo o no se otorgaron permisos.',
        );
      }
      if (codigo.contains('denied') || codigo.contains('permission')) {
        throw const ErrorPerfilPaciente(
          'Permiso de galería denegado. Habilítalo en la configuración del dispositivo.',
        );
      }
      throw const ErrorPerfilPaciente(
        'No se pudo acceder a la galería del dispositivo. Verifica los permisos e inténtalo nuevamente.',
      );
    } catch (_) {
      throw ErrorPerfilPaciente(
        origen == ImageSource.camera
            ? 'La cámara no está disponible en este dispositivo o no se otorgaron permisos.'
            : 'No se pudo acceder a la galería del dispositivo. Verifica los permisos e inténtalo nuevamente.',
      );
    }
  }

  /// Mantiene compatibilidad con llamadas anteriores a la seleccion desde galeria.
  Future<ArchivoFotoPacienteSeleccionada?> seleccionarFotografiaGaleria({
    ImageSource origen = ImageSource.gallery,
  }) => seleccionarFotografia(origen: origen);

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

  String? _obtenerUidActual() {
    if (lectorUsuarioActualId != null) {
      return lectorUsuarioActualId!();
    }
    final cliente = _cliente;
    return cliente.auth.currentSession?.user.id ?? cliente.auth.currentUser?.id;
  }

  Future<dynamic> _invocarRpc(
    String nombreFuncion, {
    Map<String, dynamic>? parametros,
  }) {
    if (ejecutorRpc != null) {
      return ejecutorRpc!(nombreFuncion, parametros: parametros);
    }
    return _cliente.rpc(nombreFuncion, params: parametros);
  }

  Future<RespuestaFotoPacienteEdge> _invocarEdgeFoto(
    Map<String, dynamic> cuerpo,
  ) async {
    if (invocadorFotoEdge != null) {
      return invocadorFotoEdge!(nombreFuncionGestionarFoto, cuerpo: cuerpo);
    }
    final respuesta = await _cliente.functions.invoke(
      nombreFuncionGestionarFoto,
      body: cuerpo,
    );
    return RespuestaFotoPacienteEdge(
      estado: respuesta.status,
      datos: respuesta.data,
    );
  }

  /// Obtiene el perfil del paciente autenticado desde el backend.
  /// Usa `obtener_perfil_paciente_propio` (migracion 24) con respaldo automatico
  /// a `perfil_del_usuario_actual` si la RPC nueva aun no esta instalada.
  Future<PerfilUsuario> obtenerPerfilPropio() async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilPaciente(
        'No hay una sesión activa. Inicia sesión nuevamente.',
      );
    }

    dynamic datos;
    try {
      datos = await _invocarRpc('obtener_perfil_paciente_propio');
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        datos = await _invocarRpc('perfil_del_usuario_actual');
      } else {
        rethrow;
      }
    }

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

  /// Sube la fotografia validada a Cloudinary mediante la Edge Function
  /// `gestionar-foto-paciente` y verifica su persistencia en Supabase.
  Future<PerfilUsuario> subirYGuardarFotografia(
    ArchivoFotoPacienteSeleccionada imagen,
  ) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilPaciente(
        'Sesión no válida para actualizar la fotografía.',
      );
    }

    validarFotografiaLocal(imagen.bytes, nombreArchivo: imagen.nombreArchivo);

    try {
      final respuesta = await _invocarEdgeFoto(<String, dynamic>{
        'accion': 'subir',
        'archivoBase64': base64Encode(imagen.bytes),
      }).timeout(tiempoEsperaFoto);

      if (respuesta.estado != 200) {
        throw ErrorPerfilPaciente(
          _mapearMensajeErrorEdge(respuesta.estado, respuesta.datos),
        );
      }

      final datosMapa = _normalizarMapaRespuesta(respuesta.datos);
      final urlSubida = (datosMapa?['fotoUrl'] as String?)?.trim() ?? '';
      if (!urlSubida.startsWith('https://')) {
        throw const ErrorPerfilPaciente(
          'No se pudo obtener una URL válida para la fotografía subida.',
        );
      }

      final perfilVerificado = await obtenerPerfilPropio();
      final fotoAsociada = perfilVerificado.fotoUrl?.trim() ?? '';
      if (fotoAsociada.isEmpty ||
          fotoAsociada != urlSubida ||
          !perfilVerificado.tieneFotoPersonalizada) {
        throw const ErrorPerfilPaciente(
          'No se pudo confirmar la actualización de la fotografía.',
        );
      }
      return perfilVerificado;
    } on TimeoutException {
      throw const ErrorPerfilPaciente(
        'La actualización de la fotografía tardó demasiado.',
      );
    } on FunctionException catch (error) {
      throw ErrorPerfilPaciente(
        _mapearMensajeErrorEdge(error.status, error.details),
      );
    } on ErrorPerfilPaciente {
      rethrow;
    } catch (_) {
      throw const ErrorPerfilPaciente('No se pudo actualizar la foto');
    }
  }

  /// Elimina la fotografia personalizada del paciente en Cloudinary y Supabase
  /// mediante la Edge Function `gestionar-foto-paciente`.
  Future<PerfilUsuario> eliminarFotografia() async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilPaciente(
        'Sesión no válida para eliminar la fotografía.',
      );
    }

    try {
      final respuesta = await _invocarEdgeFoto(const <String, dynamic>{
        'accion': 'eliminar',
      }).timeout(tiempoEsperaFoto);

      if (respuesta.estado != 200) {
        throw ErrorPerfilPaciente(
          _mapearMensajeErrorEdge(respuesta.estado, respuesta.datos),
        );
      }

      final perfilVerificado = await obtenerPerfilPropio();
      if (perfilVerificado.tieneFotoPersonalizada) {
        throw const ErrorPerfilPaciente(
          'No se pudo confirmar la eliminación de la fotografía.',
        );
      }
      return perfilVerificado.copiarCon(limpiarFotoUrl: true);
    } on TimeoutException {
      throw const ErrorPerfilPaciente(
        'La eliminación de la fotografía tardó demasiado.',
      );
    } on FunctionException catch (error) {
      throw ErrorPerfilPaciente(
        _mapearMensajeErrorEdge(error.status, error.details),
      );
    } on ErrorPerfilPaciente {
      rethrow;
    } catch (_) {
      throw const ErrorPerfilPaciente('No se pudo eliminar la foto');
    }
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

    await _invocarRpc(
      'actualizar_nombre_apellido',
      parametros: {'p_nombre': nombreLimpio, 'p_apellido': apellidoLimpio},
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

  Map<String, dynamic>? _normalizarMapaRespuesta(dynamic datos) {
    if (datos is Map<String, dynamic>) {
      return datos;
    }
    if (datos is Map) {
      return Map<String, dynamic>.from(datos);
    }
    if (datos is String && datos.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(datos);
        if (decodificado is Map) {
          return Map<String, dynamic>.from(decodificado);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _mapearMensajeErrorEdge(int estado, dynamic detalles) {
    final mapa = _normalizarMapaRespuesta(detalles);
    final mensajeServidor = (mapa?['mensaje'] as String?)?.trim();
    if (mensajeServidor != null && mensajeServidor.isNotEmpty) {
      return mensajeServidor;
    }
    if (estado == 401) {
      return 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.';
    }
    if (estado == 403) {
      return 'No tienes permiso para modificar esta fotografía.';
    }
    if (estado == 400 || estado == 413 || estado == 415) {
      return 'Solo se permiten fotografías JPG o PNG de hasta 5 MB.';
    }
    return 'No se pudo actualizar la foto';
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
