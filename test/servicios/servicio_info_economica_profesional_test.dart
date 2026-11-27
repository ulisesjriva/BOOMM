import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/modelos/info_economica_profesional.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_info_economica_profesional.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_horarios_profesional_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';

Profesional _crearProfesional({required String id, required String nombre}) {
  return Profesional(
    id: id,
    idProfesional: id,
    nombre: nombre,
    especialidad: 'Psicología Clínica',
    especialidades: const ['Psicología Clínica'],
    modalidad: 'Presencial',
    descripcion: 'Atención psicológica integral.',
    servicios: 'Terapia individual',
    disponibilidadTexto: 'Horarios disponibles',
    distanciaTexto: 'Riobamba',
    direccionConsultorio: 'Av. Daniel León Borja',
    latitud: -1.6635,
    longitud: -78.6546,
    tieneUbicacion: true,
  );
}

void main() {
  group('InfoEconomicaProfesional - representación monetaria exacta', () {
    test(
      'calcula saldo exacto en centavos enteros sin imprecisiones de double',
      () {
        // 19.99 - 10.09 en double produce 9.899999999999999; en centavos enteros es exactamente 990 ($9.90)
        final info = InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': true,
          'moneda': 'USD',
          'precio_consulta': '19.99',
          'requiere_adelanto': true,
          'monto_adelanto_exigible': '10.09',
          'saldo_despues_adelanto': '9.90',
        });

        expect(info.profesionalVisible, isTrue);
        expect(info.tienePrecioConfigurado, isTrue);
        expect(info.exigeAdelanto, isTrue);
        expect(info.precioConsultaCentavos, 1999);
        expect(info.montoAdelantoExigibleCentavos, 1009);
        expect(info.saldoDespuesAdelantoCentavos, 990);
        expect(info.textoPrecioConsulta, '\$19.99');
        expect(info.textoMontoAdelanto, '\$10.09');
        expect(info.textoSaldoDespuesAdelanto, '\$9.90');
      },
    );

    test('cuando requiere_adelanto es falso fuerza adelanto exigible a 0 aunque exista monto previo', () {
      final info = InfoEconomicaProfesional.desdeMapa({
        'tiene_configuracion': true,
        'moneda': 'USD',
        'precio_consulta': '42.50',
        'requiere_adelanto': false,
        'monto_adelanto_exigible': '15.00',
        'saldo_despues_adelanto': '42.50',
      });

      expect(info.tienePrecioConfigurado, isTrue);
      expect(info.exigeAdelanto, isFalse);
      expect(info.montoAdelantoExigibleCentavos, 0);
      expect(info.saldoDespuesAdelantoCentavos, 4250);
      expect(info.textoPrecioConsulta, '\$42.50');
      expect(info.textoSaldoDespuesAdelanto, '\$42.50');
    });

    test(
      'sin configuración devuelve resultado explícito sin asumir gratuidad',
      () {
        final info = InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': false,
          'moneda': 'USD',
          'precio_consulta': null,
          'requiere_adelanto': false,
          'monto_adelanto_exigible': null,
          'saldo_despues_adelanto': null,
        });

        expect(info.profesionalVisible, isTrue);
        expect(info.tieneConfiguracion, isFalse);
        expect(info.tienePrecioConfigurado, isFalse);
        expect(info.precioConsultaCentavos, isNull);
        expect(info.textoPrecioConsulta, isNull);
      },
    );

    test('requiere_adelanto activo con monto faltante, cero o superior al precio lanza FormatException', () {
      for (final montoInvalido in [null, '0.00', '-5.00', '50.00', 'abc']) {
        expect(
          () => InfoEconomicaProfesional.desdeMapa({
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '40.00',
            'requiere_adelanto': true,
            'monto_adelanto_exigible': montoInvalido,
            'saldo_despues_adelanto': '40.00',
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('saldo_despues_adelanto faltante o discrepante lanza FormatException sin sustituirlo', () {
      expect(
        () => InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': true,
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'requiere_adelanto': true,
          'monto_adelanto_exigible': '15.00',
          'saldo_despues_adelanto': '20.00',
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': true,
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'requiere_adelanto': true,
          'monto_adelanto_exigible': '15.00',
          'saldo_despues_adelanto': null,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'moneda distinta de USD o importe fuera de rango lanza FormatException',
      () {
        for (final monedaInvalida in ['EUR', 'COP', '', null]) {
          expect(
            () => InfoEconomicaProfesional.desdeMapa({
              'tiene_configuracion': true,
              'moneda': monedaInvalida,
              'precio_consulta': '40.00',
              'requiere_adelanto': false,
              'monto_adelanto_exigible': '0.00',
              'saldo_despues_adelanto': '40.00',
            }),
            throwsA(isA<FormatException>()),
          );
        }

        expect(
          () => InfoEconomicaProfesional.desdeMapa({
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '100000000.00',
            'requiere_adelanto': false,
            'monto_adelanto_exigible': '0.00',
            'saldo_despues_adelanto': '100000000.00',
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('requiere_adelanto activo con monto faltante, cero o superior al precio lanza FormatException', () {
      for (final montoInvalido in [null, '0.00', '-5.00', '50.00', 'abc']) {
        expect(
          () => InfoEconomicaProfesional.desdeMapa({
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '40.00',
            'requiere_adelanto': true,
            'monto_adelanto_exigible': montoInvalido,
            'saldo_despues_adelanto': '40.00',
          }),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('saldo_despues_adelanto faltante o discrepante lanza FormatException sin sustituirlo', () {
      expect(
        () => InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': true,
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'requiere_adelanto': true,
          'monto_adelanto_exigible': '15.00',
          'saldo_despues_adelanto': '20.00',
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => InfoEconomicaProfesional.desdeMapa({
          'tiene_configuracion': true,
          'moneda': 'USD',
          'precio_consulta': '40.00',
          'requiere_adelanto': true,
          'monto_adelanto_exigible': '15.00',
          'saldo_despues_adelanto': null,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'moneda distinta de USD o importe fuera de rango lanza FormatException',
      () {
        for (final monedaInvalida in ['EUR', 'COP', '', null]) {
          expect(
            () => InfoEconomicaProfesional.desdeMapa({
              'tiene_configuracion': true,
              'moneda': monedaInvalida,
              'precio_consulta': '40.00',
              'requiere_adelanto': false,
              'monto_adelanto_exigible': '0.00',
              'saldo_despues_adelanto': '40.00',
            }),
            throwsA(isA<FormatException>()),
          );
        }

        expect(
          () => InfoEconomicaProfesional.desdeMapa({
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '100000000.00',
            'requiere_adelanto': false,
            'monto_adelanto_exigible': '0.00',
            'saldo_despues_adelanto': '100000000.00',
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group(
    'ServicioInfoEconomicaProfesional y ControladorInfoEconomicaProfesional',
    () {
      test('respuesta malformada o inconsistente produce error recuperable y no profesional no disponible', () async {
        final respuestasMalformadas = <dynamic>[
          null,
          'texto inesperado',
          123,
          [123],
          [
            {'tiene_configuracion': true, 'moneda': 'EUR'},
          ],
          [
            {
              'tiene_configuracion': true,
              'moneda': 'USD',
              'precio_consulta': '40.00',
              'requiere_adelanto': true,
              'monto_adelanto_exigible': null,
              'saldo_despues_adelanto': '40.00',
            },
          ],
          [
            {'tiene_configuracion': false, 'moneda': 'USD'},
            {'tiene_configuracion': false, 'moneda': 'USD'},
          ],
        ];

        for (final respuesta in respuestasMalformadas) {
          final servicio = ServicioInfoEconomicaProfesional(
            lectorUsuarioActualId: () => 'pac-1',
            ejecutorRpc: (nombre, {parametros}) async => respuesta,
          );

          await expectLater(
            servicio.obtenerInfoEconomicaProfesional(idProfesional: 'prof-1'),
            throwsA(isA<ErrorInfoEconomicaProfesional>()),
          );
        }
      });
      test('respuesta malformada o inconsistente produce error recuperable y no profesional no disponible', () async {
        final respuestasMalformadas = <dynamic>[
          null,
          'texto inesperado',
          123,
          [123],
          [
            {'tiene_configuracion': true, 'moneda': 'EUR'},
          ],
          [
            {
              'tiene_configuracion': true,
              'moneda': 'USD',
              'precio_consulta': '40.00',
              'requiere_adelanto': true,
              'monto_adelanto_exigible': null,
              'saldo_despues_adelanto': '40.00',
            },
          ],
          [
            {'tiene_configuracion': false, 'moneda': 'USD'},
            {'tiene_configuracion': false, 'moneda': 'USD'},
          ],
        ];

        for (final respuesta in respuestasMalformadas) {
          final servicio = ServicioInfoEconomicaProfesional(
            lectorUsuarioActualId: () => 'pac-1',
            ejecutorRpc: (nombre, {parametros}) async => respuesta,
          );

          await expectLater(
            servicio.obtenerInfoEconomicaProfesional(idProfesional: 'prof-1'),
            throwsA(isA<ErrorInfoEconomicaProfesional>()),
          );
        }
      });
      test('profesional no visible o no autorizado devuelve noDisponible o rechaza con 42501', () async {
        final servicioNoVisible = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async => const [],
        );

        final info = await servicioNoVisible.obtenerInfoEconomicaProfesional(
          idProfesional: 'prof-pendiente',
        );
        expect(info.profesionalVisible, isFalse);
        expect(info.tienePrecioConfigurado, isFalse);

        final servicioSinSesion = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => null,
          ejecutorRpc: (nombre, {parametros}) async => const [],
        );
        await expectLater(
          servicioSinSesion.obtenerInfoEconomicaProfesional(
            idProfesional: 'prof-1',
          ),
          throwsA(isA<ErrorInfoEconomicaProfesional>()),
        );

        final servicioNoAutorizado = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'usr-inactivo',
          ejecutorRpc: (nombre, {parametros}) async {
            throw const PostgrestException(
              message: 'permission denied',
              code: '42501',
            );
          },
        );
        await expectLater(
          servicioNoAutorizado.obtenerInfoEconomicaProfesional(
            idProfesional: 'prof-1',
          ),
          throwsA(
            isA<ErrorInfoEconomicaProfesional>().having(
              (e) => e.mensaje.toLowerCase(),
              'sin jerga técnica',
              allOf(isNot(contains('supabase')), isNot(contains('sql'))),
            ),
          ),
        );
      });

      test('maneja error de consulta y reintento exitoso sin conservar valores previos', () async {
        var intento = 0;
        final servicio = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            intento++;
            if (intento == 1) {
              throw Exception('fallo temporal de red');
            }
            return [
              {
                'tiene_configuracion': true,
                'moneda': 'USD',
                'precio_consulta': '35.00',
                'requiere_adelanto': true,
                'monto_adelanto_exigible': '15.00',
                'saldo_despues_adelanto': '20.00',
              },
            ];
          },
        );

        final controlador = ControladorInfoEconomicaProfesional(
          servicio: servicio,
        );

        await controlador.cargar('prof-1');
        expect(controlador.mensajeError, isNotNull);
        expect(controlador.info, isNull);

        await controlador.reintentar();
        expect(controlador.mensajeError, isNull);
        expect(controlador.info?.textoPrecioConsulta, '\$35.00');
        expect(controlador.info?.textoMontoAdelanto, '\$15.00');
        expect(controlador.info?.textoSaldoDespuesAdelanto, '\$20.00');
        controlador.dispose();
      });

      test('cambio entre profesionales descarta respuestas tardías y nunca mezcla importes', () async {
        final completerProfA = Completer<dynamic>();
        final completerProfB = Completer<dynamic>();

        final servicio = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) {
            final id = parametros?['p_id_profesional'];
            if (id == 'prof-A') return completerProfA.future;
            return completerProfB.future;
          },
        );

        final controlador = ControladorInfoEconomicaProfesional(
          servicio: servicio,
        );

        final cargaA = controlador.cargar('prof-A');
        final cargaB = controlador.cargar('prof-B');

        // Primero responde B
        completerProfB.complete([
          {
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '50.00',
            'requiere_adelanto': false,
            'monto_adelanto_exigible': '0.00',
            'saldo_despues_adelanto': '50.00',
          },
        ]);
        await cargaB;
        expect(controlador.info?.textoPrecioConsulta, '\$50.00');

        // Luego llega la respuesta tardía de A: debe descartarse
        completerProfA.complete([
          {
            'tiene_configuracion': true,
            'moneda': 'USD',
            'precio_consulta': '25.00',
            'requiere_adelanto': true,
            'monto_adelanto_exigible': '10.00',
            'saldo_despues_adelanto': '15.00',
          },
        ]);
        await cargaA;

        expect(controlador.idProfesionalActual, 'prof-B');
        expect(controlador.info?.textoPrecioConsulta, '\$50.00');
        expect(controlador.info?.exigeAdelanto, isFalse);
        controlador.dispose();
      });
    },
  );

  group('UI - Perfil público y resumen previo de solicitud de cita', () {
    testWidgets(
      'PantallaPerfilPublicoProfesional muestra adelanto activo, cambia de profesional sin mezclar y no expone datos bancarios',
      (tester) async {
        final profConAdelanto = _crearProfesional(
          id: 'prof-1',
          nombre: 'Dra. Elena Viteri',
        );
        final profSinConfig = _crearProfesional(
          id: 'prof-2',
          nombre: 'Dr. Carlos Mena',
        );

        final servicioInfo = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            final id = parametros?['p_id_profesional'];
            if (id == 'prof-1') {
              return [
                {
                  'tiene_configuracion': true,
                  'moneda': 'USD',
                  'precio_consulta': '40.25',
                  'requiere_adelanto': true,
                  'monto_adelanto_exigible': '15.50',
                  'saldo_despues_adelanto': '24.75',
                  // Aunque el backend nunca los envia, validamos que la UI jamas los muestre
                  'ruta_qr_storage': 'prof-1/qr_privado.png',
                  'banco_beneficiario': 'Banco Secreto',
                  'titular_beneficiario': 'Titular Privado',
                  'numero_cuenta_referencia': '2200998877',
                },
              ];
            }
            return [
              {
                'tiene_configuracion': false,
                'moneda': 'USD',
                'precio_consulta': null,
                'requiere_adelanto': false,
                'monto_adelanto_exigible': null,
                'saldo_despues_adelanto': null,
              },
            ];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaPerfilPublicoProfesional(
              profesional: profConAdelanto,
              mostrarMapaInteractivo: false,
              servicioInfoEconomica: servicioInfo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Valor de consulta: \$40.25'), findsOneWidget);
        expect(find.text('Adelanto: \$15.50'), findsOneWidget);
        expect(
          find.text('Saldo después del adelanto: \$24.75'),
          findsOneWidget,
        );
        // Confirmar que no se exponen datos bancarios, rutas privadas ni botones de pago
        expect(find.textContaining('Banco Secreto'), findsNothing);
        expect(find.textContaining('Titular Privado'), findsNothing);
        expect(find.textContaining('2200998877'), findsNothing);
        expect(find.textContaining('qr_privado.png'), findsNothing);
        expect(find.textContaining('Pagar'), findsNothing);
        expect(find.textContaining('comprobante'), findsNothing);

        // Cambiar al segundo profesional sin configuración: no conserva los importes de prof-1
        await tester.pumpWidget(
          MaterialApp(
            home: PantallaPerfilPublicoProfesional(
              profesional: profSinConfig,
              mostrarMapaInteractivo: false,
              servicioInfoEconomica: servicioInfo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Valor de consulta: \$40.25'), findsNothing);
        expect(find.text('Adelanto: \$15.50'), findsNothing);
        expect(
          find.text('Precio por confirmar con el profesional'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PantallaPerfilPublicoProfesional muestra error y permite reintentar',
      (tester) async {
        var fallar = true;
        final servicioInfo = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            if (fallar) {
              throw Exception('error temporal');
            }
            return [
              {
                'tiene_configuracion': true,
                'moneda': 'USD',
                'precio_consulta': '30.00',
                'requiere_adelanto': false,
                'monto_adelanto_exigible': '0.00',
                'saldo_despues_adelanto': '30.00',
              },
            ];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaPerfilPublicoProfesional(
              profesional: _crearProfesional(
                id: 'prof-1',
                nombre: 'Dra. Elena Viteri',
              ),
              mostrarMapaInteractivo: false,
              servicioInfoEconomica: servicioInfo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('estadoErrorInfoEconomica')),
          findsOneWidget,
        );

        fallar = false;
        await tester.tap(find.byKey(const Key('botonReintentarInfoEconomica')));
        await tester.pumpAndSettle();

        expect(find.text('Valor de consulta: \$30.00'), findsOneWidget);
        expect(
          find.text('Este profesional no requiere adelanto'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PantallaHorariosProfesionalPaciente muestra resumen económico y aviso informativo antes de enviar solicitud',
      (tester) async {
        final servicioCitas = ServicioCitasPaciente(
          lectorUsuarioActualId: () => 'pac-1',
          proveedorAhoraUtc: () => DateTime.utc(2026, 11, 25, 13, 0),
          ejecutorRpc: (nombreFuncion, [parametros]) async {
            if (nombreFuncion == 'listar_horarios_disponibles_profesional') {
              return [
                {
                  'id_disponibilidad': 'disp-1',
                  'id_profesional': 'prof-1',
                  'fecha': '2026-11-26',
                  'hora_inicio': '10:00:00',
                  'hora_fin': '11:00:00',
                  'estado': 'disponible',
                },
              ];
            }
            return const [];
          },
        );

        final servicioInfo = ServicioInfoEconomicaProfesional(
          lectorUsuarioActualId: () => 'pac-1',
          ejecutorRpc: (nombre, {parametros}) async {
            return [
              {
                'tiene_configuracion': true,
                'moneda': 'USD',
                'precio_consulta': '35.00',
                'requiere_adelanto': true,
                'monto_adelanto_exigible': '12.50',
                'saldo_despues_adelanto': '22.50',
              },
            ];
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PantallaHorariosProfesionalPaciente(
              profesional: _crearProfesional(
                id: 'prof-1',
                nombre: 'Dra. Elena Viteri',
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

        expect(find.byKey(const Key('resumenSolicitudCita')), findsOneWidget);
        expect(find.text('Valor de consulta: \$35.00'), findsOneWidget);
        expect(find.text('Adelanto: \$12.50'), findsOneWidget);
        expect(
          find.text('Saldo después del adelanto: \$22.50'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('avisoCondicionesAdelantoSolicitud')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('casillaAceptarCondicionesAdelanto')),
          findsOneWidget,
        );
        expect(
          find.textContaining('24 horas antes de la cita'),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.byKey(const Key('botonEnviarSolicitudCita')),
          findsOneWidget,
        );
      },
    );
  });
}
