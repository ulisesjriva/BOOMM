import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_verificar_correo.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_verificar_correo.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class ServicioConsultaCorreoPrueba extends ServicioRegistro {
  int consultas = 0;
  int reenvios = 0;
  String? correoRecibido;
  PerfilUsuario? perfil;
  Object? errorConsulta;
  Object? errorReenvio;
  Future<void>? esperaConsulta;

  @override
  Future<PerfilUsuario?> comprobarConfirmacion(String correo) async {
    consultas++;
    correoRecibido = correo;
    await esperaConsulta;
    final error = errorConsulta;
    if (error != null) {
      throw error;
    }
    return perfil;
  }

  @override
  Future<void> reenviarEnlace(String correo) async {
    reenvios++;
    correoRecibido = correo;
    final error = errorReenvio;
    if (error != null) {
      throw error;
    }
  }
}

class ServicioConfirmacionPrueba extends ServicioEnlaceAutenticacion {
  int confirmaciones = 0;
  int cierres = 0;
  Object? errorConfirmacion;
  Future<void>? espera;

  @override
  Future<String> confirmarCorreo(EnlaceAutenticacion enlace) async {
    confirmaciones++;
    await espera;
    final error = errorConfirmacion;
    if (error != null) {
      throw error;
    }
    return 'prueba@example.com';
  }

  @override
  Future<void> cerrar() async {
    cierres++;
  }
}

const perfilPrueba = PerfilUsuario(
  id: 'perfil-prueba',
  nombre: 'Sara',
  apellido: 'Prueba',
  rol: 'paciente',
  aprobacion: 'no_aplica',
  cuentaActiva: true,
);

EnlaceAutenticacion crearEnlace({
  String tipo = 'signup',
}) => EnlaceAutenticacion.desdeUri(
  Uri.parse(
    'https://psicobloom-7201a.web.app/autenticacion.html#tipo=$tipo&token_hash=token_de_prueba',
  ),
)!;

