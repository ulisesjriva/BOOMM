import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/main.dart';

void main() {
  testWidgets('Verificacion de pantalla de bienvenida y navegacion a iniciar sesion',
      (WidgetTester probador) async {
    await probador.pumpWidget(const AplicacionPsicoBloom());
    await probador.pumpAndSettle();

    // Comprueba elementos en bienvenida
    expect(find.text('PsicoBloom'), findsWidgets);
    expect(
      find.text('Tu camino hacia el bienestar\ncomienza con una conexión'),
      findsOneWidget,
    );
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);

    // Navega a iniciar sesion
    await probador.tap(find.text('Iniciar sesión'));
    await probador.pumpAndSettle();

    expect(find.text('Qué gusto verte de nuevo'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
  });

  testWidgets('Verificacion del flujo de registro en dos pasos',
      (WidgetTester probador) async {
    await probador.pumpWidget(const AplicacionPsicoBloom());
    await probador.pumpAndSettle();

    // Pulsa Crear cuenta desde bienvenida
    await probador.tap(find.text('Crear cuenta'));
    await probador.pumpAndSettle();

    // Verifica paso 1
    expect(find.text('Paso 1 de 2'), findsOneWidget);
    expect(find.text('Comencemos con tus datos personales.'), findsOneWidget);

    // Ingresa datos en el formulario del paso 1
    final camposTexto = find.byType(TextFormField);
    expect(camposTexto, findsNWidgets(3));

    await probador.enterText(camposTexto.at(0), 'Ulises');
    await probador.enterText(camposTexto.at(1), 'Rivadeneira');
    await probador.enterText(camposTexto.at(2), 'ulises@correo.com');
    await probador.pumpAndSettle();

    // Pulsa Continuar hacia el paso 2
    await probador.tap(find.text('Continuar'));
    await probador.pumpAndSettle();

    // Verifica paso 2
    expect(find.text('Paso 2 de 2'), findsOneWidget);
    expect(find.text('Protege tu cuenta'), findsOneWidget);
    expect(find.text('Paciente'), findsOneWidget);
    expect(find.text('Profesional'), findsOneWidget);
  });
}
