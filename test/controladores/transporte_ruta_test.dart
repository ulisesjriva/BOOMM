import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/paciente/controladores/controlador_ruta_consultorio.dart';
import 'package:boom/modulos/paciente/componentes/mapa_consultorio_ruta.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';

class _UbicacionPrueba extends ServicioUbicacionConsultorio {
  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async =>
      const ResultadoUbicacionDispositivo.obtenida(
        latitud: -1.65,
        longitud: -78.67,
      );
}

void main() {
  final solicitudes = <String>[];
  ServicioRutasConsultorio servicio({bool confirmarTransporte = true}) =>
      ServicioRutasConsultorio(
        invocadorPorTransporte:
            ({
              required origenLatitud,
              required origenLongitud,
              required destinoLatitud,
              required destinoLongitud,
              required medioTransporte,
            }) async {
              solicitudes.add(medioTransporte);
              return {
                'puntosRuta': [
                  {'latitud': origenLatitud, 'longitud': origenLongitud},
                  {'latitud': -1.66, 'longitud': -78.65},
                  {'latitud': destinoLatitud, 'longitud': destinoLongitud},
                ],
                'distanciaMetros': medioTransporte == 'auto' ? 3800 : 3200,
                'duracionEstimadaSegundos': medioTransporte == 'auto'
                    ? 310
                    : 2400,
                if (confirmarTransporte) 'medioTransporte': medioTransporte,
              };
            },
      );
  setUp(solicitudes.clear);

  test('Auto y caminata obtienen metricas separadas del proveedor y limpian la ruta previa', () async {
    final controlador = ControladorRutaConsultorio(
      servicioUbicacion: _UbicacionPrueba(),
      servicioRutas: servicio(),
    );
    addTearDown(controlador.dispose);
    await controlador.calcularRutaHaciaConsultorio(
      destinoLatitud: -1.67275,
      destinoLongitud: -78.64830,
    );
    expect(controlador.ruta!.medioTransporte, MedioTransporte.auto);
    expect(controlador.ruta!.tiempoEstimadoTexto, '6 min aprox.');
    expect(
      controlador.cambiarMedioTransporte(MedioTransporte.caminando),
      isTrue,
    );
    expect(controlador.ruta, isNull);
    await controlador.calcularRutaHaciaConsultorio(
      destinoLatitud: -1.67275,
      destinoLongitud: -78.64830,
    );
    expect(solicitudes, ['auto', 'caminando']);
    expect(controlador.ruta!.medioTransporte, MedioTransporte.caminando);
    expect(controlador.ruta!.distanciaMetros, 3200);
    expect(controlador.ruta!.tiempoEstimadoTexto, '40 min aprox.');
    expect(controlador.ruta!.avisoNaturalezaTiempo, contains('ritmo'));
  });

  test(
    'No presenta una respuesta del servidor anterior como ruta caminando',
    () async {
      final resultado = await servicio(confirmarTransporte: false).calcularRuta(
        origenLatitud: -1.65,
        origenLongitud: -78.67,
        destinoLatitud: -1.67275,
        destinoLongitud: -78.64830,
        medioTransporte: MedioTransporte.caminando,
      );
      expect(resultado.fueExitoso, isFalse);
      expect(resultado.ruta, isNull);
      expect(resultado.mensaje, contains('medio de transporte'));
    },
  );

  testWidgets(
    'El selector solicita recalculo y el resumen identifica el transporte',
    (probador) async {
      final controlador = ControladorRutaConsultorio(
        servicioUbicacion: _UbicacionPrueba(),
        servicioRutas: servicio(),
      );
      await probador.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controlador,
              builder: (_, _) => PanelResultadoRutaConsultorio(
                controlador: controlador,
                alSolicitarRuta: () {
                  controlador.calcularRutaHaciaConsultorio(
                    destinoLatitud: -1.67275,
                    destinoLongitud: -78.64830,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await probador.tap(find.byKey(const Key('transporte_caminando')));
      await probador.pumpAndSettle();
      expect(solicitudes, ['caminando']);
      expect(find.text('Caminando · 40 min aprox.'), findsOneWidget);
      await probador.tap(find.byKey(const Key('transporte_auto')));
      await probador.pumpAndSettle();
      expect(solicitudes, ['caminando', 'auto']);
      expect(find.text('En auto · 6 min aprox.'), findsOneWidget);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
      controlador.dispose();
    },
  );
}
