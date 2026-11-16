import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/nucleo/servicios/servicio_geoapify.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Mapa real, compartido por el directorio, perfil publico y selector del profesional.
class MapaGeoapify extends StatefulWidget {
  final LatLng centro;
  final List<Marker> marcadores;
  final List<LatLng> ruta;
  final ValueChanged<LatLng>? alTocar;
  final double altura;
  final TileProvider? proveedorTeselas;
  final VoidCallback? alAmpliar;
  const MapaGeoapify({
    super.key,
    required this.centro,
    this.marcadores = const [],
    this.ruta = const [],
    this.alTocar,
    this.altura = 220,
    this.proveedorTeselas,
    this.alAmpliar,
  });
  @override
  State<MapaGeoapify> createState() => _MapaGeoapifyState();
}

class _MapaGeoapifyState extends State<MapaGeoapify> {
  final _camara = MapController();
  final _reinicio = StreamController<void>.broadcast();
  late final TileProvider _proveedor;
  StreamSubscription<AuthState>? _sesion;
  bool _lista = false;
  bool _moverMapa = false;
  late final ClienteTeselasGeoapify _clienteTeselas;

  bool get _tieneAcceso =>
      widget.proveedorTeselas != null ||
      (ConfiguracionSupabase.estaConfigurado &&
          ServicioGeoapify.clienteActual?.auth.currentSession != null);

  @override
  void initState() {
    super.initState();
    _clienteTeselas = ClienteTeselasGeoapify();
    _proveedor =
        widget.proveedorTeselas ??
        NetworkTileProvider(
          httpClient: _clienteTeselas,
          silenceExceptions: true,
          attemptDecodeOfHttpErrorResponses: false,
          abortObsoleteRequests: false,
        );
    _sesion = ServicioGeoapify.clienteActual?.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapaGeoapify oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centro != widget.centro ||
        !listEquals(oldWidget.ruta, widget.ruta)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _encuadrar();
        }
      });
    }
  }

  void _encuadrar() {
    if (!_lista) {
      return;
    }
    if (widget.ruta.length >= 2) {
      _camara.fitCamera(
        CameraFit.coordinates(
          coordinates: widget.ruta,
          padding: const EdgeInsets.all(36),
          maxZoom: 16,
        ),
      );
    } else {
      _camara.move(widget.centro, 15);
    }
  }

  Future<void> _abrirCredito(String direccion) async {
    try {
      await launchUrl(
        Uri.parse(direccion),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      /* La atribucion permanece visible aunque no haya navegador. */
    }
  }

  @override
  void dispose() {
    _sesion?.cancel();
    _reinicio.close();
    _camara.dispose();
    _clienteTeselas.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      height: widget.altura,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  key: const Key('mapaGeoapify'),
                  mapController: _camara,
                  options: MapOptions(
                    initialCenter: widget.centro,
                    initialZoom: 15,
                    minZoom: 10,
                    maxZoom: 19,
                    // En una ficha desplazable, un arrastre normal debe mover la pagina.
                    // La mano habilita deliberadamente el desplazamiento del mapa.
                    interactionOptions: InteractionOptions(
                      flags: _moverMapa
                          ? InteractiveFlag.all
                          : InteractiveFlag.none,
                    ),
                    onMapReady: () {
                      _lista = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _encuadrar();
                        }
                      });
                    },
                    onTap: _tieneAcceso && widget.alTocar != null
                        ? (_, punto) => widget.alTocar!(punto)
                        : null,
                  ),
                  children: [
                    if (_tieneAcceso)
                      TileLayer(
                        urlTemplate: ServicioGeoapify.plantillaTeselas,
                        tileProvider: _proveedor,
                        maxNativeZoom: 19,
                        retinaMode: false,
                        panBuffer: 0,
                        keepBuffer: 0,
                        userAgentPackageName: 'com.example.boom',
                        reset: _reinicio.stream,
                      ),
                    if (widget.ruta.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: widget.ruta,
                            color: TemaPsicobloom.colorPrincipal,
                            strokeWidth: 5,
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: widget.marcadores),
                  ],
                ),
                if (!_tieneAcceso)
                  const Positioned(
                    left: 8,
                    right: 8,
                    top: 8,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Inicia sesión para cargar el mapa.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                if (_tieneAcceso)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Column(
                      children: [
                        _boton(
                          Icons.add,
                          'Acercar mapa',
                          () => _camara.move(
                            _camara.camera.center,
                            (_camara.camera.zoom + 1)
                                .clamp(10.0, 19.0)
                                .toDouble(),
                          ),
                        ),
                        _boton(
                          Icons.remove,
                          'Alejar mapa',
                          () => _camara.move(
                            _camara.camera.center,
                            (_camara.camera.zoom - 1)
                                .clamp(10.0, 19.0)
                                .toDouble(),
                          ),
                        ),
                        _boton(
                          Icons.center_focus_strong,
                          'Centrar mapa',
                          _encuadrar,
                        ),
                        _boton(
                          _moverMapa
                              ? Icons.lock_open
                              : Icons.pan_tool_outlined,
                          _moverMapa
                              ? 'Bloquear mapa para desplazar la página'
                              : 'Activar movimiento del mapa',
                          () => setState(() => _moverMapa = !_moverMapa),
                        ),
                      ],
                    ),
                  ),
                if (_tieneAcceso)
                  Positioned(
                    left: 6,
                    right: 52,
                    top: 6,
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _clienteTeselas.aviso,
                      builder: (_, mensaje, _) => mensaje == null
                          ? const SizedBox.shrink()
                          : Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      mensaje,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        _clienteTeselas.aviso.value = null;
                                        _reinicio.add(null);
                                      },
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                if (widget.alAmpliar != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: TemaPsicobloom.colorSuperficie.withValues(
                        alpha: 0.96,
                      ),
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const Key('botonAmpliarMapa'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.alAmpliar,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: TemaPsicobloom.colorBorde,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_full_rounded,
                                size: 15,
                                color: TemaPsicobloom.colorPrincipal,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Ampliar mapa',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: TemaPsicobloom.colorTexto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Creditos siempre visibles: nunca ocultos detras de un boton o marcador.
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                _credito('Powered by Geoapify', 'https://www.geoapify.com/'),
                _credito(
                  '© OpenStreetMap contributors',
                  'https://www.openstreetmap.org/copyright',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _credito(String texto, String direccion) => InkWell(
    onTap: () => _abrirCredito(direccion),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 10,
          color: TemaPsicobloom.colorPrincipal,
        ),
      ),
    ),
  );
  Widget _boton(IconData icono, String ayuda, VoidCallback accion) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: IconButton(
      tooltip: ayuda,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      onPressed: accion,
      icon: Icon(icono, size: 18),
    ),
  );
}
