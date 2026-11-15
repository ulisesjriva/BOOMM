import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/controladores/controlador_sesion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/autenticacion/vistas/navegador_roles.dart';
import 'package:boom/modulos/paciente/controladores/gestor_favoritos.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_profesionales_simulado.dart';

class _ServicioSesionFalso extends ServicioSesion {
  ResultadoResolucionSesion resultadoSimulado;
  int llamadasCerrarSesion = 0;

  _ServicioSesionFalso({required this.resultadoSimulado});

  @override
  Future<ResultadoResolucionSesion> resolverSesionActual() async {
    return resultadoSimulado;
  }

  @override
  Future<void> cerrarSesion() async {
    llamadasCerrarSesion++;
    GestorFavoritos.instancia.limpiar();
  }
}

void main() {
  const perfilPacienteActivo = PerfilUsuario(
    id: 'pac-1',
    nombre: 'Ana',
    apellido: 'Gómez',
    correo: 'ana@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  const perfilProfesionalActivo = PerfilUsuario(
    id: 'prof-1',
    nombre: 'Carlos',
    apellido: 'Pérez',
    correo: 'carlos@ejemplo.com',
    rol: 'profesional',
    aprobacion: 'aprobado',
    cuentaActiva: true,
  );

  const perfilAdminActivo = PerfilUsuario(
    id: 'adm-1',
    nombre: 'Elena',
    apellido: 'Vargas',
    correo: 'elena@ejemplo.com',
    rol: 'administrador',
    aprobacion: 'no_aplica',
    cuentaActiva: true,
  );

  const perfilInactivo = PerfilUsuario(
    id: 'pac-inactivo',
    nombre: 'Pedro',
    apellido: 'Ruiz',
    correo: 'pedro@ejemplo.com',
    rol: 'paciente',
    aprobacion: 'no_aplica',
    cuentaActiva: false,
  );

  setUp(() {
    GestorFavoritos.instancia.limpiar();
  });

  group('ControladorSesion - Resolucion de sesion, roles y estado', () {
    test('Restaura sesion activa y resuelve rol de paciente', () async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.autenticado(
          perfilPacienteActivo,
        ),
      );
      final controlador = ControladorSesion(servicio: servicio);

      final resultado = await controlador.verificarSesionInicial();

      expect(resultado.estado, equals(EstadoResolucionSesion.autenticado));
      expect(controlador.tieneSesionActiva, isTrue);
      expect(controlador.perfilActual?.rol, equals('paciente'));
    });

    test('Restaura sesion activa para profesional y administrador', () async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.autenticado(
          perfilProfesionalActivo,
        ),
      );
      final controlador = ControladorSesion(servicio: servicio);

      await controlador.verificarSesionInicial();
      expect(controlador.perfilActual?.rol, equals('profesional'));

      servicio.resultadoSimulado = const ResultadoResolucionSesion.autenticado(
        perfilAdminActivo,
      );
      await controlador.verificarSesionInicial();
      expect(controlador.perfilActual?.rol, equals('administrador'));
    });

    test('Bloquea cuenta inactiva sin autorizar sesion', () async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.cuentaInactiva(
          perfil: perfilInactivo,
          mensaje: 'Cuenta desactivada por administración.',
        ),
      );
      final controlador = ControladorSesion(servicio: servicio);

      final resultado = await controlador.verificarSesionInicial();

      expect(resultado.estado, equals(EstadoResolucionSesion.cuentaInactiva));
      expect(controlador.tieneSesionActiva, isFalse);
      expect(controlador.perfilActual?.cuentaActiva, isFalse);
    });

    test('Diferencia falla de red respecto de una cuenta desactivada', () async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.errorConexion(
          mensaje:
              'No se pudo verificar la sesión. Revisa tu conexión a internet.',
        ),
      );
      final controlador = ControladorSesion(servicio: servicio);

      final resultado = await controlador.verificarSesionInicial();

      expect(resultado.estado, equals(EstadoResolucionSesion.errorConexion));
      expect(controlador.estado, isNot(EstadoResolucionSesion.cuentaInactiva));
      expect(controlador.tieneSesionActiva, isFalse);
    });

    test(
      'Cerrar sesion limpia el estado local y deja la sesion sin autorizacion',
      () async {
        GestorFavoritos.instancia.alternarFavorito('prof-favorito');
        expect(GestorFavoritos.instancia.favoritos.value, isNotEmpty);

        final servicio = _ServicioSesionFalso(
          resultadoSimulado: const ResultadoResolucionSesion.autenticado(
            perfilPacienteActivo,
          ),
        );
        final controlador = ControladorSesion(servicio: servicio);
        await controlador.verificarSesionInicial();
        expect(controlador.tieneSesionActiva, isTrue);

        await controlador.cerrarSesion();

        expect(servicio.llamadasCerrarSesion, equals(1));
        expect(controlador.tieneSesionActiva, isFalse);
        expect(controlador.perfilActual, isNull);
        expect(GestorFavoritos.instancia.favoritos.value, isEmpty);
      },
    );
  });

  group('NavegadorRoles - Enrutamiento y restriccion de acceso por rol', () {
    testWidgets('Dirige a cada rol a su pantalla de inicio correspondiente', (
      WidgetTester probador,
    ) async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.sinSesion(),
      );

      // Rol profesional
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: NavegadorRoles.construirDestinoPorPerfil(
            perfilProfesionalActivo,
            servicioSesion: servicio,
          ),
        ),
      );
      await probador.pump();
      expect(find.text('PsicoBloom'), findsOneWidget);
      expect(find.text('Hola, Carlos 👋'), findsOneWidget);
      expect(find.text('Estas son tus citas de hoy'), findsOneWidget);

      // Rol administrador
      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: NavegadorRoles.construirDestinoPorPerfil(
            perfilAdminActivo,
            servicioSesion: servicio,
          ),
        ),
      );
      await probador.pump();
      expect(find.text('Administración PsicoBloom'), findsOneWidget);
      expect(find.text('Elena Vargas'), findsOneWidget);
    });

    testWidgets(
      'Impide que un paciente acceda a una pantalla protegida de administrador',
      (WidgetTester probador) async {
        final servicio = _ServicioSesionFalso(
          resultadoSimulado: const ResultadoResolucionSesion.sinSesion(),
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: NavegadorRoles.protegerPorRol(
              perfil: perfilPacienteActivo,
              rolRequerido: 'administrador',
              servicioSesion: servicio,
              constructorContenido: (_) =>
                  const Scaffold(body: Text('Contenido secreto admin')),
            ),
          ),
        );
        await probador.pump();

        expect(find.text('Contenido secreto admin'), findsNothing);
        expect(find.text('Acceso restringido'), findsOneWidget);
      },
    );

    testWidgets('Impide que una cuenta inactiva acceda a contenido protegido', (
      WidgetTester probador,
    ) async {
      final servicio = _ServicioSesionFalso(
        resultadoSimulado: const ResultadoResolucionSesion.sinSesion(),
      );

      await probador.pumpWidget(
        MaterialApp(
          theme: TemaPsicobloom.obtenerTema(),
          home: NavegadorRoles.protegerPorRol(
            perfil: perfilInactivo,
            rolRequerido: 'paciente',
            servicioSesion: servicio,
            constructorContenido: (_) =>
                const Scaffold(body: Text('Contenido privado paciente')),
          ),
        ),
      );
      await probador.pump();

      expect(find.text('Contenido privado paciente'), findsNothing);
      expect(find.text('Cuenta inactiva'), findsOneWidget);
    });

    testWidgets(
      'Cerrar sesion desde Perfil profesional reemplaza la pila de navegacion y la campana no cierra sesion',
      (WidgetTester probador) async {
        final servicio = _ServicioSesionFalso(
          resultadoSimulado: const ResultadoResolucionSesion.autenticado(
            perfilProfesionalActivo,
          ),
        );

        await probador.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: NavegadorRoles.construirDestinoPorPerfil(
              perfilProfesionalActivo,
              servicioSesion: servicio,
            ),
          ),
        );
        await probador.pump();

        // El icono de salir ya no existe en la cabecera profesional
        expect(
          find.byKey(const Key('botonCerrarSesionProfesional')),
          findsNothing,
        );

        // La campana de notificaciones muestra aviso informativo y NUNCA cierra sesion
        await probador.tap(
          find.byKey(const Key('botonNotificacionesProfesional')),
        );
        await probador.pump();
        expect(
          find.text('Las notificaciones estarán disponibles próximamente'),
          findsOneWidget,
        );
        expect(servicio.llamadasCerrarSesion, equals(0));
        await probador.pumpAndSettle(const Duration(seconds: 3));

        // El cierre de sesion funciona desde la seccion Perfil
        await probador.tap(find.byKey(const Key('pestanaProfesional_perfil')));
        await probador.pumpAndSettle();

        final botonCerrarSesionPerfil = find.byKey(
          const Key('botonCerrarSesionDesdePerfilProfesional'),
        );
        await probador.scrollUntilVisible(
          botonCerrarSesionPerfil,
          300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await probador.pumpAndSettle();

        await probador.tap(botonCerrarSesionPerfil);
        await probador.pumpAndSettle();

        expect(servicio.llamadasCerrarSesion, equals(1));
        expect(find.text('Hola, Carlos 👋'), findsNothing);
        expect(find.text('Iniciar sesión'), findsOneWidget);
      },
    );
  });

  testWidgets('PantallaInicioPaciente se construye desde NavegadorRoles', (
    WidgetTester probador,
  ) async {
    final repositorioSimulado = RepositorioProfesionalesSimulado();
    await probador.pumpWidget(
      MaterialApp(
        theme: TemaPsicobloom.obtenerTema(),
        home: Builder(
          builder: (_) =>
              NavegadorRoles.construirDestinoPorPerfil(perfilPacienteActivo),
        ),
      ),
    );
    await probador.pump();
    expect(repositorioSimulado, isNotNull);
    expect(find.text('Hola, Ana 👋'), findsOneWidget);
  });
}
