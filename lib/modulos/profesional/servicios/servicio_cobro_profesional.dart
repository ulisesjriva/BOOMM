import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/profesional/modelos/configuracion_cobro_profesional.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorCobroProfesional implements Exception {
  final String mensaje;
  const ErrorCobroProfesional(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Imagen QR seleccionada sin recortes ni compresion destructiva.
class ArchivoQrSeleccionado {
  final Uint8List bytes;
  final String extensionArchivo;
  final String tipoMime;

  const ArchivoQrSeleccionado({
    required this.bytes,
    required this.extensionArchivo,
    required this.tipoMime,
  });
}

typedef EjecutorRpcCobro = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

typedef SubidorQrPrivadoStorage = Future<String> Function({
  required String rutaObjeto,
  required Uint8List bytes,
  required String tipoMime,
});

typedef GeneradorUrlTemporalQr = Future<String?> Function(String rutaObjeto);

/// Gestiona la configuracion de cobro del profesional y la subida de su QR
/// bancario en el bucket PRIVADO `qr-cobro-profesionales` de Supabase Storage.
/// No utiliza Cloudinary publico ni guarda URLs firmadas en base de datos.
class ServicioCobroProfesional {
  final EjecutorRpcCobro? ejecutorRpc;
  final SubidorQrPrivadoStorage? subidorQrPrivado;
  final GeneradorUrlTemporalQr? generadorUrlTemporalQr;
  final String? Function()? lectorUsuarioActualId;

  const ServicioCobroProfesional({
    this.ejecutorRpc,
    this.subidorQrPrivado,
    this.generadorUrlTemporalQr,
    this.lectorUsuarioActualId,
  });

  static const String nombreBucketQrPrivado = 'qr-cobro-profesionales';
  static const int limiteBytesQr = 5 * 1024 * 1024; // 5 MB
  static const int segundosUrlTemporalVista = 120;

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorCobroProfesional(
        'Falta la configuración de Supabase para gestionar los datos de cobro.',
      );
    }
    return Supabase.instance.client;
  }

  String? _obtenerUidActual() {
    if (lectorUsuarioActualId != null) return lectorUsuarioActualId!();
    if (!ConfiguracionSupabase.estaConfigurado) return null;
    return Supabase.instance.client.auth.currentUser?.id;
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

  /// Selecciona una imagen QR desde galeria sin recortar ni recomprimir
  /// para preservar la legibilidad del codigo bancario.
  Future<ArchivoQrSeleccionado?> seleccionarImagenQr({
    ImageSource origen = ImageSource.gallery,
  }) async {
    try {
      final selector = ImagePicker();
      final archivo = await selector.pickImage(source: origen);
      if (archivo == null) return null;
      final bytes = await archivo.readAsBytes();
      return validarBytesQr(bytes);
    } on ErrorCobroProfesional {
      rethrow;
    } catch (_) {
      throw const ErrorCobroProfesional(
        'No se pudo acceder a la galería para elegir el código QR.',
      );
    }
  }

  /// Valida tamano maximo (5 MB) y firma real de bytes (PNG o JPG).
  static ArchivoQrSeleccionado validarBytesQr(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ErrorCobroProfesional('El archivo seleccionado está vacío.');
    }
    if (bytes.lengthInBytes > limiteBytesQr) {
      throw const ErrorCobroProfesional(
        'La imagen del QR supera el límite de 5 MB.',
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
      return ArchivoQrSeleccionado(
        bytes: bytes,
        extensionArchivo: 'png',
        tipoMime: 'image/png',
      );
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return ArchivoQrSeleccionado(
        bytes: bytes,
        extensionArchivo: 'jpg',
        tipoMime: 'image/jpeg',
      );
    }
    throw const ErrorCobroProfesional(
      'El código QR debe ser una imagen PNG o JPG válida.',
    );
  }

  static String _generarSufijoUnico() {
    final generador = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(generador.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Sube el QR al bucket privado `<uid>/qr_<micros>_<aleatorio>.<ext>` sin
  /// sobrescribir objetos existentes (`upsert: false`) y devuelve unicamente
  /// la ruta del objeto (no una URL firmada).
  /// Ante fallos o respuestas de red ambiguas nunca borra archivos automaticamente
  /// para no comprometer un posible QR vigente.
  Future<String> subirQrPrivado(ArchivoQrSeleccionado archivo) async {
    final uid = _obtenerUidActual()?.trim() ?? '';
    if (uid.isEmpty) {
      throw const ErrorCobroProfesional(
        'Sesión no válida para subir el código QR.',
      );
    }
    final validado = validarBytesQr(archivo.bytes);
    final rutaObjeto =
        '$uid/qr_${DateTime.now().microsecondsSinceEpoch}_${_generarSufijoUnico()}.${validado.extensionArchivo}';

    try {
      if (subidorQrPrivado != null) {
        final rutaDevuelta = await subidorQrPrivado!(
          rutaObjeto: rutaObjeto,
          bytes: validado.bytes,
          tipoMime: validado.tipoMime,
        );
        return _validarRutaPrivadaPropia(rutaDevuelta, uid);
      }

      await _cliente.storage
          .from(nombreBucketQrPrivado)
          .uploadBinary(
            rutaObjeto,
            validado.bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: validado.tipoMime,
            ),
          );
      return rutaObjeto;
    } on ErrorCobroProfesional {
      rethrow;
    } on StorageException catch (error) {
      throw ErrorCobroProfesional(
        TraductorErroresSupabase.traducirErrorAlmacenamiento(
          error,
          accionPorDefecto:
              'No se pudo guardar el código QR privado en este momento.',
        ),
      );
    } catch (_) {
      throw const ErrorCobroProfesional(
        'No se pudo subir el código QR. Revisa tu conexión e inténtalo nuevamente.',
      );
    }
  }

  /// Genera una URL firmada temporal SOLO para previsualizar el QR en pantalla.
  Future<String?> obtenerUrlTemporalVistaQr(String rutaObjeto) async {
    final limpia = rutaObjeto.trim();
    if (limpia.isEmpty) return null;
    try {
      if (generadorUrlTemporalQr != null) {
        return await generadorUrlTemporalQr!(limpia);
      }
      return await _cliente.storage
          .from(nombreBucketQrPrivado)
          .createSignedUrl(limpia, segundosUrlTemporalVista);
    } catch (_) {
      return null;
    }
  }

  Future<ConfiguracionCobroProfesional> obtenerConfiguracionPropia() async {
    try {
      final respuesta = await _invocarRpc('obtener_configuracion_cobro_propia');
      if (respuesta is List && respuesta.isNotEmpty && respuesta.first is Map) {
        return ConfiguracionCobroProfesional.desdeMapa(
          Map<String, dynamic>.from(respuesta.first as Map),
        );
      }
      return const ConfiguracionCobroProfesional();
    } on PostgrestException catch (error) {
      throw ErrorCobroProfesional(explicarError(error));
    } catch (error) {
      if (error is ErrorCobroProfesional) rethrow;
      throw const ErrorCobroProfesional(
        'No se pudo cargar la configuración de cobro en este momento.',
      );
    }
  }

  /// Valida montos exactos en USD y requisitos antes de persistir en servidor.
  Future<ConfiguracionCobroProfesional> guardarConfiguracionPropia(
    ConfiguracionCobroProfesional configuracion,
  ) async {
    final uid = _obtenerUidActual()?.trim() ?? '';
    if (uid.isEmpty) {
      throw const ErrorCobroProfesional(
        'Sesión no válida para guardar la configuración de cobro.',
      );
    }

    final precio = configuracion.precioConsulta;
    final adelanto = configuracion.montoAdelanto;
    final rutaOriginal = configuracion.rutaQrStorage;
    if (rutaOriginal != null && rutaOriginal.trim().isEmpty) {
      throw const ErrorCobroProfesional(
        'La ruta del código QR no puede estar vacía.',
      );
    }
    final rutaQr = rutaOriginal?.trim();
    final banco = configuracion.bancoBeneficiario?.trim();
    final titular = configuracion.titularBeneficiario?.trim();

    if (precio != null) {
      final errorPrecio = ConfiguracionCobroProfesional.validarMontoUsd(
        precio,
        etiqueta: 'El precio total de la consulta',
      );
      if (errorPrecio != null) {
        throw ErrorCobroProfesional(errorPrecio);
      }
    }
    if (adelanto != null) {
      final errorAdelanto = ConfiguracionCobroProfesional.validarMontoUsd(
        adelanto,
        etiqueta: 'El monto del adelanto',
      );
      if (errorAdelanto != null) {
        throw ErrorCobroProfesional(errorAdelanto);
      }
    }
    if (precio != null && adelanto != null && adelanto > precio) {
      throw const ErrorCobroProfesional(
        'El monto del adelanto no puede superar el precio total.',
      );
    }
    if (rutaQr != null && rutaQr.isNotEmpty) {
      _validarRutaPrivadaPropia(rutaQr, uid);
    }

    if (configuracion.requiereAdelanto) {
      if (precio == null) {
        throw const ErrorCobroProfesional(
          'Ingresa un precio total positivo en USD antes de activar el cobro.',
        );
      }
      if (adelanto == null || adelanto > precio) {
        throw const ErrorCobroProfesional(
          'Ingresa un adelanto mayor a 0 USD y no superior al precio total.',
        );
      }
      if (rutaQr == null || rutaQr.isEmpty) {
        throw const ErrorCobroProfesional(
          'Debes cargar tu código QR bancario antes de activar el adelanto.',
        );
      }
      if (banco == null || banco.length < 2) {
        throw const ErrorCobroProfesional(
          'Indica el banco o entidad financiera del beneficiario.',
        );
      }
      if (titular == null || titular.length < 3) {
        throw const ErrorCobroProfesional(
          'Indica el nombre completo del titular de la cuenta.',
        );
      }
    }

    try {
      final respuesta = await _invocarRpc(
        'guardar_configuracion_cobro_propia',
        parametros: {
          'p_requiere_adelanto': configuracion.requiereAdelanto,
          'p_precio_consulta': precio,
          'p_monto_adelanto': adelanto,
          'p_ruta_qr_storage': rutaQr,
          'p_banco_beneficiario': (banco != null && banco.isNotEmpty)
              ? banco
              : null,
          'p_titular_beneficiario': (titular != null && titular.isNotEmpty)
              ? titular
              : null,
          'p_tipo_cuenta_beneficiario':
              configuracion.tipoCuentaBeneficiario?.trim().isNotEmpty == true
              ? configuracion.tipoCuentaBeneficiario!.trim()
              : null,
          'p_numero_cuenta_referencia':
              configuracion.numeroCuentaReferencia?.trim().isNotEmpty == true
              ? configuracion.numeroCuentaReferencia!.trim()
              : null,
        },
      );

      ConfiguracionCobroProfesional? persistida;
      if (respuesta is List && respuesta.isNotEmpty && respuesta.first is Map) {
        persistida = ConfiguracionCobroProfesional.desdeMapa(
          Map<String, dynamic>.from(respuesta.first as Map),
        );
      } else if (respuesta is Map) {
        persistida = ConfiguracionCobroProfesional.desdeMapa(
          Map<String, dynamic>.from(respuesta),
        );
      }

      if (persistida == null) {
        throw const ErrorCobroProfesional(
          'El servidor no confirmó los datos persistidos de la configuración de cobro.',
        );
      }

      if (!_coincideConPersistido(
        esperada: configuracion,
        persistida: persistida,
        rutaEsperada: rutaQr,
      )) {
        throw const ErrorCobroProfesional(
          'Los valores devueltos por el servidor no coinciden con la configuración enviada.',
        );
      }

      return persistida;
    } on PostgrestException catch (error) {
      throw ErrorCobroProfesional(explicarError(error));
    } catch (error) {
      if (error is ErrorCobroProfesional) rethrow;
      throw const ErrorCobroProfesional(
        'No se pudo guardar la configuración de cobro. Inténtalo nuevamente.',
      );
    }
  }

  static bool _coincideConPersistido({
    required ConfiguracionCobroProfesional esperada,
    required ConfiguracionCobroProfesional persistida,
    required String? rutaEsperada,
  }) {
    bool montosIguales(double? a, double? b) {
      if (a == null && b == null) return true;
      if (a == null || b == null) return false;
      return (a - b).abs() < 1e-6;
    }

    return persistida.requiereAdelanto == esperada.requiereAdelanto &&
        persistida.moneda == 'USD' &&
        montosIguales(esperada.precioConsulta, persistida.precioConsulta) &&
        montosIguales(esperada.montoAdelanto, persistida.montoAdelanto) &&
        (persistida.rutaQrStorage?.trim()) == rutaEsperada;
  }

  String _validarRutaPrivadaPropia(String ruta, String uid) {
    final limpia = ruta.trim();
    if (limpia.startsWith('http://') ||
        limpia.startsWith('https://') ||
        limpia.contains('..')) {
      throw const ErrorCobroProfesional(
        'Solo se permite guardar la ruta privada del QR, no una URL firmada.',
      );
    }
    if (!limpia.startsWith('$uid/')) {
      throw const ErrorCobroProfesional(
        'La ruta del QR no corresponde a tu cuenta profesional.',
      );
    }
    return limpia;
  }

  static String explicarError(Object error) {
    if (error is ErrorCobroProfesional) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'No tienes permiso para modificar la configuración de cobro.';
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'La configuración de cobro aún no está habilitada en el servidor.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto:
            'No se pudo actualizar la configuración de cobro en este momento.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto:
          'No se pudo completar la operación de cobro. Revisa tu conexión.',
    );
  }
}
