import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/profesional/controladores/controlador_citas_profesional.dart';
import 'package:boom/modulos/profesional/modelos/cita_profesional.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/modulos/profesional/servicios/servicio_citas_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_inicio_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Simulador en memoria del contrato compartido entre `08_solicitud_citas_paciente.sql`
/// y `10_respuesta_citas_profesional.sql`.
/// Distingue id_usuario (auth.uid), id_profesional e id_paciente, valida rol,
/// cuenta activa, aprobacion del profesional, zona horaria America/Guayaquil,
/// reversion atomica ante fallo y conservacion historica de citas rechazadas.
class _BackendRespuestaCitasFalso {
  _BackendRespuestaCitasFalso({required this.ahoraUtc});

  DateTime ahoraUtc;
  bool migracion10Aplicada = true;
  bool forzarFalloAlActualizarDisponibilidad = false;
  Duration latenciaRpc = Duration.zero;

  final Map<String, Map<String, dynamic>> usuariosPorId =
      <String, Map<String, dynamic>>{
        'usr-prof-1': <String, dynamic>{
          'rol': 'profesional',
          'activa': true,
          'aprobacion': 'aprobado',
          'id_profesional': 'prof-distinto-101',
          'nombre_completo': 'Dra. Elena Viteri',
          'modalidad': 'Híbrida',
        },
        'usr-prof-2': <String, dynamic>{
          'rol': 'profesional',
          'activa': true,
          'aprobacion': 'aprobado',
          'id_profesional': 'prof-distinto-202',
          'nombre_completo': 'Dr. Carlos Mena',
          'modalidad': 'Presencial',
        },
        'usr-prof-inactivo': <String, dynamic>{
          'rol': 'profesional',
          'activa': false,
          'aprobacion': 'aprobado',
          'id_profesional': 'prof-distinto-303',
          'nombre_completo': 'Dr. Dario Paredes',
          'modalidad': 'Virtual',
        },
        'usr-prof-pendiente': <String, dynamic>{
          'rol': 'profesional',
          'activa': true,
          'aprobacion': 'pendiente',
          'id_profesional': 'prof-distinto-404',
          'nombre_completo': 'Dra. Sofia Lara',
          'modalidad': 'Presencial',
        },
        'usr-pac-1': <String, dynamic>{
          'rol': 'paciente',
          'activa': true,
          'id_paciente': 'pac-distinto-101',
          'nombre_completo': 'Lucia Andrade',
        },
        'usr-pac-2': <String, dynamic>{
          'rol': 'paciente',
          'activa': true,
          'id_paciente': 'pac-distinto-202',
          'nombre_completo': 'Mateo Salazar',
        },
      };

  final List<Map<String, dynamic>> filasDisponibilidad =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> filasCitas = <Map<String, dynamic>>[];
  int _secuenciaCita = 10;

  ServicioCitasProfesional crearServicioProfesional(String? idUsuario) {
    return ServicioCitasProfesional(
      lectorUsuarioActualId: () => idUsuario,
      proveedorAhoraUtc: () => ahoraUtc,
      ejecutorRpc: (nombreFuncion, [parametros]) => ejecutarRpcComoUsuario(
        idUsuario: idUsuario,
        nombreFuncion: nombreFuncion,
        parametros: parametros,
      ),
    );
  }

  ServicioCitasPaciente crearServicioPaciente(String? idUsuario) {
    return ServicioCitasPaciente(
      lectorUsuarioActualId: () => idUsuario,
      proveedorAhoraUtc: () => ahoraUtc,
      ejecutorRpc: (nombreFuncion, [parametros]) => ejecutarRpcComoUsuario(
        idUsuario: idUsuario,
        nombreFuncion: nombreFuncion,
        parametros: parametros,
      ),
    );
  }

  Map<String, dynamic> _validarProfesionalActivoYAprobado(String? idUsuario) {
    if (idUsuario == null || idUsuario.trim().isEmpty) {
      throw const PostgrestException(
        message: 'Se requiere una cuenta de profesional activa.',
        code: '42501',
      );
    }
    final cuenta = usuariosPorId[idUsuario];
    if (cuenta == null ||
        cuenta['rol'] != 'profesional' ||
        cuenta['activa'] != true) {
      throw const PostgrestException(
        message: 'Se requiere una cuenta de profesional activa para gestionar solicitudes de citas.',
        code: '42501',
      );
    }
    if (cuenta['aprobacion'] != 'aprobado') {
      throw const PostgrestException(
        message: 'Tu perfil profesional debe estar aprobado y activo para gestionar solicitudes de citas.',
        code: '42501',
      );
    }
    return cuenta;
  }

  Map<String, dynamic> _validarPacienteActivo(String? idUsuario) {
    if (idUsuario == null || idUsuario.trim().isEmpty) {
      throw const PostgrestException(
        message: 'Se requiere una cuenta de paciente activa.',
        code: '42501',
      );
    }
    final cuenta = usuariosPorId[idUsuario];
    if (cuenta == null ||
        cuenta['rol'] != 'paciente' ||
        cuenta['activa'] != true) {
      throw const PostgrestException(
        message: 'Se requiere una cuenta de paciente activa.',
        code: '42501',
      );
    }
    return cuenta;
  }

