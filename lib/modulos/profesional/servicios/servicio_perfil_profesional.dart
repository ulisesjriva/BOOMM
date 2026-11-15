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

typedef SubidorFotografiaStorage = Future<String> Function({
  required String rutaArchivo,
  required Uint8List bytes,
  required String tipoMime,
});

/// Servicio encargado de consultar y actualizar el perfil profesional,
/// sus especialidades (`public."ProfesionalEspecialidad"`), servicios (`public."Servicios"`),
/// modalidad y ubicacion (`public."Profesionales"`) y fotografia en Supabase Storage.
/// No utiliza secretos privados en Flutter; las politicas RLS protegen la carpeta UID.
class ServicioPerfilProfesional {
  final RepositorioEspecialidades repositorioEspecialidades;
  final EjecutorRpcPerfilProfesional? ejecutorRpc;
  final SubidorFotografiaStorage? subidorFotografia;
  final String? Function()? lectorUsuarioActualId;

  const ServicioPerfilProfesional({
    this.repositorioEspecialidades = const RepositorioEspecialidadesSupabase(),
    this.ejecutorRpc,
    this.subidorFotografia,
    this.lectorUsuarioActualId,
  });

  static const String nombreBucketFotos = 'fotos-profesionales';
  static const int limiteBytesFotografia = 5 * 1024 * 1024; // 5 MB

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
      if (bytes.isEmpty) {
        throw const ErrorPerfilProfesional(
          'El archivo seleccionado está vacío.',
        );
      }
      if (bytes.lengthInBytes > limiteBytesFotografia) {
        throw const ErrorPerfilProfesional(
          'La fotografía supera el límite de 5 MB. Elige una imagen más ligera.',
        );
      }
      final nombre = archivo.name.toLowerCase();
      final esPng = nombre.endsWith('.png');
      final esWebp = nombre.endsWith('.webp');
      return ArchivoImagenSeleccionada(
        bytes: bytes,
        extensionArchivo: esPng
            ? 'png'
            : esWebp
            ? 'webp'
            : 'jpg',
        tipoMime: esPng
            ? 'image/png'
            : esWebp
            ? 'image/webp'
            : 'image/jpeg',
      );
    } on ErrorPerfilProfesional {
      rethrow;
    } catch (_) {
      throw const ErrorPerfilProfesional(
        'No se pudo acceder a la galería o cámara. Verifica los permisos del dispositivo.',
      );
    }
  }

  /// Sube la fotografia a la carpeta propia `<uid>/perfil.<ext>` en Supabase Storage,
  /// actualiza `foto_url` mediante la RPC `actualizar_foto_profesional_propia` y
  /// comprueba que la URL haya quedado efectivamente asociada al perfil profesional.
  Future<String> subirYGuardarFotografia(
    ArchivoImagenSeleccionada imagen,
  ) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorPerfilProfesional(
        'Sesión no válida para subir la fotografía.',
      );
    }

    final rutaArchivo = '$uid/perfil.${imagen.extensionArchivo}';
    try {
      final String urlConMarcaTiempo;
      if (subidorFotografia != null) {
        urlConMarcaTiempo = await subidorFotografia!(
          rutaArchivo: rutaArchivo,
          bytes: imagen.bytes,
          tipoMime: imagen.tipoMime,
        );
      } else {
        final cliente = _cliente;
        await cliente.storage
            .from(nombreBucketFotos)
            .uploadBinary(
              rutaArchivo,
              imagen.bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: imagen.tipoMime,
              ),
            );

        final urlPublica = cliente.storage
            .from(nombreBucketFotos)
            .getPublicUrl(rutaArchivo);
        urlConMarcaTiempo =
            '$urlPublica?t=${DateTime.now().millisecondsSinceEpoch}';
      }

      if (urlConMarcaTiempo.trim().isEmpty) {
        throw const ErrorPerfilProfesional(
          'No se pudo obtener una URL válida para la fotografía subida.',
        );
      }

      await _invocarRpc(
        'actualizar_foto_profesional_propia',
        parametros: {'p_foto_url': urlConMarcaTiempo},
      );

      final perfilVerificado = await obtenerPerfilPropio();
      final fotoAsociada = perfilVerificado.fotoUrl?.trim() ?? '';
      if (fotoAsociada.isEmpty || fotoAsociada != urlConMarcaTiempo.trim()) {
        throw const ErrorPerfilProfesional(
          'Se subió la imagen, pero la fotografía no quedó asociada a tu perfil profesional. Inténtalo nuevamente.',
        );
      }

      return fotoAsociada;
    } on StorageException catch (error) {
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorAlmacenamiento(
          error,
          accionPorDefecto: 'No pudimos guardar la fotografía en este momento. Inténtalo nuevamente.',
        ),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const ErrorPerfilProfesional(
          'Se subió la imagen, pero el servidor no tiene disponible la función para asociar la fotografía al perfil profesional.',
        );
      }
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorBaseDatos(
          error,
          accionPorDefecto: 'Se subió la imagen, pero no pudimos asociar la fotografía a tu perfil en este momento. Inténtalo nuevamente.',
        ),
      );
    } catch (error) {
      if (error is ErrorPerfilProfesional) rethrow;
      throw ErrorPerfilProfesional(
        TraductorErroresSupabase.traducirErrorAlmacenamiento(
          error,
          accionPorDefecto: 'No se pudo cargar la fotografía. Comprueba tu conexión e inténtalo nuevamente.',
        ),
      );
    }
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
