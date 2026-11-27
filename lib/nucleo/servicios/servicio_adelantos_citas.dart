import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/adelanto_cita.dart';
import 'package:boom/modulos/profesional/servicios/servicio_cobro_profesional.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

typedef EjecutorRpcAdelantos = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

typedef SubidorComprobantePrivado = Future<String> Function({
  required String rutaObjeto,
  required Uint8List bytes,
  required String tipoMime,
});

typedef GeneradorUrlTemporalPrivada = Future<String?> Function(
  String bucket,
  String rutaObjeto,
);

class ErrorAdelantoCita implements Exception {
  final String mensaje;
  final String? codigo;

  const ErrorAdelantoCita(this.mensaje, {this.codigo});

  @override
  String toString() => mensaje;
}

class ArchivoComprobanteSeleccionado {
  final Uint8List bytes;
  final String extensionArchivo;
  final String tipoMime;

  const ArchivoComprobanteSeleccionado({
    required this.bytes,
    required this.extensionArchivo,
    required this.tipoMime,
  });
}

/// Gestiona el flujo de adelantos, acceso privado al QR, carga de comprobantes
/// privados (bucket `comprobantes-adelantos`), incidencias y verificacion del
/// profesional. Nunca almacena URLs firmadas ni sobrescribe evidencia.
class ServicioAdelantosCitas {
  static const String bucketComprobantesPrivados = 'comprobantes-adelantos';
  static const String bucketQrPrivados =
      ServicioCobroProfesional.nombreBucketQrPrivado;
  static const int limiteBytesComprobante = 5 * 1024 * 1024; // 5 MB
  static const int segundosUrlTemporal = 120;

  final EjecutorRpcAdelantos? ejecutorRpc;
  final SubidorComprobantePrivado? subidorComprobantePrivado;
  final GeneradorUrlTemporalPrivada? generadorUrlTemporal;
  final String? Function()? lectorUsuarioActualId;

