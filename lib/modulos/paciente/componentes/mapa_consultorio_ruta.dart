import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modulos/paciente/controladores/controlador_ruta_consultorio.dart';
import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Marcador individual de un consultorio con coordenadas validas en Riobamba.
class MarcadorConsultorioMapa {
  final String id;
  final String titulo;
  final String subtitulo;
  final double latitud;
  final double longitud;
  final bool seleccionado;

  const MarcadorConsultorioMapa({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.latitud,
    required this.longitud,
    this.seleccionado = false,
  });
}

/// Visualizador seguro del mapa de consultorios en Riobamba y su ruta vial.
/// Si existe `GOOGLE_MAPS_API_KEY` nativa usa `GoogleMap`; en caso contrario
/// dibuja un lienzo interactivo Flutter con marcadores reales y polilinea vial.
class MapaConsultorioRuta extends StatelessWidget {
  final List<MarcadorConsultorioMapa> marcadores;
  final CoordenadaMapa? ubicacionPaciente;
  final RutaConsultorio? rutaActiva;
  final ValueChanged<String>? alSeleccionarMarcador;
  final double altura;

  const MapaConsultorioRuta({
    super.key,
    required this.marcadores,
    this.ubicacionPaciente,
    this.rutaActiva,
    this.alSeleccionarMarcador,
    this.altura = 220,
  });

