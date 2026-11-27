import 'package:boom/nucleo/componentes/pantalla_gestion_cancelacion_cita.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boom/modelos/adelanto_cita.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class _ComprobanteSubidoPendiente {
  final String rutaStorage;
  final String claveIdempotencia;
  final String notaPaciente;

  const _ComprobanteSubidoPendiente({
    required this.rutaStorage,
    required this.claveIdempotencia,
    required this.notaPaciente,
  });
}

/// Lector de tiempo transcurrido de un reloj monotónico.
/// En producción se usa [Stopwatch]; en pruebas permite avanzar el reloj de
/// forma determinista sin cerrar ni minimizar la pantalla.
typedef LectorTiempoMonotonico = Duration Function();

/// Hoja/pantalla de detalle privado del adelanto para paciente o profesional.
/// Nunca se muestra al administrador ni expone datos a terceros.
/// Conserva la ruta ya subida y la clave de idempotencia ante respuestas
/// perdidas (incluso al cerrar y volver a abrir la pantalla) sin borrar evidencia.
class HojaDetalleAdelantoCita extends StatefulWidget {
  final String idCita;
  final bool esProfesional;
  final ServicioAdelantosCitas servicio;
  final VoidCallback? alActualizar;
  final LectorTiempoMonotonico? lectorTiempoMonotonico;

  /// Registro en memoria por idCita para recuperar un envio pendiente tras cerrar
  /// y volver a abrir la pantalla sin volver a subir el archivo.
  static final Map<String, _ComprobanteSubidoPendiente> _pendientesPorCita = {};

  static void limpiarPendientesParaPruebas() => _pendientesPorCita.clear();

  const HojaDetalleAdelantoCita({
    super.key,
    required this.idCita,
    required this.esProfesional,
    this.servicio = const ServicioAdelantosCitas(),
    this.alActualizar,
    this.lectorTiempoMonotonico,
  });

  @override
  State<HojaDetalleAdelantoCita> createState() =>
      _HojaDetalleAdelantoCitaState();
}

