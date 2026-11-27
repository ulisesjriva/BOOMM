import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/profesional/controladores/controlador_perfil_profesional.dart';
import 'package:boom/modulos/profesional/modelos/configuracion_cobro_profesional.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_avisos_telegram.dart';
import 'package:boom/modulos/profesional/servicios/servicio_cobro_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_perfil_profesional.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

// PNG 1x1 valido (transparente) para probar decodificacion y firma de bytes.
final Uint8List _bytesPngValido = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

final Uint8List _bytesJpgValido = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

class _ServicioPerfilSimple extends ServicioPerfilProfesional {
  final PerfilProfesional perfil;
  const _ServicioPerfilSimple(this.perfil);

  @override
  Future<PerfilProfesional> obtenerPerfilPropio() async => perfil;
}

class _RepositorioEspecialidadesSimple implements RepositorioEspecialidades {
  const _RepositorioEspecialidadesSimple();

  @override
  Future<List<Especialidad>> obtenerCatalogoEspecialidades() async => const [
    Especialidad(id: 'esp-1', nombre: 'Psicología Clínica', activa: true),
  ];

  @override
  Future<void> guardarEspecialidadesProfesional(
    List<String> especialidadesIds,
  ) async {}
}

class _ServicioTelegramSimple extends ServicioAvisosTelegram {
  const _ServicioTelegramSimple();

  @override
  Future<EstadoTelegramProfesional> obtenerEstado() async =>
      const EstadoTelegramProfesional(
        conectado: false,
        tieneCodigoPendiente: false,
      );
}

class _ServicioCobroFalso extends ServicioCobroProfesional {
  ConfiguracionCobroProfesional configuracionActual;
  ArchivoQrSeleccionado? qrSimulado;
  String? errorCargaInicial;
  String? errorSubida;
  String? errorGuardado;
  int llamadasGuardar = 0;

  _ServicioCobroFalso({
    this.configuracionActual = const ConfiguracionCobroProfesional(),
    this.qrSimulado,
    this.errorCargaInicial,
    this.errorSubida,
    this.errorGuardado,
  });

  @override
  Future<ConfiguracionCobroProfesional> obtenerConfiguracionPropia() async {
    if (errorCargaInicial != null) {
      throw ErrorCobroProfesional(errorCargaInicial!);
    }
    return configuracionActual;
  }

  @override
  Future<ArchivoQrSeleccionado?> seleccionarImagenQr({
    ImageSource origen = ImageSource.gallery,
  }) async {
    return qrSimulado;
  }

  @override
  Future<String> subirQrPrivado(ArchivoQrSeleccionado archivo) async {
    if (errorSubida != null) {
      throw ErrorCobroProfesional(errorSubida!);
    }
    return 'prof-100/qr_1700000000000.${archivo.extensionArchivo}';
  }

  @override
  Future<String?> obtenerUrlTemporalVistaQr(String rutaObjeto) async => null;

  @override
  Future<ConfiguracionCobroProfesional> guardarConfiguracionPropia(
    ConfiguracionCobroProfesional configuracion,
  ) async {
    llamadasGuardar++;
    if (errorGuardado != null) {
      throw ErrorCobroProfesional(errorGuardado!);
    }
    configuracionActual = configuracion;
    return configuracionActual;
  }
}

PerfilProfesional _perfilPrueba() {
  return const PerfilProfesional(
    id: 'prof-100',
    nombre: 'Sofía',
    apellido: 'Paredes',
    correo: 'sofia.paredes@psicobloom.test',
    cuentaActiva: true,
    aprobacion: 'aprobado',
    modalidad: 'Virtual',
    especialidadesIds: ['esp-1'],
    especialidadesNombres: ['Psicología Clínica'],
  );
}

