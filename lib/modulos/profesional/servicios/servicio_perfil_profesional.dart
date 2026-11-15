import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

class ErrorPerfilProfesional implements Exception {
  final String mensaje;
  const ErrorPerfilProfesional(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Datos de una imagen seleccionada localmente antes de subirla al servidor.
class ArchivoImagenSeleccionada {
  final Uint8List bytes;
  final String extensionArchivo;
  final String tipoMime;

  const ArchivoImagenSeleccionada({
    required this.bytes,
    required this.extensionArchivo,
    required this.tipoMime,
  });
}

typedef EjecutorRpcPerfilProfesional = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

/// Respuesta normalizada de la Edge Function de subida de fotografía.
class RespuestaSubidaFotoEdge {
  final int estado;
  final dynamic datos;

  const RespuestaSubidaFotoEdge({required this.estado, required this.datos});
}

typedef InvocadorSubidaFotoEdge = Future<RespuestaSubidaFotoEdge> Function(
  String nombreFuncion, {
  required Map<String, dynamic> cuerpo,
});

/// Servicio encargado de consultar y actualizar el perfil profesional,
/// sus especialidades (`public."ProfesionalEspecialidad"`), servicios (`public."Servicios"`),
/// modalidad y ubicacion (`public."Profesionales"`) y fotografia mediante la Edge Function
/// `subir-foto-profesional` (Cloudinary firmado en servidor).
/// No utiliza secretos privados en Flutter.
class ServicioPerfilProfesional {
  final RepositorioEspecialidades repositorioEspecialidades;
  final EjecutorRpcPerfilProfesional? ejecutorRpc;
  final InvocadorSubidaFotoEdge? invocadorSubidaFoto;
  final String? Function()? lectorUsuarioActualId;

  const ServicioPerfilProfesional({
    this.repositorioEspecialidades = const RepositorioEspecialidadesSupabase(),
    this.ejecutorRpc,
    this.invocadorSubidaFoto,
    this.lectorUsuarioActualId,
  });

  static const String nombreFuncionSubirFoto = 'subir-foto-profesional';
  static const int limiteBytesFotografia = 5 * 1024 * 1024; // 5 MB
  static const Duration tiempoEsperaSubidaFoto = Duration(seconds: 25);

  /// Duracion estandar acordada en minutos para los servicios registrados
  /// desde el perfil profesional (unificada con `05_perfiles_especialidades_ubicacion.sql`).
  static const int duracionServicioMinutosAcordada = 60;

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorPerfilProfesional(
        'Falta la configuración de Supabase. Ejecuta la aplicación con la URL y la clave pública.',
      );
    }
    return Supabase.instance.client;
  }

  String? _obtenerUidActual() {
    if (lectorUsuarioActualId != null) {
      return lectorUsuarioActualId!();
    }
    return _cliente.auth.currentUser?.id;
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

  /// Extrae y normaliza la lista de servicios a partir de texto separado por comas o saltos de linea.
  static List<String> extraerNombresServicios(String? serviciosTexto) {
    final texto = serviciosTexto?.trim() ?? '';
    if (texto.isEmpty) {
      return const <String>[];
    }
    final vistos = <String>{};
    final resultado = <String>[];
    for (final fragmento in texto.split(RegExp(r'[,;\n\r]+'))) {
      final limpio = fragmento.trim();
      if (limpio.isEmpty) continue;
      final claveNormalizada = limpio.toLowerCase();
      if (vistos.add(claveNormalizada)) {
        resultado.add(limpio);
      }
    }
    return List<String>.unmodifiable(resultado);
  }

  /// Consulta el perfil profesional propio desde el backend usando el contrato transaccional.
  Future<PerfilProfesional> obtenerPerfilPropio() async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilProfesional(
        'No hay una sesión activa. Inicia sesión nuevamente.',
      );
    }

