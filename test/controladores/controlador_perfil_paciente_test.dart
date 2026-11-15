import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/paciente/controladores/controlador_perfil_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_perfil_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_paciente.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

class _ServicioPerfilPacienteFalso extends ServicioPerfilPaciente {
  PerfilUsuario perfilAlmacenado;
  bool simularErrorGuardado;
  int llamadasGuardar = 0;

  _ServicioPerfilPacienteFalso({
    required this.perfilAlmacenado,
    this.simularErrorGuardado = false,
  });

  @override
  Future<PerfilUsuario> obtenerPerfilPropio() async {
    return perfilAlmacenado;
  }

  @override
  Future<PerfilUsuario> actualizarDatosBasicos({
    required String nombre,
    required String apellido,
  }) async {
    llamadasGuardar++;
    if (simularErrorGuardado) {
      throw const ErrorPerfilPaciente('No se pudieron guardar los cambios.');
    }
    perfilAlmacenado = perfilAlmacenado.copiarCon(
      nombre: nombre,
      apellido: apellido,
    );
    return perfilAlmacenado;
  }
}

class _ServicioSesionFalso extends ServicioSesion {
  int llamadasCerrar = 0;

  @override
  Future<void> cerrarSesion() async {
    llamadasCerrar++;
  }
}

void main() {
  const perfilInicial = PerfilUsuario(
    id: 'pac-10',
    nombre: 'Lucía',
    apellido: 'Mendoza',
    correo: 'lucia@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  group('ControladorPerfilPaciente - Carga, validacion y persistencia', () {
    test('Carga el perfil actual del paciente desde el servicio', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final controlador = ControladorPerfilPaciente(servicio: servicio);

      await controlador.cargarPerfil();

      expect(controlador.estaCargando, isFalse);
      expect(controlador.perfil?.nombre, equals('Lucía'));
      expect(controlador.perfil?.apellido, equals('Mendoza'));
      expect(controlador.mensajeError, isNull);
    });

    test('Valida campos obligatorios y longitud minima', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicio,
        perfilInicial: perfilInicial,
      );

      expect(
        ControladorPerfilPaciente.validarNombreOApellido('', 'nombre'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('A', 'nombre'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('Lucía', 'nombre'),
        isNull,
      );

      expect(
        ControladorPerfilPaciente.validarNombreOApellido('', 'apellido'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('B', 'apellido'),
        isNotNull,
      );
      expect(
        ControladorPerfilPaciente.validarNombreOApellido('Mendoza', 'apellido'),
        isNull,
      );

      final exitoInvalido = await controlador.guardarPerfil(
        nombre: 'A',
        apellido: '',
      );
      expect(exitoInvalido, isFalse);
      expect(servicio.llamadasGuardar, equals(0));
    });

    test(
      'Guarda cambios validos y conserva los datos tras recargar el perfil',
      () async {
        final servicio = _ServicioPerfilPacienteFalso(
          perfilAlmacenado: perfilInicial,
        );
        final controlador = ControladorPerfilPaciente(
          servicio: servicio,
          perfilInicial: perfilInicial,
        );

        final exito = await controlador.guardarPerfil(
          nombre: 'Lucía Fernanda',
          apellido: 'Mendoza Ortiz',
        );

        expect(exito, isTrue);
        expect(servicio.llamadasGuardar, equals(1));
        expect(controlador.perfil?.nombre, equals('Lucía Fernanda'));
        expect(controlador.perfil?.apellido, equals('Mendoza Ortiz'));
        expect(
          controlador.mensajeExito,
          equals('Tu perfil se actualizó correctamente en PsicoBloom.'),
        );

        // Simula nuevo inicio de sesion cargando desde el servicio
        final nuevoControlador = ControladorPerfilPaciente(servicio: servicio);
        await nuevoControlador.cargarPerfil();
        expect(nuevoControlador.perfil?.nombre, equals('Lucía Fernanda'));
        expect(nuevoControlador.perfil?.apellido, equals('Mendoza Ortiz'));
      },
    );

    test('Informa error cuando falla la persistencia en el backend', () async {
      final servicio = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
        simularErrorGuardado: true,
      );
      final controlador = ControladorPerfilPaciente(
        servicio: servicio,
        perfilInicial: perfilInicial,
      );

      final exito = await controlador.guardarPerfil(
        nombre: 'Lucía',
        apellido: 'Actualizada',
      );

      expect(exito, isFalse);
      expect(
        controlador.mensajeError,
        equals('No se pudieron guardar los cambios.'),
      );
    });
  });

  group('PantallaPerfilPaciente - Interfaz y flujo de edicion', () {
    testWidgets('Permite editar y guardar cambios en el perfil', (
      WidgetTester probador,
    ) async {
      probador.view.physicalSize = const Size(1080, 2400);
      probador.view.devicePixelRatio = 2.0;
      addTearDown(probador.view.resetPhysicalSize);
      addTearDown(probador.view.resetDevicePixelRatio);

      final servicioPerfil = _ServicioPerfilPacienteFalso(
        perfilAlmacenado: perfilInicial,
      );
      final servicioSesion = _ServicioSesionFalso();
      PerfilUsuario? perfilNotificado;

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: PantallaPerfilPaciente(
            perfilInicial: perfilInicial,
            servicio: servicioPerfil,
            servicioSesion: servicioSesion,
            alActualizarPerfil: (nuevo) => perfilNotificado = nuevo,
          ),
        ),
      );
      await probador.pumpAndSettle();

      expect(find.text('Lucía Mendoza'), findsOneWidget);
      expect(find.text('lucia@ejemplo.com'), findsAtLeastNWidgets(1));

      await probador.enterText(
        find.byKey(const Key('campoNombrePaciente')),
        'Valeria',
      );
      await probador.enterText(
        find.byKey(const Key('campoApellidoPaciente')),
        'Salazar',
      );

      final botonGuardar = find.byKey(const Key('botonGuardarPerfilPaciente'));
      await probador.ensureVisible(botonGuardar);
      await probador.tap(botonGuardar);
      await probador.pumpAndSettle();

      expect(servicioPerfil.llamadasGuardar, equals(1));
      expect(perfilNotificado?.nombre, equals('Valeria'));
      expect(perfilNotificado?.apellido, equals('Salazar'));
      expect(
        find.text('Tu perfil se actualizó correctamente en PsicoBloom.'),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
