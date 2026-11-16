import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/paciente/controladores/gestor_resultado_orientacion.dart';
import 'package:boom/modulos/paciente/modelos/cuestionario_orientacion.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_cuestionario_completado.dart';

void main() {
  setUp(() {
    GestorResultadoOrientacion.instancia.limpiar();
    GestorResultadoOrientacion.instancia.guardarResultado(
      const ResultadoOrientacion(
        especialidadRecomendada: 'Psicología Clínica',
        descripcion: 'Orientación para manejo del estado de ánimo.',
        categoriasDetectadas: ['Estado de Ánimo y Afectividad'],
        centrosRecomendados: ['Hospital General Docente de Riobamba'],
        requiereAtencionPrioritaria: false,
        esSimulado: true,
      ),
    );
  });

  tearDown(() {
    GestorResultadoOrientacion.instancia.limpiar();
  });

  Widget crearPantallaDePrueba() {
    return MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: const PantallaCuestionarioCompletado(),
    );
  }

  testWidgets(
    'Muestra estado de cuestionario completado y resumen de orientacion',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      expect(find.text('Cuestionario completado'), findsOneWidget);
      expect(
        find.textContaining('Ya has completado tu cuestionario de orientación psicológica'),
        findsOneWidget,
      );
      expect(find.text('Psicología Clínica'), findsOneWidget);
      expect(find.text('Estado de Ánimo y Afectividad'), findsOneWidget);
      expect(find.text('Ver recomendaciones detalladas'), findsOneWidget);
      expect(find.text('Volver a realizar el cuestionario'), findsOneWidget);
    },
  );

  testWidgets(
    'Al pulsar Ver recomendaciones detalladas abre la pantalla de resultado',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      await probador.tap(find.text('Ver recomendaciones detalladas'));
      await probador.pumpAndSettle();

      expect(find.text('Resultado de orientación'), findsOneWidget);
      expect(find.text('Hospital General Docente de Riobamba'), findsOneWidget);
    },
  );

  testWidgets(
    'Al pulsar Volver a realizar el cuestionario muestra confirmacion y reinicia',
    (WidgetTester probador) async {
      await probador.pumpWidget(crearPantallaDePrueba());
      await probador.pumpAndSettle();

      await probador.tap(find.text('Volver a realizar el cuestionario'));
      await probador.pumpAndSettle();

      expect(find.text('¿Deseas repetir el cuestionario?'), findsOneWidget);

      // Confirmar
      await probador.tap(find.text('Sí, repetir'));
      await probador.pumpAndSettle();

      // Debe abrir la pantalla del cuestionario desde el inicio
      expect(find.text('Cuestionario de Orientación'), findsOneWidget);
      expect(find.text('Comenzar cuestionario'), findsOneWidget);
      // El gestor en memoria debio quedar limpio
      expect(GestorResultadoOrientacion.instancia.tieneResultado, isFalse);
    },
  );
}
