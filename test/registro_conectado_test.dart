import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_dos.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_verificar_correo.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';

// Dobles de prueba: verifican la interfaz, no una conexion real a Supabase.
class ServicioRegistroPrueba extends ServicioRegistro {
  int registros = 0;
  String? claveRecibida;
  bool? profesionalRecibido;
  Object? error;
  final espera = Completer<void>();
  PerfilUsuario? perfil;

  @override
  Future<void> registrar({
    required String nombre,
    required String apellido,
    required String correo,
    required String clave,
    required bool esProfesional,
  }) async {
    registros++;
    claveRecibida = clave;
    profesionalRecibido = esProfesional;
    if (error != null) throw error!;
    await espera.future;
  }

  @override
  Future<PerfilUsuario?> comprobarConfirmacion(String correo) async => perfil;
}

Future<void> abrirRegistro(
  WidgetTester probador,
  ServicioRegistroPrueba servicio,
) async {
  probador.view.physicalSize = const Size(1000, 1800);
  probador.view.devicePixelRatio = 1;
  addTearDown(probador.view.resetPhysicalSize);
  addTearDown(probador.view.resetDevicePixelRatio);
  await probador.pumpWidget(
    MaterialApp(
      home: PantallaRegistroPasoDos(
        nombre: 'Prueba',
        apellido: 'Bloom',
        correo: 'prueba@example.com',
        servicio: servicio,
      ),
    ),
  );
}

Future<void> completarFormulario(WidgetTester probador, String clave) async {
  final campos = find.byType(TextFormField);
  await probador.enterText(campos.at(0), clave);
  await probador.enterText(campos.at(1), clave);
  await probador.tap(find.byType(Checkbox));
  await probador.ensureVisible(find.text('Crear cuenta'));
  await probador.tap(find.text('Crear cuenta'));
  await probador.pump();
}

void main() {
  test('El modelo rechaza un rol desconocido recibido del servidor', () {
    expect(
      () => PerfilUsuario.desdeMapa({
        'id': 'prueba',
        'nombre': 'Prueba',
        'apellido': 'Bloom',
        'rol': 'superusuario',
        'aprobacion': 'no_aplica',
        'cuenta_activa': true,
      }),
      throwsFormatException,
    );
  });

  testWidgets('No envia contrasenas menores a 11 caracteres', (probador) async {
    final servicio = ServicioRegistroPrueba();
    await abrirRegistro(probador, servicio);
    await completarFormulario(probador, 'Corta123');
    expect(servicio.registros, 0);
    expect(
      find.text('La contraseña debe contener al menos 11 caracteres'),
      findsOneWidget,
    );
    await probador.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Un error de registro conserva el formulario y muestra el mensaje',
    (probador) async {
      final servicio = ServicioRegistroPrueba()
        ..error = const ErrorRegistro(
          'Registro rechazado por el servidor de prueba.',
        );
      await abrirRegistro(probador, servicio);
      await completarFormulario(probador, 'PruebaBloom123!');
      await probador.pumpAndSettle();
      expect(servicio.registros, 1);
      expect(find.byType(PantallaVerificarCorreo), findsNothing);
      expect(
        find.text('Registro rechazado por el servidor de prueba.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'PruebaBloom123!'),
        findsNWidgets(2),
      );
      await probador.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Espera la respuesta de registro antes de abrir verificacion', (
    probador,
  ) async {
    final servicio = ServicioRegistroPrueba();
    await abrirRegistro(probador, servicio);
    await probador.tap(find.text('Profesional'));
    await completarFormulario(probador, 'PruebaBloom123!');
    expect(servicio.registros, 1);
    expect(servicio.claveRecibida, 'PruebaBloom123!');
    expect(servicio.profesionalRecibido, isTrue);
    expect(find.byType(PantallaVerificarCorreo), findsNothing);
    servicio.espera.complete();
    await probador.pumpAndSettle();
    expect(find.byType(PantallaVerificarCorreo), findsOneWidget);
    await probador.pumpWidget(const SizedBox());
  });

  testWidgets('Sin sesion no anuncia una confirmacion exitosa', (
    probador,
  ) async {
    final servicio = ServicioRegistroPrueba();
    await probador.pumpWidget(
      MaterialApp(
        home: PantallaVerificarCorreo(
          correo: 'prueba@example.com',
          servicio: servicio,
        ),
      ),
    );
    await probador.ensureVisible(find.text('Ya verifiqué mi correo'));
    await probador.tap(find.text('Ya verifiqué mi correo'));
    await probador.pumpAndSettle();
    expect(
      find.text('Confirmación pendiente en esta aplicación'),
      findsOneWidget,
    );
    expect(find.text('Correo y perfil comprobados'), findsNothing);
    await probador.pumpWidget(const SizedBox());
  });
  testWidgets('Muestra el perfil devuelto tras comprobar el correo', (
    probador,
  ) async {
    final servicio = ServicioRegistroPrueba()
      ..perfil = const PerfilUsuario(
        id: 'perfil-de-prueba',
        nombre: 'Prueba',
        apellido: 'Bloom',
        rol: 'profesional',
        aprobacion: 'pendiente',
        cuentaActiva: true,
      );
    await probador.pumpWidget(
      MaterialApp(
        home: PantallaVerificarCorreo(
          correo: 'prueba@example.com',
          servicio: servicio,
        ),
      ),
    );
    await probador.ensureVisible(find.text('Ya verifiqué mi correo'));
    await probador.tap(find.text('Ya verifiqué mi correo'));
    await probador.pumpAndSettle();
    expect(find.text('Correo y perfil comprobados'), findsOneWidget);
    expect(find.textContaining('Rol: profesional'), findsOneWidget);
    expect(find.textContaining('Aprobación: pendiente'), findsOneWidget);
    await probador.pumpWidget(const SizedBox());
  });
}
