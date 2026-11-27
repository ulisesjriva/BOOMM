import 'package:flutter/material.dart';
import 'package:boom/modelos/gestion_cancelacion_cita.dart';
import 'package:boom/nucleo/servicios/servicio_cancelaciones_citas.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';

class BotonGestionCancelacion extends StatelessWidget {
  final String idCita;
  final ServicioAdelantosCitas servicioAdelantos;
  final VoidCallback alActualizar;
  const BotonGestionCancelacion({super.key, required this.idCita,
    required this.servicioAdelantos, required this.alActualizar});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: Key('gestionCancelacion_$idCita'),
    icon: const Icon(Icons.event_busy_outlined),
    label: const Text('Cancelación y devolución'),
    onPressed: () async {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) =>
        PantallaGestionCancelacionCita(idCita: idCita,
          servicio: ServicioCancelacionesCitas(ejecutorRpc: servicioAdelantos.ejecutorRpc,
            lectorUsuarioActualId: servicioAdelantos.lectorUsuarioActualId))));
      alActualizar();
    },
  );
}

class PantallaGestionCancelacionCita extends StatefulWidget {
  final String idCita;
  final ServicioCancelacionesCitas servicio;
  const PantallaGestionCancelacionCita({super.key, required this.idCita,
    this.servicio = const ServicioCancelacionesCitas()});
  @override
  State<PantallaGestionCancelacionCita> createState() => _PantallaGestionCancelacionCitaState();
}

class _PantallaGestionCancelacionCitaState extends State<PantallaGestionCancelacionCita> {
  final _motivo = TextEditingController();
  final _revision = TextEditingController();
  final _referencia = TextEditingController();
  GestionCancelacionCita? _gestion;
  bool _ocupada = false;
  bool _pagoReportado = false;
  String? _error;
  String? _aviso;
  String? _url;
  String? _rutaPendiente;
  String? _referenciaPendiente;
  // Retiene el archivo ya subido al volver a abrir; clave separada por sesión/cita.
  static final Map<String, ({String ruta, String referencia})> _pendientes = {};

  @override
  void initState() { super.initState(); _cargar(); }
  @override
  void dispose() { _motivo.dispose(); _revision.dispose(); _referencia.dispose(); super.dispose(); }

  String _explicar(Object error) => error is FormatException ? error.message.toString() :
      ServicioAdelantosCitas.explicarError(error);

  Future<void> _mostrar(GestionCancelacionCita gestion) async {
    String? url;
    String? errorImagen;
    if (gestion.rutaComprobante != null) {
      try { url = await widget.servicio.obtenerUrlDevolucion(gestion.rutaComprobante!); }
      catch (_) { errorImagen = 'La devolución está registrada. No se pudo cargar su imagen; pulsa Actualizar.'; }
    }
    if (!mounted) return;
    final clave = widget.servicio.claveSesion(widget.idCita);
    if (gestion.estadoDevolucion == 'registrada') _pendientes.remove(clave);
    final pendiente = gestion.rol == 'profesional' ? _pendientes[clave] : null;
    setState(() {
      _gestion = gestion; _url = url;
      _rutaPendiente = pendiente?.ruta;
      _referenciaPendiente = pendiente?.referencia;
      if (pendiente != null) _referencia.text = pendiente.referencia;
      if (errorImagen != null) _aviso = errorImagen;
    });
  }

  Future<void> _cargar() async {
    if (_ocupada) return;
    setState(() { _ocupada = true; _error = null; });
    try { await _mostrar(await widget.servicio.obtener(widget.idCita)); }
    catch (error) { if (mounted) setState(() => _error = _explicar(error)); }
    finally { if (mounted) setState(() => _ocupada = false); }
  }

  Future<void> _operar(Future<GestionCancelacionCita> Function() accion) async {
    if (_ocupada) return;
    setState(() { _ocupada = true; _error = null; _aviso = null; });
    try { await _mostrar(await accion()); }
    catch (error) { if (mounted) setState(() => _error = _explicar(error)); }
    finally { if (mounted) setState(() => _ocupada = false); }
  }

