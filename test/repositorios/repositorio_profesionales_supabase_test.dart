import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_buscar_profesionales.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_supabase.dart';

class _RepositorioConError implements RepositorioProfesionales {
  @override
  Future<List<Profesional>> obtenerProfesionales() async {
    throw Exception('Fallo de red simulado');
  }

  @override
  Future<List<Profesional>> buscarProfesionales(
    FiltroProfesional filtro,
  ) async {
    throw Exception('Fallo de red simulado');
  }

  @override
  Future<Profesional?> obtenerProfesionalPorId(String id) async {
    throw Exception('Fallo de red simulado');
  }

  @override
  Future<List<String>> obtenerEspecialidades() async => const ['Todas'];

  @override
  Future<List<String>> obtenerModalidades() async => const ['Todas'];

  @override
  Future<List<String>> obtenerDisponibilidades() async => const ['Todas'];
}

class _RepositorioEspecialidadesPrueba implements RepositorioEspecialidades {
  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async {
    return const [
      Especialidad(
        id: 'esp-1',
        nombre: 'Psicología Clínica',
        descripcion: 'Evaluación',
        activa: true,
      ),
      Especialidad(
        id: 'esp-2',
        nombre: 'Terapia Cognitiva',
        descripcion: 'TCC',
        activa: true,
      ),
    ];
  }

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {}
}