  @override
  Widget build(BuildContext context) {
    final marcadorFoco =
        marcadores.where((m) => m.seleccionado).firstOrNull ??
        marcadores.firstOrNull;
    final centroInicial = marcadorFoco != null
        ? LatLng(marcadorFoco.latitud, marcadorFoco.longitud)
        : const LatLng(
            ServicioUbicacionConsultorio.latitudReferenciaRiobamba,
            ServicioUbicacionConsultorio.longitudReferenciaRiobamba,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: altura,
        width: double.infinity,
        child: ConfiguracionSupabase.tieneClaveGoogleMaps
            ? _construirGoogleMapNativo(centroInicial)
            : _LienzoMapaRutaRiobamba(
                marcadores: marcadores,
                ubicacionPaciente: ubicacionPaciente,
                rutaActiva: rutaActiva,
                alSeleccionarMarcador: alSeleccionarMarcador,
              ),
      ),
    );
  }

  Widget _construirGoogleMapNativo(LatLng centroInicial) {
    final conjuntoMarcadores = <Marker>{
      for (final m in marcadores)
        Marker(
          markerId: MarkerId('consultorio_${m.id}'),
          position: LatLng(m.latitud, m.longitud),
          infoWindow: InfoWindow(title: m.titulo, snippet: m.subtitulo),
          onTap: alSeleccionarMarcador != null
              ? () => alSeleccionarMarcador!(m.id)
              : null,
        ),
      if (ubicacionPaciente != null && ubicacionPaciente!.esValida)
        Marker(
          markerId: const MarkerId('origen_paciente'),
          position: LatLng(
            ubicacionPaciente!.latitud,
            ubicacionPaciente!.longitud,
          ),
          infoWindow: const InfoWindow(title: 'Tu ubicación actual'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
    };

    final conjuntoPolilineas = <Polyline>{
      if (rutaActiva != null && rutaActiva!.esRutaCalleValida)
        Polyline(
          polylineId: const PolylineId('ruta_vial_consultorio'),
          color: TemaPsicobloom.colorPrincipal,
          width: 5,
          points: rutaActiva!.puntosPolilinea
              .map((p) => LatLng(p.latitud, p.longitud))
              .toList(),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: centroInicial, zoom: 14.8),
      markers: conjuntoMarcadores,
      polylines: conjuntoPolilineas,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}

class _LienzoMapaRutaRiobamba extends StatelessWidget {
  final List<MarcadorConsultorioMapa> marcadores;
  final CoordenadaMapa? ubicacionPaciente;
  final RutaConsultorio? rutaActiva;
  final ValueChanged<String>? alSeleccionarMarcador;

  const _LienzoMapaRutaRiobamba({
    required this.marcadores,
    this.ubicacionPaciente,
    this.rutaActiva,
    this.alSeleccionarMarcador,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        final ancho = restricciones.maxWidth;
        final alto = restricciones.maxHeight;
        final proyeccion = _ProyeccionCoordenadasRiobamba.calcular(
          marcadores: marcadores,
          ubicacionPaciente: ubicacionPaciente,
          rutaActiva: rutaActiva,
        );

        final puntosRutaPantalla = <Offset>[];
        if (rutaActiva != null &&
            rutaActiva!.esRutaCalleValida &&
            ancho > 0 &&
            alto > 0) {
          for (final p in rutaActiva!.puntosPolilinea) {
            puntosRutaPantalla.add(
              proyeccion.proyectar(p.latitud, p.longitud, ancho, alto),
            );
          }
        }

        Offset? posicionPaciente;
        if (ubicacionPaciente != null &&
            ubicacionPaciente!.esValida &&
            ancho > 0 &&
            alto > 0) {
          posicionPaciente = proyeccion.proyectar(
            ubicacionPaciente!.latitud,
            ubicacionPaciente!.longitud,
            ancho,
            alto,
          );
        }

        final marcadorSeleccionado =
            marcadores.where((m) => m.seleccionado).firstOrNull ??
            marcadores.firstOrNull;

        return Stack(
          key: const Key('lienzoMapaRutaRiobamba'),
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _PintorFondoYRutaRiobamba(
                puntosPolilinea: puntosRutaPantalla,
              ),
            ),
            if (posicionPaciente != null)
              Positioned(
                left: posicionPaciente.dx - 11,
                top: posicionPaciente.dy - 11,
                child: Tooltip(
                  message: 'Tu ubicación actual',
                  child: Container(
                    key: const Key('marcadorOrigenPaciente'),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: TemaPsicobloom.colorInformacion,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            for (final marcador in marcadores)
              if (ancho > 0 && alto > 0)
                Builder(
                  builder: (context) {
                    final pos = proyeccion.proyectar(
                      marcador.latitud,
                      marcador.longitud,
                      ancho,
                      alto,
                    );
                    return Positioned(
                      left: pos.dx - 18,
                      top: pos.dy - 34,
                      child: GestureDetector(
                        key: Key('marcadorConsultorio_${marcador.id}'),
                        onTap: alSeleccionarMarcador != null
                            ? () => alSeleccionarMarcador!(marcador.id)
                            : null,
                        child: Tooltip(
                          message: '${marcador.titulo} • ${marcador.subtitulo}',
                          child: Icon(
                            Icons.location_on_rounded,
                            size: marcador.seleccionado ? 38 : 32,
                            color: marcador.seleccionado
                                ? TemaPsicobloom.colorPrincipal
                                : TemaPsicobloom.colorSecundario,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            Positioned(
              top: 8,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TemaPsicobloom.colorBorde),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: TemaPsicobloom.colorPrincipal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        marcadorSeleccionado != null
                            ? '${marcadorSeleccionado.titulo} (${marcadorSeleccionado.latitud.toStringAsFixed(4)}, ${marcadorSeleccionado.longitud.toStringAsFixed(4)})'
                            : 'Riobamba, Ecuador',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Riobamba, Ecuador',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: TemaPsicobloom.colorTextoSecundario,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProyeccionCoordenadasRiobamba {
  final double latCentro;
  final double lngCentro;
  final double rangoLat;
  final double rangoLng;

  const _ProyeccionCoordenadasRiobamba({
    required this.latCentro,
    required this.lngCentro,
    required this.rangoLat,
    required this.rangoLng,
  });

  factory _ProyeccionCoordenadasRiobamba.calcular({
    required List<MarcadorConsultorioMapa> marcadores,
    required CoordenadaMapa? ubicacionPaciente,
    required RutaConsultorio? rutaActiva,
  }) {
    final latitudes = <double>[];
    final longitudes = <double>[];

    for (final m in marcadores) {
      latitudes.add(m.latitud);
      longitudes.add(m.longitud);
    }
    if (ubicacionPaciente != null && ubicacionPaciente.esValida) {
      latitudes.add(ubicacionPaciente.latitud);
      longitudes.add(ubicacionPaciente.longitud);
    }
    if (rutaActiva != null && rutaActiva.esRutaCalleValida) {
      for (final p in rutaActiva.puntosPolilinea) {
        latitudes.add(p.latitud);
        longitudes.add(p.longitud);
      }
    }

    if (latitudes.isEmpty || longitudes.isEmpty) {
      return const _ProyeccionCoordenadasRiobamba(
        latCentro: ServicioUbicacionConsultorio.latitudReferenciaRiobamba,
        lngCentro: ServicioUbicacionConsultorio.longitudReferenciaRiobamba,
        rangoLat: 0.025,
        rangoLng: 0.025,
      );
    }

    final minLat = latitudes.reduce(math.min);
    final maxLat = latitudes.reduce(math.max);
    final minLng = longitudes.reduce(math.min);
    final maxLng = longitudes.reduce(math.max);

    final centroLat = (minLat + maxLat) / 2.0;
    final centroLng = (minLng + maxLng) / 2.0;
    final spanLat = math.max((maxLat - minLat) * 0.75, 0.015);
    final spanLng = math.max((maxLng - minLng) * 0.75, 0.015);

    return _ProyeccionCoordenadasRiobamba(
      latCentro: centroLat,
      lngCentro: centroLng,
      rangoLat: spanLat,
      rangoLng: spanLng,
    );
  }

  Offset proyectar(double lat, double lng, double ancho, double alto) {
    final normX = ((lng - lngCentro) / (2 * rangoLng) + 0.5).clamp(0.10, 0.90);
    final normY = ((latCentro - lat) / (2 * rangoLat) + 0.5).clamp(0.18, 0.86);
    return Offset(normX * ancho, normY * alto);
  }
}

class _PintorFondoYRutaRiobamba extends CustomPainter {
  final List<Offset> puntosPolilinea;

  const _PintorFondoYRutaRiobamba({required this.puntosPolilinea});

  @override
  void paint(Canvas canvas, Size size) {
    final fondo = Paint()..color = const Color(0xFFEEF3F1);
    canvas.drawRect(Offset.zero & size, fondo);

    final areaVerde = Paint()..color = const Color(0xFFDCEBE2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.10,
          size.height * 0.24,
          size.width * 0.22,
          size.height * 0.24,
        ),
        const Radius.circular(10),
      ),
      areaVerde,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.66,
          size.height * 0.54,
          size.width * 0.22,
          size.height * 0.25,
        ),
        const Radius.circular(10),
      ),
      areaVerde,
    );

    final calleSecundaria = Paint()
      ..color = const Color(0xFFD5DFDC)
      ..strokeWidth = 1.4;
    for (var i = 1; i <= 5; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), calleSecundaria);
    }
    for (var j = 1; j <= 4; j++) {
      final y = size.height * (j / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), calleSecundaria);
    }

    final avenidaPrincipal = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.5;
    canvas.drawLine(
      Offset(0, size.height * 0.48),
      Offset(size.width, size.height * 0.48),
      avenidaPrincipal,
    );
    canvas.drawLine(
      Offset(size.width * 0.52, 0),
      Offset(size.width * 0.52, size.height),
      avenidaPrincipal,
    );

    // Traza unicamente la polilinea vial cuando existe una ruta real de calles
    if (puntosPolilinea.length >= 2) {
      final trazoRuta = Path()
        ..moveTo(puntosPolilinea.first.dx, puntosPolilinea.first.dy);
      for (var i = 1; i < puntosPolilinea.length; i++) {
        trazoRuta.lineTo(puntosPolilinea[i].dx, puntosPolilinea[i].dy);
      }

      final pinturaBordeRuta = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final pinturaRuta = Paint()
        ..color = TemaPsicobloom.colorPrincipal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(trazoRuta, pinturaBordeRuta);
      canvas.drawPath(trazoRuta, pinturaRuta);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorFondoYRutaRiobamba oldDelegate) {
    return oldDelegate.puntosPolilinea != puntosPolilinea;
  }
}

/// Panel interactivo reutilizable que muestra el boton para calcular ruta,
/// la distancia por calles, el tiempo estimado y el manejo de errores o permisos.
class PanelResultadoRutaConsultorio extends StatelessWidget {
  final ControladorRutaConsultorio controlador;
  final VoidCallback alSolicitarRuta;
  final Key? claveBotonCalcular;

  const PanelResultadoRutaConsultorio({
    super.key,
    required this.controlador,
    required this.alSolicitarRuta,
    this.claveBotonCalcular,
  });

  @override
  Widget build(BuildContext context) {
    final ruta = controlador.ruta;
    final mensaje = controlador.mensajeEstado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: claveBotonCalcular ?? const Key('botonCalcularRutaConsultorio'),
          onPressed: controlador.estaCalculando ? null : alSolicitarRuta,
          icon: controlador.estaCalculando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: TemaPsicobloom.colorPrincipal,
                  ),
                )
              : const Icon(Icons.directions_car_outlined, size: 18),
          label: Text(
            controlador.estaCalculando
                ? 'Calculando ruta hacia el consultorio...'
                : ruta != null
                ? 'Actualizar ruta desde mi ubicación'
                : 'Cómo llegar (calcular ruta, distancia y tiempo)',
          ),
        ),
        if (ruta != null &&
            controlador.estado == EstadoCalculoRuta.rutaObtenida) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('tarjetaResumenRutaConsultorio'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorMenta.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TemaPsicobloom.colorSecundario.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            size: 18,
                            color: TemaPsicobloom.colorSecundario,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Distancia vial: ${ruta.distanciaTexto}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: TemaPsicobloom.colorTexto,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: TemaPsicobloom.colorPrincipalOscuro,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Tiempo: ${ruta.tiempoEstimadoTexto}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: TemaPsicobloom.colorTexto,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ruta.avisoNaturalezaTiempo,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: TemaPsicobloom.colorTextoSecundario,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (mensaje != null && mensaje.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('avisoErrorRutaConsultorio'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorFondoAdvertencia,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TemaPsicobloom.colorAdvertencia.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: TemaPsicobloom.colorAdvertencia,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: TemaPsicobloom.colorTexto,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
