import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_nueva_clave.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_nueva_clave.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class ServicioEnlacePrueba extends ServicioEnlaceAutenticacion {
  int validaciones = 0;
  int guardados = 0;
  int cierres = 0;
  Object? errorValidacion;
  Object? errorGuardado;
  Future<void>? esperaValidacion;
  Future<void>? esperaGuardado;
  String? claveRecibida;

  @override
  Future<void> validarRecuperacion(EnlaceAutenticacion enlace) async {
    validaciones++;
    await esperaValidacion;
    final error = errorValidacion;
    if (error != null) throw error;
  }

  @override
  Future<void> guardarClave(String clave) async {
    guardados++;
    claveRecibida = clave;
    await esperaGuardado;
    final error = errorGuardado;
    if (error != null) throw error;
  }

  @override
  Future<void> cerrar() async {
    cierres++;
  }
}

EnlaceAutenticacion crearEnlace({
  String tipo = 'recovery',
}) => EnlaceAutenticacion.desdeUri(
  Uri.parse(
    'https://psicobloom-7201a.web.app/autenticacion.html#tipo=$tipo&token_hash=token_de_prueba',
  ),
)!;

const clavePrueba = 'ClavePrueba123!';

Future<void> abrirPantalla(
  WidgetTester probador,
  ServicioEnlacePrueba servicio, {
  EnlaceAutenticacion? enlace,
}) async {
  probador.view.physicalSize = const Size(1080, 2400);
  probador.view.devicePixelRatio = 2;
  addTearDown(probador.view.resetPhysicalSize);
  addTearDown(probador.view.resetDevicePixelRatio);
  await probador.pumpWidget(
    MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaNuevaClave(enlace: enlace, servicio: servicio),
    ),
  );
  await probador.pumpAndSettle();
}