  Future<void> _cancelar() async {
    if (_ocupada) return;
    try { ServicioCancelacionesCitas.validarTexto(_motivo.text); }
    catch (error) { setState(() => _error = _explicar(error)); return; }
    // Se vuelve a consultar antes de presentar la consecuencia; la RPC valida
    // además su versión bajo bloqueo, incluso al cruzar el límite de 24 horas.
    GestionCancelacionCita previa;
    setState(() { _ocupada = true; _error = null; });
    try {
      previa = await widget.servicio.obtener(widget.idCita);
      await _mostrar(previa);
    } catch (error) {
      if (mounted) setState(() { _ocupada = false; _error = _explicar(error); });
      return;
    }
    if (!mounted) return;
    setState(() => _ocupada = false);
    if (!previa.puedeCancelar) return;
    final confirmar = await showDialog<bool>(context: context, builder: (contexto) => AlertDialog(
      title: const Text('Confirmar cancelación'),
      content: SingleChildScrollView(child: Text('Adelanto de la cita: ${previa.textoMonto}.\n\n'
        '${previa.textoConsecuencia}\n\n'
        '${_pagoReportado ? "Has indicado una transferencia que deberá verificar el profesional. " : ""}'
        'La cita se cancelará y el horario quedará liberado. No se realiza ninguna transferencia automática.')),
      actions: [TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Cancelar cita'))],
    ));
    if (confirmar != true || !mounted) return;
    await _operar(() => widget.servicio.cancelar(previa, _motivo.text, pagoReportado: _pagoReportado));
  }

  Future<void> _revisar(bool recibido) async {
    if (_ocupada) return;
    try { ServicioCancelacionesCitas.validarTexto(_revision.text); }
    catch (error) { setState(() => _error = _explicar(error)); return; }
    final confirmar = await showDialog<bool>(context: context, builder: (contexto) => AlertDialog(
      title: const Text('Registrar verificación bancaria'),
      content: Text(recibido
        ? 'Confirma únicamente si verificaste el ingreso real en tu cuenta. La cita seguirá cancelada.'
        : 'Registrarás que no recibiste el ingreso reportado. Conservaremos el historial y el motivo. La cita seguirá cancelada.'),
      actions: [TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Confirmar resultado'))],
    ));
    if (confirmar != true || !mounted) return;
    await _operar(() => widget.servicio.revisarPago(widget.idCita, recibido, _revision.text));
  }

  Future<void> _registrarDevolucion() async {
    if (_ocupada) return;
    try { ServicioCancelacionesCitas.validarTexto(_referencia.text, maximo: 150); }
    catch (error) { setState(() => _error = _explicar(error)); return; }
    final referencia = _referenciaPendiente ?? _referencia.text.trim();
    final confirmar = await showDialog<bool>(context: context, builder: (contexto) => AlertDialog(
      title: const Text('Registrar devolución manual'),
      content: Text('Declaro haber devuelto ${_gestion!.textoMonto}. Adjuntaré su comprobante privado. '
        'La app registra esta declaración; no ejecuta ni verifica automáticamente una transferencia bancaria.'),
      actions: [TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Adjuntar comprobante'))],
    ));
    if (confirmar != true || !mounted) return;
    await _operar(() async {
      if (_rutaPendiente == null) {
        final archivo = await const ServicioAdelantosCitas().seleccionarImagenComprobante();
        if (archivo == null) return widget.servicio.obtener(widget.idCita);
        final ruta = await widget.servicio.subirDevolucion(widget.idCita, archivo);
        _rutaPendiente = ruta; _referenciaPendiente = referencia;
        _pendientes[widget.servicio.claveSesion(widget.idCita)] = (ruta: ruta, referencia: referencia);
      }
      return widget.servicio.registrarDevolucion(widget.idCita, _rutaPendiente!, referencia);
    });
  }

  Widget _campo(TextEditingController controlador, String etiqueta, {int maximo = 500, bool habilitado = true}) =>
    TextField(controller: controlador, enabled: !_ocupada && habilitado, maxLength: maximo,
      minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) {
    final g = _gestion;
    return Scaffold(appBar: AppBar(title: const Text('Cancelación y devolución'), actions: [
      IconButton(tooltip: 'Actualizar', onPressed: _ocupada ? null : _cargar, icon: const Icon(Icons.refresh)),
    ]), body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      if (_ocupada) const LinearProgressIndicator(),
      if (_error != null) ...[Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _ocupada ? null : _cargar, child: const Text('Actualizar estado'))],
      if (_aviso != null) Text(_aviso!),
      if (g != null) ...[
        Text('Adelanto: ${g.textoMonto}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12), Text(g.textoConsecuencia),
        const SizedBox(height: 16),
        if (g.estaCancelada) ...[
          Text('Cita cancelada · ${g.fechaCancelacion ?? ""}'),
          Text('Motivo: ${g.motivo ?? ""}'), const SizedBox(height: 12),
          Text(g.etiquetaDevolucion, style: Theme.of(context).textTheme.titleMedium),
          if (g.motivoRevision != null) Text('Verificación del ingreso: ${g.motivoRevision}'),
          if (g.referencia != null) Text('Referencia de devolución: ${g.referencia}'),
        ],
        if (g.puedeCancelar) ...[
          _campo(_motivo, 'Motivo de cancelación (5 a 500 caracteres)'),
          if (g.montoCentavos > 0 && g.estadoPago == 'no_reportado') CheckboxListTile(
            value: _pagoReportado, onChanged: _ocupada ? null : (valor) => setState(() => _pagoReportado = valor ?? false),
            title: const Text('Ya se realizó una transferencia, aunque no se adjuntó comprobante'),
            subtitle: const Text('El ingreso quedará pendiente de verificación.'), controlAffinity: ListTileControlAffinity.leading),
          FilledButton.icon(onPressed: _ocupada ? null : _cancelar,
            icon: const Icon(Icons.event_busy), label: const Text('Revisar y cancelar cita')),
        ],
        if (g.puedeRevisarPago) ...[
          const SizedBox(height: 20), const Text('Verifica el ingreso real en tu cuenta bancaria antes de registrar el resultado.'),
          _campo(_revision, 'Motivo de la verificación'),
          FilledButton(onPressed: _ocupada ? null : () => _revisar(true), child: const Text('Ingreso recibido')),
          OutlinedButton(onPressed: _ocupada ? null : () => _revisar(false), child: const Text('Ingreso no recibido')),
        ],
        if (g.puedeRegistrarDevolucion) ...[
          const SizedBox(height: 20), const Text('Realiza la devolución fuera de la app y luego adjunta su comprobante. No vuelvas a transferir si falla el registro.'),
          _campo(_referencia, 'Referencia de la devolución', maximo: 150, habilitado: _rutaPendiente == null),
          FilledButton(onPressed: _ocupada ? null : _registrarDevolucion,
            child: Text(_rutaPendiente == null ? 'Adjuntar y registrar devolución' : 'Reintentar registro del comprobante ya subido')),
        ],
        if (g.rutaComprobante != null) ...[
          const SizedBox(height: 20), const Text('Comprobante privado de devolución'),
          if (_url != null) Image.network(_url!, errorBuilder: (context, error, stack) =>
            const Text('No se pudo mostrar la imagen. Pulsa Actualizar para renovar el acceso.')),
          const Text('Registrada por el profesional. Esto no constituye una verificación bancaria automática.'),
        ],
        if (!g.puedeCancelar && !g.estaCancelada) const Text('Esta cita ya no permite cancelación. Su historial se conserva.'),
      ],
    ])));
  }
}
