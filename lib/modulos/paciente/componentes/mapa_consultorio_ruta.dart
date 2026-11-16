import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:boom/nucleo/componentes/mapa_geoapify.dart';
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
  final String? fotoUrl;
  final bool seleccionado;

  const MarcadorConsultorioMapa({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.latitud,
    required this.longitud,
    this.fotoUrl,
    this.seleccionado = false,
  });
}

/// Visualiza consultorios reales y la ruta calculada por OpenRouteService.
class MapaConsultorioRuta extends StatelessWidget {
  final List<MarcadorConsultorioMapa> marcadores;
  final CoordenadaMapa? ubicacionPaciente;
  final RutaConsultorio? rutaActiva;
  final ValueChanged<String>? alSeleccionarMarcador;
  final VoidCallback? alAmpliar;
  final double altura;
  const MapaConsultorioRuta({
    super.key,
    required this.marcadores,
    this.ubicacionPaciente,
    this.rutaActiva,
    this.alSeleccionarMarcador,
    this.alAmpliar,
    this.altura = 220,
  });

  @override
  Widget build(BuildContext context) {
    final foco =
        marcadores.where((punto) => punto.seleccionado).firstOrNull ??
        marcadores.firstOrNull;
    return MapaGeoapify(
      centro: foco == null
          ? const LatLng(
              ServicioUbicacionConsultorio.latitudReferenciaRiobamba,
              ServicioUbicacionConsultorio.longitudReferenciaRiobamba,
            )
          : LatLng(foco.latitud, foco.longitud),
      altura: altura,
      alAmpliar: alAmpliar,
      ruta: rutaActiva?.esRutaCalleValida == true
          ? rutaActiva!.puntosPolilinea
                .map((punto) => LatLng(punto.latitud, punto.longitud))
                .toList()
          : const [],
      marcadores: [
        for (final punto in marcadores)
          Marker(
            point: LatLng(punto.latitud, punto.longitud),
            width: punto.seleccionado ? 60 : 48,
            height: punto.seleccionado ? 68 : 56,
            alignment: Alignment.topCenter,
            child: Semantics(
              label: 'Consultorio de ${punto.titulo}',
              button: true,
              selected: punto.seleccionado,
              child: GestureDetector(
                key: Key('marcadorConsultorio_${punto.id}'),
                onTap: alSeleccionarMarcador == null
                    ? null
                    : () => alSeleccionarMarcador!(punto.id),
                child: Tooltip(
                  message: '${punto.titulo} • ${punto.subtitulo}',
                  child: _MarcadorFotoProfesional(
                    nombre: punto.titulo,
                    fotoUrl: punto.fotoUrl,
                    seleccionado: punto.seleccionado,
                  ),
                ),
              ),
            ),
          ),
        if (ubicacionPaciente?.esValida == true)
          Marker(
            point: LatLng(
              ubicacionPaciente!.latitud,
              ubicacionPaciente!.longitud,
            ),
            width: 24,
            height: 24,
            child: const Tooltip(
              message: 'Tu ubicación actual',
              child: Icon(
                Icons.my_location,
                key: Key('marcadorOrigenPaciente'),
                color: TemaPsicobloom.colorInformacion,
                size: 24,
              ),
            ),
          ),
      ],
    );
  }
}

/// Avatar circular reutilizable para marcadores y tarjetas del mapa.
class AvatarFotoProfesional extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;
  final double diametro;
  final Color colorBorde;
  final double anchoBorde;

  const AvatarFotoProfesional({
    super.key,
    required this.nombre,
    this.fotoUrl,
    this.diametro = 44,
    this.colorBorde = TemaPsicobloom.colorBorde,
    this.anchoBorde = 1.5,
  });

  String _obtenerIniciales(String texto) {
    final partes = texto
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = fotoUrl?.trim() ?? '';
    final tieneFoto = url.isNotEmpty;
    final iniciales = _obtenerIniciales(nombre);

    Widget respaldo() => Container(
      color: TemaPsicobloom.colorLavanda,
      alignment: Alignment.center,
      child: iniciales.isNotEmpty
          ? Text(
              iniciales,
              style: TextStyle(
                fontSize: diametro * 0.34,
                fontWeight: FontWeight.bold,
                color: TemaPsicobloom.colorPrincipalOscuro,
              ),
            )
          : Icon(
              Icons.person_rounded,
              size: diametro * 0.54,
              color: TemaPsicobloom.colorPrincipal,
            ),
    );

    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TemaPsicobloom.colorLavanda,
        border: Border.all(color: colorBorde, width: anchoBorde),
      ),
      child: ClipOval(
        child: tieneFoto
            ? Image.network(
                url,
                width: diametro,
                height: diametro,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => respaldo(),
              )
            : respaldo(),
      ),
    );
  }
}

class _MarcadorFotoProfesional extends StatelessWidget {
  final String nombre;
  final String? fotoUrl;
  final bool seleccionado;

  const _MarcadorFotoProfesional({
    required this.nombre,
    required this.fotoUrl,
    required this.seleccionado,
  });

