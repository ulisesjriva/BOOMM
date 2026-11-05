import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';

void main() {
  Widget crearPantallaDePrueba({String nombrePaciente = 'María'}) {
    return MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaInicioPaciente(nombrePaciente: nombrePaciente),
    );
  }

  testWidgets(
    'Verificacion de elementos visuales principales de la Pantalla de Inicio',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // 1. Cabecera e identidad
      expect(find.text('PsicoBloom'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // 2. Saludo al paciente
      expect(find.text('Hola, María 👋'), findsOneWidget);
      expect(find.text('¿En qué podemos ayudarte?'), findsOneWidget);

      // 3. Tarjetas de accion rapida
      expect(find.text('Buscar profesional'), findsOneWidget);
      expect(find.text('Orientarme'), findsOneWidget);

      // 4. Seccion de profesionales recomendados
      expect(find.text('Profesionales cerca de ti'), findsOneWidget);
      expect(find.text('Ver todos'), findsOneWidget);
      expect(
        find.text('Demostración con datos referenciales para Riobamba.'),
        findsOneWidget,
      );

      // 5. Profesionales simulados renderizados
      expect(find.text('Dra. María López'), findsOneWidget);
      expect(find.text('Psicología Clínica'), findsOneWidget);
      expect(find.text('Dr. Carlos Pérez'), findsOneWidget);

      // 6. Barra de navegacion inferior con las cinco opciones
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Mapa'), findsOneWidget);
      expect(find.text('Citas'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
    },
  );

  testWidgets(
    'Interaccion con tarjetas de accion rapida muestra mensajes y navega a buscar',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // Pulsa en Orientarme
      await probador.tap(find.text('Orientarme'));
      await probador.pump();

      expect(
        find.text(
          'El cuestionario de orientación psicológica estará disponible en próximas etapas.',
        ),
        findsOneWidget,
      );

      // Pulsa en Buscar profesional y navega a la pantalla 6
      await probador.tap(find.text('Buscar profesional'));
      await probador.pumpAndSettle();

      expect(find.text('Encuentra el apoyo que necesitas'), findsOneWidget);
      expect(find.text('Nombre, especialidad o palabra clave'), findsOneWidget);
    },
  );

  testWidgets(
    'Interaccion con favoritos y botones de la tarjeta del profesional',
    (WidgetTester probador) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pump();

      // Pulsa el primer boton de favorito
      final primerBotonFavorito = find.byTooltip('Agregar a favoritos').first;
      await probador.ensureVisible(primerBotonFavorito);
      await probador.pump();

      await probador.tap(primerBotonFavorito);
      await probador.pump();
      await probador.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Guardado en tus profesionales favoritos'),
        findsOneWidget,
      );

      // Pulsa en Ver perfil
      final primerBotonVerPerfil = find.text('Ver perfil').first;
      await probador.ensureVisible(primerBotonVerPerfil);
      await probador.pump();

      await probador.tap(primerBotonVerPerfil);
      await probador.pump();
      await probador.pump(const Duration(milliseconds: 100));

      expect(
        find.text(
          'La visualización de perfil detallado se implementará en etapas posteriores.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Interaccion con las opciones de la barra de navegacion', (
    WidgetTester probador,
  ) async {
    await probador.pumpWidget(crearPantallaDePrueba());
    await probador.pump();

    // Pulsa en la pestana Mapa
    await probador.tap(find.text('Mapa'));
    await probador.pump();

    expect(
      find.text(
        'El Mapa interactivo de profesionales se implementará en la Etapa 4.',
      ),
      findsOneWidget,
    );

    // Pulsa en la pestana Buscar y navega a la pantalla 6
    await probador.tap(find.text('Buscar'));
    await probador.pumpAndSettle();

    expect(find.text('Encuentra el apoyo que necesitas'), findsOneWidget);
  });
}
