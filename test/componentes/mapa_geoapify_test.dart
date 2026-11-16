import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:boom/nucleo/componentes/mapa_geoapify.dart';

class _TeselasPrueba extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
}

void main() {
  testWidgets(
    'Selecciona coordenadas con proyeccion real y muestra atribuciones',
    (probador) async {
      LatLng? elegido;
      await probador.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapaGeoapify(
              centro: const LatLng(-1.67098, -78.64712),
              altura: 300,
              proveedorTeselas: _TeselasPrueba(),
              alTocar: (punto) => elegido = punto,
            ),
          ),
        ),
      );
      await probador.pumpAndSettle();
      await probador.tapAt(
        probador.getCenter(find.byKey(const Key('mapaGeoapify'))),
      );
      // El mapa distingue el toque simple del doble toque para acercar.
      await probador.pump(const Duration(milliseconds: 500));
      await probador.pumpAndSettle();
      expect(elegido, isNotNull);
      expect(elegido!.latitude, closeTo(-1.67098, 0.002));
      expect(elegido!.longitude, closeTo(-78.64712, 0.002));
      expect(find.text('Powered by Geoapify'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Desplazar la ficha no mueve el mapa bloqueado', (
    probador,
  ) async {
    await probador.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            key: const Key('listaPruebaMapa'),
            children: [
              const SizedBox(height: 80),
              MapaGeoapify(
                centro: const LatLng(-1.67098, -78.64712),
                altura: 300,
                proveedorTeselas: _TeselasPrueba(),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );
    await probador.pumpAndSettle();
    final mapa = find.byKey(const Key('mapaGeoapify'));
    final camara = probador.widget<FlutterMap>(mapa).mapController!;
    final centroAntes = camara.camera.center;
    await probador.drag(mapa, const Offset(0, -100));
    await probador.pumpAndSettle();
    final lista = find
        .descendant(
          of: find.byKey(const Key('listaPruebaMapa')),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      probador.state<ScrollableState>(lista).position.pixels,
      greaterThan(0),
    );
    expect(
      camara.camera.center.latitude,
      closeTo(centroAntes.latitude, 0.000001),
    );
    expect(
      camara.camera.center.longitude,
      closeTo(centroAntes.longitude, 0.000001),
    );
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Centrar mapa encuadra toda la ruta despues de actualizarla', (
    probador,
  ) async {
    final proveedor = _TeselasPrueba();
    const ruta = [
      LatLng(-1.67275, -78.64830),
      LatLng(-1.67000, -78.65000),
      LatLng(-1.65000, -78.67000),
    ];
    Widget pantalla(List<LatLng> puntos) => MaterialApp(
      home: Scaffold(
        body: MapaGeoapify(
          centro: ruta.first,
          altura: 300,
          ruta: puntos,
          proveedorTeselas: proveedor,
        ),
      ),
    );
    await probador.pumpWidget(pantalla(const []));
    await probador.pumpAndSettle();
    await probador.pumpWidget(pantalla(ruta));
    await probador.pumpAndSettle();
    final camara = probador
        .widget<FlutterMap>(find.byKey(const Key('mapaGeoapify')))
        .mapController!;
    expect(camara.camera.visibleBounds.contains(ruta.first), isTrue);
    expect(camara.camera.visibleBounds.contains(ruta.last), isTrue);
    expect(find.byType(PolylineLayer), findsOneWidget);
    await probador.tap(find.byTooltip('Centrar mapa'));
    await probador.pumpAndSettle();
    expect(camara.camera.visibleBounds.contains(ruta.first), isTrue);
    expect(camara.camera.visibleBounds.contains(ruta.last), isTrue);
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
  });
}