void main() {
  test('Sin sesion local devuelve null sin anunciar confirmacion', () async {
    final servicio = ServicioConsultaCorreoPrueba();
    final controlador = ControladorVerificarCorreo(
      servicio: servicio,
      iniciarEspera: false,
    );
    addTearDown(controlador.dispose);
    expect(
      await controlador.comprobarConfirmacion(' prueba@example.com '),
      isNull,
    );
    expect(servicio.correoRecibido, 'prueba@example.com');
    expect(controlador.mensajeError, isNull);
    expect(controlador.confirmadoDesdeEnlace, isFalse);
  });

  test(
    'Devuelve el perfil comprobado por el servicio sin inventar datos',
    () async {
      final servicio = ServicioConsultaCorreoPrueba()..perfil = perfilPrueba;
      final controlador = ControladorVerificarCorreo(
        servicio: servicio,
        iniciarEspera: false,
      );
      addTearDown(controlador.dispose);
      expect(
        await controlador.comprobarConfirmacion('prueba@example.com'),
        same(perfilPrueba),
      );
      expect(controlador.estaComprobando, isFalse);
      expect(controlador.mensajeError, isNull);
    },
  );

  test('Distingue un fallo de consulta de la ausencia de sesion', () async {
    final servicio = ServicioConsultaCorreoPrueba()
      ..errorConsulta = const ErrorRegistro('Consulta no disponible');
    final controlador = ControladorVerificarCorreo(
      servicio: servicio,
      iniciarEspera: false,
    );
    addTearDown(controlador.dispose);
    expect(
      await controlador.comprobarConfirmacion('prueba@example.com'),
      isNull,
    );
    expect(controlador.mensajeError, 'Consulta no disponible');
    servicio.errorConsulta = null;
    await controlador.comprobarConfirmacion('prueba@example.com');
    expect(controlador.mensajeError, isNull);
  });

  testWidgets('Espera 60 segundos y reinicia la espera al aceptar el reenvio', (
    probador,
  ) async {
    final servicio = ServicioConsultaCorreoPrueba();
    final controlador = ControladorVerificarCorreo(servicio: servicio);
    addTearDown(controlador.dispose);

    try {
      expect(controlador.segundosReenvio, 60);
      expect(await controlador.reenviarEnlace('prueba@example.com'), isFalse);
      expect(servicio.reenvios, 0);

      await probador.pump(const Duration(seconds: 60));

      expect(controlador.segundosReenvio, 0);
      expect(await controlador.reenviarEnlace(' prueba@example.com '), isTrue);
      expect(servicio.correoRecibido, 'prueba@example.com');
      expect(controlador.segundosReenvio, 60);
      expect(controlador.confirmadoDesdeEnlace, isFalse);
      expect(servicio.reenvios, 1);
    } finally {
      await controlador.cerrar();
    }
  });

  test('Un reenvio rechazado permite reintentar y comunica el error', () async {
    final servicio = ServicioConsultaCorreoPrueba()
      ..errorReenvio = const ErrorRegistro('Reenvio rechazado');
    final controlador = ControladorVerificarCorreo(
      servicio: servicio,
      iniciarEspera: false,
    );
    addTearDown(controlador.dispose);
    expect(await controlador.reenviarEnlace('prueba@example.com'), isFalse);
    expect(controlador.mensajeError, 'Reenvio rechazado');
    expect(controlador.segundosReenvio, 0);
    servicio.errorReenvio = null;
    expect(await controlador.reenviarEnlace('prueba@example.com'), isTrue);
    expect(controlador.mensajeError, isNull);
  });

  test('Un enlace rechazado no se presenta como confirmado', () async {
    final servicio = ServicioConfirmacionPrueba()
      ..errorConfirmacion = const ErrorEnlaceAutenticacion(
        'Enlace vencido de prueba',
      );
    final controlador = ControladorVerificarCorreo(
      servicioEnlace: servicio,
      iniciarEspera: false,
    );
    addTearDown(controlador.dispose);
    expect(await controlador.confirmarEnlace(crearEnlace()), isFalse);
    expect(controlador.confirmadoDesdeEnlace, isFalse);
    expect(controlador.mensajeEnlace, 'Enlace vencido de prueba');
    expect(controlador.estaComprobando, isFalse);
  });

  test(
    'Confirma solo al solicitarlo y no consume otra vez el mismo proceso',
    () async {
      final servicio = ServicioConfirmacionPrueba();
      final controlador = ControladorVerificarCorreo(
        servicioEnlace: servicio,
        iniciarEspera: false,
      );
      addTearDown(controlador.dispose);
      expect(servicio.confirmaciones, 0);
      expect(await controlador.confirmarEnlace(crearEnlace()), isTrue);
      expect(await controlador.confirmarEnlace(crearEnlace()), isTrue);
      expect(servicio.confirmaciones, 1);
      expect(controlador.confirmadoDesdeEnlace, isTrue);
      expect(controlador.mensajeEnlace, contains('prueba@example.com'));
    },
  );

  test('Rechaza un enlace ausente o de recuperacion sin confirmarlo', () async {
    final servicio = ServicioConfirmacionPrueba();
    final controlador = ControladorVerificarCorreo(
      servicioEnlace: servicio,
      iniciarEspera: false,
    );
    addTearDown(controlador.dispose);
    expect(await controlador.confirmarEnlace(null), isFalse);
    expect(
      await controlador.confirmarEnlace(crearEnlace(tipo: 'recovery')),
      isFalse,
    );
    expect(servicio.confirmaciones, 0);
    expect(controlador.confirmadoDesdeEnlace, isFalse);
  });

  test(
    'Bloquea otras operaciones durante una comprobacion pendiente',
    () async {
      final espera = Completer<void>();
      final consulta = ServicioConsultaCorreoPrueba()
        ..esperaConsulta = espera.future;
      final confirmacion = ServicioConfirmacionPrueba();
      final controlador = ControladorVerificarCorreo(
        servicio: consulta,
        servicioEnlace: confirmacion,
        iniciarEspera: false,
      );
      addTearDown(controlador.dispose);
      final pendiente = controlador.comprobarConfirmacion('prueba@example.com');
      expect(
        await controlador.comprobarConfirmacion('prueba@example.com'),
        isNull,
      );
      expect(await controlador.reenviarEnlace('prueba@example.com'), isFalse);
      expect(await controlador.confirmarEnlace(crearEnlace()), isFalse);
      expect(consulta.consultas, 1);
      expect(consulta.reenvios, 0);
      expect(confirmacion.confirmaciones, 0);
      espera.complete();
      await pendiente;
    },
  );

  testWidgets(
    'Cerrar cancela la espera y dispone del servicio temporal una vez',
    (probador) async {
      final servicio = ServicioConfirmacionPrueba();
      final controlador = ControladorVerificarCorreo(servicioEnlace: servicio);
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      await probador.pump(const Duration(seconds: 1));
      expect(controlador.segundosReenvio, 59);
      final cantidadAntesDeCerrar = notificaciones;
      await controlador.cerrar();
      controlador.dispose();
      await probador.pump(const Duration(seconds: 120));
      expect(notificaciones, cantidadAntesDeCerrar);
      expect(servicio.cierres, 1);
      expect(await controlador.reenviarEnlace('prueba@example.com'), isFalse);
    },
  );

  test(
    'Una respuesta de confirmacion posterior al cierre no cambia el estado',
    () async {
      final espera = Completer<void>();
      final servicio = ServicioConfirmacionPrueba()..espera = espera.future;
      final controlador = ControladorVerificarCorreo(
        servicioEnlace: servicio,
        iniciarEspera: false,
      );
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      final pendiente = controlador.confirmarEnlace(crearEnlace());
      await controlador.cerrar();
      espera.complete();
      expect(await pendiente, isFalse);
      expect(controlador.confirmadoDesdeEnlace, isFalse);
      expect(notificaciones, 1);
      controlador.dispose();
    },
  );

  testWidgets(
    'La vista del enlace exige el clic y luego muestra la confirmacion',
    (probador) async {
      final servicio = ServicioConfirmacionPrueba();
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaVerificarCorreo.desdeEnlace(
            enlace: crearEnlace(),
            servicioEnlace: servicio,
          ),
        ),
      );
      await probador.pumpAndSettle();
      expect(servicio.confirmaciones, 0);
      await probador.tap(find.text('Confirmar mi correo'));
      await probador.pumpAndSettle();
      expect(find.text('Tu correo está confirmado'), findsOneWidget);
      expect(find.textContaining('prueba@example.com'), findsOneWidget);
      expect(find.text('Confirmar mi correo'), findsNothing);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
      await probador.pumpAndSettle();
      expect(servicio.cierres, 1);
    },
  );

  testWidgets(
    'La vista habilita el reenvio al terminar la espera y muestra su resultado',
    (probador) async {
      probador.view.physicalSize = const Size(1000, 1800);
      probador.view.devicePixelRatio = 1;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);
      final servicio = ServicioConsultaCorreoPrueba();
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaVerificarCorreo(
            correo: 'prueba@example.com',
            servicio: servicio,
          ),
        ),
      );
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      await probador.pump(const Duration(seconds: 60));
      final reenviar = find.widgetWithText(OutlinedButton, 'Reenviar enlace');
      await probador.ensureVisible(reenviar);
      await probador.pumpAndSettle();
      await probador.tap(reenviar);
      await probador.pumpAndSettle();
      expect(servicio.reenvios, 1);
      expect(
        find.textContaining('Solicitud de reenvío aceptada.'),
        findsOneWidget,
      );
      expect(find.textContaining('Reenviar en '), findsOneWidget);
      expect(probador.takeException(), isNull);
      await probador.pumpWidget(const SizedBox.shrink());
      await probador.pumpAndSettle();
    },
  );
}
