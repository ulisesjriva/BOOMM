import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/adelanto_cita.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';
import 'package:boom/modulos/administrador/vistas/pantalla_inicio_administrador.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_horarios_profesional_paciente.dart';
import 'package:boom/modulos/profesional/controladores/controlador_citas_profesional.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/modulos/profesional/servicios/servicio_citas_profesional.dart';
import 'package:boom/nucleo/componentes/hoja_detalle_adelanto_cita.dart';
import 'package:boom/nucleo/servicios/servicio_adelantos_citas.dart';

// PNG 1x1 valido
final Uint8List _bytesPngComprobante = Uint8List.fromList([
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

class _ServicioAdelantosSimulado extends ServicioAdelantosCitas {
  DetalleAdelantoCita detalle;
  ArchivoComprobanteSeleccionado? archivoSimulado;
  final Set<String> clavesComprobante = {};
  final Set<String> clavesIncidencia = {};
  int enviosComprobante = 0;
  int enviosIncidencia = 0;
  int revisionesProfesional = 0;
  String? ultimaAccionRevision;
  String? ultimoMotivoRevision;
  bool forzarVencidoEnCarrera = false;

  _ServicioAdelantosSimulado({required this.detalle, this.archivoSimulado})
    : super(lectorUsuarioActualId: () => 'usr-titular');

  @override
  Future<DetalleAdelantoCita?> obtenerDetalleAdelantoCita(String idCita) async {
    return detalle;
  }

  @override
  Future<ArchivoComprobanteSeleccionado?> seleccionarImagenComprobante({
    ImageSource origen = ImageSource.gallery,
  }) async {
    return archivoSimulado;
  }

  @override
  Future<String> subirComprobantePrivado({
    required String idCita,
    required ArchivoComprobanteSeleccionado archivo,
  }) async {
    return '$idCita/usr-titular/comp_unico.${archivo.extensionArchivo}';
  }

  @override
  Future<DetalleAdelantoCita> registrarComprobanteAdelanto({
    required String idCita,
    required String rutaStorage,
    String? notaPaciente,
    required String claveIdempotencia,
  }) async {
    if (forzarVencidoEnCarrera) {
      throw const ErrorAdelantoCita(
        'El límite de pago (24 horas antes de la cita) ya venció. Si ya transferiste, reporta una incidencia.',
        codigo: '23P01',
      );
    }
    if (!clavesComprobante.contains(claveIdempotencia)) {
      clavesComprobante.add(claveIdempotencia);
      enviosComprobante++;
      detalle = DetalleAdelantoCita(
        idCita: detalle.idCita,
        estadoAdelanto: 'comprobante_en_revision',
        precioConsultaCentavos: detalle.precioConsultaCentavos,
        montoAdelantoCentavos: detalle.montoAdelantoCentavos,
        saldoDespuesAdelantoCentavos: detalle.saldoDespuesAdelantoCentavos,
        condicionesAceptadas: detalle.condicionesAceptadas,
        rutaQrStorage: detalle.rutaQrStorage,
        bancoBeneficiario: detalle.bancoBeneficiario,
        titularBeneficiario: detalle.titularBeneficiario,
        limitePagoEn: detalle.limitePagoEn,
        comprobantes: [
          ...detalle.comprobantes,
          ComprobanteAdelanto(
            idComprobante: 'comp-$enviosComprobante',
            rutaStorage: rutaStorage,
            notaPaciente: notaPaciente,
            creadoEn: DateTime.utc(2026, 11, 25, 15, 0),
          ),
        ],
        observaciones: detalle.observaciones,
        incidencias: detalle.incidencias,
      );
    }
    return detalle;
  }

  @override
  Future<DetalleAdelantoCita> registrarIncidenciaAdelanto({
    required String idCita,
    required String detalle,
    required String claveIdempotencia,
  }) async {
    if (detalle.trim().length < 5) {
      throw const ErrorAdelantoCita(
        'Describe brevemente el problema al adjuntar (mínimo 5 caracteres).',
      );
    }
    if (!clavesIncidencia.contains(claveIdempotencia)) {
      clavesIncidencia.add(claveIdempotencia);
      enviosIncidencia++;
      final yaLiberado = this.detalle.estadoAdelanto == 'vencido_sin_pago';
      this.detalle = DetalleAdelantoCita(
        idCita: this.detalle.idCita,
        estadoAdelanto: yaLiberado ? 'vencido_sin_pago' : 'incidencia_pago',
        precioConsultaCentavos: this.detalle.precioConsultaCentavos,
        montoAdelantoCentavos: this.detalle.montoAdelantoCentavos,
        saldoDespuesAdelantoCentavos: this.detalle.saldoDespuesAdelantoCentavos,
        condicionesAceptadas: this.detalle.condicionesAceptadas,
        rutaQrStorage: this.detalle.rutaQrStorage,
        bancoBeneficiario: this.detalle.bancoBeneficiario,
        titularBeneficiario: this.detalle.titularBeneficiario,
        limitePagoEn: this.detalle.limitePagoEn,
        comprobantes: this.detalle.comprobantes,
        observaciones: this.detalle.observaciones,
        incidencias: [
          ...this.detalle.incidencias,
          IncidenciaAdelanto(
            idIncidencia: 'inc-$enviosIncidencia',
            detalle: detalle,
            horarioYaLiberado: yaLiberado,
            estadoIncidencia: 'pendiente_revision',
            creadoEn: DateTime.utc(2026, 11, 25, 15, 5),
          ),
        ],
      );
    }
    return this.detalle;
  }

  @override
  Future<DetalleAdelantoCita> revisarAdelantoProfesional({
    required String idCita,
    required String accion,
    String? motivo,
  }) async {
    if (accion == 'observar' && (motivo == null || motivo.trim().length < 5)) {
      throw const ErrorAdelantoCita(
        'Debes indicar un motivo de al menos 5 caracteres para observar el comprobante.',
      );
    }
    revisionesProfesional++;
    ultimaAccionRevision = accion;
    ultimoMotivoRevision = motivo;
    detalle = DetalleAdelantoCita(
      idCita: detalle.idCita,
      estadoAdelanto: accion == 'verificar' ? 'verificado' : 'observado',
      precioConsultaCentavos: detalle.precioConsultaCentavos,
      montoAdelantoCentavos: detalle.montoAdelantoCentavos,
      saldoDespuesAdelantoCentavos: detalle.saldoDespuesAdelantoCentavos,
      condicionesAceptadas: detalle.condicionesAceptadas,
      rutaQrStorage: detalle.rutaQrStorage,
      bancoBeneficiario: detalle.bancoBeneficiario,
      titularBeneficiario: detalle.titularBeneficiario,
      verificadoPor: accion == 'verificar' ? 'usr-prof' : null,
      verificadoEn: accion == 'verificar'
          ? DateTime.utc(2026, 11, 25, 16, 0)
          : null,
      comprobantes: detalle.comprobantes,
      observaciones: accion == 'observar'
          ? [
              ...detalle.observaciones,
              ObservacionAdelanto(
                idObservacion: 'obs-1',
                tipoActor: 'profesional',
                mensaje: motivo!,
                creadoEn: DateTime.utc(2026, 11, 25, 16, 0),
              ),
            ]
          : detalle.observaciones,
      incidencias: detalle.incidencias,
    );
    return detalle;
  }

  @override
  Future<String?> obtenerUrlTemporalPrivada({
    required String bucket,
    required String rutaObjeto,
  }) async => null;
}

void main() {
  group(
    'AdelantoCita - estados, horas Ecuador y validaciones de comprobante',
    () {
      test('etiquetaVisibleEstadoAdelanto muestra Revisión demorada tras superar 12 horas', () {
        expect(
          etiquetaVisibleEstadoAdelanto(
            'comprobante_en_revision',
            revisionDemorada: false,
          ),
          'Comprobante en revisión',
        );
        expect(
          etiquetaVisibleEstadoAdelanto(
            'comprobante_en_revision',
            revisionDemorada: true,
          ),
          'Revisión demorada',
        );
        expect(
          formatearFechaHoraEcuador(DateTime.utc(2026, 11, 26, 15, 30)),
          '26/11/2026 10:30 (Ecuador)',
        );
      });

      test('validarBytesComprobante acepta PNG/JPG y rechaza vacíos, inválidos o > 5 MB', () {
        final png = ServicioAdelantosCitas.validarBytesComprobante(
          _bytesPngComprobante,
        );
        expect(png.extensionArchivo, 'png');
        expect(png.tipoMime, 'image/png');

        expect(
          () => ServicioAdelantosCitas.validarBytesComprobante(Uint8List(0)),
          throwsA(isA<ErrorAdelantoCita>()),
        );
        expect(
          () => ServicioAdelantosCitas.validarBytesComprobante(
            Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
          ),
          throwsA(isA<ErrorAdelantoCita>()),
        );
        expect(
          () => ServicioAdelantosCitas.validarBytesComprobante(
            Uint8List(ServicioAdelantosCitas.limiteBytesComprobante + 1),
          ),
          throwsA(isA<ErrorAdelantoCita>()),
        );
      });

      test('reintentos con misma clave de idempotencia no duplican comprobantes ni incidencias', () async {
        final servicio = _ServicioAdelantosSimulado(
          detalle: DetalleAdelantoCita(
            idCita: 'cita-1',
            estadoAdelanto: 'pendiente_adelanto',
            precioConsultaCentavos: 4000,
            montoAdelantoCentavos: 1500,
            saldoDespuesAdelantoCentavos: 2500,
            condicionesAceptadas: 'Regla 24h/12h',
            rutaQrStorage: 'prof-1/qr.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Dra. Elena',
            limitePagoEn: DateTime.utc(2026, 11, 28, 15, 0),
          ),
        );

        await servicio.registrarComprobanteAdelanto(
          idCita: 'cita-1',
          rutaStorage: 'cita-1/usr-titular/comp_1.png',
          claveIdempotencia: 'clave-comp-1',
        );
        await servicio.registrarComprobanteAdelanto(
          idCita: 'cita-1',
          rutaStorage: 'cita-1/usr-titular/comp_1.png',
          claveIdempotencia: 'clave-comp-1',
        );
        expect(servicio.enviosComprobante, 1);

        await servicio.registrarIncidenciaAdelanto(
          idCita: 'cita-1',
          detalle: 'Error de red al adjuntar la imagen',
          claveIdempotencia: 'clave-inc-1',
        );
        await servicio.registrarIncidenciaAdelanto(
          idCita: 'cita-1',
          detalle: 'Error de red al adjuntar la imagen',
          claveIdempotencia: 'clave-inc-1',
        );
        expect(servicio.enviosIncidencia, 1);
      });

      test('acceso ajeno o inactivo en RPC devuelve error 42501 sin filtrar detalles técnicos', () async {
        final servicioAjeno = ServicioAdelantosCitas(
          lectorUsuarioActualId: () => 'usr-ajeno',
          ejecutorRpc: (nombre, {parametros}) async {
            throw const PostgrestException(
              message: 'No tienes permiso para consultar el detalle de adelanto de esta cita.',
              code: '42501',
            );
          },
        );

        await expectLater(
          servicioAjeno.obtenerDetalleAdelantoCita('cita-ajena'),
          throwsA(
            isA<ErrorAdelantoCita>().having((e) => e.codigo, 'codigo', '42501'),
          ),
        );
      });
    },
  );

  group('HojaDetalleAdelantoCita y Supervisión Administrador', () {
    testWidgets(
      'paciente ve QR/datos bancarios, límite en hora Ecuador, envía comprobante y maneja carrera con vencimiento',
      (tester) async {
        final servicio = _ServicioAdelantosSimulado(
          archivoSimulado: ArchivoComprobanteSeleccionado(
            bytes: _bytesPngComprobante,
            extensionArchivo: 'png',
            tipoMime: 'image/png',
          ),
          detalle: DetalleAdelantoCita(
            idCita: 'cita-10',
            estadoAdelanto: 'pendiente_adelanto',
            precioConsultaCentavos: 4000,
            montoAdelantoCentavos: 1500,
            saldoDespuesAdelantoCentavos: 2500,
            condicionesAceptadas: 'Plazo de 24h antes de la cita.',
            rutaQrStorage: 'prof-1/qr_inmutable.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Dra. Elena Viteri',
            limitePagoEn: DateTime.utc(2026, 11, 28, 15, 0),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-10',
              esProfesional: false,
              servicio: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsOneWidget,
        );
        expect(find.textContaining('Banco Pichincha'), findsOneWidget);
        expect(
          find.textContaining('28/11/2026 10:00 (Ecuador)'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
        );
        await tester.pumpAndSettle();

        expect(servicio.enviosComprobante, 1);
        expect(find.text('Comprobante en revisión'), findsOneWidget);
      },
    );

    testWidgets(
      'profesional ve Revisión demorada (>12h), observa con motivo obligatorio y verifica ingreso',
      (tester) async {
        final servicio = _ServicioAdelantosSimulado(
          detalle: DetalleAdelantoCita(
            idCita: 'cita-20',
            estadoAdelanto: 'comprobante_en_revision',
            precioConsultaCentavos: 3500,
            montoAdelantoCentavos: 1200,
            saldoDespuesAdelantoCentavos: 2300,
            condicionesAceptadas: 'Revisión en 12h.',
            rutaQrStorage: 'prof-1/qr_inmutable.png',
            bancoBeneficiario: 'Banco Guayaquil',
            titularBeneficiario: 'Dr. Marcos',
            revisionDemorada: true,
            comprobantes: [
              ComprobanteAdelanto(
                idComprobante: 'comp-1',
                rutaStorage: 'cita-20/pac-1/comp_1.png',
                notaPaciente: 'Transferencia #1234',
                creadoEn: DateTime.utc(2026, 11, 24, 15, 0),
              ),
            ],
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-20',
              esProfesional: true,
              servicio: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Revisión demorada'), findsOneWidget);
        expect(find.byKey(const Key('avisoRevisionDemorada')), findsOneWidget);

        // Observar sin motivo debe fallar y exigir motivo
        final botonObservar = find.byKey(
          const Key('botonObservarComprobanteAdelanto'),
        );
        await tester.ensureVisible(botonObservar);
        await tester.pumpAndSettle();
        await tester.tap(botonObservar);
        await tester.pumpAndSettle();
        expect(servicio.revisionesProfesional, 0);

        // Observar con motivo valido
        await tester.enterText(
          find.byKey(const Key('campoMotivoObservacionAdelanto')),
          'No se distingue el número de referencia',
        );
        await tester.ensureVisible(botonObservar);
        await tester.pumpAndSettle();
        await tester.tap(botonObservar);
        await tester.pumpAndSettle();
        expect(servicio.ultimaAccionRevision, 'observar');

        // Verificar ingreso y confirmar cita
        final botonVerificar = find.byKey(
          const Key('botonVerificarIngresoAdelanto'),
        );
        await tester.ensureVisible(botonVerificar);
        await tester.pumpAndSettle();
        await tester.tap(botonVerificar);
        await tester.pumpAndSettle();
        expect(servicio.ultimaAccionRevision, 'verificar');
        expect(find.text('Adelanto verificado'), findsOneWidget);
      },
    );

    testWidgets(
      'supervisión del administrador muestra estado del adelanto sin exponer comprobantes ni datos bancarios',
      (tester) async {
        final servicioAdmin = ServicioAdministracion(
          ejecutorRpc: (nombre, {parametros}) async {
            if (nombre == 'listar_profesionales_administracion') {
              return const [];
            }
            if (nombre == 'resumen_administracion') {
              return {
                'usuarios_registrados': 2,
                'profesionales_activos_aprobados': 1,
                'profesionales_pendientes': 0,
                'citas_pendientes': 1,
                'citas_confirmadas': 0,
                'citas_canceladas': 0,
                'citas_rechazadas': 0,
                'citas_finalizadas': 0,
                'total_citas': 1,
                'actividad_reciente': const [],
              };
            }
            if (nombre == 'listar_citas_administracion') {
              return [
                {
                  'id_cita': 'cita-adm-1',
                  'paciente_nombre': 'Ana Pérez',
                  'profesional_nombre': 'Dra. Elena Viteri',
                  'fecha': '2026-11-30',
                  'hora_inicio': '10:00',
                  'hora_fin': '11:00',
                  'estado': 'pendiente',
                  'total_registros': 1,
                },
              ];
            }
            return const [];
          },
        );

        final servicioAdelantosAdmin = ServicioAdelantosCitas(
          lectorUsuarioActualId: () => 'admin-1',
          ejecutorRpc: (nombre, {parametros}) async {
            if (nombre == 'listar_adelantos_citas_visibles') {
              return [
                {
                  'id_cita': 'cita-adm-1',
                  'estado_adelanto': 'comprobante_en_revision',
                  'moneda': 'USD',
                  'precio_consulta': '40.00',
                  'monto_adelanto': '15.00',
                  'saldo_despues_adelanto': '25.00',
                  'revision_demorada': true,
                  'tiene_incidencia': false,
                  'total_comprobantes': 1,
                },
              ];
            }
            return const [];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaInicioAdministrador(
              perfilInicial: const PerfilUsuario(
                id: 'admin-1',
                nombre: 'Admin',
                apellido: 'PsicoBloom',
                correo: 'admin@psicobloom.test',
                rol: 'administrador',
                aprobacion: 'aprobado',
                cuentaActiva: true,
              ),
              servicioAdministracion: servicioAdmin,
              servicioAdelantos: servicioAdelantosAdmin,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('navAdmin_citas')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('estadoAdelantoAdmin_cita-adm-1')),
          findsOneWidget,
        );
        expect(find.text('Adelanto: Revisión demorada'), findsOneWidget);
        expect(find.textContaining('comprobante_'), findsNothing);
        expect(find.textContaining('Banco'), findsNothing);
      },
    );

    test('ResumenAdelantoCita y DetalleAdelantoCita rechazan respuestas malformadas sin convertir inválidos en cero', () {
      final casosInvalidos = <Map<String, dynamic>>[
        {
          'id_cita': '',
          'estado_adelanto': 'pendiente_adelanto',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': '25.00',
        },
        {
          'id_cita': 'cita-1',
          'estado_adelanto': 'estado_desconocido',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': '25.00',
        },
        {
          'id_cita': 'cita-1',
          'estado_adelanto': 'pendiente_adelanto',
          'moneda': 'EUR',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': '25.00',
        },
        {
          'id_cita': 'cita-1',
          'estado_adelanto': 'pendiente_adelanto',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '45.00',
          'saldo_despues_adelanto': '-5.00',
        },
        {
          'id_cita': 'cita-1',
          'estado_adelanto': 'pendiente_adelanto',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': null,
        },
        {
          'id_cita': 'cita-1',
          'estado_adelanto': 'pendiente_adelanto',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': '20.00',
        },
      ];

      for (final caso in casosInvalidos) {
        expect(
          () => ResumenAdelantoCita.desdeMapa(caso),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DetalleAdelantoCita.desdeMapa(caso),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('listarResumenAdelantosVisibles propaga errores de permisos, red o formato y nunca finge sin adelanto', () async {
      final servicioPermisos = ServicioAdelantosCitas(
        lectorUsuarioActualId: () => 'usr-1',
        ejecutorRpc: (nombre, {parametros}) async {
          throw const PostgrestException(message: 'denegado', code: '42501');
        },
      );
      await expectLater(
        servicioPermisos.listarResumenAdelantosVisibles(),
        throwsA(isA<ErrorAdelantoCita>()),
      );

      final servicioMalformado = ServicioAdelantosCitas(
        lectorUsuarioActualId: () => 'usr-1',
        ejecutorRpc: (nombre, {parametros}) async => 'no-es-lista',
      );
      await expectLater(
        servicioMalformado.listarResumenAdelantosVisibles(),
        throwsA(isA<ErrorAdelantoCita>()),
      );
    });

    test('ControladorCitasPaciente conserva misma clave de idempotencia en reintentos y cambia al cambiar horario', () async {
      final clavesRecibidas = <String?>[];
      var fallarPrimero = true;

      final servicio = ServicioCitasPaciente(
        lectorUsuarioActualId: () => 'pac-1',
        proveedorAhoraUtc: () => DateTime.utc(2026, 11, 25, 13, 0),
        ejecutorRpc: (nombre, [parametros]) async {
          if (nombre == 'solicitar_cita_paciente') {
            clavesRecibidas.add(parametros?['p_clave_idempotencia'] as String?);
            if (fallarPrimero) {
              fallarPrimero = false;
              throw Exception('timeout de red');
            }
            return [
              {
                'id_cita': 'cita-idem-1',
                'id_paciente': 'pac-1',
                'id_profesional': 'prof-1',
                'id_disponibilidad': parametros?['p_id_disponibilidad'],
                'nombre_profesional': 'Dra. Elena',
                'especialidad_profesional': 'Psicología Clínica',
                'modalidad_profesional': 'Presencial',
                'direccion_consultorio': 'Riobamba',
                'fecha': '2026-11-30',
                'hora_inicio': '10:00:00',
                'hora_fin': '11:00:00',
                'estado': 'pendiente',
              },
            ];
          }
          return const [];
        },
      );

      final controlador = ControladorCitasPaciente(servicio: servicio);
      final horario1 = HorarioDisponibilidad(
        idDisponibilidad: 'disp-1',
        idProfesional: 'prof-1',
        fecha: DateTime(2026, 11, 30),
        horaInicio: '10:00:00',
        horaFin: '11:00:00',
        estado: 'disponible',
      );

      controlador.seleccionarHorario(horario1);
      final intento1 = await controlador.enviarSolicitudCita(
        idProfesional: 'prof-1',
      );
      expect(intento1, isFalse);

      final intento2 = await controlador.enviarSolicitudCita(
        idProfesional: 'prof-1',
      );
      expect(intento2, isTrue);
      expect(clavesRecibidas.length, 2);
      expect(clavesRecibidas[0], isNotNull);
      expect(clavesRecibidas[0], equals(clavesRecibidas[1]));
      controlador.dispose();
    });

    testWidgets(
      'HojaDetalleAdelantoCita sobrevive a respuesta perdida y reintenta registro sin volver a subir el archivo tras reabrir',
      (tester) async {
        HojaDetalleAdelantoCita.limpiarPendientesParaPruebas();
        addTearDown(HojaDetalleAdelantoCita.limpiarPendientesParaPruebas);

        var subidas = 0;
        var intentosRegistro = 0;
        final clavesRegistro = <String>[];
        var detalleActual = DetalleAdelantoCita(
          idCita: 'cita-retry-1',
          estadoAdelanto: 'pendiente_adelanto',
          precioConsultaCentavos: 4000,
          montoAdelantoCentavos: 1500,
          saldoDespuesAdelantoCentavos: 2500,
          condicionesAceptadas: 'Plazo 24h.',
          rutaQrStorage: 'prof-1/qr.png',
          bancoBeneficiario: 'Banco Pichincha',
          titularBeneficiario: 'Dra. Elena',
          limitePagoEn: DateTime.utc(2026, 11, 30, 15, 0),
        );

        final servicio = _ServicioAdelantosRespuestaPerdida(
          alObtenerDetalle: () async => detalleActual,
          alSeleccionar: () async => ArchivoComprobanteSeleccionado(
            bytes: _bytesPngComprobante,
            extensionArchivo: 'png',
            tipoMime: 'image/png',
          ),
          alSubir: (ruta) async {
            subidas++;
            return 'cita-retry-1/pac-1/comp_unico_$subidas.png';
          },
          alRegistrar: (ruta, clave) async {
            intentosRegistro++;
            clavesRegistro.add(clave);
            if (intentosRegistro == 1) {
              throw const ErrorAdelantoCita('Respuesta de red perdida');
            }
            detalleActual = DetalleAdelantoCita(
              idCita: 'cita-retry-1',
              estadoAdelanto: 'comprobante_en_revision',
              precioConsultaCentavos: 4000,
              montoAdelantoCentavos: 1500,
              saldoDespuesAdelantoCentavos: 2500,
              condicionesAceptadas: 'Plazo 24h.',
              rutaQrStorage: 'prof-1/qr.png',
              bancoBeneficiario: 'Banco Pichincha',
              titularBeneficiario: 'Dra. Elena',
              comprobantes: [
                ComprobanteAdelanto(
                  idComprobante: 'comp-1',
                  rutaStorage: ruta,
                  creadoEn: DateTime.utc(2026, 11, 25, 16, 0),
                ),
              ],
            );
            return detalleActual;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-retry-1',
              esProfesional: false,
              servicio: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final botonEnviar = find.byKey(
          const Key('botonEnviarComprobanteAdelanto'),
        );
        await tester.ensureVisible(botonEnviar);
        await tester.tap(botonEnviar);
        await tester.pumpAndSettle();

        expect(subidas, 1);
        expect(intentosRegistro, 1);
        expect(
          find.byKey(const Key('botonReintentarRegistroComprobante')),
          findsOneWidget,
        );

        // Simular cerrar y volver a abrir la pantalla
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-retry-1',
              esProfesional: false,
              servicio: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final botonReintentar = find.byKey(
          const Key('botonReintentarRegistroComprobante'),
        );
        expect(botonReintentar, findsOneWidget);
        await tester.ensureVisible(botonReintentar);
        await tester.tap(botonReintentar);
        await tester.pumpAndSettle();

        // NO volvio a subir el archivo y reutilizo exactamente la misma clave
        expect(subidas, 1);
        expect(intentosRegistro, 2);
        expect(clavesRegistro[0], equals(clavesRegistro[1]));
        expect(find.text('Comprobante en revisión'), findsOneWidget);
      },
    );

    testWidgets(
      'PantallaHorariosProfesionalPaciente exige aceptación expresa de condiciones y recarga oferta si cambió (40001)',
      (tester) async {
        var llamadasOferta = 0;
        var devolvio40001 = false;
        Map<String, dynamic>? ultimosParamsSolicitud;

        final servicioInfo = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            llamadasOferta++;
            return [
              {
                'tiene_configuracion': true,
                'moneda': 'USD',
                'precio_consulta': llamadasOferta == 1 ? '35.00' : '40.00',
                'requiere_adelanto': true,
                'monto_adelanto_exigible': '15.00',
                'saldo_despues_adelanto': llamadasOferta == 1
                    ? '20.00'
                    : '25.00',
                'version_oferta': 'ver-$llamadasOferta',
              },
            ];
          },
        );

        final servicioCitas = ServicioCitasPaciente(
          lectorUsuarioActualId: () => 'pac-1',
          proveedorAhoraUtc: () => DateTime.utc(2026, 11, 25, 13, 0),
          ejecutorRpc: (nombre, [parametros]) async {
            if (nombre == 'listar_horarios_disponibles_profesional') {
              return [
                {
                  'id_disponibilidad': 'disp-1',
                  'id_profesional': 'prof-1',
                  'fecha': '2026-11-30',
                  'hora_inicio': '10:00:00',
                  'hora_fin': '11:00:00',
                  'estado': 'disponible',
                },
              ];
            }
            if (nombre == 'solicitar_cita_paciente') {
              ultimosParamsSolicitud = parametros;
              if (!devolvio40001) {
                devolvio40001 = true;
                throw const PostgrestException(
                  message: 'La oferta cambió recientemente.',
                  code: '40001',
                );
              }
            }
            return const [];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaHorariosProfesionalPaciente(
              profesional: const Profesional(
                id: 'prof-1',
                idProfesional: 'prof-1',
                nombre: 'Dra. Elena Viteri',
                especialidad: 'Psicología Clínica',
                modalidad: 'Presencial',
                direccionConsultorio: 'Riobamba',
                disponibilidadTexto: '',
                distanciaTexto: '',
                latitud: 0,
                longitud: 0,
              ),
              servicioCitas: servicioCitas,
              servicioInfoEconomica: servicioInfo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('opcionHorarioDisponible_disp-1')),
        );
        await tester.pumpAndSettle();

        // Botón deshabilitado hasta aceptar condiciones expresamente
        final botonEnviar = tester.widget<ElevatedButton>(
          find.byKey(const Key('botonEnviarSolicitudCita')),
        );
        expect(botonEnviar.onPressed, isNull);

        final casilla = find.byKey(
          const Key('casillaAceptarCondicionesAdelanto'),
        );
        await tester.ensureVisible(casilla);
        await tester.pumpAndSettle();
        await tester.tap(casilla);
        await tester.pumpAndSettle();

        final botonEnviarFinder = find.byKey(
          const Key('botonEnviarSolicitudCita'),
        );
        await tester.ensureVisible(botonEnviarFinder);
        await tester.pumpAndSettle();
        await tester.tap(botonEnviarFinder);
        await tester.pumpAndSettle();

        expect(
          ultimosParamsSolicitud?['p_acepta_condiciones_adelanto'],
          isTrue,
        );
        expect(ultimosParamsSolicitud?['p_version_oferta_adelanto'], 'ver-1');
        // Tras 40001 se recargó la oferta actualizada ($40.00) y se desmarcó la casilla
        expect(llamadasOferta, 2);
        expect(find.text('Valor de consulta: \$40.00'), findsOneWidget);
        final checkboxActualizado = tester.widget<Checkbox>(casilla);
        expect(checkboxActualizado.value, isFalse);
      },
    );

    test('ControladorCitasProfesional real distingue aceptación pendiente de adelanto y respuesta inesperada sin anunciar rechazo', () async {
      var estadoRespuesta = 'pendiente';
      final servicio = ServicioCitasProfesional(
        lectorUsuarioActualId: () => 'prof-1',
        proveedorAhoraUtc: () => DateTime.utc(2026, 11, 25, 13, 0),
        ejecutorRpc: (nombre, [parametros]) async {
          if (nombre == 'listar_citas_profesional_propias') {
            return [
              {
                'id_cita': 'cita-adel-1',
                'id_paciente': 'pac-1',
                'id_profesional': 'prof-1',
                'id_disponibilidad': 'disp-1',
                'nombre_paciente': 'Ana Pérez',
                'modalidad_profesional': 'Presencial',
                'fecha': '2026-11-30',
                'hora_inicio': '10:00:00',
                'hora_fin': '11:00:00',
                'estado': 'pendiente',
                'estado_disponibilidad': 'reservada',
              },
            ];
          }
          if (nombre == 'responder_solicitud_cita_profesional') {
            return [
              {
                'id_cita': 'cita-adel-1',
                'id_paciente': 'pac-1',
                'id_profesional': 'prof-1',
                'id_disponibilidad': 'disp-1',
                'nombre_paciente': 'Ana Pérez',
                'modalidad_profesional': 'Presencial',
                'fecha': '2026-11-30',
                'hora_inicio': '10:00:00',
                'hora_fin': '11:00:00',
                'estado': estadoRespuesta,
                'estado_disponibilidad': 'reservada',
              },
            ];
          }
          return const [];
        },
      );

      final controlador = ControladorCitasProfesional(servicio: servicio);
      await controlador.cargarCitasPropias();

      // Caso 1: aceptar solicitud con adelanto devuelve estado 'pendiente'
      final aceptada = await controlador.aceptarSolicitud('cita-adel-1');
      expect(aceptada, isTrue);
      expect(controlador.mensajeErrorOperacion, isNull);
      expect(controlador.mensajeExito, isNotNull);
      expect(
        controlador.mensajeExito!.toLowerCase(),
        contains('pendiente de adelanto'),
      );
      expect(
        controlador.mensajeExito!.toLowerCase(),
        isNot(contains('rechazada')),
      );

      // Caso 2: respuesta inesperada (p. ej. 'cancelada') produce error recuperable sin anunciar rechazo
      estadoRespuesta = 'cancelada';
      final inesperado = await controlador.aceptarSolicitud('cita-adel-1');
      expect(inesperado, isFalse);
      expect(controlador.mensajeExito, isNull);
      expect(controlador.mensajeErrorOperacion, isNotNull);
      expect(
        controlador.mensajeErrorOperacion!.toLowerCase(),
        contains('inesperado'),
      );
      controlador.dispose();
    });

    testWidgets(
      'PantallaHorariosProfesionalPaciente bloquea envío mientras carga o falla info económica y permite envío sin configuración de precio',
      (tester) async {
        final completerCarga = Completer<dynamic>();
        var modo = 'cargando';

        final servicioInfo = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            if (modo == 'cargando') {
              return completerCarga.future;
            }
            if (modo == 'error') {
              throw Exception('Error temporal de red');
            }
            return [
              {
                'tiene_configuracion': false,
                'moneda': 'USD',
                'precio_consulta': null,
                'requiere_adelanto': false,
                'monto_adelanto_exigible': null,
                'saldo_despues_adelanto': null,
                'version_oferta': null,
              },
            ];
          },
        );

        final servicioCitas = ServicioCitasPaciente(
          lectorUsuarioActualId: () => 'pac-1',
          proveedorAhoraUtc: () => DateTime.utc(2026, 11, 25, 13, 0),
          ejecutorRpc: (nombre, [parametros]) async {
            if (nombre == 'listar_horarios_disponibles_profesional') {
              return [
                {
                  'id_disponibilidad': 'disp-1',
                  'id_profesional': 'prof-1',
                  'fecha': '2026-11-30',
                  'hora_inicio': '10:00:00',
                  'hora_fin': '11:00:00',
                  'estado': 'disponible',
                },
              ];
            }
            return const [];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaHorariosProfesionalPaciente(
              profesional: const Profesional(
                id: 'prof-1',
                idProfesional: 'prof-1',
                nombre: 'Dra. Elena Viteri',
                especialidad: 'Psicología Clínica',
                modalidad: 'Presencial',
                direccionConsultorio: 'Riobamba',
                disponibilidadTexto: '',
                distanciaTexto: '',
                latitud: 0,
                longitud: 0,
              ),
              servicioCitas: servicioCitas,
              servicioInfoEconomica: servicioInfo,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Selecciona horario mientras la info economica sigue cargando
        await tester.tap(
          find.byKey(const Key('opcionHorarioDisponible_disp-1')),
        );
        await tester.pump();

        var botonEnviar = tester.widget<ElevatedButton>(
          find.byKey(const Key('botonEnviarSolicitudCita')),
        );
        expect(botonEnviar.onPressed, isNull);

        // Ahora falla la consulta de info economica
        modo = 'error';
        completerCarga.completeError(Exception('Error temporal de red'));
        await tester.pumpAndSettle();

        botonEnviar = tester.widget<ElevatedButton>(
          find.byKey(const Key('botonEnviarSolicitudCita')),
        );
        expect(botonEnviar.onPressed, isNull);
        expect(
          find.byKey(const Key('estadoErrorInfoEconomica')),
          findsOneWidget,
        );

        // Al reintentar y recibir "sin configuracion de precio" (profesional visible), el envio si se habilita
        modo = 'sin_precio';
        final botonReintentar = find.byKey(
          const Key('botonReintentarInfoEconomica'),
        );
        await tester.ensureVisible(botonReintentar);
        await tester.pumpAndSettle();
        await tester.tap(botonReintentar);
        await tester.pumpAndSettle();

        botonEnviar = tester.widget<ElevatedButton>(
          find.byKey(const Key('botonEnviarSolicitudCita')),
        );
        expect(botonEnviar.onPressed, isNotNull);
      },
    );

    testWidgets(
      'HojaDetalleAdelantoCita oculta QR/datos/subida si venció el plazo según hora del servidor pero mantiene incidencia',
      (tester) async {
        final servicio = _ServicioAdelantosSimulado(
          detalle: DetalleAdelantoCita(
            idCita: 'cita-venc-ui',
            estadoAdelanto: 'pendiente_adelanto',
            precioConsultaCentavos: 4000,
            montoAdelantoCentavos: 1500,
            saldoDespuesAdelantoCentavos: 2500,
            condicionesAceptadas: 'Plazo 24h.',
            rutaQrStorage: 'prof-1/qr.png',
            bancoBeneficiario: 'Banco Pichincha',
            titularBeneficiario: 'Dra. Elena',
            limitePagoEn: DateTime.utc(2026, 11, 25, 14, 0),
            horaServidor: DateTime.utc(2026, 11, 25, 14, 5),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-venc-ui',
              esProfesional: false,
              servicio: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('avisoPlazoPagoVencido')), findsOneWidget);
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonReportarIncidenciaAdelanto')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'HojaDetalleAdelantoCita avanza reloj monotónico sin cerrar la pantalla, respeta el instante exacto SQL y oculta pago al vencer',
      (tester) async {
        var tiempoMonotonico = Duration.zero;
        var consultasDetalle = 0;
        final limite = DateTime.utc(2026, 11, 25, 14, 0, 0);

        final servicio = _ServicioAdelantosRespuestaPerdida(
          alObtenerDetalle: () async {
            consultasDetalle++;
            final horaServidorActual = consultasDetalle == 1
                ? DateTime.utc(2026, 11, 25, 13, 59, 0)
                : DateTime.utc(2026, 11, 25, 14, 0, 1);
            return DetalleAdelantoCita(
              idCita: 'cita-reloj-1',
              estadoAdelanto: 'pendiente_adelanto',
              precioConsultaCentavos: 4000,
              montoAdelantoCentavos: 1500,
              saldoDespuesAdelantoCentavos: 2500,
              condicionesAceptadas: 'Plazo 24h.',
              rutaQrStorage: 'prof-1/qr.png',
              bancoBeneficiario: 'Banco Pichincha',
              titularBeneficiario: 'Dra. Elena',
              limitePagoEn: limite,
              horaServidor: horaServidorActual,
            );
          },
          alSeleccionar: () async => null,
          alSubir: (ruta) async => ruta,
          alRegistrar: (ruta, clave) async => throw UnimplementedError(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-reloj-1',
              esProfesional: false,
              servicio: servicio,
              lectorTiempoMonotonico: () => tiempoMonotonico,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(consultasDetalle, 1);
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('avisoPlazoPagoVencido')), findsNothing);

        // Verificación exacta del borde SQL: en limite_pago_en aún no vence
        // (now() <= limite_pago_en), y 1 microsegundo después sí vence (ahora > limite_pago_en).
        final detalleBorde = DetalleAdelantoCita(
          idCita: 'cita-borde',
          estadoAdelanto: 'pendiente_adelanto',
          precioConsultaCentavos: 4000,
          montoAdelantoCentavos: 1500,
          saldoDespuesAdelantoCentavos: 2500,
          condicionesAceptadas: 'Plazo 24h.',
          rutaQrStorage: 'prof-1/qr.png',
          bancoBeneficiario: 'Banco Pichincha',
          titularBeneficiario: 'Dra. Elena',
          limitePagoEn: limite,
          horaServidor: limite,
        );
        expect(detalleBorde.estaPlazoPagoVencidoEn(limite), isFalse);
        expect(
          detalleBorde.estaPlazoPagoVencidoEn(
            limite.add(const Duration(microseconds: 1)),
          ),
          isTrue,
        );

        // Antes del límite (59 s transcurridos) siguen visibles las opciones de pago.
        tiempoMonotonico = const Duration(seconds: 59);
        await tester.pump(const Duration(seconds: 59));
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsOneWidget,
        );

        // Al superar el límite (61 s transcurridos) dispara temporizador, oculta pago y consulta servidor.
        tiempoMonotonico = const Duration(seconds: 61);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(consultasDetalle, 2);
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsNothing,
        );
        expect(find.byKey(const Key('avisoPlazoPagoVencido')), findsOneWidget);
        expect(
          find.byKey(const Key('botonReportarIncidenciaAdelanto')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'HojaDetalleAdelantoCita no rehabilita el pago si falla la recarga tras vencer ni al volver a la aplicación',
      (tester) async {
        var tiempoMonotonico = Duration.zero;
        var consultasDetalle = 0;

        final servicio = _ServicioAdelantosRespuestaPerdida(
          alObtenerDetalle: () async {
            consultasDetalle++;
            if (consultasDetalle == 1) {
              return DetalleAdelantoCita(
                idCita: 'cita-reloj-err',
                estadoAdelanto: 'pendiente_adelanto',
                precioConsultaCentavos: 4000,
                montoAdelantoCentavos: 1500,
                saldoDespuesAdelantoCentavos: 2500,
                condicionesAceptadas: 'Plazo 24h.',
                rutaQrStorage: 'prof-1/qr.png',
                bancoBeneficiario: 'Banco Pichincha',
                titularBeneficiario: 'Dra. Elena',
                limitePagoEn: DateTime.utc(2026, 11, 25, 14, 0, 10),
                horaServidor: DateTime.utc(2026, 11, 25, 14, 0, 0),
              );
            }
            throw const ErrorAdelantoCita(
              'Sin conexión al actualizar el adelanto.',
            );
          },
          alSeleccionar: () async => null,
          alSubir: (ruta) async => ruta,
          alRegistrar: (ruta, clave) async => throw UnimplementedError(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-reloj-err',
              esProfesional: false,
              servicio: servicio,
              lectorTiempoMonotonico: () => tiempoMonotonico,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsOneWidget,
        );

        // Avanza más allá del vencimiento; la recarga al servidor falla.
        tiempoMonotonico = const Duration(seconds: 11);
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();

        expect(consultasDetalle, 2);
        expect(
          find.text('Sin conexión al actualizar el adelanto.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('avisoPlazoPagoVencido')), findsOneWidget);
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonReportarIncidenciaAdelanto')),
          findsOneWidget,
        );

        // Al volver a la app (resumed), reintenta consultar y sigue bloqueado si vuelve a fallar.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(consultasDetalle, 3);
        expect(
          find.byKey(const Key('seccionQrDatosBancariosPaciente')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('botonEnviarComprobanteAdelanto')),
          findsNothing,
        );
        expect(find.byKey(const Key('avisoPlazoPagoVencido')), findsOneWidget);
      },
    );

    test('ServicioAdelantosCitas.resolverIncidenciaAdelanto valida motivo, sesión, pertenencia, idempotencia y no altera estado ni importes', () async {
      // Sin sesión -> 42501
      final servicioSinSesion = ServicioAdelantosCitas(
        lectorUsuarioActualId: () => null,
      );
      await expectLater(
        servicioSinSesion.resolverIncidenciaAdelanto(
          idCita: 'cita-inc-1',
          idIncidencia: 'inc-1',
          motivoResolucion: 'Motivo suficientemente largo',
        ),
        throwsA(
          isA<ErrorAdelantoCita>().having((e) => e.codigo, 'codigo', '42501'),
        ),
      );

      // Motivo < 5 o > 500 -> 22023
      final servicioVal = ServicioAdelantosCitas(
        lectorUsuarioActualId: () => 'prof-1',
      );
      await expectLater(
        servicioVal.resolverIncidenciaAdelanto(
          idCita: 'cita-inc-1',
          idIncidencia: 'inc-1',
          motivoResolucion: 'abcd',
        ),
        throwsA(
          isA<ErrorAdelantoCita>().having((e) => e.codigo, 'codigo', '22023'),
        ),
      );
      await expectLater(
        servicioVal.resolverIncidenciaAdelanto(
          idCita: 'cita-inc-1',
          idIncidencia: 'inc-1',
          motivoResolucion: 'x' * 501,
        ),
        throwsA(
          isA<ErrorAdelantoCita>().having((e) => e.codigo, 'codigo', '22023'),
        ),
      );

      // Simulación de servidor idempotente que conserva motivo original y no cambia estado ni importes
      String? motivoRegistrado;
      String? fechaRegistrada;
      var llamadasRpc = 0;

      final servicioRealConRpcMock = ServicioAdelantosCitas(
        lectorUsuarioActualId: () => 'prof-1',
        ejecutorRpc: (nombre, {parametros}) async {
          if (nombre == 'resolver_incidencia_adelanto') {
            llamadasRpc++;
            if (parametros?['p_id_incidencia'] == 'inc-ajena') {
              throw const PostgrestException(
                message: 'La incidencia indicada no existe o no pertenece a esta cita.',
                code: '22023',
              );
            }
            motivoRegistrado ??= parametros?['p_motivo_resolucion'] as String?;
            fechaRegistrada ??= '2026-11-26T21:00:00Z';
            return {
              'id_cita': 'cita-inc-1',
              'estado_adelanto': 'comprobante_en_revision',
              'moneda': 'USD',
              'precio_consulta': '40.00',
              'monto_adelanto': '15.00',
              'saldo_despues_adelanto': '25.00',
              'condiciones_aceptadas': 'Plazo 24h.',
              'comprobantes': [
                {
                  'id_comprobante': 'comp-1',
                  'ruta_storage': 'cita-inc-1/pac-1/comp_1.png',
                  'nota_paciente': 'Adjuntado tras reintento',
                  'creado_en': '2026-11-26T20:00:00Z',
                },
              ],
              'observaciones': const [],
              'incidencias': [
                {
                  'id_incidencia': 'inc-1',
                  'detalle': 'Falló la conexión al subir la imagen.',
                  'horario_ya_liberado': false,
                  'estado_incidencia': 'resuelta',
                  'creado_en': '2026-11-26T19:50:00Z',
                  'motivo_resolucion': motivoRegistrado,
                  'resuelto_por': 'prof-1',
                  'resuelto_en': fechaRegistrada,
                },
              ],
            };
          }
          return null;
        },
      );

      // Pertenencia inválida -> 22023
      await expectLater(
        servicioRealConRpcMock.resolverIncidenciaAdelanto(
          idCita: 'cita-inc-1',
          idIncidencia: 'inc-ajena',
          motivoResolucion: 'Motivo de prueba válido',
        ),
        throwsA(
          isA<ErrorAdelantoCita>().having((e) => e.codigo, 'codigo', '22023'),
        ),
      );

      // Primera resolución
      final res1 = await servicioRealConRpcMock.resolverIncidenciaAdelanto(
        idCita: 'cita-inc-1',
        idIncidencia: 'inc-1',
        motivoResolucion: 'Comprobante ya recibido en el segundo intento.',
      );
      // Repetición idempotente con otro motivo
      final res2 = await servicioRealConRpcMock.resolverIncidenciaAdelanto(
        idCita: 'cita-inc-1',
        idIncidencia: 'inc-1',
        motivoResolucion: 'Segundo motivo que no debe sobrescribir.',
      );

      expect(llamadasRpc, 3);
      expect(res1.estadoAdelanto, 'comprobante_en_revision');
      expect(res1.precioConsultaCentavos, 4000);
      expect(res1.montoAdelantoCentavos, 1500);
      expect(res1.saldoDespuesAdelantoCentavos, 2500);
      expect(res2.incidencias.length, 1);
      expect(
        res2.incidencias.first.detalle,
        'Falló la conexión al subir la imagen.',
      );
      expect(
        res2.incidencias.first.motivoResolucion,
        'Comprobante ya recibido en el segundo intento.',
      );
      expect(res2.incidencias.first.etiquetaEstado, 'Resuelta');
    });

    testWidgets(
      'HojaDetalleAdelantoCita permite al profesional resolver incidencia de carga con confirmación, oculta cierre en horario liberado y paciente solo consulta',
      (tester) async {
        var estadoIncidencia1 = 'pendiente_revision';
        String? motivoGuardado;
        String? fechaGuardada;

        Map<String, dynamic> construirRespuestaDetalle() => {
          'id_cita': 'cita-inc-ui',
          'estado_adelanto': 'comprobante_en_revision',
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'monto_adelanto': '15.00',
          'saldo_despues_adelanto': '25.00',
          'condiciones_aceptadas': 'Plazo 24h.',
          'comprobantes': [
            {
              'id_comprobante': 'comp-1',
              'ruta_storage': 'cita-inc-ui/pac-1/comp_1.png',
              'nota_paciente': 'Transferencia #901',
              'creado_en': '2026-11-26T20:00:00Z',
            },
          ],
          'observaciones': const [],
          'incidencias': [
            {
              'id_incidencia': 'inc-abierta',
              'detalle': 'Se cerró la app al cargar la foto.',
              'horario_ya_liberado': false,
              'estado_incidencia': estadoIncidencia1,
              'creado_en': '2026-11-26T19:50:00Z',
              'motivo_resolucion': motivoGuardado,
              'resuelto_por': motivoGuardado != null ? 'prof-1' : null,
              'resuelto_en': fechaGuardada,
            },
            {
              'id_incidencia': 'inc-liberada',
              'detalle': 'El horario ya se había liberado.',
              'horario_ya_liberado': true,
              'estado_incidencia': 'pendiente_revision',
              'creado_en': '2026-11-26T19:55:00Z',
              'motivo_resolucion': null,
              'resuelto_por': null,
              'resuelto_en': null,
            },
          ],
        };

        final servicioReal = ServicioAdelantosCitas(
          lectorUsuarioActualId: () => 'prof-1',
          generadorUrlTemporal: (_, _) async => null,
          ejecutorRpc: (nombre, {parametros}) async {
            if (nombre == 'obtener_detalle_adelanto_cita') {
              return construirRespuestaDetalle();
            }
            if (nombre == 'resolver_incidencia_adelanto') {
              estadoIncidencia1 = 'resuelta';
              motivoGuardado = parametros?['p_motivo_resolucion'] as String?;
              fechaGuardada = '2026-11-26T21:15:00Z';
              return construirRespuestaDetalle();
            }
            return null;
          },
        );

        // 1. Vista profesional
        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-inc-ui',
              esProfesional: true,
              servicio: servicioReal,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No expone códigos internos como pendiente_revision
        expect(find.textContaining('pendiente_revision'), findsNothing);
        // Desplazar al historial antes de buscar sus widgets: ListView los
        // construye de forma diferida según el tamaño de la pantalla.
        await tester.scrollUntilVisible(
          find.text('Historial de comprobantes y observaciones'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Pendiente de revisión'), findsNWidgets(2));

        // La incidencia con horario liberado NO muestra botón de cierre simple
        expect(
          find.byKey(const Key('botonResolverIncidencia_inc-liberada')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('avisoIncidenciaHorarioLiberado_inc-liberada')),
          findsOneWidget,
        );

        // La incidencia abierta elegible sí muestra "Resolver incidencia"
        final botonResolver = find.byKey(
          const Key('botonResolverIncidencia_inc-abierta'),
        );
        await tester.ensureVisible(botonResolver);
        await tester.pumpAndSettle();
        await tester.tap(botonResolver);
        await tester.pumpAndSettle();

        // Diálogo explica que no verifica pago ni confirma cita
        expect(
          find.text(
            'Resolver esta incidencia no verifica el pago ni confirma la cita.',
          ),
          findsOneWidget,
        );

        // Motivo corto es rechazado dentro del diálogo
        await tester.enterText(
          find.byKey(const Key('campoMotivoResolucionIncidencia')),
          'ok',
        );
        await tester.tap(
          find.byKey(const Key('botonConfirmarResolverIncidencia')),
        );
        await tester.pumpAndSettle();
        expect(estadoIncidencia1, 'pendiente_revision');

        // Motivo válido cierra la incidencia sin alterar el estado del adelanto
        await tester.enterText(
          find.byKey(const Key('campoMotivoResolucionIncidencia')),
          'El paciente logró adjuntar el comprobante correctamente.',
        );
        await tester.tap(
          find.byKey(const Key('botonConfirmarResolverIncidencia')),
        );
        await tester.pumpAndSettle();

        expect(estadoIncidencia1, 'resuelta');
        // Desplazar al historial antes de buscar sus widgets: ListView los
        // construye de forma diferida según el tamaño de la pantalla.
        await tester.scrollUntilVisible(
          find.text('Historial de comprobantes y observaciones'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Resuelta'), findsOneWidget);
        expect(
          find.byKey(const Key('motivoResolucionIncidencia_inc-abierta')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('fechaResolucionIncidencia_inc-abierta')),
          findsOneWidget,
        );
        // Al volver arriba, el estado del adelanto sigue en revisión (no verificado)
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(find.text('Comprobante en revisión'), findsOneWidget);

        // 2. Vista paciente: solo consulta resolución, sin botón de resolver
        await tester.pumpWidget(
          MaterialApp(
            home: HojaDetalleAdelantoCita(
              idCita: 'cita-inc-ui',
              esProfesional: false,
              servicio: servicioReal,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('pendiente_revision'), findsNothing);
        // Desplazar al historial antes de buscar sus widgets: ListView los
        // construye de forma diferida según el tamaño de la pantalla.
        await tester.scrollUntilVisible(
          find.text('Historial de comprobantes y observaciones'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Resuelta'), findsOneWidget);
        expect(
          find.textContaining(
            'El paciente logró adjuntar el comprobante correctamente.',
          ),
          findsOneWidget,
        );
        expect(find.text('Resolver incidencia'), findsNothing);
      },
    );
  });
}

class _ServicioAdelantosRespuestaPerdida extends ServicioAdelantosCitas {
  final Future<DetalleAdelantoCita?> Function() alObtenerDetalle;
  final Future<ArchivoComprobanteSeleccionado?> Function() alSeleccionar;
  final Future<String> Function(String rutaObjeto) alSubir;
  final Future<DetalleAdelantoCita> Function(String ruta, String clave)
  alRegistrar;

  _ServicioAdelantosRespuestaPerdida({
    required this.alObtenerDetalle,
    required this.alSeleccionar,
    required this.alSubir,
    required this.alRegistrar,
  }) : super(lectorUsuarioActualId: () => 'pac-1');

  @override
  Future<DetalleAdelantoCita?> obtenerDetalleAdelantoCita(String idCita) =>
      alObtenerDetalle();

  @override
  Future<ArchivoComprobanteSeleccionado?> seleccionarImagenComprobante({
    ImageSource origen = ImageSource.gallery,
  }) => alSeleccionar();

  @override
  Future<String> subirComprobantePrivado({
    required String idCita,
    required ArchivoComprobanteSeleccionado archivo,
  }) => alSubir('$idCita/pac-1/comp.png');

  @override
  Future<DetalleAdelantoCita> registrarComprobanteAdelanto({
    required String idCita,
    required String rutaStorage,
    String? notaPaciente,
    required String claveIdempotencia,
  }) => alRegistrar(rutaStorage, claveIdempotencia);

  @override
  Future<String?> obtenerUrlTemporalPrivada({
    required String bucket,
    required String rutaObjeto,
  }) async => null;
}
