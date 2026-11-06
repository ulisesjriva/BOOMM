import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_enlaces_autenticacion.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';

Uri crearUri({String token = 'token_uno'}) => Uri.parse(
  'https://psicobloom-7201a.web.app/autenticacion.html#tipo=recovery&token_hash=$token',
);

void main() {
  test('El enlace inicial queda pendiente hasta finalizar la carga', () {
    final controlador = ControladorEnlacesAutenticacion();
    addTearDown(controlador.dispose);
    controlador.recibirEnlace(crearUri());
    expect(controlador.tomarEnlacePendiente(), isNull);
    expect(controlador.finalizarArranque(), isTrue);
    expect(
      controlador.tomarEnlacePendiente()?.tipo,
      TipoEnlaceAutenticacion.recuperacion,
    );
    expect(controlador.tomarEnlacePendiente(), isNull);
  });

  test(
    'No duplica el proceso activo y conserva el ultimo enlace pendiente',
    () {
      final controlador = ControladorEnlacesAutenticacion();
      addTearDown(controlador.dispose);
      controlador.finalizarArranque();
      controlador.recibirEnlace(crearUri());
      controlador.tomarEnlacePendiente();
      controlador.recibirEnlace(crearUri());
      expect(controlador.tomarAviso(), isNull);
      controlador.recibirEnlace(crearUri(token: 'token_dos'));
      expect(controlador.tomarAviso(), contains('Termina o cierra'));
      expect(controlador.tomarAviso(), isNull);
      controlador.recibirEnlace(crearUri(token: 'token_tres'));
      expect(controlador.tomarEnlacePendiente(), isNull);
      controlador.finalizarProcesoActual();
      expect(controlador.tomarEnlacePendiente()?.tokenHash, 'token_tres');
    },
  );

  test(
    'Ignora duplicados recientes y permite recibirlos fuera de la ventana',
    () {
      var ahora = DateTime.utc(2026, 11, 5);
      final controlador = ControladorEnlacesAutenticacion(
        obtenerHora: () => ahora,
      );
      addTearDown(controlador.dispose);
      controlador.finalizarArranque();
      controlador.recibirEnlace(crearUri());
      controlador.tomarEnlacePendiente();
      controlador.finalizarProcesoActual();
      ahora = ahora.add(const Duration(seconds: 1));
      controlador.recibirEnlace(crearUri());
      expect(controlador.tomarEnlacePendiente(), isNull);
      ahora = ahora.add(const Duration(seconds: 2));
      controlador.recibirEnlace(crearUri());
      expect(controlador.tomarEnlacePendiente(), isNotNull);
    },
  );

  test(
    'Ignora dominios ajenos y conserva el estado invalido de un enlace propio',
    () {
      final controlador = ControladorEnlacesAutenticacion();
      addTearDown(controlador.dispose);
      controlador.recibirEnlace(
        Uri.parse('https://example.com/autenticacion.html'),
      );
      expect(controlador.finalizarArranque(), isFalse);
      expect(controlador.tomarEnlacePendiente(), isNull);
      controlador.recibirEnlace(
        Uri.parse('https://psicobloom-7201a.web.app/autenticacion.html'),
      );
      expect(
        controlador.tomarEnlacePendiente()?.tipo,
        TipoEnlaceAutenticacion.invalido,
      );
    },
  );

  test(
    'Recibe el enlace inicial y los eventos posteriores sin un plugin nativo',
    () async {
      final flujo = StreamController<Uri>();
      final controlador = ControladorEnlacesAutenticacion();
      addTearDown(() async {
        await controlador.cerrar();
        controlador.dispose();
        await flujo.close();
      });
      await controlador.escuchar(
        flujo: flujo.stream,
        obtenerInicial: () async => crearUri(),
      );
      expect(controlador.finalizarArranque(), isTrue);
      expect(controlador.tomarEnlacePendiente()?.tokenHash, 'token_uno');
      controlador.finalizarProcesoActual();
      flujo.add(crearUri(token: 'token_dos'));
      await Future<void>.delayed(Duration.zero);
      expect(controlador.tomarEnlacePendiente()?.tokenHash, 'token_dos');
    },
  );

  test('Comunica errores de las fuentes sin exponer sus detalles', () async {
    final flujo = StreamController<Uri>();
    final controlador = ControladorEnlacesAutenticacion();
    addTearDown(() async {
      await controlador.cerrar();
      controlador.dispose();
      await flujo.close();
    });
    await controlador.escuchar(
      flujo: flujo.stream,
      obtenerInicial: () async {
        throw StateError('detalle_interno');
      },
    );
    const aviso =
        'No se pudo abrir el enlace. Intentalo de nuevo desde tu correo.';
    expect(controlador.tomarAviso(), aviso);
    flujo.addError(StateError('otro_detalle_interno'));
    await Future<void>.delayed(Duration.zero);
    expect(controlador.tomarAviso(), aviso);
    expect(controlador.tomarAviso(), isNull);
  });

  test(
    'Cerrar cancela la escucha e ignora un enlace inicial que llega tarde',
    () async {
      final flujo = StreamController<Uri>();
      final inicial = Completer<Uri?>();
      final controlador = ControladorEnlacesAutenticacion();
      addTearDown(() async {
        await controlador.cerrar();
        controlador.dispose();
        await flujo.close();
      });
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      final escucha = controlador.escuchar(
        flujo: flujo.stream,
        obtenerInicial: () => inicial.future,
      );
      expect(flujo.hasListener, isTrue);
      await controlador.cerrar();
      expect(flujo.hasListener, isFalse);
      inicial.complete(crearUri());
      await escucha;
      controlador.recibirEnlace(crearUri());
      expect(notificaciones, 0);
      expect(controlador.finalizarArranque(), isFalse);
      expect(controlador.tomarEnlacePendiente(), isNull);
    },
  );

  test('Una segunda inicializacion no crea otra suscripcion ni lee otro enlace inicial', () async {
    final flujo = StreamController<Uri>.broadcast();
    final controlador = ControladorEnlacesAutenticacion();
    addTearDown(() async {
      await controlador.cerrar();
      controlador.dispose();
      await flujo.close();
    });
    var lecturasIniciales = 0;
    Future<Uri?> obtenerInicial() async {
      lecturasIniciales++;
      return null;
    }

    await controlador.escuchar(
      flujo: flujo.stream,
      obtenerInicial: obtenerInicial,
    );
    await controlador.escuchar(
      flujo: flujo.stream,
      obtenerInicial: obtenerInicial,
    );
    expect(lecturasIniciales, 1);
    expect(controlador.finalizarArranque(), isFalse);
    await controlador.cerrar();
    expect(flujo.hasListener, isFalse);
  });
}