  Future<dynamic> ejecutarRpcComoUsuario({
    required String? idUsuario,
    required String nombreFuncion,
    Map<String, dynamic>? parametros,
  }) async {
    if (latenciaRpc > Duration.zero) {
      await Future<void>.delayed(latenciaRpc);
    }

    final params = parametros ?? const <String, dynamic>{};

    switch (nombreFuncion) {
      case 'listar_citas_profesional_propias':
        if (!migracion10Aplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.listar_citas_profesional_propias in the schema cache',
            code: 'PGRST202',
          );
        }
        final cuentaProf = _validarProfesionalActivoYAprobado(idUsuario);
        final idProf = cuentaProf['id_profesional'] as String;

        final propias = filasCitas
            .where((c) => c['id_profesional'] == idProf)
            .map((c) {
              final disp = filasDisponibilidad.firstWhere(
                (d) => d['id_disponibilidad'] == c['id_disponibilidad'],
              );
              return <String, dynamic>{
                ...c,
                'fecha': disp['fecha'],
                'hora_inicio': disp['hora_inicio'],
                'hora_fin': disp['hora_fin'],
                'estado_disponibilidad': disp['estado'],
                'modalidad_profesional': cuentaProf['modalidad'],
              };
            })
            .toList();

        propias.sort((a, b) {
          final cmpFecha = (a['fecha'] as String).compareTo(
            b['fecha'] as String,
          );
          if (cmpFecha != 0) return cmpFecha;
          return (a['hora_inicio'] as String).compareTo(
            b['hora_inicio'] as String,
          );
        });
        return propias;

      case 'responder_solicitud_cita_profesional':
        if (!migracion10Aplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.responder_solicitud_cita_profesional in the schema cache',
            code: 'PGRST202',
          );
        }
        final cuentaProf = _validarProfesionalActivoYAprobado(idUsuario);
        final idProf = cuentaProf['id_profesional'] as String;
        final idCita = (params['p_id_cita'] ?? '').toString().trim();
        final decision = (params['p_decision'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (decision != 'confirmada' && decision != 'rechazada') {
          throw const PostgrestException(
            message: 'La decisión indicada no es válida.',
            code: '22023',
          );
        }

        final indiceCita = filasCitas.indexWhere(
          (c) => c['id_cita'] == idCita && c['id_profesional'] == idProf,
        );
        if (indiceCita < 0) {
          throw const PostgrestException(
            message: 'La solicitud indicada no existe o no pertenece a tu perfil profesional.',
            code: '42501',
          );
        }

        final citaActual = filasCitas[indiceCita];
        final indiceDisp = filasDisponibilidad.indexWhere(
          (d) =>
              d['id_disponibilidad'] == citaActual['id_disponibilidad'] &&
              d['id_profesional'] == idProf,
        );
        if (indiceDisp < 0) {
          throw const PostgrestException(
            message: 'No se encontró el horario asociado a la solicitud.',
            code: '22023',
          );
        }

        final dispActual = filasDisponibilidad[indiceDisp];

        if (citaActual['estado'] != 'pendiente') {
          throw PostgrestException(
            message:
                'Esta solicitud ya fue respondida anteriormente (estado actual: ${citaActual['estado']}) y no puede modificarse.',
            code: '23P01',
          );
        }

        final horario = HorarioDisponibilidad.desdeMapa(dispActual);
        if (!horario.esFuturoEnEcuador(referenciaUtc: ahoraUtc)) {
          throw const PostgrestException(
            message: 'No se puede responder una solicitud cuyo intervalo ya ha comenzado (hora de Ecuador).',
            code: '22023',
          );
        }

        // Transaccion atomica con reversion completa en caso de fallo
        final respaldoCita = Map<String, dynamic>.from(citaActual);
        final respaldoDisp = Map<String, dynamic>.from(dispActual);

        try {
          if (decision == 'confirmada') {
            if (dispActual['estado'] != 'reservada') {
              throw const PostgrestException(
                message: 'El horario asociado no se encuentra reservado.',
                code: '23P01',
              );
            }
            if (forzarFalloAlActualizarDisponibilidad) {
              throw const PostgrestException(
                message: 'Fallo forzado durante la transacción de respuesta.',
                code: 'XX000',
              );
            }
            filasCitas[indiceCita] = <String, dynamic>{
              ...citaActual,
              'estado': 'confirmada',
            };
          } else {
            filasCitas[indiceCita] = <String, dynamic>{
              ...citaActual,
              'estado': 'rechazada',
            };

            if (forzarFalloAlActualizarDisponibilidad) {
              throw const PostgrestException(
                message: 'Fallo forzado al liberar disponibilidad en la transacción.',
                code: 'XX000',
              );
            }

            final existeOtraCitaActiva = filasCitas.any(
              (c) =>
                  c['id_disponibilidad'] == dispActual['id_disponibilidad'] &&
                  c['id_profesional'] == idProf &&
                  c['id_cita'] != idCita &&
                  (c['estado'] == 'pendiente' || c['estado'] == 'confirmada'),
            );

            if (!existeOtraCitaActiva) {
              filasDisponibilidad[indiceDisp] = <String, dynamic>{
                ...dispActual,
                'estado': 'disponible',
              };
            }
          }
        } catch (_) {
          filasCitas[indiceCita] = respaldoCita;
          filasDisponibilidad[indiceDisp] = respaldoDisp;
          rethrow;
        }

        final citaFinal = filasCitas[indiceCita];
        final dispFinal = filasDisponibilidad[indiceDisp];
        return <Map<String, dynamic>>[
          <String, dynamic>{
            ...citaFinal,
            'fecha': dispFinal['fecha'],
            'hora_inicio': dispFinal['hora_inicio'],
            'hora_fin': dispFinal['hora_fin'],
            'estado_disponibilidad': dispFinal['estado'],
            'modalidad_profesional': cuentaProf['modalidad'],
          },
        ];

      case 'listar_citas_paciente_propias':
        final cuentaPac = _validarPacienteActivo(idUsuario);
        final idPac = cuentaPac['id_paciente'] as String;
        return filasCitas.where((c) => c['id_paciente'] == idPac).map((c) {
          final disp = filasDisponibilidad.firstWhere(
            (d) => d['id_disponibilidad'] == c['id_disponibilidad'],
          );
          return <String, dynamic>{
            ...c,
            'nombre_profesional': 'Dra. Elena Viteri',
            'especialidad_profesional': 'Psicología Clínica',
            'modalidad_profesional': 'Híbrida',
            'direccion_consultorio': 'Av. Daniel León Borja, Riobamba',
            'fecha': disp['fecha'],
            'hora_inicio': disp['hora_inicio'],
            'hora_fin': disp['hora_fin'],
          };
        }).toList();

      case 'solicitar_cita_paciente':
        final cuentaPac = _validarPacienteActivo(idUsuario);
        final idPac = cuentaPac['id_paciente'] as String;
        final idProfesional = (params['p_id_profesional'] ?? '')
            .toString()
            .trim();
        final idDisponibilidad = (params['p_id_disponibilidad'] ?? '')
            .toString()
            .trim();

        final indiceDisp = filasDisponibilidad.indexWhere(
          (d) =>
              d['id_disponibilidad'] == idDisponibilidad &&
              d['id_profesional'] == idProfesional,
        );
        if (indiceDisp < 0) {
          throw const PostgrestException(
            message: 'Horario no encontrado.',
            code: '22023',
          );
        }
        final disp = filasDisponibilidad[indiceDisp];
        final ocupadaActiva = filasCitas.any(
          (c) =>
              c['id_disponibilidad'] == idDisponibilidad &&
              (c['estado'] == 'pendiente' || c['estado'] == 'confirmada'),
        );
        if (disp['estado'] != 'disponible' || ocupadaActiva) {
          throw const PostgrestException(
            message: 'Este horario ya está ocupado.',
            code: '23P01',
          );
        }

        final nuevaCita = <String, dynamic>{
          'id_cita': 'cita-${_secuenciaCita++}',
          'id_paciente': idPac,
          'id_profesional': idProfesional,
          'id_disponibilidad': idDisponibilidad,
          'nombre_paciente': cuentaPac['nombre_completo'],
          'estado': 'pendiente',
          'fecha_solicitud': ahoraUtc.toIso8601String(),
        };
        filasCitas.add(nuevaCita);
        filasDisponibilidad[indiceDisp] = <String, dynamic>{
          ...disp,
          'estado': 'reservada',
        };
        return <Map<String, dynamic>>[
          <String, dynamic>{
            ...nuevaCita,
            'nombre_profesional': 'Dra. Elena Viteri',
            'especialidad_profesional': 'Psicología Clínica',
            'modalidad_profesional': 'Híbrida',
            'direccion_consultorio': 'Av. Daniel León Borja, Riobamba',
            'fecha': disp['fecha'],
            'hora_inicio': disp['hora_inicio'],
            'hora_fin': disp['hora_fin'],
          },
        ];

      default:
        throw PostgrestException(
          message: 'Función no soportada: $nombreFuncion',
          code: 'PGRST202',
        );
    }
  }
}