class _HojaDetalleAdelantoCitaState extends State<HojaDetalleAdelantoCita>
    with WidgetsBindingObserver {
  final _controladorNota = TextEditingController();
  final _controladorMotivo = TextEditingController();
  final _controladorIncidencia = TextEditingController();
  final Stopwatch _cronometroMonotonico = Stopwatch();

  DetalleAdelantoCita? _detalle;
  String? _urlQrTemporal;
  final Map<String, String> _urlsComprobantes = {};
  bool _cargando = true;
  bool _recargando = false;
  bool _procesando = false;
  String? _error;
  String? _exito;
  String? _claveIdempotenciaIncidencia;

  DateTime? _horaServidorBaseUtc;
  Duration? _marcaMonotonicaConsulta;
  Timer? _temporizadorVencimiento;
  bool _vencimientoAlcanzadoEnSesion = false;

  _ComprobanteSubidoPendiente? get _pendienteComprobante =>
      HojaDetalleAdelantoCita._pendientesPorCita[widget.idCita];

  Duration _leerTiempoMonotonico() {
    return widget.lectorTiempoMonotonico?.call() ??
        _cronometroMonotonico.elapsed;
  }

  DateTime _obtenerAhoraServidorEstimadoUtc() {
    final base = _horaServidorBaseUtc;
    final marca = _marcaMonotonicaConsulta;
    if (base == null || marca == null) {
      return DateTime.now().toUtc();
    }
    final transcurrido = _leerTiempoMonotonico() - marca;
    return base.add(transcurrido.isNegative ? Duration.zero : transcurrido);
  }

  bool _estaPlazoPagoVencido(DetalleAdelantoCita detalle) {
    if (detalle.estadoAdelanto == 'vencido_sin_pago') {
      return true;
    }
    if (detalle.estadoAdelanto != 'pendiente_adelanto') {
      return false;
    }
    if (_vencimientoAlcanzadoEnSesion) {
      return true;
    }
    return detalle.estaPlazoPagoVencidoEn(_obtenerAhoraServidorEstimadoUtc());
  }

  bool _tieneDatosPagoVisiblesActuales(DetalleAdelantoCita detalle) {
    if (detalle.estadoAdelanto == 'pendiente_adelanto' &&
        _estaPlazoPagoVencido(detalle)) {
      return false;
    }
    return detalle.tieneDatosPagoVisiblesEn(_obtenerAhoraServidorEstimadoUtc());
  }

  bool _puedeEnviarComprobanteActual(DetalleAdelantoCita detalle) {
    if (detalle.estadoAdelanto == 'pendiente_adelanto' &&
        _estaPlazoPagoVencido(detalle)) {
      return false;
    }
    return detalle.puedeEnviarComprobanteEn(_obtenerAhoraServidorEstimadoUtc());
  }

  void _registrarReferenciaTemporalYProgramarVencimiento(
    DetalleAdelantoCita? detalle,
  ) {
    _temporizadorVencimiento?.cancel();
    _temporizadorVencimiento = null;

    if (detalle == null) {
      return;
    }

    _horaServidorBaseUtc =
        detalle.horaServidor?.toUtc() ?? DateTime.now().toUtc();
    _marcaMonotonicaConsulta = _leerTiempoMonotonico();

    final ahoraEstimado = _obtenerAhoraServidorEstimadoUtc();
    if (detalle.estadoAdelanto == 'pendiente_adelanto' &&
        detalle.limitePagoEn != null) {
      if (detalle.estaPlazoPagoVencidoEn(ahoraEstimado)) {
        _vencimientoAlcanzadoEnSesion = true;
        _urlQrTemporal = null;
        return;
      }

      _vencimientoAlcanzadoEnSesion = false;
      final restante = detalle.limitePagoEn!.toUtc().difference(ahoraEstimado);
      // En SQL el vencimiento ocurre estrictamente después de limite_pago_en
      // (ahora > limite_pago_en), por lo que sumamos 1 ms al instante límite.
      final espera = restante.isNegative
          ? const Duration(milliseconds: 1)
          : restante + const Duration(milliseconds: 1);
      _temporizadorVencimiento = Timer(espera, _alAlcanzarVencimientoLocal);
    } else if (detalle.estadoAdelanto == 'vencido_sin_pago') {
      _vencimientoAlcanzadoEnSesion = true;
      _urlQrTemporal = null;
    } else {
      _vencimientoAlcanzadoEnSesion = false;
    }
  }

  void _alAlcanzarVencimientoLocal() {
    if (!mounted) return;
    final detalleActual = _detalle;
    if (detalleActual == null ||
        detalleActual.estadoAdelanto != 'pendiente_adelanto') {
      return;
    }
    setState(() {
      _vencimientoAlcanzadoEnSesion = true;
      _urlQrTemporal = null;
    });
    if (!_recargando && !_procesando) {
      unawaited(_cargarDetalle(silencioso: true));
    }
  }

  @override
  void initState() {
    super.initState();
    _cronometroMonotonico.start();
    WidgetsBinding.instance.addObserver(this);
    final pendiente = _pendienteComprobante;
    if (pendiente != null && pendiente.notaPaciente.isNotEmpty) {
      _controladorNota.text = pendiente.notaPaciente;
    }
    unawaited(_cargarDetalle());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_cargando &&
        !_recargando &&
        !_procesando) {
      unawaited(_cargarDetalle(silencioso: true));
    }
  }

  @override
  void dispose() {
    _temporizadorVencimiento?.cancel();
    _temporizadorVencimiento = null;
    _cronometroMonotonico.stop();
    WidgetsBinding.instance.removeObserver(this);
    _controladorNota.dispose();
    _controladorMotivo.dispose();
    _controladorIncidencia.dispose();
    super.dispose();
  }

  Future<void> _cargarDetalle({bool silencioso = false}) async {
    final mostrarPantallaCarga = !silencioso || _detalle == null;
    setState(() {
      if (mostrarPantallaCarga) {
        _cargando = true;
      }
      _recargando = true;
      _error = null;
    });
    try {
      final detalle = await widget.servicio.obtenerDetalleAdelantoCita(
        widget.idCita,
      );
      if (!mounted) return;
      _detalle = detalle;
      _registrarReferenciaTemporalYProgramarVencimiento(detalle);
      // Si el comprobante pendiente ya quedo registrado en servidor, limpiarlo
      final pendiente = _pendienteComprobante;
      if (pendiente != null &&
          detalle != null &&
          detalle.comprobantes.any(
            (c) => c.rutaStorage == pendiente.rutaStorage,
          )) {
        HojaDetalleAdelantoCita._pendientesPorCita.remove(widget.idCita);
      }
      await _cargarUrlsTemporales(detalle);
    } catch (error) {
      if (!mounted) return;
      // Si la recarga tras vencer falla, conservamos el estado vencido local y
      // nunca rehabilitamos QR ni subida con información antigua.
      if (_detalle != null && _estaPlazoPagoVencido(_detalle!)) {
        _urlQrTemporal = null;
      }
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _recargando = false;
        });
      }
    }
  }

  Future<void> _cargarUrlsTemporales(DetalleAdelantoCita? detalle) async {
    if (detalle == null) return;
    if (_tieneDatosPagoVisiblesActuales(detalle) &&
        detalle.rutaQrStorage != null &&
        detalle.rutaQrStorage!.isNotEmpty) {
      _urlQrTemporal = await widget.servicio.obtenerUrlTemporalPrivada(
        bucket: ServicioAdelantosCitas.bucketQrPrivados,
        rutaObjeto: detalle.rutaQrStorage!,
      );
    } else {
      _urlQrTemporal = null;
    }
    for (final comp in detalle.comprobantes) {
      if (!_urlsComprobantes.containsKey(comp.idComprobante)) {
        final url = await widget.servicio.obtenerUrlTemporalPrivada(
          bucket: ServicioAdelantosCitas.bucketComprobantesPrivados,
          rutaObjeto: comp.rutaStorage,
        );
        if (url != null && mounted) {
          _urlsComprobantes[comp.idComprobante] = url;
        }
      }
    }
  }

  /// Reintenta el registro de un comprobante ya subido sin volver a subirlo:
  /// primero consulta el estado en servidor por si la respuesta previa se perdio.
  Future<void> _reintentarRegistroComprobantePendiente() async {
    final pendiente = _pendienteComprobante;
    if (_procesando || pendiente == null) return;
    if (_detalle != null && !_puedeEnviarComprobanteActual(_detalle!)) {
      setState(() {});
      return;
    }
    setState(() {
      _procesando = true;
      _error = null;
      _exito = null;
    });

    try {
      final estadoServidor = await widget.servicio.obtenerDetalleAdelantoCita(
        widget.idCita,
      );
      if (!mounted) return;
      if (estadoServidor != null &&
          estadoServidor.comprobantes.any(
            (c) => c.rutaStorage == pendiente.rutaStorage,
          )) {
        HojaDetalleAdelantoCita._pendientesPorCita.remove(widget.idCita);
        _controladorNota.clear();
        _detalle = estadoServidor;
        _registrarReferenciaTemporalYProgramarVencimiento(estadoServidor);
        await _cargarUrlsTemporales(estadoServidor);
        _exito = 'Comprobante confirmado en el servidor (ya había sido registrado en el intento anterior).';
        widget.alActualizar?.call();
        return;
      }

      final actualizado = await widget.servicio.registrarComprobanteAdelanto(
        idCita: widget.idCita,
        rutaStorage: pendiente.rutaStorage,
        notaPaciente: pendiente.notaPaciente,
        claveIdempotencia: pendiente.claveIdempotencia,
      );
      if (!mounted) return;
      HojaDetalleAdelantoCita._pendientesPorCita.remove(widget.idCita);
      _controladorNota.clear();
      _detalle = actualizado;
      _registrarReferenciaTemporalYProgramarVencimiento(actualizado);
      await _cargarUrlsTemporales(actualizado);
      _exito = 'Comprobante registrado para revisión del profesional sin duplicar el archivo.';
      widget.alActualizar?.call();
    } catch (error) {
      if (!mounted) return;
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  /// Sube un nuevo archivo (envio inicial o correccion nueva) generando una
  /// clave de idempotencia propia y conservando ruta+clave si falla el registro.
  Future<void> _enviarNuevoComprobante() async {
    if (_procesando) return;
    if (_detalle != null && !_puedeEnviarComprobanteActual(_detalle!)) {
      setState(() {});
      return;
    }
    setState(() {
      _procesando = true;
      _error = null;
      _exito = null;
    });

    try {
      final archivo = await widget.servicio.seleccionarImagenComprobante();
      if (archivo == null || !mounted) return;

      final claveNueva = ServicioAdelantosCitas.generarClaveIdempotencia(
        'comp_reg',
      );
      final notaActual = _controladorNota.text.trim();

      final rutaPrivada = await widget.servicio.subirComprobantePrivado(
        idCita: widget.idCita,
        archivo: archivo,
      );

      HojaDetalleAdelantoCita._pendientesPorCita[widget.idCita] =
          _ComprobanteSubidoPendiente(
            rutaStorage: rutaPrivada,
            claveIdempotencia: claveNueva,
            notaPaciente: notaActual,
          );

      final actualizado = await widget.servicio.registrarComprobanteAdelanto(
        idCita: widget.idCita,
        rutaStorage: rutaPrivada,
        notaPaciente: notaActual,
        claveIdempotencia: claveNueva,
      );

      if (!mounted) return;
      HojaDetalleAdelantoCita._pendientesPorCita.remove(widget.idCita);
      _controladorNota.clear();
      _detalle = actualizado;
      _registrarReferenciaTemporalYProgramarVencimiento(actualizado);
      await _cargarUrlsTemporales(actualizado);
      _exito = 'Comprobante enviado para revisión del profesional. Recuerda que el envío no confirma automáticamente el ingreso.';
      widget.alActualizar?.call();
    } catch (error) {
      if (!mounted) return;
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  Future<void> _reportarIncidencia() async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _error = null;
      _exito = null;
    });
    try {
      _claveIdempotenciaIncidencia ??=
          ServicioAdelantosCitas.generarClaveIdempotencia('inc');

      final actualizado = await widget.servicio.registrarIncidenciaAdelanto(
        idCita: widget.idCita,
        detalle: _controladorIncidencia.text,
        claveIdempotencia: _claveIdempotenciaIncidencia!,
      );
      if (!mounted) return;
      _claveIdempotenciaIncidencia = null;
      _controladorIncidencia.clear();
      _detalle = actualizado;
      _registrarReferenciaTemporalYProgramarVencimiento(actualizado);
      final liberado = actualizado.incidencias.any((i) => i.horarioYaLiberado);
      _exito = liberado
          ? 'Incidencia registrada para revisión. El horario ya fue liberado al vencer el plazo y no puede recuperarse automáticamente si fue asignado a otra persona.'
          : 'Incidencia registrada para revisión. La reserva se mantendrá mientras se revisa tu caso.';
      widget.alActualizar?.call();
    } catch (error) {
      if (!mounted) return;
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  Future<void> _revisarComoProfesional(String accion) async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _error = null;
      _exito = null;
    });
    try {
      final actualizado = await widget.servicio.revisarAdelantoProfesional(
        idCita: widget.idCita,
        accion: accion,
        motivo: accion == 'observar' ? _controladorMotivo.text : null,
      );
      if (!mounted) return;
      _controladorMotivo.clear();
      _detalle = actualizado;
      _registrarReferenciaTemporalYProgramarVencimiento(actualizado);
      _exito = accion == 'verificar'
          ? 'Ingreso verificado correctamente. La cita ha quedado confirmada.'
          : 'Observación registrada. El paciente podrá enviar una aclaración o comprobante sin solicitar otra transferencia automáticamente.';
      widget.alActualizar?.call();
    } catch (error) {
      if (!mounted) return;
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  Future<void> _abrirDialogoResolverIncidencia(
    IncidenciaAdelanto incidencia,
  ) async {
    if (_procesando || !widget.esProfesional) return;

    final motivoConfirmado = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoResolverIncidencia(),
    );

    if (motivoConfirmado == null || !mounted) return;
    await _resolverIncidenciaComoProfesional(
      incidencia.idIncidencia,
      motivoConfirmado,
    );
  }

  Future<void> _resolverIncidenciaComoProfesional(
    String idIncidencia,
    String motivoResolucion,
  ) async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _error = null;
      _exito = null;
    });
    try {
      final actualizado = await widget.servicio.resolverIncidenciaAdelanto(
        idCita: widget.idCita,
        idIncidencia: idIncidencia,
        motivoResolucion: motivoResolucion,
      );
      if (!mounted) return;
      _detalle = actualizado;
      _registrarReferenciaTemporalYProgramarVencimiento(actualizado);
      await _cargarUrlsTemporales(actualizado);
      _exito = 'Incidencia marcada como resuelta. Recuerda que resolverla no verifica el pago ni confirma la cita.';
      widget.alActualizar?.call();
    } catch (error) {
      if (!mounted) return;
      _error = ServicioAdelantosCitas.explicarError(error);
    } finally {
      if (mounted) {
        setState(() => _procesando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemaPsicobloom.colorFondo,
      appBar: AppBar(
        title: Text(
          widget.esProfesional
              ? 'Revisión de adelanto'
              : 'Adelanto de la solicitud',
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando || _recargando || _procesando
                ? null
                : () => unawaited(_cargarDetalle(silencioso: true)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(
                child: CircularProgressIndicator(
                  color: TemaPsicobloom.colorPrincipal,
                ),
              )
            : _detalle == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? 'Esta cita no tiene un adelanto asociado.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: TemaPsicobloom.colorTextoSecundario,
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _construirResumenMontos(_detalle!),
                  const SizedBox(height: 14),
                  if (_error != null) ...[
                    _construirBanner(_error!, esError: true),
                    const SizedBox(height: 12),
                  ],
                  if (_exito != null) ...[
                    _construirBanner(_exito!, esError: false),
                    const SizedBox(height: 12),
                  ],
                  if (!widget.esProfesional &&
                      _tieneDatosPagoVisiblesActuales(_detalle!)) ...[
                    _construirSeccionQrYDatosBancarios(_detalle!),
                    const SizedBox(height: 14),
                  ],
                  if (!widget.esProfesional &&
                      _puedeEnviarComprobanteActual(_detalle!)) ...[
                    _construirSeccionEnvioComprobante(),
                    const SizedBox(height: 14),
                  ],
                  if (!widget.esProfesional &&
                      _detalle!.puedeReportarIncidencia) ...[
                    _construirSeccionIncidencia(),
                    const SizedBox(height: 14),
                  ],
                  if (widget.esProfesional &&
                      _detalle!.puedeRevisarProfesional) ...[
                    _construirAccionesProfesional(),
                    const SizedBox(height: 14),
                  ],
                  BotonGestionCancelacion(idCita: widget.idCita,
                    servicioAdelantos: widget.servicio, alActualizar: () {
                      if (!mounted) return;
                      unawaited(_cargarDetalle(silencioso: true));
                      widget.alActualizar?.call();
                    }),
                  _construirHistorial(_detalle!),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _construirBanner(String mensaje, {required bool esError}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esError
            ? TemaPsicobloom.colorFondoError
            : TemaPsicobloom.colorMenta,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esError
              ? TemaPsicobloom.colorError.withValues(alpha: 0.4)
              : TemaPsicobloom.colorSecundario.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        mensaje,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: esError
              ? TemaPsicobloom.colorError
              : TemaPsicobloom.colorSecundario,
        ),
      ),
    );
  }

  Widget _construirResumenMontos(DetalleAdelantoCita d) {
    return Container(
      key: const Key('tarjetaResumenAdelantoDetalle'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Estado del adelanto',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: TemaPsicobloom.colorTexto,
                  ),
                ),
              ),
              Container(
                key: const Key('chipEstadoAdelantoDetalle'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: d.revisionDemorada
                      ? TemaPsicobloom.colorFondoAdvertencia
                      : TemaPsicobloom.colorLavanda,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  d.etiquetaEstado,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: d.revisionDemorada
                        ? TemaPsicobloom.colorAdvertencia
                        : TemaPsicobloom.colorPrincipalOscuro,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Valor de consulta: ${d.textoPrecioConsulta} USD',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Adelanto: ${d.textoMontoAdelanto} USD',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: TemaPsicobloom.colorPrincipalOscuro,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo después del adelanto: ${d.textoSaldo} USD',
            style: const TextStyle(
              fontSize: 13.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          if (d.limitePagoEn != null) ...[
            const SizedBox(height: 8),
            Text(
              'Límite exacto para enviar comprobante: ${formatearFechaHoraEcuador(d.limitePagoEn!)}',
              key: const Key('textoLimitePagoExacto'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorTexto,
              ),
            ),
          ],
          if (d.estadoAdelanto == 'pendiente_adelanto' &&
              _estaPlazoPagoVencido(d)) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('avisoPlazoPagoVencido'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoError,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: TemaPsicobloom.colorError.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'El plazo de pago venció según la hora del servidor. No realices una nueva transferencia para esta solicitud; si ya transferiste y tuviste un problema al adjuntar el comprobante, puedes reportar una incidencia abajo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorError,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
          if (d.revisionDemorada) ...[
            const SizedBox(height: 8),
            const Text(
              'Revisión demorada: han pasado más de 12 horas desde el envío del comprobante. Tu reserva se mantiene activa mientras el profesional completa la verificación.',
              key: Key('avisoRevisionDemorada'),
              style: TextStyle(
                fontSize: 12.5,
                color: TemaPsicobloom.colorAdvertencia,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (d.condicionesAceptadas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              d.condicionesAceptadas,
              style: const TextStyle(
                fontSize: 12,
                color: TemaPsicobloom.colorTextoSecundario,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirSeccionQrYDatosBancarios(DetalleAdelantoCita d) {
    return Container(
      key: const Key('seccionQrDatosBancariosPaciente'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Datos privados para transferir el adelanto',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: TemaPsicobloom.colorTexto,
            ),
          ),
          const SizedBox(height: 10),
          if (_urlQrTemporal != null && _urlQrTemporal!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _urlQrTemporal!,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.qr_code_2_rounded,
                  size: 64,
                  color: TemaPsicobloom.colorPrincipal,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text('Banco: ${d.bancoBeneficiario ?? '-'}'),
          Text('Titular: ${d.titularBeneficiario ?? '-'}'),
          if (d.tipoCuentaBeneficiario != null &&
              d.tipoCuentaBeneficiario!.isNotEmpty)
            Text('Tipo de cuenta: ${d.tipoCuentaBeneficiario}'),
          if (d.numeroCuentaReferencia != null &&
              d.numeroCuentaReferencia!.isNotEmpty)
            Text('Cuenta: ${d.numeroCuentaReferencia}'),
        ],
      ),
    );
  }

  Widget _construirSeccionEnvioComprobante() {
    final pendiente = _pendienteComprobante;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Adjuntar comprobante privado (PNG/JPG, máx. 5 MB)',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
          ),
          if (pendiente != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('avisoComprobanteSubidoPendiente'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TemaPsicobloom.colorFondoAdvertencia,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Ya existe un comprobante subido pendiente de confirmar en el servidor. Puedes reintentar su registro sin volver a subir el archivo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: TemaPsicobloom.colorAdvertencia,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              key: const Key('botonReintentarRegistroComprobante'),
              onPressed: _procesando
                  ? null
                  : _reintentarRegistroComprobantePendiente,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                _procesando
                    ? 'Verificando y reintentando...'
                    : 'Reintentar registro del comprobante subido',
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          TextField(
            key: const Key('campoNotaComprobantePaciente'),
            controller: _controladorNota,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Aclaración o número de referencia (opcional)',
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            key: const Key('botonEnviarComprobanteAdelanto'),
            onPressed: _procesando ? null : _enviarNuevoComprobante,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              _procesando
                  ? 'Enviando comprobante...'
                  : (pendiente != null
                        ? 'Subir un comprobante diferente (corrección)'
                        : 'Seleccionar y enviar comprobante'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionIncidencia() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '¿Ya transferiste y tuviste un problema al adjuntar?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Registra una incidencia para revisión. Si el horario ya venció y fue asignado a otra persona, no puede recuperarse automáticamente.',
            style: TextStyle(
              fontSize: 12,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('campoDetalleIncidenciaAdelanto'),
            controller: _controladorIncidencia,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Describe brevemente el problema al adjuntar...',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('botonReportarIncidenciaAdelanto'),
            onPressed: _procesando ? null : _reportarIncidencia,
            icon: const Icon(Icons.report_problem_outlined, size: 18),
            label: const Text('Ya transferí y tuve un problema al adjuntar'),
          ),
        ],
      ),
    );
  }

  Widget _construirAccionesProfesional() {
    return Container(
      key: const Key('seccionAccionesRevisionProfesional'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Verificación de ingreso',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Confirma únicamente después de verificar el ingreso real en tu cuenta bancaria. Un comprobante enviado no equivale a un ingreso verificado.',
            style: TextStyle(
              fontSize: 12.5,
              color: TemaPsicobloom.colorTextoSecundario,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            key: const Key('botonVerificarIngresoAdelanto'),
            onPressed: _procesando
                ? null
                : () => _revisarComoProfesional('verificar'),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verificar ingreso y confirmar cita'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('campoMotivoObservacionAdelanto'),
            controller: _controladorMotivo,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Motivo de observación (mínimo 5 caracteres)',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('botonObservarComprobanteAdelanto'),
            onPressed: _procesando
                ? null
                : () => _revisarComoProfesional('observar'),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Observar comprobante y pedir aclaración'),
          ),
        ],
      ),
    );
  }

  Widget _construirHistorial(DetalleAdelantoCita d) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemaPsicobloom.colorSuperficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemaPsicobloom.colorBorde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historial de comprobantes y observaciones',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (d.comprobantes.isEmpty &&
              d.observaciones.isEmpty &&
              d.incidencias.isEmpty)
            const Text(
              'Aún no se han registrado comprobantes ni observaciones.',
              style: TextStyle(
                fontSize: 13,
                color: TemaPsicobloom.colorTextoSecundario,
              ),
            ),
          ...d.comprobantes.map((comp) {
            final url = _urlsComprobantes[comp.idComprobante];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comprobante enviado ${comp.creadoEn != null ? formatearFechaHoraEcuador(comp.creadoEn!) : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (comp.notaPaciente != null &&
                      comp.notaPaciente!.isNotEmpty)
                    Text(
                      'Nota: ${comp.notaPaciente}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  if (url != null && url.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.receipt_long_outlined,
                          size: 40,
                          color: TemaPsicobloom.colorPrincipal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          ...d.observaciones.map(
            (obs) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${obs.tipoActor == 'profesional' ? 'Observación del profesional' : 'Aclaración del paciente'}: ${obs.mensaje}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
          ...d.incidencias.map((inc) {
            final puedeCerrar =
                widget.esProfesional && d.puedeResolverIncidenciaCarga(inc);
            return Container(
              key: Key('tarjetaIncidenciaAdelanto_${inc.idIncidencia}'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: inc.estaResuelta
                    ? TemaPsicobloom.colorMenta.withValues(alpha: 0.45)
                    : TemaPsicobloom.colorFondoAdvertencia.withValues(
                        alpha: 0.45,
                      ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: inc.estaResuelta
                      ? TemaPsicobloom.colorSecundario.withValues(alpha: 0.35)
                      : TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Incidencia de carga',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: TemaPsicobloom.colorTexto,
                          ),
                        ),
                      ),
                      Container(
                        key: Key(
                          'estadoIncidenciaAdelanto_${inc.idIncidencia}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: inc.estaResuelta
                              ? TemaPsicobloom.colorMenta
                              : TemaPsicobloom.colorFondoAdvertencia,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          inc.etiquetaEstado,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: inc.estaResuelta
                                ? TemaPsicobloom.colorSecundario
                                : TemaPsicobloom.colorAdvertencia,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    inc.detalle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TemaPsicobloom.colorTexto,
                    ),
                  ),
                  if (inc.horarioYaLiberado) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Esta incidencia ocurrió con el horario ya liberado y requiere tratamiento posterior (no aplica el cierre simple de carga).',
                      key: Key(
                        'avisoIncidenciaHorarioLiberado_${inc.idIncidencia}',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: TemaPsicobloom.colorError,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (inc.estaResuelta) ...[
                    if (inc.motivoResolucion != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Motivo de resolución: ${inc.motivoResolucion}',
                        key: Key(
                          'motivoResolucionIncidencia_${inc.idIncidencia}',
                        ),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                    ],
                    if (inc.textoResueltoEnEcuador != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Resuelta el: ${inc.textoResueltoEnEcuador}',
                        key: Key(
                          'fechaResolucionIncidencia_${inc.idIncidencia}',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: TemaPsicobloom.colorTextoSecundario,
                        ),
                      ),
                    ],
                  ],
                  if (puedeCerrar) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: Key('botonResolverIncidencia_${inc.idIncidencia}'),
                      onPressed: _procesando
                          ? null
                          : () =>
                                unawaited(_abrirDialogoResolverIncidencia(inc)),
                      icon: const Icon(Icons.task_alt_rounded, size: 18),
                      label: const Text('Resolver incidencia'),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DialogoResolverIncidencia extends StatefulWidget {
  const _DialogoResolverIncidencia();

  @override
  State<_DialogoResolverIncidencia> createState() =>
      _DialogoResolverIncidenciaState();
}

class _DialogoResolverIncidenciaState
    extends State<_DialogoResolverIncidencia> {
  final _controladorMotivo = TextEditingController();
  String? _errorDialogo;

  @override
  void dispose() {
    _controladorMotivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolver incidencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resolver esta incidencia no verifica el pago ni confirma la cita.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TemaPsicobloom.colorAdvertencia,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('campoMotivoResolucionIncidencia'),
              controller: _controladorMotivo,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Motivo de resolución',
                hintText: 'Explica brevemente cómo se cerró el problema de carga (5 a 500 caracteres)',
                errorText: _errorDialogo,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('botonConfirmarResolverIncidencia'),
          onPressed: () {
            final texto = _controladorMotivo.text.trim();
            if (texto.length < 5 || texto.length > 500) {
              setState(() {
                _errorDialogo = 'Ingresa un motivo entre 5 y 500 caracteres.';
              });
              return;
            }
            Navigator.of(context).pop(texto);
          },
          child: const Text('Confirmar resolución'),
        ),
      ],
    );
  }
}