void main() {
  test(
    'Rechaza enlaces ausentes o de confirmacion sin usar el servicio',
    () async {
      final servicio = ServicioEnlacePrueba();
      final controlador = ControladorNuevaClave(servicio: servicio);
      addTearDown(controlador.dispose);
      expect(await controlador.validarEnlace(null), isFalse);
      expect(
        await controlador.validarEnlace(crearEnlace(tipo: 'signup')),
        isFalse,
      );
      expect(servicio.validaciones, 0);
      expect(controlador.enlaceValidado, isFalse);
      expect(controlador.mensajeEnlace, isNotNull);
    },
  );

  test('Un enlace validado no se consume una segunda vez', () async {
    final servicio = ServicioEnlacePrueba();
    final controlador = ControladorNuevaClave(servicio: servicio);
    addTearDown(controlador.dispose);
    expect(await controlador.validarEnlace(crearEnlace()), isTrue);
    expect(await controlador.validarEnlace(crearEnlace()), isTrue);
    expect(servicio.validaciones, 1);
    expect(controlador.enlaceValidado, isTrue);
    expect(controlador.ocupado, isFalse);
  });

  test('Bloquea el guardado sin validacion y rechaza claves debiles', () async {
    final servicio = ServicioEnlacePrueba();
    final controlador = ControladorNuevaClave(servicio: servicio);
    addTearDown(controlador.dispose);
    expect(await controlador.guardarClave(clavePrueba), isFalse);
    await controlador.validarEnlace(crearEnlace());
    expect(await controlador.guardarClave('corta'), isFalse);
    expect(servicio.guardados, 0);
    expect(controlador.enlaceValidado, isTrue);
    expect(controlador.mensajeEnlace, 'Usa al menos 11 caracteres.');
  });

  test('Un enlace rechazado no habilita el cambio de clave', () async {
    final servicio = ServicioEnlacePrueba()
      ..errorValidacion = const ErrorEnlaceAutenticacion(
        'Enlace vencido de prueba',
      );
    final controlador = ControladorNuevaClave(servicio: servicio);
    addTearDown(controlador.dispose);
    expect(await controlador.validarEnlace(crearEnlace()), isFalse);
    expect(controlador.enlaceValidado, isFalse);
    expect(controlador.mensajeEnlace, 'Enlace vencido de prueba');
    expect(controlador.ocupado, isFalse);
  });

  test(
    'Permite reintentar el guardado cuando el servicio informa un fallo',
    () async {
      final servicio = ServicioEnlacePrueba()
        ..errorGuardado = const ErrorEnlaceAutenticacion(
          'Guardado no disponible',
        );
      final controlador = ControladorNuevaClave(servicio: servicio);
      addTearDown(controlador.dispose);
      await controlador.validarEnlace(crearEnlace());
      expect(await controlador.guardarClave(clavePrueba), isFalse);
      expect(controlador.enlaceValidado, isTrue);
      expect(controlador.mensajeEnlace, 'Guardado no disponible');
      servicio.errorGuardado = null;
      expect(await controlador.guardarClave(clavePrueba), isTrue);
      expect(servicio.claveRecibida, clavePrueba);
      expect(controlador.enlaceValidado, isFalse);
      expect(controlador.claveActualizada, isTrue);
      expect(controlador.mensajeEnlace, isNull);
    },
  );

  test(
    'Bloquea solicitudes simultaneas durante validacion y guardado',
    () async {
      final validacionPendiente = Completer<void>();
      final guardadoPendiente = Completer<void>();
      final servicio = ServicioEnlacePrueba()
        ..esperaValidacion = validacionPendiente.future
        ..esperaGuardado = guardadoPendiente.future;
      final controlador = ControladorNuevaClave(servicio: servicio);
      addTearDown(controlador.dispose);
      final validacion = controlador.validarEnlace(crearEnlace());
      expect(await controlador.validarEnlace(crearEnlace()), isFalse);
      expect(await controlador.guardarClave(clavePrueba), isFalse);
      expect(servicio.validaciones, 1);
      validacionPendiente.complete();
      expect(await validacion, isTrue);
      final guardado = controlador.guardarClave(clavePrueba);
      expect(await controlador.guardarClave(clavePrueba), isFalse);
      expect(servicio.guardados, 1);
      guardadoPendiente.complete();
      expect(await guardado, isTrue);
    },
  );

  test(
    'Cerrar impide notificaciones tardias y cierra el servicio una sola vez',
    () async {
      final espera = Completer<void>();
      final servicio = ServicioEnlacePrueba()..esperaValidacion = espera.future;
      final controlador = ControladorNuevaClave(servicio: servicio);
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      final validacion = controlador.validarEnlace(crearEnlace());
      await controlador.cerrar();
      espera.complete();
      expect(await validacion, isFalse);
      expect(controlador.enlaceValidado, isFalse);
      expect(notificaciones, 1);
      expect(await controlador.guardarClave(clavePrueba), isFalse);
      controlador.dispose();
      expect(servicio.cierres, 1);
    },
  );

  test(
    'Tras guardar no admite validar ni guardar de nuevo en el mismo proceso',
    () async {
      final servicio = ServicioEnlacePrueba();
      final controlador = ControladorNuevaClave(servicio: servicio);
      addTearDown(controlador.dispose);
      await controlador.validarEnlace(crearEnlace());
      await controlador.guardarClave(clavePrueba);
      expect(await controlador.validarEnlace(crearEnlace()), isFalse);
      expect(await controlador.guardarClave(clavePrueba), isFalse);
      expect(servicio.validaciones, 1);
      expect(servicio.guardados, 1);
    },
  );

  testWidgets(
    'La vista habilita campos tras validar y vuelve al acceso tras guardar',
    (probador) async {
      final servicio = ServicioEnlacePrueba();
      await abrirPantalla(probador, servicio, enlace: crearEnlace());
      expect(
        probador
            .widget<TextFormField>(find.byType(TextFormField).first)
            .enabled,
        isFalse,
      );
      await probador.tap(find.text('Validar enlace de recuperación'));
      await probador.pumpAndSettle();
      expect(
        probador
            .widget<TextFormField>(find.byType(TextFormField).first)
            .enabled,
        isTrue,
      );
      await probador.enterText(find.byType(TextFormField).at(0), clavePrueba);
      await probador.enterText(find.byType(TextFormField).at(1), clavePrueba);
      final guardar = find.widgetWithText(ElevatedButton, 'Guardar contraseña');
      await probador.ensureVisible(guardar);
      await probador.pumpAndSettle();
      await probador.tap(guardar);
      // El indicador del fondo se mantiene mientras se muestra la confirmacion.
      await probador.pump();
      await probador.pump(const Duration(milliseconds: 400));
      expect(find.text('Contraseña actualizada'), findsOneWidget);
      expect(servicio.guardados, 1);
      await probador.tap(find.text('Iniciar sesión'));
      await probador.pumpAndSettle();
      expect(find.byType(PantallaIniciarSesion), findsOneWidget);
      expect(servicio.cierres, 1);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
      await probador.pumpAndSettle();
    },
  );

  testWidgets('Sin enlace valido la vista conserva los campos deshabilitados', (
    probador,
  ) async {
    final servicio = ServicioEnlacePrueba();
    await abrirPantalla(probador, servicio);
    await probador.tap(find.text('Validar enlace de recuperación'));
    await probador.pumpAndSettle();
    expect(
      find.text('Abre un enlace de recuperación válido desde tu correo.'),
      findsOneWidget,
    );
    expect(
      probador.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    expect(servicio.validaciones, 0);
    await probador.pumpWidget(const SizedBox.shrink());
    await probador.pumpAndSettle();
    expect(servicio.cierres, 1);
  });
}
