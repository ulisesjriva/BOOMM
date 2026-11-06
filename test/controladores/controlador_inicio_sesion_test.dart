import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_inicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/pantalla_iniciar_sesion.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_inicio_paciente.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class ServicioInicioSesionPrueba extends ServicioInicioSesion {
  ServicioInicioSesionPrueba(this.autenticar);

  final Future<PerfilUsuario> Function(String correo, String clave) autenticar;

  @override
  Future<PerfilUsuario> iniciarSesionPaciente({
    required String correo,
    required String clave,
  }) => autenticar(correo, clave);
}

const perfilPrueba = PerfilUsuario(
  id: 'paciente-prueba',
  nombre: 'Sara',
  apellido: 'Prueba',
  rol: 'paciente',
  aprobacion: 'no_aplica',
  cuentaActiva: true,
);

Future<void> abrirFormulario(
  WidgetTester probador,
  ServicioInicioSesion servicio,
) async {
  probador.view.physicalSize = const Size(1080, 2400);
  probador.view.devicePixelRatio = 2;
  addTearDown(probador.view.resetPhysicalSize);
  addTearDown(probador.view.resetDevicePixelRatio);
  await probador.pumpWidget(
    MaterialApp(
      theme: TemaPsicobloom.obtenerTema(),
      home: PantallaIniciarSesion(servicio: servicio),
    ),
  );
  await probador.pumpAndSettle();
  final campos = find.byType(TextFormField);
  await probador.enterText(campos.at(0), 'prueba@example.com');
  await probador.enterText(campos.at(1), 'ClavePrueba123!');
  final boton = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
  await probador.ensureVisible(boton);
  await probador.pumpAndSettle();
  await probador.tap(boton);
}

void main() {
  test(
    'Devuelve el perfil, recorta el correo y conserva la clave exacta',
    () async {
      final servicio = ServicioInicioSesionPrueba((correo, clave) async {
        expect(correo, 'prueba@example.com');
        expect(clave, ' ClavePrueba123! ');
        return perfilPrueba;
      });
      final controlador = ControladorInicioSesion(servicio: servicio);
      addTearDown(controlador.dispose);
      final estados = <bool>[];
      controlador.addListener(() => estados.add(controlador.estaCargando));
      final perfil = await controlador.iniciarSesion(
        correo: ' prueba@example.com ',
        clave: ' ClavePrueba123! ',
      );
      expect(perfil, same(perfilPrueba));
      expect(estados, [true, false]);
      expect(controlador.mensajeError, isNull);
    },
  );

  test(
    'Comunica el fallo del servicio y limpia el error al reintentar',
    () async {
      var debeFallar = true;
      final controlador = ControladorInicioSesion(
        servicio: ServicioInicioSesionPrueba((correo, clave) async {
          if (debeFallar) throw const ErrorInicioSesion('Cuenta no disponible');
          return perfilPrueba;
        }),
      );
      addTearDown(controlador.dispose);
      final perfilFallido = await controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'ClavePrueba123!',
      );
      expect(perfilFallido, isNull);
      expect(controlador.mensajeError, 'Cuenta no disponible');
      expect(controlador.estaCargando, isFalse);
      debeFallar = false;
      final reintento = controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'ClavePrueba123!',
      );
      expect(controlador.mensajeError, isNull);
      expect(await reintento, same(perfilPrueba));
      expect(controlador.estaCargando, isFalse);
    },
  );

  test(
    'Ignora un segundo envio mientras la primera solicitud esta pendiente',
    () async {
      final espera = Completer<PerfilUsuario>();
      var solicitudes = 0;
      final controlador = ControladorInicioSesion(
        servicio: ServicioInicioSesionPrueba((correo, clave) {
          solicitudes++;
          return espera.future;
        }),
      );
      addTearDown(controlador.dispose);
      final primera = controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'clave',
      );
      final segunda = await controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'clave',
      );
      expect(segunda, isNull);
      expect(solicitudes, 1);
      expect(controlador.estaCargando, isTrue);
      espera.complete(perfilPrueba);
      expect(await primera, same(perfilPrueba));
    },
  );

  test(
    'Una respuesta posterior al cierre no devuelve un perfil ni notifica',
    () async {
      final espera = Completer<PerfilUsuario>();
      final controlador = ControladorInicioSesion(
        servicio: ServicioInicioSesionPrueba((correo, clave) => espera.future),
      );
      var notificaciones = 0;
      controlador.addListener(() => notificaciones++);
      final solicitud = controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'clave',
      );
      controlador.dispose();
      espera.complete(perfilPrueba);
      expect(await solicitud, isNull);
      expect(notificaciones, 1);
    },
  );

  test('Despues de cerrar no inicia nuevas solicitudes', () async {
    var solicitudes = 0;
    final controlador = ControladorInicioSesion(
      servicio: ServicioInicioSesionPrueba((correo, clave) async {
        solicitudes++;
        return perfilPrueba;
      }),
    );
    controlador.dispose();
    expect(
      await controlador.iniciarSesion(
        correo: 'prueba@example.com',
        clave: 'clave',
      ),
      isNull,
    );
    expect(solicitudes, 0);
  });

  testWidgets('La vista abre el inicio del paciente con el perfil devuelto', (
    probador,
  ) async {
    await abrirFormulario(
      probador,
      ServicioInicioSesionPrueba((correo, clave) async => perfilPrueba),
    );
    await probador.pumpAndSettle();
    expect(find.byType(PantallaInicioPaciente), findsOneWidget);
    expect(
      probador
          .widget<PantallaInicioPaciente>(find.byType(PantallaInicioPaciente))
          .nombrePaciente,
      'Sara',
    );
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
    await probador.pumpAndSettle();
  });

  testWidgets('La vista muestra el error y permite volver a enviar', (
    probador,
  ) async {
    await abrirFormulario(
      probador,
      ServicioInicioSesionPrueba((correo, clave) async {
        throw const ErrorInicioSesion('Credenciales de prueba incorrectas');
      }),
    );
    await probador.pumpAndSettle();
    expect(find.text('Credenciales de prueba incorrectas'), findsOneWidget);
    expect(find.byType(PantallaInicioPaciente), findsNothing);
    final boton = probador.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Iniciar sesión'),
    );
    expect(boton.onPressed, isNotNull);
    expect(probador.takeException(), isNull);
    await probador.pumpWidget(const SizedBox.shrink());
    await probador.pumpAndSettle();
  });
}
