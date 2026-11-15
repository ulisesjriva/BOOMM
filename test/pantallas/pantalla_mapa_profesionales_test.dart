import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_mapa_profesionales.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';

class _RepositorioConError implements RepositorioProfesionales {
  bool fallar = true;
  final List<Profesional> profesionalesRespaldo;

  _RepositorioConError({required this.profesionalesRespaldo});

  @override
  Future<List<Profesional>> obtenerProfesionales() async {
    if (fallar) {
      throw Exception('PostgrestException: internal technical detail 42P01');
    }
    return profesionalesRespaldo;
  }

  @override
  Future<List<Profesional>> buscarProfesionales(FiltroProfesional filtro) =>
      obtenerProfesionales();

  @override
  Future<Profesional?> obtenerProfesionalPorId(String id) async => null;

  @override
  Future<List<String>> obtenerDisponibilidades() async => const ['Todas'];

  @override
  Future<List<String>> obtenerEspecialidades() async => const ['Todas'];

  @override
  Future<List<String>> obtenerModalidades() async => const ['Todas'];
}

void main() {
  const profesionalesAprobadosPrueba = [
    Profesional(
      id: 'prof-1',
      nombre: 'Dra. Valeria Andrade',
      especialidad: 'Psicología Clínica',
      especialidades: ['Psicología Clínica', 'Terapia Cognitiva'],
      modalidad: 'Presencial',
      descripcion: 'Atención clínica integral en Riobamba.',
      servicios: 'Psicoterapia individual, Evaluación psicológica',
      disponibilidadTexto: 'Consulta disponible',
      distanciaTexto: '1.2 km',
      direccionConsultorio: 'Av. Daniel León Borja y Lavalle, Riobamba',
      latitud: -1.6685,
      longitud: -78.6512,
    ),
    Profesional(
      id: 'prof-2',
      nombre: 'Dr. Mateo Salazar',
      especialidad: 'Psicología Familiar',
      especialidades: ['Psicología Familiar'],
      modalidad: 'Híbrida',
      descripcion: 'Orientación familiar y de pareja.',
      servicios: 'Terapia familiar',
      disponibilidadTexto: 'Consulta disponible',
      distanciaTexto: '2.0 km',
      direccionConsultorio: 'Calle Primera Constituyente, Riobamba',
      latitud: -1.6710,
      longitud: -78.6475,
    ),
  ];

  setUp(() {
    GestorFavoritos.instancia.limpiar();
  });

  testWidgets(
    'PantallaMapaProfesionales muestra encabezado, area preliminar, profesionales aprobados y abre perfil publico',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      final repositorio = RepositorioProfesionalesSimulado(
        fuenteDatos: profesionalesAprobadosPrueba,
      );

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaMapaProfesionales(repositorio: repositorio),
        ),
      );
      await probador.pumpAndSettle();

      // A. Encabezado
      expect(find.text('Profesionales en Riobamba'), findsOneWidget);
      expect(
        find.text(
          'Consulta los profesionales disponibles y la ubicación de sus consultorios.',
        ),
        findsOneWidget,
      );

      // B. Area del mapa con marcadores de consultorios y calculo de ruta
      expect(find.byKey(const Key('areaPreliminarMapa')), findsOneWidget);
      expect(find.text('2 consultorios en el mapa'), findsOneWidget);
      expect(
        find.text('Consultorio seleccionado: Dra. Valeria Andrade'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('botonCalcularRutaMapa')), findsOneWidget);

      // C. Seccion Profesionales disponibles con datos de la consulta
      expect(find.text('Profesionales disponibles'), findsOneWidget);
      expect(find.text('Dra. Valeria Andrade'), findsOneWidget);
      expect(
        find.text('Psicología Clínica, Terapia Cognitiva'),
        findsOneWidget,
      );
      expect(find.text('Presencial'), findsOneWidget);
      expect(
        find.text('Av. Daniel León Borja y Lavalle, Riobamba'),
        findsOneWidget,
      );

      expect(find.text('Dr. Mateo Salazar'), findsOneWidget);
      expect(
        find.text('Calle Primera Constituyente, Riobamba'),
        findsOneWidget,
      );

      // D. Barra de navegacion inferior
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Mapa'), findsOneWidget);
      expect(find.text('Citas'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);

      // Boton Ver perfil abre el perfil publico del profesional
      await probador.tap(find.text('Ver perfil').first);
      await probador.pumpAndSettle();

      expect(find.text('Perfil del profesional'), findsOneWidget);
      expect(
        find.text('Atención clínica integral en Riobamba.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PantallaMapaProfesionales muestra estado vacio amigable cuando no hay profesionales aprobados',
    (WidgetTester probador) async {
      final repositorioVacio = RepositorioProfesionalesSimulado(
        fuenteDatos: const <Profesional>[],
      );

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaMapaProfesionales(repositorio: repositorioVacio),
        ),
      );
      await probador.pumpAndSettle();

      expect(
        find.text('No hay profesionales aprobados disponibles'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PantallaMapaProfesionales oculta detalles tecnicos ante un error y permite reintentar',
    (WidgetTester probador) async {
      final repositorioError = _RepositorioConError(
        profesionalesRespaldo: profesionalesAprobadosPrueba,
      );

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaMapaProfesionales(repositorio: repositorioError),
        ),
      );
      await probador.pumpAndSettle();

      expect(
        find.textContaining(
          'No pudimos cargar los profesionales disponibles en este momento.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);

      repositorioError.fallar = false;
      await probador.ensureVisible(find.text('Reintentar'));
      await probador.pumpAndSettle();
      await probador.tap(find.text('Reintentar'));
      await probador.pumpAndSettle();

      expect(find.text('Dra. Valeria Andrade'), findsWidgets);
    },
  );

  testWidgets(
    'PantallaMapaProfesionales calcula ruta vial, distancia y tiempo estimado hacia el consultorio seleccionado',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      final repositorio = RepositorioProfesionalesSimulado(
        fuenteDatos: profesionalesAprobadosPrueba,
      );
      final servicioUbicacion = _ServicioUbicacionPacientePrueba();
      final servicioRutas = ServicioRutasConsultorio(
        invocadorFuncionRuta:
            ({
              required origenLatitud,
              required origenLongitud,
              required destinoLatitud,
              required destinoLongitud,
            }) async {
              return <String, dynamic>{
                'puntosRuta': <Map<String, double>>[
                  {'latitud': origenLatitud, 'longitud': origenLongitud},
                  {'latitud': -1.6698, 'longitud': -78.6495},
                  {'latitud': destinoLatitud, 'longitud': destinoLongitud},
                ],
                'distanciaMetros': 1450.0,
                'duracionEstimadaSegundos': 310,
                'incluyeTraficoTiempoReal': false,
                'proveedor': 'openrouteservice',
              };
            },
      );

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaMapaProfesionales(
            repositorio: repositorio,
            servicioUbicacion: servicioUbicacion,
            servicioRutas: servicioRutas,
          ),
        ),
      );
      await probador.pumpAndSettle();

      final botonRuta = find.byKey(const Key('botonCalcularRutaMapa'));
      await probador.ensureVisible(botonRuta);
      await probador.pumpAndSettle();
      await probador.tap(botonRuta);
      await probador.pumpAndSettle();

      expect(
        find.byKey(const Key('tarjetaResumenRutaConsultorio')),
        findsOneWidget,
      );
      expect(find.text('Distancia vial: 1.5 km'), findsOneWidget);
      expect(find.text('Tiempo: 6 min aprox.'), findsOneWidget);
      expect(
        find.text(
          'Tiempo estimado según la vía (no incluye tráfico en tiempo real).',
        ),
        findsOneWidget,
      );
    },
  );
}

class _ServicioUbicacionPacientePrueba extends ServicioUbicacionConsultorio {
  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async {
    return const ResultadoUbicacionDispositivo.obtenida(
      latitud: -1.6725,
      longitud: -78.6460,
    );
  }
}