void main() {
  final filasDirectorioSimuladas = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'prof-real-1',
      'nombre': 'Valeria',
      'apellido': 'Cárdenas',
      'especialidad': 'Psicología Clínica',
      'especialidades': <String>['Psicología Clínica', 'Terapia Cognitiva'],
      'anios_experiencia': 7,
      'descripcion': 'Especialista en ansiedad y depresión en adultos.',
      'foto_url': 'https://ejemplo.com/valeria.jpg',
      'modalidad': 'Híbrida',
      'servicios': 'Evaluación clínica, Psicoterapia individual',
      'direccion_consultorio': 'Av. Daniel León Borja y Lavalle, Riobamba',
      'latitud': -1.67098,
      'longitud': -78.64712,
    },
    <String, dynamic>{
      'id': 'prof-real-2',
      'nombre': 'Mateo',
      'apellido': 'Hidalgo',
      'especialidad': 'Psicología Infantil y Adolescente',
      'especialidades': <String>['Psicología Infantil y Adolescente'],
      'anios_experiencia': 4,
      'descripcion': 'Acompañamiento emocional infantil.',
      'foto_url': null,
      'modalidad': 'Virtual',
      'servicios': 'Orientación a padres, Terapia infantil',
      'direccion_consultorio': 'Sector Parque Sucre, Riobamba',
      'latitud': null,
      'longitud': null,
    },
  ];

  group('RepositorioProfesionalesSupabase - Busqueda y filtros reales', () {
    test('Mapea filas del directorio y filtra por nombre, especialidad y modalidad sin repetir consultas de red', () async {
      var llamadasRed = 0;
      final repositorio = RepositorioProfesionalesSupabase(
        repositorioEspecialidades: _RepositorioEspecialidadesPrueba(),
        proveedorFilasDirectorio: () async {
          llamadasRed++;
          return filasDirectorioSimuladas;
        },
      );

      final todos = await repositorio.obtenerProfesionales();
      expect(llamadasRed, equals(1));
      expect(todos.length, equals(2));
      expect(todos.first.nombre, equals('Valeria Cárdenas'));
      expect(todos.first.tieneCoordenadasValidas, isTrue);
      expect(todos.last.tieneCoordenadasValidas, isFalse);

      // No inventa distancias en km ni disponibilidad de agenda inexistente
      expect(todos.first.distanciaTexto, isNot(contains('km')));
      expect(
        todos.first.disponibilidadTexto,
        equals('Consulta de perfil disponible'),
      );
      final disponibilidadesReales = await repositorio
          .obtenerDisponibilidades();
      expect(disponibilidadesReales, isNot(contains('Hoy')));

      // Busqueda por servicio ignorando tildes y mayusculas (usa cache en memoria)
      final porServicio = await repositorio.buscarProfesionales(
        FiltroProfesional.inicial().copiarCon(
          textoBusqueda: 'orientacion a padres',
        ),
      );
      expect(porServicio.length, equals(1));
      expect(porServicio.first.id, equals('prof-real-2'));

      // Filtro por especialidad asociada en el arreglo
      final porEspecialidad = await repositorio.buscarProfesionales(
        FiltroProfesional.inicial().copiarCon(
          especialidad: 'Terapia Cognitiva',
        ),
      );
      expect(porEspecialidad.length, equals(1));
      expect(porEspecialidad.first.id, equals('prof-real-1'));

      // Filtro por modalidad
      final porModalidad = await repositorio.buscarProfesionales(
        FiltroProfesional.inicial().copiarCon(modalidad: 'Virtual'),
      );
      expect(porModalidad.length, equals(1));
      expect(porModalidad.first.id, equals('prof-real-2'));

      // Busqueda sin coincidencias devuelve lista vacia honesta
      final vacio = await repositorio.buscarProfesionales(
        FiltroProfesional.inicial().copiarCon(
          textoBusqueda: 'NeuropsicologiaInexistente',
        ),
      );
      expect(vacio, isEmpty);

      // Verifica que todas las busquedas y filtros reutilizaron la cache sin disparar nuevas peticiones
      expect(llamadasRed, equals(1));
    });

    test('ControladorBuscarProfesionales informa error sin volver en silencio a datos simulados', () async {
      final controlador = ControladorBuscarProfesionales(
        repositorio: _RepositorioConError(),
      );

      await controlador.inicializar();

      expect(controlador.estaCargando, isFalse);
      expect(controlador.mensajeError, isNotNull);
      expect(controlador.profesionales, isEmpty);
    });

    test('Especialidad y Profesional mapean identificadores reales del esquema remoto', () {
      final especialidadRemota = Especialidad.desdeMapa(const {
        'id_especialidad': 'e9f0c1a2-3b4d-4e5f-8a9b-0c1d2e3f4a5b',
        'nombre': 'Psicología Clínica',
        'descripcion': 'Evaluación y psicoterapia.',
      });
      expect(
        especialidadRemota.id,
        equals('e9f0c1a2-3b4d-4e5f-8a9b-0c1d2e3f4a5b'),
      );
      expect(especialidadRemota.activa, isTrue);
      expect(
        especialidadRemota.aMapa()['id_especialidad'],
        equals('e9f0c1a2-3b4d-4e5f-8a9b-0c1d2e3f4a5b'),
      );

      final profesionalRemoto = Profesional.desdeMapa(const {
        'id_profesional': 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d',
        'nombres': 'Elena',
        'apellidos': 'Montalvo',
        'especialidad': 'Psicoterapia Cognitiva',
        'direccion_consultorio': 'Av. Unidad Nacional, Riobamba',
        'latitud': -1.6712345,
        'longitud': -78.6481234,
      });
      expect(
        profesionalRemoto.id,
        equals('a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d'),
      );
      expect(profesionalRemoto.nombre, equals('Elena Montalvo'));
      expect(profesionalRemoto.tieneCoordenadasValidas, isTrue);
    });
  });

  group(
    'PantallaPerfilPublicoProfesional - Informacion publica autorizada',
    () {
      testWidgets(
        'Muestra especialidades, modalidad, servicios y estado honesto de ubicacion',
        (WidgetTester probador) async {
          probador.view.physicalSize = const Size(1080, 2400);
          probador.view.devicePixelRatio = 2.0;
          addTearDown(probador.view.resetPhysicalSize);
          addTearDown(probador.view.resetDevicePixelRatio);

          const profesionalSinCoordenadas = Profesional(
            id: 'prof-pub-1',
            nombre: 'Lic. Mateo Hidalgo',
            especialidad: 'Psicología Infantil y Adolescente',
            especialidades: [
              'Psicología Infantil y Adolescente',
              'Orientación Vocacional',
            ],
            modalidad: 'Virtual',
            disponibilidadTexto: 'Atención virtual',
            distanciaTexto: 'Riobamba',
            direccionConsultorio: 'Sector Parque Sucre, Riobamba',
            latitud: 0.0,
            longitud: 0.0,
            tieneUbicacion: false,
            calificacion: 5.0,
            aniosExperiencia: 4,
            descripcion: 'Acompañamiento emocional infantil y juvenil.',
            servicios: 'Orientación a padres, Terapia infantil',
          );

          await probador.pumpWidget(
            MaterialApp(
              theme: TemaPsicobloom.obtenerTema(),
              home: const PantallaPerfilPublicoProfesional(
                profesional: profesionalSinCoordenadas,
              ),
            ),
          );
          await probador.pumpAndSettle();

          expect(find.text('Lic. Mateo Hidalgo'), findsOneWidget);
          expect(find.text('Orientación Vocacional'), findsOneWidget);
          expect(find.text('Orientación a padres'), findsOneWidget);
          expect(find.text('Terapia infantil'), findsOneWidget);
          expect(
            find.text(
              'El profesional aún no ha registrado coordenadas en el mapa.',
            ),
            findsOneWidget,
          );
        },
      );
    },
  );
}