    try {
      final respuestaRpc = await _invocarRpc(
        'obtener_perfil_profesional_propio',
      );
      if (respuestaRpc is List &&
          respuestaRpc.isNotEmpty &&
          respuestaRpc.first is Map) {
        final mapaRpc = Map<String, dynamic>.from(respuestaRpc.first as Map);
        return PerfilProfesional.desdeMapa(mapaRpc);
      }
      throw const ErrorPerfilProfesional(
        'No se encontró el perfil profesional asociado a tu cuenta.',
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const ErrorPerfilProfesional(
          'No tienes permiso para acceder al perfil profesional o tu cuenta está inactiva.',
        );
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const ErrorPerfilProfesional(
          'El servidor no cuenta con la función necesaria para consultar el perfil profesional completo. Contacta al administrador.',
        );
      }
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No pudimos consultar tu perfil profesional en este momento. Inténtalo nuevamente.',
        ),
      );
    } catch (error) {
      if (error is ErrorPerfilProfesional) rethrow;
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo cargar el perfil profesional. Comprueba tu conexión e inténtalo nuevamente.',
        ),
      );
    }
  }

  /// Abre el selector de imagenes del dispositivo. Devuelve null si el usuario cancela.
  /// Permite unicamente archivos JPG/JPEG y PNG de hasta 5 MB.
  Future<ArchivoImagenSeleccionada?> seleccionarFotografia({
    ImageSource origen = ImageSource.gallery,
  }) async {
    try {
      final selector = ImagePicker();
      final archivo = await selector.pickImage(
        source: origen,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (archivo == null) {
        return null; // Cancelado por el usuario
      }
      final bytes = await archivo.readAsBytes();
      return _construirArchivoValidado(bytes);
    } on ErrorPerfilProfesional {
      rethrow;
    } catch (_) {
      throw const ErrorPerfilProfesional(
        'No se pudo acceder a la galería o cámara. Verifica los permisos del dispositivo.',
      );
    }
  }

  /// Envia la fotografia autenticada a la Edge Function `subir-foto-profesional`
  /// (que sube a Cloudinary con firma en servidor y actualiza `foto_url` en DB)
  /// y comprueba que la URL devuelta haya quedado efectivamente asociada al perfil profesional.
  Future<String> subirYGuardarFotografia(
    ArchivoImagenSeleccionada imagen,
  ) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilProfesional(
        'Sesión no válida para subir la fotografía.',
      );
    }

    _construirArchivoValidado(imagen.bytes);

    try {
      final cuerpo = <String, dynamic>{
        'archivoBase64': base64Encode(imagen.bytes),
      };

      final respuesta =
          await (invocadorSubidaFoto != null
                  ? invocadorSubidaFoto!(nombreFuncionSubirFoto, cuerpo: cuerpo)
                  : _invocarEdgeSubirFoto(cuerpo))
              .timeout(tiempoEsperaSubidaFoto);

      if (respuesta.estado != 200) {
        throw ErrorPerfilProfesional(
          _mapearMensajeErrorEdge(respuesta.estado, respuesta.datos),
        );
      }

      final datosMapa = _normalizarMapaRespuesta(respuesta.datos);
      final urlSubida = (datosMapa?['fotoUrl'] as String?)?.trim() ?? '';
      if (!urlSubida.startsWith('https://')) {
        throw const ErrorPerfilProfesional(
          'No se pudo obtener una URL válida para la fotografía subida.',
        );
      }

      final perfilVerificado = await obtenerPerfilPropio();
      final fotoAsociada = perfilVerificado.fotoUrl?.trim() ?? '';
      if (fotoAsociada.isEmpty || fotoAsociada != urlSubida) {
        throw const ErrorPerfilProfesional(
          'No se pudo confirmar la actualización de tu fotografía. Se conservó tu foto anterior.',
        );
      }

      return fotoAsociada;
    } on TimeoutException {
      throw const ErrorPerfilProfesional(
        'La subida de la fotografía tardó demasiado. Comprueba tu conexión e inténtalo nuevamente.',
      );
    } on FunctionException catch (error) {
      throw ErrorPerfilProfesional(
        _mapearMensajeErrorEdge(error.status, error.details),
      );
    } on ErrorPerfilProfesional {
      rethrow;
    } on PostgrestException catch (error) {
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo confirmar la actualización de tu fotografía. Inténtalo nuevamente.',
        ),
      );
    } catch (_) {
      throw const ErrorPerfilProfesional(
        'No se pudo subir la fotografía. Comprueba tu conexión e inténtalo nuevamente.',
      );
    }
  }

  Future<RespuestaSubidaFotoEdge> _invocarEdgeSubirFoto(
    Map<String, dynamic> cuerpo,
  ) async {
    final respuesta = await _cliente.functions.invoke(
      nombreFuncionSubirFoto,
      body: cuerpo,
    );
    return RespuestaSubidaFotoEdge(
      estado: respuesta.status,
      datos: respuesta.data,
    );
  }

  ArchivoImagenSeleccionada _construirArchivoValidado(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ErrorPerfilProfesional('El archivo seleccionado está vacío.');
    }
    if (bytes.lengthInBytes > limiteBytesFotografia) {
      throw const ErrorPerfilProfesional(
        'La fotografía supera el límite de 5 MB. Elige una imagen más ligera.',
      );
    }

    final formato = _detectarFormatoImagen(bytes);
    if (formato == null) {
      throw const ErrorPerfilProfesional(
        'Solo se permiten fotografías en formato JPG o PNG.',
      );
    }
    return formato;
  }

  ArchivoImagenSeleccionada? _detectarFormatoImagen(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ArchivoImagenSeleccionada(
        bytes: bytes,
        extensionArchivo: 'jpg',
        tipoMime: 'image/jpeg',
      );
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return ArchivoImagenSeleccionada(
        bytes: bytes,
        extensionArchivo: 'png',
        tipoMime: 'image/png',
      );
    }

    return null;
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
      return 'No tienes permiso para actualizar esta fotografía.';
    }
    if (estado == 400 || estado == 413 || estado == 415) {
      return 'Solo se permiten fotografías JPG o PNG de hasta 5 MB.';
    }
    if (estado == 504) {
      return 'La subida de la fotografía tardó demasiado. Inténtalo nuevamente.';
    }
    return 'No se pudo subir la fotografía en este momento. Inténtalo nuevamente.';
  }

  /// Guarda de forma transaccional los datos basicos, especialidades, servicios,
  /// modalidad y ubicacion del profesional mediante `actualizar_perfil_profesional_propio`
  /// y verifica que todos los datos solicitados se hayan persistido.
  /// Nunca oculta fallos al guardar servicios ni ejecuta caminos alternativos que guarden parcialmente.
  Future<PerfilProfesional> guardarPerfilCompleto({
    required String nombre,
    required String apellido,
    required List<String> especialidadesIds,
    required List<String> especialidadesNombres,
    String? numeroRegistro,
    String? descripcion,
    int? aniosExperiencia,
    String? telefonoContacto,
    required String modalidad,
    String? servicios,
    String? direccionConsultorio,
    double? latitud,
    double? longitud,
  }) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilProfesional(
        'No hay una sesión activa para guardar el perfil.',
      );
    }

    if ((latitud == null) != (longitud == null)) {
      throw const ErrorPerfilProfesional(
        'Debes indicar tanto la latitud como la longitud del consultorio.',
      );
    }
    if (latitud != null && (latitud < -90.0 || latitud > 90.0)) {
      throw const ErrorPerfilProfesional(
        'La latitud debe estar entre -90 y 90 grados.',
      );
    }
    if (longitud != null && (longitud < -180.0 || longitud > 180.0)) {
      throw const ErrorPerfilProfesional(
        'La longitud debe estar entre -180 y 180 grados.',
      );
    }

    final nombreLimpio = nombre.trim();
    final apellidoLimpio = apellido.trim();
    final modalidadLimpia = modalidad.trim().isEmpty
        ? 'Presencial'
        : modalidad.trim();
    final serviciosNormalizados = extraerNombresServicios(servicios);
    final serviciosTextoCanonica = serviciosNormalizados.join(', ');

    try {
      await _invocarRpc(
        'actualizar_perfil_profesional_propio',
        parametros: {
          'p_nombre': nombreLimpio,
          'p_apellido': apellidoLimpio,
          'p_especialidades_ids': especialidadesIds,
          'p_numero_registro': _limpiarOpcional(numeroRegistro),
          'p_descripcion': _limpiarOpcional(descripcion),
          'p_anios_experiencia': aniosExperiencia,
          'p_telefono_contacto': _limpiarOpcional(telefonoContacto),
          'p_foto_url': null,
          'p_modalidad': modalidadLimpia,
          'p_servicios': serviciosTextoCanonica,
          'p_direccion_consultorio': _limpiarOpcional(direccionConsultorio),
          'p_latitud': latitud,
          'p_longitud': longitud,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const ErrorPerfilProfesional(
          'El servidor no cuenta con la función necesaria para guardar el perfil profesional completo. No se aplicaron cambios parciales.',
        );
      }
      if (error.code == '42501') {
        throw const ErrorPerfilProfesional(
          'No tienes permiso para modificar este perfil profesional o tu cuenta está inactiva.',
        );
      }
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo guardar el perfil profesional completo. Ningún cambio parcial fue aplicado.',
        ),
      );
    } catch (error) {
      if (error is ErrorPerfilProfesional) rethrow;
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'No se pudo completar el guardado del perfil profesional. Revisa tu conexión e inténtalo nuevamente.',
        ),
      );
    }

    final perfilActualizado = await obtenerPerfilPropio();
    _verificarGuardadoCompleto(
      perfilActualizado: perfilActualizado,
      nombreEsperado: nombreLimpio,
      apellidoEsperado: apellidoLimpio,
      modalidadEsperada: modalidadLimpia,
      especialidadesIdsEsperadas: especialidadesIds,
      serviciosEsperados: serviciosNormalizados,
    );

    return perfilActualizado;
  }

  void _verificarGuardadoCompleto({
    required PerfilProfesional perfilActualizado,
    required String nombreEsperado,
    required String apellidoEsperado,
    required String modalidadEsperada,
    required List<String> especialidadesIdsEsperadas,
    required List<String> serviciosEsperados,
  }) {
    if (perfilActualizado.nombre.trim() != nombreEsperado ||
        perfilActualizado.apellido.trim() != apellidoEsperado ||
        perfilActualizado.modalidad.trim() != modalidadEsperada) {
      throw const ErrorPerfilProfesional(
        'No se pudieron actualizar todos los datos básicos del perfil profesional. Inténtalo nuevamente.',
      );
    }

    final idsEsperados = especialidadesIdsEsperadas
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final idsGuardados = perfilActualizado.especialidadesIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (idsEsperados.length != idsGuardados.length ||
        !idsGuardados.containsAll(idsEsperados)) {
      throw const ErrorPerfilProfesional(
        'No se pudieron guardar todas las especialidades seleccionadas del perfil profesional.',
      );
    }

    final serviciosEsperadosSet = serviciosEsperados
        .map((s) => s.toLowerCase())
        .toSet();
    final serviciosGuardadosSet = extraerNombresServicios(
      perfilActualizado.servicios,
    ).map((s) => s.toLowerCase()).toSet();
    if (serviciosEsperadosSet.length != serviciosGuardadosSet.length ||
        !serviciosGuardadosSet.containsAll(serviciosEsperadosSet)) {
      throw const ErrorPerfilProfesional(
        'No se pudieron guardar los servicios del perfil profesional. Verifica la información e inténtalo nuevamente.',
      );
    }
  }

  /// Consulta el motivo de rechazo administrativo si el perfil fue rechazado.
  Future<String?> consultarMotivoRechazoPropio() async {
    try {
      final respuesta = await _invocarRpc('consultar_motivo_rechazo_propio');
      if (respuesta is List && respuesta.isNotEmpty && respuesta.first is Map) {
        final mapa = Map<String, dynamic>.from(respuesta.first as Map);
        return (mapa['motivo_rechazo'] as String?)?.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _limpiarOpcional(String? valor) {
    final limpio = valor?.trim();
    if (limpio == null || limpio.isEmpty) return null;
    return limpio;
  }

  static String explicarError(Object error) {
    if (error is ErrorPerfilProfesional) return error.mensaje;
    if (error is ErrorEspecialidades) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'No tienes permiso para modificar este perfil profesional.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto: 'No pudimos guardar los cambios de tu perfil profesional en este momento. Inténtalo nuevamente.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto: 'No se pudo completar la operación del perfil profesional. Revisa tu conexión e inténtalo nuevamente.',
    );
  }
}