void main() {
  // 2026-11-15 15:00:00 UTC equivale a 2026-11-15 10:00:00 en America/Guayaquil (UTC-05:00)
  final referenciaUtcBase = DateTime.utc(2026, 11, 15, 15, 0, 0);

  late _BackendRespuestaCitasFalso backend;

  setUp(() {
    backend = _BackendRespuestaCitasFalso(ahoraUtc: referenciaUtcBase);

    backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'id_disponibilidad': 'disp-1',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-16',
        'hora_inicio': '09:00',
        'hora_fin': '09:50',
        'estado': 'reservada',
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-2',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-17',
        'hora_inicio': '15:00',
        'hora_fin': '16:00',
        'estado': 'reservada',
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-pasado',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-15',
        'hora_inicio': '09:30',
        'hora_fin': '10:15',
        'estado': 'reservada',
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-ajeno',
        'id_profesional': 'prof-distinto-202',
        'fecha': '2026-11-16',
        'hora_inicio': '11:00',
        'hora_fin': '12:00',
        'estado': 'reservada',
      },
    ]);

    backend.filasCitas.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'id_cita': 'cita-1',
        'id_paciente': 'pac-distinto-101',
        'id_profesional': 'prof-distinto-101',
        'id_disponibilidad': 'disp-1',
        'nombre_paciente': 'Lucia Andrade',
        'estado': 'pendiente',
        'fecha_solicitud': '2026-11-14T12:00:00Z',
      },
      <String, dynamic>{
        'id_cita': 'cita-2',
        'id_paciente': 'pac-distinto-101',
        'id_profesional': 'prof-distinto-101',
        'id_disponibilidad': 'disp-2',
        'nombre_paciente': 'Lucia Andrade',
        'estado': 'pendiente',
        'fecha_solicitud': '2026-11-14T12:05:00Z',
      },
      <String, dynamic>{
        'id_cita': 'cita-pasada',
        'id_paciente': 'pac-distinto-101',
        'id_profesional': 'prof-distinto-101',
        'id_disponibilidad': 'disp-pasado',
        'nombre_paciente': 'Lucia Andrade',
        'estado': 'pendiente',
        'fecha_solicitud': '2026-11-13T12:00:00Z',
      },
      <String, dynamic>{
        'id_cita': 'cita-ajena',
        'id_paciente': 'pac-distinto-202',
        'id_profesional': 'prof-distinto-202',
        'id_disponibilidad': 'disp-ajeno',
        'nombre_paciente': 'Mateo Salazar',
        'estado': 'pendiente',
        'fecha_solicitud': '2026-11-14T12:10:00Z',
      },
    ]);
  });

  group('I3-03 ControladorCitasProfesional y ServicioCitasProfesional', () {
    test('consulta exclusivamente las citas propias del profesional autenticado y filtra por estado', () async {
      final controlador = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );

      await controlador.cargarCitasPropias();

      expect(controlador.mensajeErrorCarga, isNull);
      expect(controlador.citas.length, 3);
      expect(controlador.citas.any((c) => c.idCita == 'cita-ajena'), isFalse);
      expect(controlador.totalPendientes, 3);
      expect(controlador.totalConfirmadas, 0);
      expect(controlador.totalRechazadas, 0);
    });

    test('aceptar solicitud cambia la cita a confirmada, mantiene el horario reservado y actualiza Mis citas del paciente', () async {
      final controladorProf = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controladorProf.cargarCitasPropias();

      final exito = await controladorProf.aceptarSolicitud('cita-1');
      expect(exito, isTrue);
      expect(controladorProf.totalPendientes, 2);
      expect(controladorProf.totalConfirmadas, 1);

      controladorProf.cambiarFiltro(FiltroEstadoCitaProfesional.confirmadas);
      expect(controladorProf.citasFiltradas.length, 1);
      expect(controladorProf.citasFiltradas.first.idCita, 'cita-1');
      expect(controladorProf.citasFiltradas.first.esConfirmada, isTrue);

      final disp = backend.filasDisponibilidad.firstWhere(
        (d) => d['id_disponibilidad'] == 'disp-1',
      );
      expect(disp['estado'], 'reservada');

      // El paciente ve su cita confirmada al cargar o actualizar Mis citas
      final controladorPac = ControladorCitasPaciente(
        servicio: backend.crearServicioPaciente('usr-pac-1'),
      );
      await controladorPac.cargarCitasPropias();
      final citaPac = controladorPac.citasPropias.firstWhere(
        (c) => c.idCita == 'cita-1',
      );
      expect(citaPac.esConfirmada, isTrue);
      expect(citaPac.etiquetaEstado, 'Confirmada');
    });

    test('rechazar solicitud conserva la cita como rechazada, libera el horario y permite una nueva solicitud sin alterar la anterior', () async {
      final controladorProf = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controladorProf.cargarCitasPropias();

      final exito = await controladorProf.rechazarSolicitud('cita-2');
      expect(exito, isTrue);
      expect(controladorProf.totalRechazadas, 1);

      controladorProf.cambiarFiltro(FiltroEstadoCitaProfesional.rechazadas);
      expect(controladorProf.citasFiltradas.length, 1);
      expect(controladorProf.citasFiltradas.first.idCita, 'cita-2');
      expect(controladorProf.citasFiltradas.first.esRechazada, isTrue);

      final dispLiberada = backend.filasDisponibilidad.firstWhere(
        (d) => d['id_disponibilidad'] == 'disp-2',
      );
      expect(dispLiberada['estado'], 'disponible');

      // Paciente 1 ve la cita rechazada en Mis citas
      final controladorPac1 = ControladorCitasPaciente(
        servicio: backend.crearServicioPaciente('usr-pac-1'),
      );
      await controladorPac1.cargarCitasPropias();
      final citaRechazada = controladorPac1.citasPropias.firstWhere(
        (c) => c.idCita == 'cita-2',
      );
      expect(citaRechazada.esRechazada, isTrue);
      expect(citaRechazada.etiquetaEstado, 'Rechazada');

      // Paciente 2 envia una nueva solicitud sobre el horario liberado 'disp-2'
      final servicioPac2 = backend.crearServicioPaciente('usr-pac-2');
      final nuevaCita = await servicioPac2.solicitarCita(
        idProfesional: 'prof-distinto-101',
        idDisponibilidad: 'disp-2',
      );
      expect(nuevaCita.esPendiente, isTrue);

      // La cita rechazada anterior permanece intacta en el historial
      final filaHistorica = backend.filasCitas.firstWhere(
        (c) => c['id_cita'] == 'cita-2',
      );
      expect(filaHistorica['estado'], 'rechazada');
    });

    test('al rechazar no libera el horario si otra cita activa ocupa ese mismo intervalo', () async {
      // Simulamos que otra cita activa ocupa disp-2
      backend.filasCitas.add(<String, dynamic>{
        'id_cita': 'cita-activa-extra',
        'id_paciente': 'pac-distinto-202',
        'id_profesional': 'prof-distinto-101',
        'id_disponibilidad': 'disp-2',
        'nombre_paciente': 'Mateo Salazar',
        'estado': 'confirmada',
        'fecha_solicitud': '2026-11-14T13:00:00Z',
      });

      final controladorProf = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controladorProf.cargarCitasPropias();

      final exito = await controladorProf.rechazarSolicitud('cita-2');
      expect(exito, isTrue);

      final disp = backend.filasDisponibilidad.firstWhere(
        (d) => d['id_disponibilidad'] == 'disp-2',
      );
      expect(disp['estado'], 'reservada');
    });

    test('rechaza acceso ajeno, rol incorrecto, cuenta inactiva, profesional no aprobado, solicitud pasada o migracion 10 pendiente', () async {
      final servicioProf1 = backend.crearServicioProfesional('usr-prof-1');

      // Acceso ajeno
      await expectLater(
        () => servicioProf1.responderSolicitudCita(
          idCita: 'cita-ajena',
          decision: 'confirmada',
        ),
        throwsA(isA<ErrorCitasProfesional>()),
      );

      // Rol incorrecto (paciente intentando usar el servicio del profesional)
      final controladorRolPaciente = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-pac-1'),
      );
      await controladorRolPaciente.cargarCitasPropias();
      expect(
        controladorRolPaciente.mensajeErrorCarga,
        contains('profesional activa'),
      );

      // Cuenta inactiva
      final controladorInactivo = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-inactivo'),
      );
      await controladorInactivo.cargarCitasPropias();
      expect(
        controladorInactivo.mensajeErrorCarga,
        contains('profesional activa'),
      );

      // Profesional no aprobado
      final controladorPendiente = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-pendiente'),
      );
      await controladorPendiente.cargarCitasPropias();
      expect(
        controladorPendiente.mensajeErrorCarga,
        contains('aprobado y activo'),
      );

      // Solicitud cuyo intervalo ya comenzo en America/Guayaquil
      final controladorProf = ControladorCitasProfesional(
        servicio: servicioProf1,
      );
      await controladorProf.cargarCitasPropias();
      final exitoPasada = await controladorProf.aceptarSolicitud('cita-pasada');
      expect(exitoPasada, isFalse);
      expect(
        controladorProf.mensajeErrorOperacion,
        contains('ya ha comenzado'),
      );

      // Migracion 10 pendiente no simula exito
      backend.migracion10Aplicada = false;
      final controladorSinMigracion = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controladorSinMigracion.cargarCitasPropias();
      expect(
        controladorSinMigracion.mensajeErrorCarga,
        contains('10_respuesta_citas_profesional.sql'),
      );
    });

    test('revierte completamente la transaccion si falla la actualizacion de disponibilidad y protege frente a doble toque o respuestas simultaneas', () async {
      final controlador1 = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controlador1.cargarCitasPropias();

      // 1. Reversion completa si falla el ajuste de disponibilidad al rechazar
      backend.forzarFalloAlActualizarDisponibilidad = true;
      final exitoFallo = await controlador1.rechazarSolicitud('cita-2');
      expect(exitoFallo, isFalse);

      final citaTrasFallo = backend.filasCitas.firstWhere(
        (c) => c['id_cita'] == 'cita-2',
      );
      final dispTrasFallo = backend.filasDisponibilidad.firstWhere(
        (d) => d['id_disponibilidad'] == 'disp-2',
      );
      expect(citaTrasFallo['estado'], 'pendiente');
      expect(dispTrasFallo['estado'], 'reservada');

      // 2. Doble toque sobre el mismo controlador y dos respuestas simultaneas contradictorias
      backend.forzarFalloAlActualizarDisponibilidad = false;
      backend.latenciaRpc = const Duration(milliseconds: 20);

      final resultadosDobleToque = await Future.wait<bool>(<Future<bool>>[
        controlador1.aceptarSolicitud('cita-1'),
        controlador1.rechazarSolicitud('cita-1'),
      ]);
      expect(resultadosDobleToque.where((r) => r).length, 1);
      final cita1 = backend.filasCitas.firstWhere(
        (c) => c['id_cita'] == 'cita-1',
      );
      expect(cita1['estado'], 'confirmada');

      // Dos instancias separadas respondiendo simultaneamente sobre cita-2 (aceptar vs rechazar)
      final controlador2 = ControladorCitasProfesional(
        servicio: backend.crearServicioProfesional('usr-prof-1'),
      );
      await controlador2.cargarCitasPropias();

      final resultadosSimultaneos = await Future.wait<bool>(<Future<bool>>[
        controlador1.aceptarSolicitud('cita-2'),
        controlador2.rechazarSolicitud('cita-2'),
      ]);
      expect(resultadosSimultaneos.where((r) => r).length, 1);
      expect(resultadosSimultaneos.where((r) => !r).length, 1);

      // Intentar revertir una solicitud ya respondida es rechazado
      final reintentoRevertir = await controlador2.rechazarSolicitud('cita-1');
      expect(reintentoRevertir, isFalse);
      expect(
        backend.filasCitas.firstWhere(
          (c) => c['id_cita'] == 'cita-1',
        )['estado'],
        'confirmada',
      );
    });
  });

  group('I3-03 Flujo visual del profesional en widgets', () {
    testWidgets(
      'desde Inicio profesional consulta semana, abre Solicitudes pendientes, responde citas y actualiza conteos, tarjetas y navegacion',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final servicio = backend.crearServicioProfesional('usr-prof-1');
        const perfilProfesional = PerfilUsuario(
          id: 'usr-prof-1',
          nombre: 'Elena',
          apellido: 'Viteri',
          correo: 'elena@psicobloom.ec',
          rol: 'profesional',
          aprobacion: 'aprobado',
          cuentaActiva: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioProfesional(
              perfilInicial: perfilProfesional,
              servicioCitas: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Cabecera: icono original, marca PsicoBloom, campana de notificaciones y SIN boton de salir en cabecera
        expect(
          find.byKey(const Key('iconoMarcaCabeceraProfesional')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('textoMarcaCabeceraProfesional')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonNotificacionesProfesional')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonCerrarSesionProfesional')),
          findsNothing,
        );

        // Pulsar la campana muestra el aviso de proximamente y NUNCA cierra sesion
        await tester.tap(
          find.byKey(const Key('botonNotificacionesProfesional')),
        );
        await tester.pump();
        expect(
          find.text('Las notificaciones estarán disponibles próximamente'),
          findsOneWidget,
        );
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // 2. Bienvenida compacta con nombre real y sin insignia de aprobacion en Inicio
        expect(find.text('Hola, Elena 👋'), findsOneWidget);
        expect(find.text('Estas son tus citas de hoy'), findsOneWidget);
        expect(
          find.byKey(const Key('insigniaEstadoAprobacionProfesional')),
          findsNothing,
        );

        // 3. Consulta semanal de citas ("Tu semana"): abre en la fecha actual en America/Guayaquil (Domingo 15 nov 2026)
        expect(
          find.byKey(const Key('tituloTuSemanaProfesional')),
          findsOneWidget,
        );
        expect(find.text('Hoy · Domingo 15'), findsOneWidget);
        expect(
          find.byKey(const Key('estadoSinCitasDiaSeleccionado')),
          findsOneWidget,
        );
        expect(
          find.text('No tienes citas confirmadas para este día'),
          findsOneWidget,
        );

        // Las 3 citas iniciales estan pendientes, por lo que el conteo confirmado del dia es 0
        final conteoDom15 = tester.widget<Container>(
          find.byKey(const Key('conteoConfirmadasDia_2026-11-15')),
        );
        expect(
          find.descendant(
            of: find.byWidget(conteoDom15),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );

        // 4. Acceso compacto a Solicitudes pendientes con conteo real (3)
        expect(find.text('Solicitudes pendientes'), findsOneWidget);
        expect(
          find.byKey(const Key('contadorSolicitudesPendientesInicio')),
          findsOneWidget,
        );
        final botonGestionarCitas = find.byKey(
          const Key('botonIrACitasProfesional'),
        );
        expect(botonGestionarCitas, findsOneWidget);

        await tester.ensureVisible(botonGestionarCitas);
        await tester.pumpAndSettle();
        await tester.tap(botonGestionarCitas);
        await tester.pumpAndSettle();

        // Verifica que aparecen las tarjetas propias pendientes con paciente y modalidad
        expect(
          find.byKey(const Key('tarjetaCitaProfesional_cita-1')),
          findsOneWidget,
        );
        expect(find.text('Lucia Andrade'), findsWidgets);
        expect(find.text('Híbrida'), findsWidgets);

        // Pulsa Aceptar en cita-1 (2026-11-16 09:00-09:50) y confirma en el dialogo
        await tester.tap(find.byKey(const Key('botonAceptarCita_cita-1')));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar aceptación de cita'), findsOneWidget);

        await tester.tap(find.byKey(const Key('botonConfirmarAceptacionCita')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('bannerExitoCitasProfesional')),
          findsOneWidget,
        );

        // Pulsa Rechazar en cita-2 (2026-11-17) y confirma en el dialogo
        await tester.tap(find.byKey(const Key('botonRechazarCita_cita-2')));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar rechazo de solicitud'), findsOneWidget);

        await tester.tap(find.byKey(const Key('botonConfirmarRechazoCita')));
        await tester.pumpAndSettle();

        // Cambia al filtro Confirmadas
        await tester.tap(
          find.byKey(const Key('filtroCitasProfesional_confirmada')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('tarjetaCitaProfesional_cita-1')),
          findsOneWidget,
        );

        // Cambia al filtro Rechazadas
        await tester.tap(
          find.byKey(const Key('filtroCitasProfesional_rechazada')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('tarjetaCitaProfesional_cita-2')),
          findsOneWidget,
        );

        // 5. Regresa a la pestaña Inicio desde la barra inferior:
        //    - Hoy sigue siendo Domingo 15 (sin citas confirmadas hoy), pero ahora muestra el acceso compacto
        //      a la proxima cita confirmada futura (Lunes 16 nov 2026).
        await tester.tap(find.byKey(const Key('pestanaProfesional_inicio')));
        await tester.pumpAndSettle();

        expect(find.text('Hoy · Domingo 15'), findsOneWidget);
        expect(
          find.byKey(const Key('tarjetaProximaCitaConfirmada')),
          findsOneWidget,
        );
        expect(find.text('Próxima cita confirmada'), findsOneWidget);

        // 6. Avanza a la semana siguiente (16–22 noviembre 2026):
        //    - Selecciona coherentemente el lunes 16 de noviembre (primer dia con cita confirmada de esa semana).
        //    - El titulo del dia NO muestra "Hoy" porque es 16 de noviembre (muestra "Lunes, 16 de noviembre").
        //    - El conteo de Lunes 16 es 1 y el de Martes 17 (rechazada) es 0.
        await tester.tap(
          find.byKey(const Key('botonSemanaSiguienteInicioProfesional')),
        );
        await tester.pumpAndSettle();

        expect(find.text('16–22 noviembre 2026'), findsOneWidget);
        expect(find.text('Lunes, 16 de noviembre'), findsOneWidget);
        expect(find.textContaining('Hoy ·'), findsNothing);
        expect(find.text('1 cita confirmada'), findsOneWidget);

        expect(
          find.descendant(
            of: find.byKey(const Key('conteoConfirmadasDia_2026-11-16')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('conteoConfirmadasDia_2026-11-17')),
            matching: find.text('0'),
          ),
          findsOneWidget,
        );

        // Verifica la tarjeta de cita confirmada en el Lunes 16 con insignia "Proxima",
        // avatar con iniciales "LA", modalidad real "Hibrida" y acceso "Ver detalle"
        expect(
          find.byKey(const Key('tarjetaCitaConfirmadaInicio_cita-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('insigniaProximaCita_cita-1')),
          findsOneWidget,
        );
        expect(find.text('09:00–09:50'), findsOneWidget);
        expect(find.text('LA'), findsOneWidget);
        expect(find.text('Lucia Andrade'), findsOneWidget);
        expect(find.text('Híbrida'), findsOneWidget);

        final botonVerCita = find.byKey(
          const Key('botonVerProximaCitaConfirmada'),
        );
        expect(botonVerCita, findsOneWidget);

        await tester.tap(botonVerCita);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('dialogoDetalleProximaCitaProfesional')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('botonCerrarDetalleProximaCita')),
        );
        await tester.pumpAndSettle();

        // 7. Pulsar "Hoy" regresa a la semana actual y fecha de hoy (Domingo 15)
        await tester.tap(find.byKey(const Key('botonHoyInicioProfesional')));
        await tester.pumpAndSettle();
        expect(find.text('Hoy · Domingo 15'), findsOneWidget);

        // 8. En la pestaña Perfil se conserva la consulta del estado de aprobacion y el boton Cerrar sesion
        await tester.tap(find.byKey(const Key('pestanaProfesional_perfil')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('insigniaEstadoAprobacionPerfilProfesional')),
          findsOneWidget,
        );
        final botonCerrarSesionPerfil = find.byKey(
          const Key('botonCerrarSesionDesdePerfilProfesional'),
        );
        await tester.scrollUntilVisible(
          botonCerrarSesionPerfil,
          300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(botonCerrarSesionPerfil, findsOneWidget);
      },
    );

    testWidgets(
      'ordena citas confirmadas del dia, destaca Proxima solo en la futura mas cercana, soporta error/reintento y pantallas pequenas',
      (tester) async {
        // Probamos en pantalla compacta (340 px) con texto ampliado para comprobar que no hay desbordamientos
        tester.view.physicalSize = const Size(340, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // En hoy (2026-11-15, hora actual 10:00 en Ecuador):
        // - disp-pasado (09:30-10:15): cita confirmada cuyo inicio ya paso -> NO debe marcarse como Proxima
        // - disp-hoy-tarde (14:00-15:00): cita confirmada futura mas lejana
        // - disp-hoy-proxima (11:00-12:00): cita confirmada futura mas cercana -> UNICA que lleva "Proxima"
        backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
          <String, dynamic>{
            'id_disponibilidad': 'disp-hoy-tarde',
            'id_profesional': 'prof-distinto-101',
            'fecha': '2026-11-15',
            'hora_inicio': '14:00',
            'hora_fin': '15:00',
            'estado': 'reservada',
          },
          <String, dynamic>{
            'id_disponibilidad': 'disp-hoy-proxima',
            'id_profesional': 'prof-distinto-101',
            'fecha': '2026-11-15',
            'hora_inicio': '11:00',
            'hora_fin': '12:00',
            'estado': 'reservada',
          },
        ]);

        backend.filasCitas
          ..clear()
          ..addAll(<Map<String, dynamic>>[
            <String, dynamic>{
              'id_cita': 'cita-hoy-pasada',
              'id_paciente': 'pac-distinto-101',
              'id_profesional': 'prof-distinto-101',
              'id_disponibilidad': 'disp-pasado',
              'nombre_paciente': 'Lucia Andrade',
              'estado': 'confirmada',
              'fecha_solicitud': '2026-11-13T12:00:00Z',
            },
            <String, dynamic>{
              'id_cita': 'cita-hoy-tarde',
              'id_paciente': 'pac-distinto-202',
              'id_profesional': 'prof-distinto-101',
              'id_disponibilidad': 'disp-hoy-tarde',
              'nombre_paciente': 'Mateo Salazar',
              'estado': 'confirmada',
              'fecha_solicitud': '2026-11-14T10:00:00Z',
            },
            <String, dynamic>{
              'id_cita': 'cita-hoy-proxima',
              'id_paciente': 'pac-distinto-101',
              'id_profesional': 'prof-distinto-101',
              'id_disponibilidad': 'disp-hoy-proxima',
              'nombre_paciente': 'Juan Pérez',
              'estado': 'confirmada',
              'fecha_solicitud': '2026-11-14T11:00:00Z',
            },
          ]);

        // 1. Simulamos primero un fallo de carga para verificar el estado de error y el boton Reintentar
        backend.migracion10Aplicada = false;
        final servicio = backend.crearServicioProfesional('usr-prof-1');
        const perfilProfesional = PerfilUsuario(
          id: 'usr-prof-1',
          nombre: 'Sara',
          apellido: 'Altamirano',
          correo: 'sara@psicobloom.ec',
          rol: 'profesional',
          aprobacion: 'aprobado',
          cuentaActiva: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!,
            ),
            home: PantallaInicioProfesional(
              perfilInicial: perfilProfesional,
              servicioCitas: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Hola, Sara 👋'), findsOneWidget);
        expect(
          find.byKey(const Key('avatarBienvenidaProfesional')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('inicialesBienvenidaProfesional')),
          findsOneWidget,
        );
        expect(find.text('SA'), findsOneWidget);
        expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
        expect(
          find.byKey(const Key('estadoErrorCitasInicioProfesional')),
          findsOneWidget,
        );
        expect(
          find.text('No tienes citas confirmadas para este día'),
          findsNothing,
        );

        // 2. Reactivamos el backend y pulsamos Reintentar
        backend.migracion10Aplicada = true;
        final botonReintentar = find.byKey(
          const Key('botonReintentarCitasInicioProfesional'),
        );
        await tester.ensureVisible(botonReintentar);
        await tester.pumpAndSettle();
        await tester.tap(botonReintentar);
        await tester.pumpAndSettle();

        expect(find.text('3 citas confirmadas'), findsOneWidget);
        expect(
          find.byKey(const Key('insigniaProximaCita_cita-hoy-proxima')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('insigniaProximaCita_cita-hoy-pasada')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('insigniaProximaCita_cita-hoy-tarde')),
          findsNothing,
        );
        expect(find.text('Atendida'), findsNothing);

        // Comprueba orden ascendente por hora (09:30–10:15 arriba de 11:00–12:00 y 11:00–12:00 arriba de 14:00–15:00)
        final posPasada = tester.getTopLeft(find.text('09:30–10:15')).dy;
        final posProxima = tester.getTopLeft(find.text('11:00–12:00')).dy;
        final posTarde = tester.getTopLeft(find.text('14:00–15:00')).dy;
        expect(posPasada, lessThan(posProxima));
        expect(posProxima, lessThan(posTarde));
      },
    );
  });
}