void main() {
  group('ConfiguracionCobroProfesional y ServicioCobroProfesional', () {
    test('parsearMontoUsd acepta USD exacto hasta 2 decimales y rechaza formatos inválidos', () {
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('35'), 35.0);
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('35.5'), 35.5);
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('35,25'), 35.25);
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('35.125'), isNull);
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('0'), isNull);
      expect(
        ConfiguracionCobroProfesional.parsearMontoUsd('100000000.00'),
        isNull,
      );
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('-10'), isNull);
      expect(ConfiguracionCobroProfesional.parsearMontoUsd('abc'), isNull);

      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          double.nan,
          etiqueta: 'Precio',
        ),
        isNotNull,
      );
      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          double.infinity,
          etiqueta: 'Precio',
        ),
        isNotNull,
      );
      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          double.negativeInfinity,
          etiqueta: 'Precio',
        ),
        isNotNull,
      );
      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          100000000.0,
          etiqueta: 'Precio',
        ),
        isNotNull,
      );
      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          10.005,
          etiqueta: 'Precio',
        ),
        isNotNull,
      );
      expect(
        ConfiguracionCobroProfesional.validarMontoUsd(
          35.25,
          etiqueta: 'Precio',
        ),
        isNull,
      );
    });

    test('validarBytesQr acepta PNG/JPG y rechaza archivos vacíos, inválidos o > 5 MB', () {
      final png = ServicioCobroProfesional.validarBytesQr(_bytesPngValido);
      expect(png.extensionArchivo, 'png');
      expect(png.tipoMime, 'image/png');

      final jpg = ServicioCobroProfesional.validarBytesQr(_bytesJpgValido);
      expect(jpg.extensionArchivo, 'jpg');
      expect(jpg.tipoMime, 'image/jpeg');

      expect(
        () => ServicioCobroProfesional.validarBytesQr(Uint8List(0)),
        throwsA(isA<ErrorCobroProfesional>()),
      );
      expect(
        () => ServicioCobroProfesional.validarBytesQr(
          Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );
      expect(
        () => ServicioCobroProfesional.validarBytesQr(
          Uint8List(ServicioCobroProfesional.limiteBytesQr + 1),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );
    });

    test('guardarConfiguracionPropia rechaza URL firmada, ruta ajena y adelanto mayor al precio', () async {
      final servicio = ServicioCobroProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombre, {parametros}) async => const [],
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: true,
            precioConsulta: 30,
            montoAdelanto: 35,
            rutaQrStorage: 'prof-100/qr_1.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Sofía Paredes',
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: true,
            precioConsulta: 30,
            montoAdelanto: 15,
            rutaQrStorage:
                'https://proyecto.supabase.co/storage/v1/object/sign/qr.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Sofía Paredes',
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: true,
            precioConsulta: 30,
            montoAdelanto: 15,
            rutaQrStorage: 'otro-prof/qr_1.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Sofía Paredes',
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: true,
            precioConsulta: 30,
            montoAdelanto: 15,
            rutaQrStorage: null,
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Sofía Paredes',
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      // Rechaza NaN, Infinity, fraccion < 1 centavo (sin redondeo) y ruta vacia
      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: double.nan,
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: double.infinity,
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: 35.005,
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      await expectLater(
        servicio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: 35.00,
            rutaQrStorage: '   ',
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );
    });

    test(
      'subirQrPrivado genera nombres únicos consecutivos sin sobrescribir',
      () async {
        final rutasSubidas = <String>[];
        final servicio = ServicioCobroProfesional(
          lectorUsuarioActualId: () => 'prof-100',
          subidorQrPrivado:
              ({
                required String rutaObjeto,
                required Uint8List bytes,
                required String tipoMime,
              }) async {
                rutasSubidas.add(rutaObjeto);
                return rutaObjeto;
              },
        );
        final archivo = ArchivoQrSeleccionado(
          bytes: _bytesPngValido,
          extensionArchivo: 'png',
          tipoMime: 'image/png',
        );

        final ruta1 = await servicio.subirQrPrivado(archivo);
        final ruta2 = await servicio.subirQrPrivado(archivo);

        expect(rutasSubidas.length, 2);
        expect(ruta1, startsWith('prof-100/qr_'));
        expect(ruta2, startsWith('prof-100/qr_'));
        expect(ruta1, isNot(equals(ruta2)));
      },
    );

    test('guardarConfiguracionPropia rechaza respuesta vacía o discrepante del servidor', () async {
      final servicioDiscrepante = ServicioCobroProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombre, {parametros}) async {
          return [
            {
              'requiere_adelanto': false,
              'moneda': 'USD',
              'precio_consulta': 99.99,
              'monto_adelanto': 15.0,
              'ruta_qr_storage': null,
            },
          ];
        },
      );

      await expectLater(
        servicioDiscrepante.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: 40.0,
            montoAdelanto: 15.0,
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );

      final servicioVacio = ServicioCobroProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombre, {parametros}) async => const [],
      );

      await expectLater(
        servicioVacio.guardarConfiguracionPropia(
          const ConfiguracionCobroProfesional(
            requiereAdelanto: false,
            precioConsulta: 40.0,
            montoAdelanto: 15.0,
          ),
        ),
        throwsA(isA<ErrorCobroProfesional>()),
      );
    });

    test('guardarConfiguracionPropia envía únicamente la ruta privada y retorna la configuración guardada', () async {
      String? rpcInvocada;
      Map<String, dynamic>? paramsEnviados;

      final servicio = ServicioCobroProfesional(
        lectorUsuarioActualId: () => 'prof-100',
        ejecutorRpc: (nombre, {parametros}) async {
          rpcInvocada = nombre;
          paramsEnviados = parametros;
          if (nombre == 'guardar_configuracion_cobro_propia') {
            return [
              {
                'requiere_adelanto': true,
                'moneda': 'USD',
                'precio_consulta': 40.0,
                'monto_adelanto': 15.0,
                'ruta_qr_storage': 'prof-100/qr_1700000000000.png',
                'banco_beneficiario': 'Banco Guayaquil',
                'titular_beneficiario': 'Sofía Paredes',
                'tipo_cuenta_beneficiario': 'Ahorros',
                'numero_cuenta_referencia': '2200123456',
              },
            ];
          }
          return const [];
        },
      );

      final guardada = await servicio.guardarConfiguracionPropia(
        const ConfiguracionCobroProfesional(
          requiereAdelanto: true,
          precioConsulta: 40.0,
          montoAdelanto: 15.0,
          rutaQrStorage: 'prof-100/qr_1700000000000.png',
          bancoBeneficiario: 'Banco Guayaquil',
          titularBeneficiario: 'Sofía Paredes',
          tipoCuentaBeneficiario: 'Ahorros',
          numeroCuentaReferencia: '2200123456',
        ),
      );

      expect(rpcInvocada, 'guardar_configuracion_cobro_propia');
      expect(
        paramsEnviados?['p_ruta_qr_storage'],
        'prof-100/qr_1700000000000.png',
      );
      expect(guardada.requiereAdelanto, isTrue);
      expect(guardada.precioConsulta, 40.0);
      expect(guardada.montoAdelanto, 15.0);
      expect(guardada.rutaQrStorage, 'prof-100/qr_1700000000000.png');
    });

    test(
      'explicarError traduce 42501 y PGRST202 sin filtrar jerga técnica',
      () {
        final msgPermisos = ServicioCobroProfesional.explicarError(
          const PostgrestException(message: 'permission denied', code: '42501'),
        );
        expect(msgPermisos.toLowerCase(), isNot(contains('supabase')));
        expect(msgPermisos.toLowerCase(), isNot(contains('sql')));

        final msgNoHabilitado = ServicioCobroProfesional.explicarError(
          const PostgrestException(
            message: 'function not found',
            code: 'PGRST202',
          ),
        );
        expect(msgNoHabilitado, contains('aún no está habilitada'));
        expect(msgNoHabilitado.toLowerCase(), isNot(contains('supabase')));
      },
    );
  });

  group('ControladorPerfilProfesional - configuración de cobro', () {
    test('no bloquea la carga del perfil si la migración SQL de cobro aún no existe', () async {
      final controlador = ControladorPerfilProfesional(
        servicio: _ServicioPerfilSimple(_perfilPrueba()),
        repositorioEspecialidades: const _RepositorioEspecialidadesSimple(),
        servicioTelegram: const _ServicioTelegramSimple(),
        servicioCobro: _ServicioCobroFalso(
          errorCargaInicial: 'La función aún no existe.',
        ),
      );

      await controlador.inicializar();

      expect(controlador.perfil?.nombre, 'Sofía');
      expect(controlador.mensajeError, isNull);
      expect(controlador.configuracionCobro.requiereAdelanto, isFalse);
      controlador.dispose();
    });

    test('conserva la configuración previa si falla la subida del QR o el guardado', () async {
      const previa = ConfiguracionCobroProfesional(
        requiereAdelanto: true,
        precioConsulta: 35.0,
        montoAdelanto: 10.0,
        rutaQrStorage: 'prof-100/qr_anterior.png',
        bancoBeneficiario: 'Banco Pichincha',
        titularBeneficiario: 'Sofía Paredes',
      );
      final servicioCobro = _ServicioCobroFalso(
        configuracionActual: previa,
        qrSimulado: ArchivoQrSeleccionado(
          bytes: _bytesPngValido,
          extensionArchivo: 'png',
          tipoMime: 'image/png',
        ),
        errorSubida: 'Fallo temporal de red',
        errorGuardado: 'Error temporal del servidor',
      );

      final controlador = ControladorPerfilProfesional(
        servicio: _ServicioPerfilSimple(_perfilPrueba()),
        repositorioEspecialidades: const _RepositorioEspecialidadesSimple(),
        servicioTelegram: const _ServicioTelegramSimple(),
        servicioCobro: servicioCobro,
      );

      await controlador.inicializar();
      expect(
        controlador.configuracionCobro.rutaQrStorage,
        'prof-100/qr_anterior.png',
      );

      final subido = await controlador.seleccionarYSubirQrCobro();
      expect(subido, isFalse);
      expect(controlador.rutaQrEfectiva, 'prof-100/qr_anterior.png');

      final guardado = await controlador.guardarConfiguracionCobro(
        requiereAdelanto: true,
        textoPrecioConsulta: '45.00',
        textoMontoAdelanto: '20.00',
        bancoBeneficiario: 'Banco del Pacífico',
        titularBeneficiario: 'Sofía Paredes',
        tipoCuentaBeneficiario: 'Ahorros',
        numeroCuentaReferencia: '123456',
      );
      expect(guardado, isFalse);
      expect(controlador.configuracionCobro.precioConsulta, 35.0);
      expect(
        controlador.configuracionCobro.bancoBeneficiario,
        'Banco Pichincha',
      );
      controlador.dispose();
    });
  });

  group('PantallaPerfilProfesional - sección Cobro y adelanto', () {
    testWidgets(
      'permite cargar QR privado y guardar configuración válida de cobro',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final servicioCobro = _ServicioCobroFalso(
          qrSimulado: ArchivoQrSeleccionado(
            bytes: _bytesPngValido,
            extensionArchivo: 'png',
            tipoMime: 'image/png',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaPerfilProfesional(
              perfilInicial: _perfilPrueba(),
              servicio: _ServicioPerfilSimple(_perfilPrueba()),
              repositorioEspecialidades:
                  const _RepositorioEspecialidadesSimple(),
              servicioTelegram: const _ServicioTelegramSimple(),
              servicioCobro: servicioCobro,
              mostrarMapaInteractivo: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.byKey(const Key('botonGuardarConfiguracionCobro')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.text('Cobro y adelanto (USD)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('interruptorRequiereAdelanto')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('campoPrecioConsultaUsd')),
          '35.00',
        );
        await tester.enterText(
          find.byKey(const Key('campoMontoAdelantoUsd')),
          '15.00',
        );
        await tester.enterText(
          find.byKey(const Key('campoBancoBeneficiario')),
          'Banco Pichincha',
        );
        await tester.enterText(
          find.byKey(const Key('campoTitularBeneficiario')),
          'Sofía Paredes',
        );

        await tester.tap(find.byKey(const Key('botonCargarQrCobro')));
        await tester.pumpAndSettle();

        final botonGuardarCobro = find.byKey(
          const Key('botonGuardarConfiguracionCobro'),
        );
        ScaffoldMessenger.of(tester.element(botonGuardarCobro))
            .removeCurrentSnackBar();
        await tester.ensureVisible(botonGuardarCobro);
        await tester.pumpAndSettle();

        await tester.tap(botonGuardarCobro);
        await tester.pumpAndSettle();

        expect(servicioCobro.llamadasGuardar, 1);
        expect(servicioCobro.configuracionActual.requiereAdelanto, isTrue);
        expect(servicioCobro.configuracionActual.precioConsulta, 35.0);
        expect(servicioCobro.configuracionActual.montoAdelanto, 15.0);
        expect(
          servicioCobro.configuracionActual.rutaQrStorage,
          startsWith('prof-100/qr_'),
        );
      },
    );
  });
}
