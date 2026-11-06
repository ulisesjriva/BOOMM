import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_registro.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_registro_paso_dos.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_verificar_correo.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class ServicioRegistroSimulado extends ServicioRegistro {
  int solicitudes = 0;
  String? nombreRecibido;
  String? apellidoRecibido;
  String? correoRecibido;
  String? claveRecibida;
  bool? profesionalRecibido;
  Object? errorRegistro;
  Future<void>? espera;

  @override
  Future<void> registrar({
    required String nombre,
    required String apellido,
    required String correo,
    required String clave,
    required bool esProfesional,
  }) async {
    solicitudes++;
    nombreRecibido = nombre;
    apellidoRecibido = apellido;
    correoRecibido = correo;
    claveRecibida = clave;
    profesionalRecibido = esProfesional;
    await espera;
    final error = errorRegistro;
    if (error != null) {
      throw error;
    }
  }
}

Future<bool> registrarPrueba(
  ControladorRegistro controlador, {
  bool aceptaTerminos = true,
  bool esProfesional = false,
}) => controlador.registrar(
  nombre: ' Sara ',
  apellido: ' Prueba ',
  correo: ' prueba@example.com ',
  clave: ' ClavePrueba123! ',
  esProfesional: esProfesional,
  aceptaTerminos: aceptaTerminos,
);

void main() {
  test(
    'Transmite los datos normalizados y ambas opciones del registro publico',
    () async {
      for (final esProfesional in [false, true]) {
        final servicio = ServicioRegistroSimulado();
        final controlador = ControladorRegistro(servicio: servicio);
        final estados = <bool>[];
        controlador.addListener(() => estados.add(controlador.estaRegistrando));
        expect(
          await registrarPrueba(controlador, esProfesional: esProfesional),
          isTrue,
        );
        expect(servicio.nombreRecibido, 'Sara');
        expect(servicio.apellidoRecibido, 'Prueba');
        expect(servicio.correoRecibido, 'prueba@example.com');
        expect(servicio.claveRecibida, ' ClavePrueba123! ');
        expect(servicio.profesionalRecibido, esProfesional);
        expect(controlador.registroAceptado, isTrue);
        expect(controlador.mensajeError, isNull);
        expect(estados, [true, false]);
        controlador.dispose();
      }
    },
  );

  test('Sin aceptar terminos no llama al servicio', () async {
    final servicio = ServicioRegistroSimulado();
    final controlador = ControladorRegistro(servicio: servicio);
    addTearDown(controlador.dispose);
    expect(await registrarPrueba(controlador, aceptaTerminos: false), isFalse);
    expect(servicio.solicitudes, 0);
    expect(controlador.registroAceptado, isFalse);
    expect(controlador.estaRegistrando, isFalse);
    expect(
      controlador.mensajeError,
      'Debes aceptar los términos y condiciones para continuar.',
    );
  });

  test(
    'Comunica errores y permite reintentar sin conservar el mensaje anterior',
    () async {
      final servicio = ServicioRegistroSimulado()
        ..errorRegistro = const ErrorRegistro('Registro rechazado de prueba');
      final controlador = ControladorRegistro(servicio: servicio);
      addTearDown(controlador.dispose);
      expect(await registrarPrueba(controlador), isFalse);
      expect(controlador.registroAceptado, isFalse);
      expect(controlador.estaRegistrando, isFalse);
      expect(controlador.mensajeError, 'Registro rechazado de prueba');
      servicio.errorRegistro = null;
      final reintento = registrarPrueba(controlador);
      expect(controlador.mensajeError, isNull);
      expect(await reintento, isTrue);
      expect(servicio.solicitudes, 2);
    },
  );

  test('Espera el registro y bloquea solicitudes simultaneas', () async {
    final espera = Completer<void>();
    final servicio = ServicioRegistroSimulado()..espera = espera.future;
    final controlador = ControladorRegistro(servicio: servicio);
    addTearDown(controlador.dispose);
    final primera = registrarPrueba(controlador);
    expect(controlador.estaRegistrando, isTrue);
    expect(controlador.registroAceptado, isFalse);
    expect(await registrarPrueba(controlador), isFalse);
    expect(servicio.solicitudes, 1);
    espera.complete();
    expect(await primera, isTrue);
  });

  test('Cerrar evita notificaciones y nuevos registros con una solicitud pendiente', () async {
    final espera = Completer<void>();
    final servicio = ServicioRegistroSimulado()..espera = espera.future;
    final controlador = ControladorRegistro(servicio: servicio);
    var notificaciones = 0;
    controlador.addListener(() => notificaciones++);
    final registro = registrarPrueba(controlador);
    controlador.dispose();
    espera.complete();
    expect(await registro, isFalse);
    expect(await registrarPrueba(controlador), isFalse);
    expect(notificaciones, 1);
    expect(servicio.solicitudes, 1);
  });

  test(
    'Un registro ya aceptado no vuelve a enviarse desde el mismo proceso',
    () async {
      final servicio = ServicioRegistroSimulado();
      final controlador = ControladorRegistro(servicio: servicio);
      addTearDown(controlador.dispose);
      expect(await registrarPrueba(controlador), isTrue);
      expect(await registrarPrueba(controlador), isFalse);
      expect(servicio.solicitudes, 1);
    },
  );

  testWidgets(
    'La vista muestra el aviso de terminos y conserva el formulario',
    (probador) async {
      probador.view.physicalSize = const Size(1000, 1800);
      probador.view.devicePixelRatio = 1;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);
      final servicio = ServicioRegistroSimulado();
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaRegistroPasoDos(
            nombre: 'Sara',
            apellido: 'Prueba',
            correo: 'prueba@example.com',
            servicio: servicio,
          ),
        ),
      );
      final campos = find.byType(TextFormField);
      await probador.enterText(campos.at(0), 'ClavePrueba123!');
      await probador.enterText(campos.at(1), 'ClavePrueba123!');
      final boton = find.widgetWithText(ElevatedButton, 'Crear cuenta');
      await probador.ensureVisible(boton);
      await probador.pumpAndSettle();
      await probador.tap(boton);
      await probador.pumpAndSettle();
      expect(
        find.text('Debes aceptar los términos y condiciones para continuar.'),
        findsOneWidget,
      );
      expect(servicio.solicitudes, 0);
      expect(find.byType(PantallaVerificarCorreo), findsNothing);
      expect(find.byType(PantallaRegistroPasoDos), findsOneWidget);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
      await probador.pumpAndSettle();
    },
  );
}
