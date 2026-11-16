import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_ruta_consultorio.dart';
import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class _ServicioUbicacionConfigurable extends ServicioUbicacionConsultorio {
  ResultadoUbicacionDispositivo resultado;

  _ServicioUbicacionConfigurable(this.resultado);

  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async {
    return resultado;
  }
}

void main() {
  group('I2-05 - RutaConsultorio, ServicioRutasConsultorio y ControladorRutaConsultorio', () {
    test('Calcula ruta vial real, formatea distancia y distingue tiempo estimado de trafico en vivo', () async {
      final servicioUbicacion = _ServicioUbicacionConfigurable(
        const ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.67210,
          longitud: -78.64850,
        ),
      );
      final servicioRutas = ServicioRutasConsultorio(
        invocadorFuncionRuta:
            ({
              required origenLatitud,
              required origenLongitud,
              required destinoLatitud,
              required destinoLongitud,
            }) async {
              return <String, dynamic>{
                'puntosRuta': <List<double>>[
                  [origenLongitud, origenLatitud],
                  [-78.64780, -1.67140],
                  [destinoLongitud, destinoLatitud],
                ],
                'distanciaMetros': 1850.0,
                'duracionEstimadaSegundos': 410,
                'incluyeTraficoTiempoReal': false,
                'proveedor': 'openrouteservice',
              };
            },
      );

      final controlador = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: servicioRutas,
      );
      addTearDown(controlador.dispose);

      final exito = await controlador.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );

      expect(exito, isTrue);
      expect(controlador.estado, equals(EstadoCalculoRuta.rutaObtenida));
      expect(controlador.ruta, isNotNull);
      expect(controlador.ruta!.puntosPolilinea.length, equals(3));
      expect(controlador.ruta!.distanciaTexto, equals('1.9 km'));
      expect(controlador.ruta!.tiempoEstimadoTexto, equals('7 min aprox.'));
      expect(
        controlador.ruta!.avisoNaturalezaTiempo,
        contains('no incluye tráfico en tiempo real'),
      );
    });

    test('Maneja falta de permiso de ubicacion, GPS desactivado y coordenadas incompletas sin inventar ruta', () async {
      final servicioUbicacion = _ServicioUbicacionConfigurable(
        const ResultadoUbicacionDispositivo.fallo(
          EstadoUbicacionDispositivo.permisoRechazado,
          'Permiso de ubicación rechazado por el usuario.',
        ),
      );
      final servicioRutas = ServicioRutasConsultorio(
        invocadorFuncionRuta:
            ({
              required origenLatitud,
              required origenLongitud,
              required destinoLatitud,
              required destinoLongitud,
            }) async {
              fail(
                'No debe invocar al proveedor de rutas si falta permiso o coordenadas.',
              );
            },
      );

      final controlador = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: servicioRutas,
      );
      addTearDown(controlador.dispose);

      // 1. Coordenadas de consultorio incompletas
      final sinDestino = await controlador.calcularRutaHaciaConsultorio(
        destinoLatitud: null,
        destinoLongitud: -78.64712,
      );
      expect(sinDestino, isFalse);
      expect(
        controlador.estado,
        equals(EstadoCalculoRuta.coordenadasDestinoIncompletas),
      );
      expect(controlador.ruta, isNull);

      // 2. Permiso de ubicacion rechazado
      final sinPermiso = await controlador.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );
      expect(sinPermiso, isFalse);
      expect(controlador.estado, equals(EstadoCalculoRuta.sinUbicacionOrigen));
      expect(controlador.mensajeEstado, contains('rechazado'));
      expect(controlador.ruta, isNull);

      // 3. Servicio GPS desactivado
      servicioUbicacion.resultado = const ResultadoUbicacionDispositivo.fallo(
        EstadoUbicacionDispositivo.servicioDesactivado,
        'El servicio de ubicación (GPS) está desactivado.',
      );
      final sinGps = await controlador.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );
      expect(sinGps, isFalse);
      expect(controlador.estado, equals(EstadoCalculoRuta.sinUbicacionOrigen));
      expect(controlador.mensajeEstado, contains('GPS'));
    });

    test('Maneja ausencia de ruta vial y error del proveedor sin inventar linea recta', () async {
      final servicioUbicacion = _ServicioUbicacionConfigurable(
        const ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.67210,
          longitud: -78.64850,
        ),
      );

      // Caso 1: Proveedor indica que no hay ruta vial disponible
      final controladorSinRuta = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'codigo': 'SIN_RUTA_DISPONIBLE',
                  'mensaje': 'No se encontró una ruta vial disponible entre tu ubicación y el consultorio.',
                };
              },
        ),
      );
      addTearDown(controladorSinRuta.dispose);

      final resSinRuta = await controladorSinRuta.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );
      expect(resSinRuta, isFalse);
      expect(
        controladorSinRuta.estado,
        equals(EstadoCalculoRuta.sinRutaDisponible),
      );
      expect(controladorSinRuta.ruta, isNull);

      // Caso 2: Error de red o proveedor no configurado
      final controladorErrorProveedor = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                throw Exception('Timeout de red');
              },
        ),
      );
      addTearDown(controladorErrorProveedor.dispose);

      final resError = await controladorErrorProveedor
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resError, isFalse);
      expect(
        controladorErrorProveedor.estado,
        equals(EstadoCalculoRuta.errorProveedor),
      );
      expect(controladorErrorProveedor.ruta, isNull);
    });

    test(
      'Decodifica polilinea estandar y formatea distancias menores a 1 km',
      () {
        final puntos = RutaConsultorio.decodificarPolilinea(
          '_p~iF~ps|U_ulLnnqC',
        );
        expect(puntos.length, equals(2));
        expect(puntos.first.esValida, isTrue);

        const rutaCorta = RutaConsultorio(
          origen: CoordenadaMapa(latitud: -1.6710, longitud: -78.6480),
          destino: CoordenadaMapa(latitud: -1.6695, longitud: -78.6470),
          puntosPolilinea: [
            CoordenadaMapa(latitud: -1.6710, longitud: -78.6480),
            CoordenadaMapa(latitud: -1.6695, longitud: -78.6470),
          ],
          distanciaMetros: 640,
          duracionEstimadaSegundos: 120,
        );
        expect(rutaCorta.distanciaTexto, equals('640 m'));
        expect(rutaCorta.tiempoEstimadoTexto, equals('2 min aprox.'));
      },
    );

    test('Rechaza cuenta inactiva, controla tiempo agotado, valida geometria devuelta y oculta nombres de claves internas', () async {
      final servicioUbicacion = _ServicioUbicacionConfigurable(
        const ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.67210,
          longitud: -78.64850,
        ),
      );

      // 1. Cuenta inactiva devuelta por el contrato del servidor
      final controladorInactivo = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'codigo': 'CUENTA_INACTIVA',
                  'mensaje': 'Tu cuenta está inactiva y no puede utilizar el cálculo de rutas.',
                };
              },
        ),
      );
      addTearDown(controladorInactivo.dispose);

      final resInactivo = await controladorInactivo
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resInactivo, isFalse);
      expect(
        controladorInactivo.estado,
        equals(EstadoCalculoRuta.cuentaInactiva),
      );
      expect(controladorInactivo.ruta, isNull);
      expect(controladorInactivo.mensajeEstado, contains('inactiva'));

      // 2. Tiempo limite superado en solicitud externa
      final controladorTimeout = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          tiempoLimiteSolicitud: const Duration(milliseconds: 30),
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                await Future<void>.delayed(const Duration(milliseconds: 150));
                return <String, dynamic>{};
              },
        ),
      );
      addTearDown(controladorTimeout.dispose);

      final resTimeout = await controladorTimeout.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );
      expect(resTimeout, isFalse);
      expect(
        controladorTimeout.estado,
        equals(EstadoCalculoRuta.tiempoAgotado),
      );
      expect(controladorTimeout.ruta, isNull);
      expect(
        controladorTimeout.mensajeEstado,
        contains('tardó demasiado en responder'),
      );

      // 3. Coordenadas invalidas dentro de la geometria devuelta son rechazadas
      final controladorGeometriaInvalida = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'puntosRuta': <List<double>>[
                    [origenLongitud, origenLatitud],
                    [-78.64780, 145.0], // Latitud invalida > 90
                    [destinoLongitud, destinoLatitud],
                  ],
                  'distanciaMetros': 1200.0,
                  'duracionEstimadaSegundos': 240,
                };
              },
        ),
      );
      addTearDown(controladorGeometriaInvalida.dispose);

      final resGeometria = await controladorGeometriaInvalida
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resGeometria, isFalse);
      expect(
        controladorGeometriaInvalida.estado,
        equals(EstadoCalculoRuta.sinRutaDisponible),
      );
      expect(controladorGeometriaInvalida.ruta, isNull);

      // 4. Mensajes que mencionan ORS_API_KEY o GOOGLE_ROUTES_API_KEY se sustituyen por texto comprensible
      final controladorMensajeSaneado = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'codigo': 'PROVEEDOR_NO_CONFIGURADO',
                  'mensaje': 'Falta configurar ORS_API_KEY o GOOGLE_ROUTES_API_KEY en Edge Function.',
                };
              },
        ),
      );
      addTearDown(controladorMensajeSaneado.dispose);

      final resSaneado = await controladorMensajeSaneado
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resSaneado, isFalse);
      expect(
        controladorMensajeSaneado.mensajeEstado,
        isNot(contains('ORS_API_KEY')),
      );
      expect(
        controladorMensajeSaneado.mensajeEstado,
        isNot(contains('GOOGLE_ROUTES_API_KEY')),
      );
      expect(
        controladorMensajeSaneado.mensajeEstado,
        contains('no está disponible en este momento'),
      );
    });

    test('Rechaza cuenta inactiva, controla tiempo agotado, valida geometria devuelta y oculta nombres de claves internas', () async {
      final servicioUbicacion = _ServicioUbicacionConfigurable(
        const ResultadoUbicacionDispositivo.obtenida(
          latitud: -1.67210,
          longitud: -78.64850,
        ),
      );

      // 1. Cuenta inactiva devuelta por el contrato del servidor
      final controladorInactivo = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'codigo': 'CUENTA_INACTIVA',
                  'mensaje': 'Tu cuenta está inactiva y no puede utilizar el cálculo de rutas.',
                };
              },
        ),
      );
      addTearDown(controladorInactivo.dispose);

      final resInactivo = await controladorInactivo
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resInactivo, isFalse);
      expect(
        controladorInactivo.estado,
        equals(EstadoCalculoRuta.cuentaInactiva),
      );
      expect(controladorInactivo.ruta, isNull);
      expect(controladorInactivo.mensajeEstado, contains('inactiva'));

      // 2. Tiempo limite superado en solicitud externa
      final controladorTimeout = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          tiempoLimiteSolicitud: const Duration(milliseconds: 30),
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                await Future<void>.delayed(const Duration(milliseconds: 150));
                return <String, dynamic>{};
              },
        ),
      );
      addTearDown(controladorTimeout.dispose);

      final resTimeout = await controladorTimeout.calcularRutaHaciaConsultorio(
        destinoLatitud: -1.67098,
        destinoLongitud: -78.64712,
      );
      expect(resTimeout, isFalse);
      expect(
        controladorTimeout.estado,
        equals(EstadoCalculoRuta.tiempoAgotado),
      );
      expect(controladorTimeout.ruta, isNull);
      expect(
        controladorTimeout.mensajeEstado,
        contains('tardó demasiado en responder'),
      );

      // 3. Coordenadas invalidas dentro de la geometria devuelta son rechazadas
      final controladorGeometriaInvalida = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'puntosRuta': <List<double>>[
                    [origenLongitud, origenLatitud],
                    [-78.64780, 145.0], // Latitud invalida > 90
                    [destinoLongitud, destinoLatitud],
                  ],
                  'distanciaMetros': 1200.0,
                  'duracionEstimadaSegundos': 240,
                };
              },
        ),
      );
      addTearDown(controladorGeometriaInvalida.dispose);

      final resGeometria = await controladorGeometriaInvalida
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resGeometria, isFalse);
      expect(
        controladorGeometriaInvalida.estado,
        equals(EstadoCalculoRuta.sinRutaDisponible),
      );
      expect(controladorGeometriaInvalida.ruta, isNull);

      // 4. Mensajes que mencionan ORS_API_KEY o GOOGLE_ROUTES_API_KEY se sustituyen por texto comprensible
      final controladorMensajeSaneado = ControladorRutaConsultorio(
        servicioUbicacion: servicioUbicacion,
        servicioRutas: ServicioRutasConsultorio(
          invocadorFuncionRuta:
              ({
                required origenLatitud,
                required origenLongitud,
                required destinoLatitud,
                required destinoLongitud,
              }) async {
                return <String, dynamic>{
                  'codigo': 'PROVEEDOR_NO_CONFIGURADO',
                  'mensaje': 'Falta configurar ORS_API_KEY o GOOGLE_ROUTES_API_KEY en Edge Function.',
                };
              },
        ),
      );
      addTearDown(controladorMensajeSaneado.dispose);

      final resSaneado = await controladorMensajeSaneado
          .calcularRutaHaciaConsultorio(
            destinoLatitud: -1.67098,
            destinoLongitud: -78.64712,
          );
      expect(resSaneado, isFalse);
      expect(
        controladorMensajeSaneado.mensajeEstado,
        isNot(contains('ORS_API_KEY')),
      );
      expect(
        controladorMensajeSaneado.mensajeEstado,
        isNot(contains('GOOGLE_ROUTES_API_KEY')),
      );
      expect(
        controladorMensajeSaneado.mensajeEstado,
        contains('no está disponible en este momento'),
      );
    });

    testWidgets(
      'PantallaPerfilPublicoProfesional permite calcular ruta, distancia y tiempo estimado cuando hay coordenadas',
      (WidgetTester probador) async {
        probador.view.physicalSize = const Size(1080, 2400);
        probador.view.devicePixelRatio = 2.0;
        addTearDown(probador.view.resetPhysicalSize);
        addTearDown(probador.view.resetDevicePixelRatio);

        const profesionalConCoordenadas = Profesional(
          id: 'prof-coord-1',
          nombre: 'Dra. Valeria Cárdenas',
          especialidad: 'Psicología Clínica',
          especialidades: ['Psicología Clínica'],
          modalidad: 'Presencial',
          disponibilidadTexto: 'Consulta de perfil disponible',
          distanciaTexto: 'Av. Daniel León Borja, Riobamba',
          descripcion: 'Atención clínica en Riobamba.',
          servicios: 'Psicoterapia individual',
          direccionConsultorio: 'Av. Daniel León Borja, Riobamba',
          latitud: -1.67098,
          longitud: -78.64712,
          tieneUbicacion: true,
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPublicoProfesional(
              profesional: profesionalConCoordenadas,
              servicioUbicacion: _ServicioUbicacionConfigurable(
                const ResultadoUbicacionDispositivo.obtenida(
                  latitud: -1.67400,
                  longitud: -78.65000,
                ),
              ),
              servicioRutas: ServicioRutasConsultorio(
                invocadorFuncionRuta:
                    ({
                      required origenLatitud,
                      required origenLongitud,
                      required destinoLatitud,
                      required destinoLongitud,
                    }) async {
                      return <String, dynamic>{
                        'puntosRuta': <Map<String, double>>[
                          {
                            'latitud': origenLatitud,
                            'longitud': origenLongitud,
                          },
                          {'latitud': -1.67250, 'longitud': -78.64850},
                          {
                            'latitud': destinoLatitud,
                            'longitud': destinoLongitud,
                          },
                        ],
                        'distanciaMetros': 920.0,
                        'duracionEstimadaSegundos': 240,
                        'incluyeTraficoTiempoReal': false,
                      };
                    },
              ),
            ),
          ),
        );
        await probador.pumpAndSettle();

        final botonRuta = find.byKey(const Key('botonCalcularRutaConsultorio'));
        expect(botonRuta, findsOneWidget);

        await probador.ensureVisible(botonRuta);
        await probador.pumpAndSettle();
        await Scrollable.ensureVisible(
          probador.element(botonRuta),
          alignment: 0.5,
        );
        await probador.pumpAndSettle();
        await probador.tap(botonRuta.hitTestable());
        await probador.pumpAndSettle();

        expect(find.text('En auto · 4 min aprox.'), findsOneWidget);
        expect(find.text('Recorrido: 920 m'), findsOneWidget);
        expect(
          find.text(
            'Tiempo estimado según la vía (no incluye tráfico en tiempo real).',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
