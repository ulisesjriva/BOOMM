import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/paciente/controladores/gestor_resultado_orientacion.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_cuestionario_orientacion.dart';

void main() {
  setUp(() {
    GestorResultadoOrientacion.instancia.limpiar();
  });

  tearDown(() {
    GestorResultadoOrientacion.instancia.limpiar();
  });

  Widget crearPantallaDePrueba() {
    return MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: const PantallaCuestionarioOrientacion(),
    );
  }

  testWidgets(
    'Muestra la etapa de introduccion con el descargo medico obligatorio',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Titulo y descargo de responsabilidad
      expect(find.text('Introducción y Consentimiento'), findsOneWidget);
      expect(find.text('Aviso importante y descargo ético'), findsOneWidget);
      expect(
        find.textContaining(
          'NO constituye una respuesta médica ni un diagnóstico psicológico verídico',
        ),
        findsOneWidget,
      );
      expect(find.text('Privacidad garantizada'), findsOneWidget);
      expect(find.text('Entendido y comenzar'), findsOneWidget);
    },
  );

  testWidgets(
    'Avanza al cuestionario de preguntas y valida seleccion antes de avanzar',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Pulsar Entendido y comenzar
      await probador.ensureVisible(find.text('Entendido y comenzar'));
      await probador.pumpAndSettle();
      await probador.tap(find.text('Entendido y comenzar'));
      await probador.pumpAndSettle();

      // Debe mostrar la primera etapa de evaluacion: Estado de animo
      expect(find.text('Estado de ánimo'), findsWidgets);
      expect(find.text('Etapa 2 de 10'), findsOneWidget);
      expect(find.text('Siguiente'), findsOneWidget);

      // Si se pulsa siguiente sin responder, muestra aviso informativo
      await probador.tap(find.text('Siguiente'));
      await probador.pumpAndSettle();

      expect(
        find.text(
          'Por favor responde las preguntas visibles antes de continuar.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Muestra dialogo de confirmacion al intentar salir en medio del cuestionario',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Entrar al cuestionario
      await probador.ensureVisible(find.text('Entendido y comenzar'));
      await probador.pumpAndSettle();
      await probador.tap(find.text('Entendido y comenzar'));
      await probador.pumpAndSettle();

      // Pulsar el boton de cerrar (X) en el AppBar
      await probador.tap(find.byTooltip('Salir'));
      await probador.pumpAndSettle();

      expect(find.text('¿Deseas salir del cuestionario?'), findsOneWidget);
      expect(
        find.textContaining(
          'Tus respuestas temporales en memoria se descartarán',
        ),
        findsOneWidget,
      );

      // Cancelar salida
      await probador.tap(find.text('Continuar cuestionario'));
      await probador.pumpAndSettle();

      // Permanece en el cuestionario
      expect(find.text('Etapa 2 de 10'), findsOneWidget);
    },
  );
}
