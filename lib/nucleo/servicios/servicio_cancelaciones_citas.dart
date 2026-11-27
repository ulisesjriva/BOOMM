import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/gestion_cancelacion_cita.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';

class ServicioCancelacionesCitas {
  static const bucketDevoluciones = 'comprobantes-devoluciones';
  final EjecutorRpcAdelantos? ejecutorRpc;
  final String? Function()? lectorUsuarioActualId;
  final SubidorComprobantePrivado? subidorPrivado;
  final GeneradorUrlTemporalPrivada? generadorUrlTemporal;

  const ServicioCancelacionesCitas({this.ejecutorRpc, this.lectorUsuarioActualId,
    this.subidorPrivado, this.generadorUrlTemporal});

  String _exigirSesion() {
    final uid = lectorUsuarioActualId != null ? lectorUsuarioActualId!() :
        (ConfiguracionSupabase.estaConfigurado ? Supabase.instance.client.auth.currentUser?.id : null);
    if (uid == null || uid.trim().isEmpty) {
      throw const ErrorAdelantoCita('Debes iniciar sesión con una cuenta activa.', codigo: '42501');
    }
    return uid.trim();
  }

  String claveSesion(String idCita) => '${_exigirSesion()}:$idCita';

  static void validarTexto(String texto, {int maximo = 500}) {
    if (texto.trim().length < 5 || texto.trim().length > maximo) {
      throw ErrorAdelantoCita('El texto debe tener entre 5 y $maximo caracteres.', codigo: '22023');
    }
  }

  Future<GestionCancelacionCita> _invocar(String funcion, Map<String, dynamic> parametros) async {
    _exigirSesion();
    try {
      if (ejecutorRpc == null && !ConfiguracionSupabase.estaConfigurado) {
        throw const ErrorAdelantoCita('No se pudo conectar con el servidor de cancelaciones.');
      }
      final respuesta = ejecutorRpc != null
          ? await ejecutorRpc!(funcion, parametros: parametros)
          : await Supabase.instance.client.rpc(funcion, params: parametros);
      if (respuesta is! Map) throw const FormatException('Respuesta de cancelación incompleta.');
      return GestionCancelacionCita.desdeMapa(Map<String, dynamic>.from(respuesta));
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const ErrorAdelantoCita('La gestión de cancelaciones aún no está habilitada en el servidor.');
      }
      throw ErrorAdelantoCita(ServicioAdelantosCitas.explicarError(error), codigo: error.code);
    }
  }

  Future<GestionCancelacionCita> obtener(String idCita) =>
      _invocar('obtener_gestion_cancelacion', {'p_id_cita': idCita});

  Future<GestionCancelacionCita> cancelar(GestionCancelacionCita previa, String motivo,
      {bool pagoReportado = false}) {
    validarTexto(motivo);
    return _invocar('cancelar_cita_con_tratamiento_adelanto', {
      'p_id_cita': previa.idCita, 'p_motivo': motivo.trim(),
      'p_version_previa': previa.versionPrevia, 'p_pago_reportado': pagoReportado,
    });
  }

  Future<GestionCancelacionCita> revisarPago(String idCita, bool recibido, String motivo) {
    validarTexto(motivo);
    return _invocar('revisar_pago_cita_cancelada', {
      'p_id_cita': idCita, 'p_recibido': recibido, 'p_motivo': motivo.trim(),
    });
  }

  Future<String> subirDevolucion(String idCita, ArchivoComprobanteSeleccionado archivo) async {
    final uid = _exigirSesion();
    final validado = ServicioAdelantosCitas.validarBytesComprobante(archivo.bytes);
    final ruta = '$idCita/$uid/${ServicioAdelantosCitas.generarClaveIdempotencia('devolucion')}.${validado.extensionArchivo}';
    if (subidorPrivado != null) {
      final resultado = await subidorPrivado!(rutaObjeto: ruta, bytes: validado.bytes, tipoMime: validado.tipoMime);
      if (resultado != ruta) throw const FormatException('La subida devolvió una ruta diferente.');
      return ruta;
    }
    await Supabase.instance.client.storage.from(bucketDevoluciones).uploadBinary(ruta, validado.bytes,
        fileOptions: FileOptions(upsert: false, contentType: validado.tipoMime));
    return ruta;
  }

  Future<GestionCancelacionCita> registrarDevolucion(String idCita, String ruta, String referencia) {
    validarTexto(referencia, maximo: 150);
    return _invocar('registrar_devolucion_cita', {
      'p_id_cita': idCita, 'p_ruta_storage': ruta, 'p_referencia': referencia.trim(),
    });
  }

  Future<String?> obtenerUrlDevolucion(String ruta) async {
    _exigirSesion();
    if (generadorUrlTemporal != null) return generadorUrlTemporal!(bucketDevoluciones, ruta);
    return Supabase.instance.client.storage.from(bucketDevoluciones).createSignedUrl(ruta, 120);
  }
}