  @override
  Widget build(BuildContext context) {
    final diametro = seleccionado ? 46.0 : 36.0;
    final colorBorde = seleccionado
        ? TemaPsicobloom.colorPrincipal
        : TemaPsicobloom.colorPrincipalOscuro;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(seleccionado ? 3 : 1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: seleccionado
                ? TemaPsicobloom.colorLavanda.withValues(alpha: 0.9)
                : Colors.transparent,
            boxShadow: [
              BoxShadow(
                color: TemaPsicobloom.colorPrincipal.withValues(
                  alpha: seleccionado ? 0.35 : 0.18,
                ),
                blurRadius: seleccionado ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AvatarFotoProfesional(
            nombre: nombre,
            fotoUrl: fotoUrl,
            diametro: diametro,
            colorBorde: colorBorde,
            anchoBorde: seleccionado ? 3.0 : 2.0,
          ),
        ),
        CustomPaint(
          size: Size(seleccionado ? 14 : 11, seleccionado ? 9 : 7),
          painter: _PuntaMarcadorPainter(color: colorBorde),
        ),
      ],
    );
  }
}

class _PuntaMarcadorPainter extends CustomPainter {
  final Color color;
  const _PuntaMarcadorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PuntaMarcadorPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Panel interactivo reutilizable que muestra el selector de transporte,
/// el boton para calcular ruta, el resultado destacado y el manejo de errores.
class PanelResultadoRutaConsultorio extends StatelessWidget {
  final ControladorRutaConsultorio controlador;
  final VoidCallback alSolicitarRuta;
  final Key? claveBotonCalcular;
  final VoidCallback? alVerPerfil;

  const PanelResultadoRutaConsultorio({
    super.key,
    required this.controlador,
    required this.alSolicitarRuta,
    this.claveBotonCalcular,
    this.alVerPerfil,
  });

  @override
  Widget build(BuildContext context) {
    final ruta = controlador.ruta;
    final mensaje = controlador.mensajeEstado;

    final botonCalcular = alVerPerfil != null
        ? Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('botonVerPerfilMapa'),
                  onPressed: alVerPerfil,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Ver perfil'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  key:
                      claveBotonCalcular ??
                      const Key('botonCalcularRutaConsultorio'),
                  onPressed: controlador.estaCalculando
                      ? null
                      : alSolicitarRuta,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: controlador.estaCalculando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.directions_outlined, size: 18),
                  label: Text(
                    controlador.estaCalculando
                        ? 'Calculando...'
                        : ruta != null
                        ? 'Actualizar ruta'
                        : 'Cómo llegar',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          )
        : OutlinedButton.icon(
            key:
                claveBotonCalcular ?? const Key('botonCalcularRutaConsultorio'),
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
                : Icon(
                    controlador.medioTransporte == MedioTransporte.auto
                        ? Icons.directions_car_outlined
                        : Icons.directions_walk,
                    size: 18,
                  ),
            label: Text(
              controlador.estaCalculando
                  ? 'Calculando ruta hacia el consultorio...'
                  : ruta != null
                  ? 'Actualizar ruta desde mi ubicación'
                  : 'Cómo llegar (calcular ruta, distancia y tiempo)',
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final medio in MedioTransporte.values)
              ChoiceChip(
                key: Key('transporte_${medio.valorApi}'),
                selectedColor: TemaPsicobloom.colorPrincipal,
                backgroundColor: medio == MedioTransporte.auto
                    ? TemaPsicobloom.colorMenta.withValues(alpha: 0.6)
                    : TemaPsicobloom.colorLavanda.withValues(alpha: 0.6),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: controlador.medioTransporte == medio
                      ? Colors.white
                      : TemaPsicobloom.colorTexto,
                ),
                avatar: Icon(
                  medio == MedioTransporte.auto
                      ? Icons.directions_car_outlined
                      : Icons.directions_walk,
                  size: 18,
                  color: controlador.medioTransporte == medio
                      ? Colors.white
                      : TemaPsicobloom.colorTexto,
                ),
                label: Text(medio.etiqueta),
                selected: controlador.medioTransporte == medio,
                onSelected: controlador.estaCalculando
                    ? null
                    : (_) {
                        if (controlador.cambiarMedioTransporte(medio)) {
                          alSolicitarRuta();
                        }
                      },
              ),
          ],
        ),
        if (ruta != null &&
            controlador.estado == EstadoCalculoRuta.rutaObtenida) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('tarjetaResumenRutaConsultorio'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaPsicobloom.colorLavanda.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: TemaPsicobloom.colorPrincipal.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: TemaPsicobloom.colorSuperficie,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    ruta.medioTransporte == MedioTransporte.auto
                        ? Icons.directions_car_rounded
                        : Icons.directions_walk_rounded,
                    color: TemaPsicobloom.colorPrincipal,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ruta.medioTransporte.etiqueta} · ${ruta.tiempoEstimadoTexto}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recorrido: ${ruta.distanciaTexto}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: TemaPsicobloom.colorTexto,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ruta.avisoNaturalezaTiempo,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: TemaPsicobloom.colorTextoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        botonCalcular,
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
