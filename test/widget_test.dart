import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/main.dart';
import 'package:boom/pantallas/acceso/pantalla_carga.dart';

/// Espera la imagen antes de avanzar el tiempo de la pantalla de carga.
Future<void> completarCargaInicial(WidgetTester probador) async {
  final contexto = probador.element(find.byType(PantallaCarga));

  await probador.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/imagenes/icono_psicobloom.png'),
      contexto,
    );
  });

  await probador.pump(const Duration(milliseconds: 1600));
  await probador.pumpAndSettle();
}

void main() {
  testWidgets(
    'Verificacion de pantalla de carga y transicion a opciones de acceso',
    (WidgetTester probador) async {
      await probador.pumpWidget(const AplicacionPsicoBloom());

      // Comprueba la pantalla inicial.
      expect(find.text('PsicoBloom'), findsWidgets);
      expect(find.text('Cargando...'), findsOneWidget);

      await completarCargaInicial(probador);

      // Comprueba las opciones de acceso.
      expect(find.text('Bienvenido a PsicoBloom'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.text('Crear una cuenta'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);

      // Abre el formulario de inicio de sesion.
      await probador.tap(find.text('Iniciar sesión'));
      await probador.pumpAndSettle();

      expect(find.text('Qué gusto verte de nuevo'), findsOneWidget);
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    },
  );

  testWidgets(
    'Verificacion del flujo de registro desde opciones de acceso',
    (WidgetTester probador) async {
      await probador.pumpWidget(const AplicacionPsicoBloom());
      await completarCargaInicial(probador);

      // Abre el primer paso del registro.
      await probador.tap(find.text('Crear una cuenta'));
      await probador.pumpAndSettle();

      expect(find.text('Paso 1 de 2'), findsOneWidget);
      expect(
        find.text('Comencemos con tus datos personales.'),
        findsOneWidget,
      );

      // Completa el formulario con datos de prueba.
      final camposTexto = find.byType(TextFormField);
      expect(camposTexto, findsNWidgets(3));

      await probador.enterText(camposTexto.at(0), 'Psico');
      await probador.enterText(camposTexto.at(1), 'Bloom');
      await probador.enterText(
        camposTexto.at(2),
        'prueba@example.com',
      );
      await probador.pumpAndSettle();

      // Avanza al segundo paso del registro.
      await probador.tap(find.text('Continuar'));
      await probador.pumpAndSettle();

      expect(find.text('Paso 2 de 2'), findsOneWidget);
      expect(find.text('Protege tu cuenta'), findsOneWidget);
      expect(find.text('Paciente'), findsOneWidget);
      expect(find.text('Profesional'), findsOneWidget);
    },
  );
}