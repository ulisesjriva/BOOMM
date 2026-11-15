import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/profesional/controladores/controlador_perfil_profesional.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_avisos_telegram.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_perfil_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RepositorioEspecialidadesStub implements RepositorioEspecialidades {
  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async => const [];

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {}
}

class _ServicioPerfilFalso extends ServicioPerfilProfesional {
  _ServicioPerfilFalso(this.perfil);
  final PerfilProfesional perfil;

  @override
  Future<PerfilProfesional> obtenerPerfilPropio() async => perfil;
}

class _ServicioUbicacionFalso extends ServicioUbicacionConsultorio {
  @override
  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async =>
      const ResultadoUbicacionDispositivo.obtenida(
        latitud: -1.67,
        longitud: -78.64,
      );
}

void main() {
  group('ServicioAvisosTelegram', () {
    test(
      'genera enlace de vinculación, abre t.me, consulta estado y desconecta',
      () async {
        final llamadasRpc = <String>[];
        Uri? enlaceAbierto;
        var conectado = false;

        final servicio = ServicioAvisosTelegram(
          ejecutorRpc: (nombreFuncion, {parametros}) async {
            llamadasRpc.add(nombreFuncion);
            if (nombreFuncion == 'estado_telegram_profesional_propio') {
              return [
                {
                  'conectado': conectado,
                  'conectado_en': conectado ? '2026-11-15T16:00:00Z' : null,
                  'tiene_codigo_pendiente': !conectado,
                  'codigo_expira_en': !conectado
                      ? '2026-11-15T16:10:00Z'
                      : null,
                },
              ];
            }
            if (nombreFuncion == 'desconectar_telegram_profesional_propio') {
              conectado = false;
              return null;
            }
            return null;
          },
          invocadorEdge: (nombreFuncion) async {
            expect(nombreFuncion, equals('generar-codigo-telegram'));
            return const RespuestaEdgeTelegram(
              estado: 200,
              datos: {
                'enlaceTelegram':
                    'https://t.me/psicobloom_avisos_bot?start=codigoSeguro123',
                'expiraEn': '2026-11-15T16:10:00Z',
              },
            );
          },
          abridorEnlace: (uri) async {
            enlaceAbierto = uri;
            return true;
          },
        );

        final enlace = await servicio.generarEnlaceVinculacion();
        expect(
          enlace.enlaceTelegram,
          equals('https://t.me/psicobloom_avisos_bot?start=codigoSeguro123'),
        );

        await servicio.abrirEnlaceVinculacion(enlace.enlaceTelegram);
        expect(
          enlaceAbierto.toString(),
          equals('https://t.me/psicobloom_avisos_bot?start=codigoSeguro123'),
        );

        conectado = true;
        final estadoConectado = await servicio.obtenerEstado();
        expect(estadoConectado.conectado, isTrue);

        await servicio.desconectar();
        final estadoDesconectado = await servicio.obtenerEstado();
        expect(estadoDesconectado.conectado, isFalse);
        expect(
          llamadasRpc,
          equals([
            'estado_telegram_profesional_propio',
            'desconectar_telegram_profesional_propio',
            'estado_telegram_profesional_propio',
          ]),
        );
      },
    );

    test('rechaza sesión inválida (401), rol no autorizado (403) y enlaces inválidos', () async {
      final servicio401 = ServicioAvisosTelegram(
        invocadorEdge: (_) async => const RespuestaEdgeTelegram(
          estado: 401,
          datos: {'mensaje': 'Tu sesión expiró o no es válida.'},
        ),
      );
      await expectLater(
        servicio401.generarEnlaceVinculacion,
        throwsA(
          isA<ErrorAvisosTelegram>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('sesión expiró'),
          ),
        ),
      );

      final servicio403 = ServicioAvisosTelegram(
        invocadorEdge: (_) async => const RespuestaEdgeTelegram(
          estado: 403,
          datos: {
            'mensaje': 'Solo los profesionales con cuenta activa pueden conectar Telegram.',
          },
        ),
      );
      await expectLater(
        servicio403.generarEnlaceVinculacion,
        throwsA(
          isA<ErrorAvisosTelegram>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Solo los profesionales'),
          ),
        ),
      );

      await expectLater(
        () =>
            servicio401.abrirEnlaceVinculacion('https://ejemplo.com/malicioso'),
        throwsA(isA<ErrorAvisosTelegram>()),
      );
    });
  });

  group('Controlador y UI de Avisos por Telegram', () {
    const perfilBase = PerfilProfesional(
      id: 'usr-100',
      idProfesional: 'prof-100',
      nombre: 'Carlos',
      apellido: 'Pérez',
      correo: 'carlos@ejemplo.com',
      aprobacion: 'aprobado',
      cuentaActiva: true,
      modalidad: 'Presencial',
    );

    test('fallo al consultar estado inicial de Telegram no bloquea la carga del perfil', () async {
      final controlador = ControladorPerfilProfesional(
        servicio: _ServicioPerfilFalso(perfilBase),
        repositorioEspecialidades: _RepositorioEspecialidadesStub(),
        servicioUbicacion: _ServicioUbicacionFalso(),
        servicioTelegram: ServicioAvisosTelegram(
          ejecutorRpc: (_, {parametros}) async {
            throw const ErrorAvisosTelegram(
              'Servicio temporalmente no disponible',
            );
          },
        ),
      );

      await controlador.inicializar();
      expect(controlador.perfil?.id, equals('usr-100'));
      expect(controlador.mensajeError, isNull);
      expect(controlador.estadoTelegram.conectado, isFalse);
    });

    testWidgets(
      'muestra Avisos por Telegram y permite conectar, comprobar y desconectar',
      (tester) async {
        var conectado = false;
        Uri? uriAbierto;

        final servicioTelegram = ServicioAvisosTelegram(
          ejecutorRpc: (nombreFuncion, {parametros}) async {
            if (nombreFuncion == 'estado_telegram_profesional_propio') {
              return [
                {'conectado': conectado, 'tiene_codigo_pendiente': !conectado},
              ];
            }
            if (nombreFuncion == 'desconectar_telegram_profesional_propio') {
              conectado = false;
            }
            return null;
          },
          invocadorEdge: (_) async => const RespuestaEdgeTelegram(
            estado: 200,
            datos: {
              'enlaceTelegram':
                  'https://t.me/psicobloom_avisos_bot?start=tokenTest',
            },
          ),
          abridorEnlace: (uri) async {
            uriAbierto = uri;
            return true;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilProfesional(
              perfilInicial: perfilBase,
              servicio: _ServicioPerfilFalso(perfilBase),
              repositorioEspecialidades: _RepositorioEspecialidadesStub(),
              servicioUbicacion: _ServicioUbicacionFalso(),
              servicioTelegram: servicioTelegram,
              mostrarMapaInteractivo: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Avisos por Telegram'), findsOneWidget);
        expect(
          find.text('Recibe un aviso cuando tengas una nueva solicitud.'),
          findsOneWidget,
        );
        final botonConectar = find.byKey(const Key('botonConectarTelegram'));
        expect(botonConectar, findsOneWidget);
        await tester.ensureVisible(botonConectar);
        await tester.pumpAndSettle();
        await tester.tap(botonConectar);
        await tester.pumpAndSettle();
        expect(
          uriAbierto.toString(),
          equals('https://t.me/psicobloom_avisos_bot?start=tokenTest'),
        );

        conectado = true;
        final botonComprobar = find.byKey(const Key('botonComprobarTelegram'));
        await tester.ensureVisible(botonComprobar);
        await tester.pumpAndSettle();
        await tester.tap(botonComprobar);
        await tester.pumpAndSettle();
        expect(find.text('Conectado'), findsOneWidget);

        final botonDesconectar = find.byKey(
          const Key('botonDesconectarTelegram'),
        );
        expect(botonDesconectar, findsOneWidget);
        await tester.ensureVisible(botonDesconectar);
        await tester.pumpAndSettle();
        await tester.tap(botonDesconectar);
        await tester.pumpAndSettle();
        expect(find.text('No conectado'), findsOneWidget);
        expect(find.byKey(const Key('botonConectarTelegram')), findsOneWidget);
      },
    );
  });
}
