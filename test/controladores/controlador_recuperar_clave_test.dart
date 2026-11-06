import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_recuperar_clave.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_recuperacion_clave.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_recuperar_clave.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class ServicioRecuperacionPrueba extends ServicioRecuperacionClave {
  ServicioRecuperacionPrueba(this.solicitar);

  final Future<void> Function(String correo) solicitar;

  @override
  Future<void> solicitarEnlace(String correo) => solicitar(correo);
}

Future<void> enviarFormulario(
  WidgetTester probador,
  ServicioRecuperacionClave servicio,
) async {
  probador.view.physicalSize = const Size(1080, 2400);
  probador.view.devicePixelRatio = 2;
  addTearDown(probador.view.resetPhysicalSize);
  addTearDown(probador.view.resetDevicePixelRatio);
  await probador.pumpWidget(
    MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaRecuperarClave(servicio: servicio),
    ),
  );
  await probador.pumpAndSettle();
  await probador.enterText(find.byType(TextFormField), 'prueba@example.com');
  final boton = find.widgetWithText(ElevatedButton, 'Enviar enlace');
  await probador.ensureVisible(boton);
  await probador.pumpAndSettle();
  await probador.tap(boton);
}

void main() {
  test(
    'Recorta el correo y comunica el estado de solicitud aceptada',
    () async {
      final controlador = ControladorRecuperarClave(
        servicio: ServicioRecuperacionPrueba((correo) async {
          expect(correo, 'prueba@example.com');
        }),
      );
      addTearDown(controlador.dispose);
      final estados = <bool>[];
      controlador.addListener(() => estados.add(controlador.estaEnviando));
      expect(await controlador.solicitarEnlace(' prueba@example.com '), isTrue);
      expect(estados, [true, false]);
      expect(controlador.mensajeError, isNull);
    },
  );

  test('Comunica el error y permite reintentar sin conservarlo', () async {
    var debeFallar = true;
    final controlador = ControladorRecuperarClave(
      servicio: ServicioRecuperacionPrueba((correo) async {
        if (debeFallar)
          throw const ErrorRecuperacionClave('Solicitud no disponible');
      }),
    );
    addTearDown(controlador.dispose);
    expect(await controlador.solicitarEnlace('prueba@example.com'), isFalse);
    expect(controlador.mensajeError, 'Solicitud no disponible');
    expect(controlador.estaEnviando, isFalse);
    debeFallar = false;
    final reintento = controlador.solicitarEnlace('prueba@example.com');
    expect(controlador.mensajeError, isNull);
    expect(await reintento, isTrue);
    expect(controlador.estaEnviando, isFalse);
  });

  test('Bloquea envios simultaneos', () async {
    final espera = Completer<void>();
    var solicitudes = 0;
    final controlador = ControladorRecuperarClave(
      servicio: ServicioRecuperacionPrueba((correo) {
        solicitudes++;
        return espera.future;
      }),
    );
    addTearDown(controlador.dispose);
    final primera = controlador.solicitarEnlace('prueba@example.com');
    expect(await controlador.solicitarEnlace('prueba@example.com'), isFalse);
    expect(solicitudes, 1);
    expect(controlador.estaEnviando, isTrue);
    espera.complete();
    expect(await primera, isTrue);
  });

  test(
    'No notifica ni comunica exito si se cierra durante la solicitud',
    () async {
      final espera = Completer<void>();
      final controlador = ControladorRecuperarClave(
        servicio: ServicioRecuperacionPrueba((correo) => espera.future),
      );
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      final solicitud = controlador.solicitarEnlace('prueba@example.com');
      controlador.dispose();
      espera.complete();
      expect(await solicitud, isFalse);
      expect(notificaciones, 1);
    },
  );

  test('No inicia solicitudes despues de cerrar', () async {
    var solicitudes = 0;
    final controlador = ControladorRecuperarClave(
      servicio: ServicioRecuperacionPrueba((correo) async {
        solicitudes++;
      }),
    );
    controlador.dispose();
    expect(await controlador.solicitarEnlace('prueba@example.com'), isFalse);
    expect(solicitudes, 0);
  });

  testWidgets('La vista muestra la confirmacion generica y permite cerrarla', (
    probador,
  ) async {
    await enviarFormulario(
      probador,
      ServicioRecuperacionPrueba((correo) async {}),
    );
    // El fondo conserva un indicador animado hasta que se cierra el dialogo.
    await probador.pump();
    await probador.pump(const Duration(milliseconds: 400));
    expect(find.text('Solicitud recibida'), findsOneWidget);
    expect(
      find.textContaining('Si existe una cuenta asociada a prueba@example.com'),
      findsOneWidget,
    );
    await probador.tap(find.text('Entendido'));
    await probador.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final boton = probador.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enviar enlace'),
    );
    expect(boton.onPressed, isNotNull);
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
    await probador.pumpAndSettle();
  });

  testWidgets('La vista informa el fallo sin mostrar una solicitud aceptada', (
    probador,
  ) async {
    await enviarFormulario(
      probador,
      ServicioRecuperacionPrueba((correo) async {
        throw const ErrorRecuperacionClave('Error de recuperacion simulado');
      }),
    );
    await probador.pumpAndSettle();
    expect(find.text('Error de recuperacion simulado'), findsOneWidget);
    expect(find.text('Solicitud recibida'), findsNothing);
    final boton = probador.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Enviar enlace'),
    );
    expect(boton.onPressed, isNotNull);
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
    await probador.pumpAndSettle();
  });
}
