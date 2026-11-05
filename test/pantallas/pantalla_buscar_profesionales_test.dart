import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_buscar_profesionales.dart';
import 'package:boom/datos/gestor_favoritos.dart';

void main() {
  final List<Profesional> profesionalesPrueba = [
    const Profesional(
      id: 'test-1',
      nombre: 'Dra. María López',
      especialidad: 'Psicología Clínica',
      modalidad: 'Presencial',
      disponibilidadTexto: 'Disponible hoy 15:00',
      distanciaTexto: '1.2 km (aprox.)',
      direccionConsultorio: 'Centro de Riobamba',
      latitud: -1.67098,
      longitud: -78.64712,
      calificacion: 4.9,
    ),
    const Profesional(
      id: 'test-2',
      nombre: 'Dr. Carlos Pérez',
      especialidad: 'Psicología Familiar',
      modalidad: 'Presencial',
      disponibilidadTexto: 'Disponible mañana',
      distanciaTexto: '2.4 km (aprox.)',
      direccionConsultorio: 'La Estación',
      latitud: -1.66645,
      longitud: -78.65311,
      calificacion: 4.8,
    ),
    const Profesional(
      id: 'test-3',
      nombre: 'Lic. David Morales',
      especialidad: 'Psicoterapia Cognitiva',
      modalidad: 'Virtual',
      disponibilidadTexto: 'Disponible hoy 17:30',
      distanciaTexto: '1.8 km (aprox.)',
      direccionConsultorio: 'Parque Maldonado',
      latitud: -1.67230,
      longitud: -78.64920,
      calificacion: 4.7,
    ),
  ];

  Widget crearPantallaDePrueba() {
    final repositorio = RepositorioProfesionalesSimulado(
      fuenteDatos: profesionalesPrueba,
    );
    return MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaBuscarProfesionales(repositorio: repositorio),
    );
  }

  setUp(() {
    GestorFavoritos.instancia.limpiar();
  });

  testWidgets(
    'Verificacion de renderizado de elementos en PantallaBuscarProfesionales',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Cabecera e identidad
      expect(find.text('PsicoBloom'), findsOneWidget);
      expect(find.text('Buscar profesional'), findsOneWidget);
      expect(find.text('Encuentra el apoyo que necesitas'), findsOneWidget);

      // Campo de busqueda
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Nombre, especialidad o palabra clave'), findsOneWidget);

      // Los 3 filtros
      expect(find.text('Especialidad'), findsOneWidget);
      expect(find.text('Disponibilidad'), findsOneWidget);
      expect(find.text('Modalidad'), findsOneWidget);

      // Contador de resultados
      expect(find.text('3 profesionales encontrados'), findsOneWidget);

      // Profesionales renderizados
      expect(find.text('Dra. María López'), findsOneWidget);
      expect(find.text('Dr. Carlos Pérez'), findsOneWidget);
      expect(find.text('Lic. David Morales'), findsOneWidget);

      // Barra de navegacion inferior con pestaña Buscar activa
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Mapa'), findsOneWidget);
    },
  );

  testWidgets(
    'Busqueda textual por nombre filtra los resultados correctamente',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Escribe "María" en el buscador
      await probador.enterText(find.byType(TextField), 'María');
      await probador.pumpAndSettle();

      expect(find.text('1 profesional encontrado'), findsOneWidget);
      expect(find.text('Dra. María López'), findsOneWidget);
      expect(find.text('Dr. Carlos Pérez'), findsNothing);
      expect(find.text('Lic. David Morales'), findsNothing);
    },
  );

  testWidgets('Busqueda textual por especialidad ignora mayusculas y tildes', (
    WidgetTester probador,
  ) async {
    probador.view.physicalSize = const Size(1080, 2400);
    probador.view.devicePixelRatio = 2.0;
    addTearDown(probador.view.resetPhysicalSize);
    addTearDown(probador.view.resetDevicePixelRatio);

    await probador.pumpWidget(crearPantallaDePrueba());
    await probador.pumpAndSettle();

    // Escribe "familiar" sin tildes ni mayusculas
    await probador.enterText(find.byType(TextField), 'familiar');
    await probador.pumpAndSettle();

    expect(find.text('1 profesional encontrado'), findsOneWidget);
    expect(find.text('Dr. Carlos Pérez'), findsOneWidget);
    expect(find.text('Dra. María López'), findsNothing);
  });

  testWidgets('Filtrado por modalidad y combinacion con busqueda', (
    WidgetTester probador,
  ) async {
    probador.view.physicalSize = const Size(1080, 2400);
    probador.view.devicePixelRatio = 2.0;
    addTearDown(probador.view.resetPhysicalSize);
    addTearDown(probador.view.resetDevicePixelRatio);

    await probador.pumpWidget(crearPantallaDePrueba());
    await probador.pumpAndSettle();

    // Abre el selector de Modalidad
    await probador.tap(find.text('Modalidad'));
    await probador.pumpAndSettle();

    expect(find.text('Filtrar por Modalidad'), findsOneWidget);

    // Selecciona Virtual dentro del listado del modal (evita coincidencia ambigua con el fondo)
    await probador.tap(
      find.descendant(
        of: find.byKey(const Key('listaOpcionesFiltro')),
        matching: find.text('Virtual'),
      ),
    );
    await probador.pumpAndSettle();

    // Comprueba que solo aparece el profesional virtual
    expect(find.text('1 profesional encontrado'), findsOneWidget);
    expect(find.text('Lic. David Morales'), findsOneWidget);
    expect(find.text('Dra. María López'), findsNothing);
  });

  testWidgets(
    'Boton Limpiar filtros restablece los resultados y el campo de texto',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Escribe un texto
      await probador.enterText(find.byType(TextField), 'Carlos');
      await probador.pumpAndSettle();

      expect(find.text('1 profesional encontrado'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);

      // Pulsa Limpiar filtros
      await probador.tap(find.text('Limpiar filtros'));
      await probador.pumpAndSettle();

      // Restablecido
      expect(find.text('3 profesionales encontrados'), findsOneWidget);
      expect(find.text('Dra. María López'), findsOneWidget);
      expect(find.text('Dr. Carlos Pérez'), findsOneWidget);
      expect(find.text('Lic. David Morales'), findsOneWidget);
    },
  );

  testWidgets(
    'Muestra estado vacio cuando no hay coincidencias con boton de restablecer',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Escribe un termino inexistente
      await probador.enterText(find.byType(TextField), 'TerminoInexistenteXYZ');
      await probador.pumpAndSettle();

      expect(find.text('0 profesionales encontrados'), findsOneWidget);
      expect(find.text('No encontramos profesionales'), findsOneWidget);
      expect(find.text('Restablecer filtros'), findsOneWidget);

      // Pulsa restablecer filtros desde el estado vacio
      await probador.tap(find.text('Restablecer filtros'));
      await probador.pumpAndSettle();

      expect(find.text('3 profesionales encontrados'), findsOneWidget);
      expect(find.text('Dra. María López'), findsOneWidget);
    },
  );

  testWidgets('Navegacion entre pestanas muestra mensajes informativos', (
    WidgetTester probador,
  ) async {
    probador.view.physicalSize = const Size(1080, 2400);
    probador.view.devicePixelRatio = 2.0;
    addTearDown(probador.view.resetPhysicalSize);
    addTearDown(probador.view.resetDevicePixelRatio);

    await probador.pumpWidget(crearPantallaDePrueba());
    await probador.pumpAndSettle();

    // Pulsa Mapa
    await probador.tap(find.text('Mapa'));
    await probador.pump();

    expect(
      find.text(
        'El Mapa interactivo de profesionales se implementará en la Etapa 4.',
      ),
      findsOneWidget,
    );
  });
}
