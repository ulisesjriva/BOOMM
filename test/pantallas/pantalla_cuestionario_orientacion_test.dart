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
      expect(find.text('Cuestionario de Orientación'), findsOneWidget);
      expect(find.text('Descargo de responsabilidad médica'), findsOneWidget);
      expect(
        find.textContaining('NO constituye un diagnóstico médico'),
        findsOneWidget,
      );
      expect(
        find.textContaining('171 (Opción 6)'),
        findsOneWidget,
      );
      expect(find.text('Comenzar cuestionario'), findsOneWidget);
    },
  );

  testWidgets(
    'Avanza al cuestionario de preguntas y valida seleccion antes de avanzar',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      // Pulsar Comenzar cuestionario
      await probador.tap(find.text('Comenzar cuestionario'));
      await probador.pumpAndSettle();

      // Debe mostrar la primera etapa de evaluacion: Estado de Animo
      expect(find.text('Estado de Ánimo (Depresión)'), findsWidgets);
      expect(find.text('Etapa 2 de 10'), findsOneWidget);
      expect(find.text('Siguiente etapa'), findsOneWidget);

      // Si se pulsa siguiente sin responder, muestra aviso informativo
      await probador.tap(find.text('Siguiente etapa'));
      await probador.pumpAndSettle();

      expect(
        find.text('Por favor responde todas las preguntas de esta sección antes de continuar.'),
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
      await probador.tap(find.text('Comenzar cuestionario'));
      await probador.pumpAndSettle();

      // Pulsar el boton de cerrar (X) en el AppBar
      await probador.tap(find.byTooltip('Salir'));
      await probador.pumpAndSettle();

      expect(find.text('¿Deseas salir del cuestionario?'), findsOneWidget);
      expect(
        find.textContaining('Tus respuestas temporales en memoria se descartarán'),
        findsOneWidget,
      );

      // Cancelar salida
      await probador.tap(find.text('Continuar respondiendo'));
      await probador.pumpAndSettle();

      // Permanece en el cuestionario
      expect(find.text('Etapa 2 de 10'), findsOneWidget);
    },
  );
}