  const ServicioAdelantosCitas({
    this.ejecutorRpc,
    this.subidorComprobantePrivado,
    this.generadorUrlTemporal,
    this.lectorUsuarioActualId,
  });

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorAdelantoCita(
        'No se pudo conectar con el servidor para gestionar el adelanto.',
      );
    }
    return Supabase.instance.client;
  }

  String? _obtenerUidActual() {
    if (lectorUsuarioActualId != null) {
      return lectorUsuarioActualId!()?.trim();
    }
    if (!ConfiguracionSupabase.estaConfigurado) return null;
    return Supabase.instance.client.auth.currentUser?.id.trim();
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

  static String generarClaveIdempotencia(String prefijo) {
    final random = Random.secure();
    final sufijo = List<String>.generate(
      12,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${prefijo}_${DateTime.now().microsecondsSinceEpoch}_$sufijo';
  }

  static ArchivoComprobanteSeleccionado validarBytesComprobante(
    Uint8List bytes,
  ) {
    if (bytes.isEmpty) {
      throw const ErrorAdelantoCita('El archivo del comprobante está vacío.');
    }
    if (bytes.lengthInBytes > limiteBytesComprobante) {
      throw const ErrorAdelantoCita(
        'El comprobante supera el límite permitido de 5 MB.',
      );
    }
    try {
      final validado = ServicioCobroProfesional.validarBytesQr(bytes);
      return ArchivoComprobanteSeleccionado(
        bytes: validado.bytes,
        extensionArchivo: validado.extensionArchivo,
        tipoMime: validado.tipoMime,
      );
    } on ErrorCobroProfesional {
      throw const ErrorAdelantoCita(
        'El comprobante debe ser una imagen PNG o JPG válida de hasta 5 MB.',
      );
    }
  }

  Future<ArchivoComprobanteSeleccionado?> seleccionarImagenComprobante({
    ImageSource origen = ImageSource.gallery,
  }) async {
    try {
      final selector = ImagePicker();
      final archivo = await selector.pickImage(source: origen);
      if (archivo == null) return null;
      final bytes = await archivo.readAsBytes();
      return validarBytesComprobante(bytes);
    } on ErrorAdelantoCita {
      rethrow;
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo acceder a la galería para seleccionar el comprobante.',
      );
    }
  }

  /// Lista el estado resumido de adelantos de todas las citas visibles para el
  /// usuario actual (paciente, profesional o administrador).
  /// Nunca convierte errores de permisos, red o formato en "sin adelanto".
  Future<Map<String, ResumenAdelantoCita>>
  listarResumenAdelantosVisibles() async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.isEmpty) {
      throw const ErrorAdelantoCita(
        'Debes iniciar sesión con una cuenta activa para consultar el estado de adelantos.',
        codigo: '42501',
      );
    }
    try {
      final respuesta = await _invocarRpc('listar_adelantos_citas_visibles');
      if (respuesta is! List) {
        throw const ErrorAdelantoCita(
          'La respuesta del estado de adelantos tiene un formato inesperado.',
        );
      }
      final mapa = <String, ResumenAdelantoCita>{};
      for (final fila in respuesta) {
        if (fila is! Map) {
          throw const ErrorAdelantoCita(
            'Uno de los registros de adelanto recibidos está malformado.',
          );
        }
        final resumen = ResumenAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(fila),
        );
        mapa[resumen.idCita] = resumen;
      }
      return Map.unmodifiable(mapa);
    } on ErrorAdelantoCita {
      rethrow;
    } on FormatException {
      throw const ErrorAdelantoCita(
        'Los datos de adelanto recibidos no son consistentes. Inténtalo de nuevo.',
      );
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo consultar el estado de adelantos. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  Future<DetalleAdelantoCita?> obtenerDetalleAdelantoCita(String idCita) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.isEmpty) {
      throw const ErrorAdelantoCita(
        'Debes iniciar sesión con una cuenta activa para ver este adelanto.',
        codigo: '42501',
      );
    }
    try {
      final respuesta = await _invocarRpc(
        'obtener_detalle_adelanto_cita',
        parametros: <String, dynamic>{'p_id_cita': idCita.trim()},
      );
      if (respuesta == null) return null;
      if (respuesta is Map) {
        return DetalleAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }
      throw const ErrorAdelantoCita(
        'No se pudo interpretar el detalle del adelanto.',
      );
    } on ErrorAdelantoCita {
      rethrow;
    } on FormatException {
      throw const ErrorAdelantoCita(
        'El detalle del adelanto recibido no tiene un formato válido.',
      );
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo consultar el detalle del adelanto. Inténtalo nuevamente.',
      );
    }
  }

  Future<String> subirComprobantePrivado({
    required String idCita,
    required ArchivoComprobanteSeleccionado archivo,
  }) async {
    final uid = _obtenerUidActual();
    if (uid == null || uid.isEmpty) {
      throw const ErrorAdelantoCita(
        'Sesión no válida para subir el comprobante.',
        codigo: '42501',
      );
    }
    final validado = validarBytesComprobante(archivo.bytes);
    final sufijo = generarClaveIdempotencia('comp');
    final rutaObjeto =
        '${idCita.trim()}/$uid/$sufijo.${validado.extensionArchivo}';

    try {
      if (subidorComprobantePrivado != null) {
        return await subidorComprobantePrivado!(
          rutaObjeto: rutaObjeto,
          bytes: validado.bytes,
          tipoMime: validado.tipoMime,
        );
      }

      await _cliente.storage
          .from(bucketComprobantesPrivados)
          .uploadBinary(
            rutaObjeto,
            validado.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: validado.tipoMime,
            ),
          );
      return rutaObjeto;
    } on StorageException catch (error) {
      throw ErrorAdelantoCita(
        TraductorErroresSupabase.traducirErrorAlmacenamiento(
          error,
          accionPorDefecto:
              'No se pudo subir el comprobante privado en este momento.',
        ),
      );
    } catch (error) {
      if (error is ErrorAdelantoCita) rethrow;
      throw const ErrorAdelantoCita(
        'No se pudo subir el comprobante. Si ya transferiste, puedes reportar una incidencia.',
      );
    }
  }

  Future<DetalleAdelantoCita> registrarComprobanteAdelanto({
    required String idCita,
    required String rutaStorage,
    String? notaPaciente,
    required String claveIdempotencia,
  }) async {
    try {
      final respuesta = await _invocarRpc(
        'registrar_comprobante_adelanto',
        parametros: <String, dynamic>{
          'p_id_cita': idCita.trim(),
          'p_ruta_storage': rutaStorage.trim(),
          'p_nota_paciente': notaPaciente?.trim().isNotEmpty == true
              ? notaPaciente!.trim()
              : null,
          'p_clave_idempotencia': claveIdempotencia.trim(),
        },
      );
      if (respuesta is Map) {
        return DetalleAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }
      throw const ErrorAdelantoCita(
        'El servidor no confirmó el registro del comprobante.',
      );
    } on ErrorAdelantoCita {
      rethrow;
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo registrar el comprobante. Inténtalo nuevamente.',
      );
    }
  }

  Future<DetalleAdelantoCita> registrarIncidenciaAdelanto({
    required String idCita,
    required String detalle,
    required String claveIdempotencia,
  }) async {
    if (detalle.trim().length < 5) {
      throw const ErrorAdelantoCita(
        'Describe brevemente el problema al adjuntar (mínimo 5 caracteres).',
      );
    }
    try {
      final respuesta = await _invocarRpc(
        'registrar_incidencia_adelanto',
        parametros: <String, dynamic>{
          'p_id_cita': idCita.trim(),
          'p_detalle': detalle.trim(),
          'p_clave_idempotencia': claveIdempotencia.trim(),
        },
      );
      if (respuesta is Map) {
        return DetalleAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }
      throw const ErrorAdelantoCita(
        'El servidor no confirmó el registro de la incidencia.',
      );
    } on ErrorAdelantoCita {
      rethrow;
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo registrar la incidencia. Inténtalo nuevamente.',
      );
    }
  }

  Future<DetalleAdelantoCita> revisarAdelantoProfesional({
    required String idCita,
    required String accion,
    String? motivo,
  }) async {
    if (accion == 'observar' && (motivo == null || motivo.trim().length < 5)) {
      throw const ErrorAdelantoCita(
        'Debes indicar un motivo de al menos 5 caracteres para observar el comprobante.',
      );
    }
    try {
      final respuesta = await _invocarRpc(
        'revisar_adelanto_profesional',
        parametros: <String, dynamic>{
          'p_id_cita': idCita.trim(),
          'p_accion': accion.trim(),
          'p_motivo': motivo?.trim().isNotEmpty == true ? motivo!.trim() : null,
        },
      );
      if (respuesta is Map) {
        return DetalleAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }
      throw const ErrorAdelantoCita(
        'El servidor no confirmó la revisión del adelanto.',
      );
    } on ErrorAdelantoCita {
      rethrow;
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo registrar la revisión del adelanto. Inténtalo nuevamente.',
      );
    }
  }

  Future<DetalleAdelantoCita> resolverIncidenciaAdelanto({
    required String idCita,
    required String idIncidencia,
    required String motivoResolucion,
  }) async {
    final motivoLimpio = motivoResolucion.trim();
    if (motivoLimpio.length < 5 || motivoLimpio.length > 500) {
      throw const ErrorAdelantoCita(
        'El motivo de resolución debe tener entre 5 y 500 caracteres.',
        codigo: '22023',
      );
    }
    final uid = _obtenerUidActual();
    if (uid == null || uid.isEmpty) {
      throw const ErrorAdelantoCita(
        'Debes iniciar sesión como profesional titular activo para resolver una incidencia.',
        codigo: '42501',
      );
    }
    try {
      final respuesta = await _invocarRpc(
        'resolver_incidencia_adelanto',
        parametros: <String, dynamic>{
          'p_id_cita': idCita.trim(),
          'p_id_incidencia': idIncidencia.trim(),
          'p_motivo_resolucion': motivoLimpio,
        },
      );
      if (respuesta is Map) {
        return DetalleAdelantoCita.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }
      throw const ErrorAdelantoCita(
        'El servidor no confirmó la resolución de la incidencia.',
      );
    } on ErrorAdelantoCita {
      rethrow;
    } on FormatException {
      throw const ErrorAdelantoCita(
        'La respuesta del servidor al resolver la incidencia no tiene un formato válido.',
      );
    } on PostgrestException catch (error) {
      throw ErrorAdelantoCita(explicarError(error), codigo: error.code);
    } catch (_) {
      throw const ErrorAdelantoCita(
        'No se pudo resolver la incidencia. Inténtalo nuevamente.',
      );
    }
  }

  Future<String?> obtenerUrlTemporalPrivada({
    required String bucket,
    required String rutaObjeto,
  }) async {
    final limpia = rutaObjeto.trim();
    if (limpia.isEmpty) return null;
    try {
      if (generadorUrlTemporal != null) {
        return await generadorUrlTemporal!(bucket, limpia);
      }
      return await _cliente.storage
          .from(bucket)
          .createSignedUrl(limpia, segundosUrlTemporal);
    } catch (_) {
      return null;
    }
  }

  static String explicarError(Object error) {
    if (error is ErrorAdelantoCita) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'No tienes permisos para realizar esta operación de adelanto.';
      }
      if (error.code == '23P01' || error.code == '22023') {
        return error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'La operación no puede completarse en el estado o plazo actual.';
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'El flujo de adelantos aún no está habilitado en el servidor.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto: 'No se pudo procesar la operación del adelanto.',
      );
    }
    return 'No se pudo completar la operación del adelanto. Revisa tu conexión.';
  }
}
