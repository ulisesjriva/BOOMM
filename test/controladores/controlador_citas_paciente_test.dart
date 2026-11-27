import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_mis_citas_paciente.dart';
import 'package:boom/modulos/paciente/vistas/pantalla_perfil_publico_profesional.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Simulador en memoria del contrato RPC de `08_solicitud_citas_paciente.sql`.
/// Distingue explícitamente entre id_usuario (auth.uid), id_paciente e id_profesional,
/// aplica validación de estado activo, bloqueo de intervalo al reservar, reversión
/// atómica ante fallos y aislamiento de citas por paciente.
class _BackendCitasFalso {
  _BackendCitasFalso({required this.ahoraUtc});

  DateTime ahoraUtc;
  bool migracionAplicada = true;
  bool forzarFalloAlActualizarDisponibilidad = false;
  Duration latenciaRpc = Duration.zero;

  final Map<String, bool> cuentasActivasPorUsuario = <String, bool>{
    'usr-pac-1': true,
    'usr-pac-2': true,
    'usr-pac-inactivo': false,
  };

  final Map<String, String> idPacientePorIdUsuario = <String, String>{
    'usr-pac-1': 'pac-distinto-101',
    'usr-pac-2': 'pac-distinto-202',
    'usr-pac-inactivo': 'pac-distinto-303',
  };

  final Map<String, Map<String, dynamic>> profesionalesPorId =
      <String, Map<String, dynamic>>{
        'prof-aprobado-1': <String, dynamic>{
          'id_profesional': 'prof-aprobado-1',
          'id_usuario': 'usr-prof-1',
          'nombre_profesional': 'Dra. Elena Viteri',
          'especialidad_profesional': 'Psicología Clínica',
          'modalidad_profesional': 'Presencial',
          'direccion_consultorio': 'Av. Daniel León Borja, Riobamba',
          'publicable': true,
        },
        'prof-pendiente-2': <String, dynamic>{
          'id_profesional': 'prof-pendiente-2',
          'id_usuario': 'usr-prof-2',
          'nombre_profesional': 'Dr. Marco León',
          'especialidad_profesional': 'Psicoterapia',
          'modalidad_profesional': 'Virtual',
          'direccion_consultorio': '',
          'publicable': false,
        },
      };

  final List<Map<String, dynamic>> filasDisponibilidad =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> filasCitas = <Map<String, dynamic>>[];
  int _secuenciaCita = 1;
  int llamadasListarCitasPropias = 0;

  ServicioCitasPaciente crearServicioParaUsuario(String? idUsuario) {
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

  String _resolverIdPacientePropioActivo(String? idUsuario) {
    if (idUsuario == null || idUsuario.trim().isEmpty) {
      throw const PostgrestException(
        message: 'Debes iniciar sesión como paciente activo para realizar esta operación.',
        code: '42501',
      );
    }
    final activa = cuentasActivasPorUsuario[idUsuario] ?? false;
    if (!activa) {
      throw const PostgrestException(
        message: 'Debes iniciar sesión como paciente activo para realizar esta operación.',
        code: '42501',
      );
    }
    final idPac = idPacientePorIdUsuario[idUsuario];
    if (idPac == null) {
      throw const PostgrestException(
        message: 'No se encontró un perfil de paciente activo para tu cuenta.',
        code: 'P0002',
      );
    }
    return idPac;
  }

  Future<dynamic> ejecutarRpcComoUsuario({
    required String? idUsuario,
    required String nombreFuncion,
    Map<String, dynamic>? parametros,
  }) async {
    if (latenciaRpc > Duration.zero) {
      await Future<void>.delayed(latenciaRpc);
    }

    if (!migracionAplicada) {
      throw PostgrestException(
        message:
            'Could not find the function public.$nombreFuncion in the schema cache',
        code: 'PGRST202',
      );
    }

    final idPac = _resolverIdPacientePropioActivo(idUsuario);
    final params = parametros ?? const <String, dynamic>{};

    switch (nombreFuncion) {
      case 'listar_horarios_disponibles_profesional':
        final idProfesional = (params['p_id_profesional'] ?? '')
            .toString()
            .trim();
        final prof = profesionalesPorId[idProfesional];
        if (prof == null || prof['publicable'] != true) {
          throw const PostgrestException(
            message: 'El profesional seleccionado no se encuentra disponible para agendar citas.',
            code: '42501',
          );
        }

        final disponibles = filasDisponibilidad.where((fila) {
          if (fila['id_profesional'] != idProfesional) {
            return false;
          }
          if (fila['estado'] != 'disponible') {
            return false;
          }
          final idDisp = fila['id_disponibilidad'] as String;
          final tieneCitaActiva = filasCitas.any(
            (c) =>
                c['id_disponibilidad'] == idDisp &&
                (c['estado'] == 'pendiente' || c['estado'] == 'confirmada'),
          );
          if (tieneCitaActiva) {
            return false;
          }
          final horario = HorarioDisponibilidad.desdeMapa(fila);
          return horario.esFuturoEnEcuador(referenciaUtc: ahoraUtc);
        }).toList();

        disponibles.sort((a, b) {
          final cmpFecha = (a['fecha'] as String).compareTo(
            b['fecha'] as String,
          );
          if (cmpFecha != 0) {
            return cmpFecha;
          }
          return (a['hora_inicio'] as String).compareTo(
            b['hora_inicio'] as String,
          );
        });

        return disponibles
            .map((fila) => Map<String, dynamic>.from(fila))
            .toList();

      case 'solicitar_cita_paciente':
        final idProfesional = (params['p_id_profesional'] ?? '')
            .toString()
            .trim();
        final idDisponibilidad = (params['p_id_disponibilidad'] ?? '')
            .toString()
            .trim();

        final prof = profesionalesPorId[idProfesional];
        if (prof == null || prof['publicable'] != true) {
          throw const PostgrestException(
            message: 'El profesional seleccionado no se encuentra disponible para agendar citas.',
            code: '42501',
          );
        }

        final indiceDisp = filasDisponibilidad.indexWhere(
          (f) => f['id_disponibilidad'] == idDisponibilidad,
        );
        if (indiceDisp < 0) {
          throw const PostgrestException(
            message: 'El horario seleccionado no existe.',
            code: 'P0002',
          );
        }

        final filaDisp = filasDisponibilidad[indiceDisp];
        if (filaDisp['id_profesional'] != idProfesional) {
          throw const PostgrestException(
            message:
                'El horario seleccionado no pertenece al profesional indicado.',
            code: '22023',
          );
        }

        final horario = HorarioDisponibilidad.desdeMapa(filaDisp);
        if (!horario.esFuturoEnEcuador(referenciaUtc: ahoraUtc)) {
          throw const PostgrestException(
            message: 'No se puede solicitar una cita en una fecha u hora que ya pasó (hora de Ecuador continental).',
            code: '22023',
          );
        }

        final duplicadaMismoPaciente = filasCitas.any(
          (c) =>
              c['id_disponibilidad'] == idDisponibilidad &&
              c['id_paciente'] == idPac &&
              (c['estado'] == 'pendiente' || c['estado'] == 'confirmada'),
        );
        if (duplicadaMismoPaciente) {
          throw const PostgrestException(
            message: 'Ya enviaste una solicitud para este horario. Puedes revisarla en Mis citas.',
            code: '23505',
          );
        }

        final ocupadaPorOtro = filasCitas.any(
          (c) =>
              c['id_disponibilidad'] == idDisponibilidad &&
              (c['estado'] == 'pendiente' || c['estado'] == 'confirmada'),
        );
        if (ocupadaPorOtro || filaDisp['estado'] == 'reservada') {
          throw const PostgrestException(
            message: 'Este horario acaba de ser reservado por otro paciente. Selecciona otro horario disponible.',
            code: '23P01',
          );
        }

        if (filaDisp['estado'] != 'disponible') {
          throw const PostgrestException(
            message: 'Este horario ya no está disponible porque fue bloqueado por el profesional.',
            code: '23P01',
          );
        }

        // Simulacion de transaccion atomica con reversion completa en caso de error
        final respaldoDisp = Map<String, dynamic>.from(filaDisp);
        final nuevaCita = <String, dynamic>{
          'id_cita': 'cita-${_secuenciaCita++}',
          'id_paciente': idPac,
          'id_profesional': idProfesional,
          'id_disponibilidad': idDisponibilidad,
          'nombre_profesional': prof['nombre_profesional'],
          'especialidad_profesional': prof['especialidad_profesional'],
          'modalidad_profesional': prof['modalidad_profesional'],
          'direccion_consultorio': prof['direccion_consultorio'],
          'fecha': filaDisp['fecha'],
          'hora_inicio': filaDisp['hora_inicio'],
          'hora_fin': filaDisp['hora_fin'],
          'estado': 'pendiente',
          'fecha_solicitud': ahoraUtc.toIso8601String(),
        };

        filasCitas.add(nuevaCita);
        try {
          if (forzarFalloAlActualizarDisponibilidad) {
            throw const PostgrestException(
              message: 'Fallo forzado al actualizar Disponibilidad dentro de la transacción.',
              code: 'XX000',
            );
          }
          filasDisponibilidad[indiceDisp] = <String, dynamic>{
            ...filaDisp,
            'estado': 'reservada',
            'tiene_cita_vinculada': true,
          };
        } catch (error) {
          filasCitas.removeWhere((c) => c['id_cita'] == nuevaCita['id_cita']);
          filasDisponibilidad[indiceDisp] = respaldoDisp;
          rethrow;
        }

        return <Map<String, dynamic>>[Map<String, dynamic>.from(nuevaCita)];

      case 'listar_citas_paciente_propias':
        llamadasListarCitasPropias++;
        final propias = filasCitas
            .where((c) => c['id_paciente'] == idPac)
            .map((c) => Map<String, dynamic>.from(c))
            .toList();
        propias.sort((a, b) {
          final cmpFecha = (a['fecha'] as String).compareTo(
            b['fecha'] as String,
          );
          if (cmpFecha != 0) {
            return cmpFecha;
          }
          return (a['hora_inicio'] as String).compareTo(
            b['hora_inicio'] as String,
          );
        });
        return propias;

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

  late _BackendCitasFalso backend;

  setUp(() {
    backend = _BackendCitasFalso(ahoraUtc: referenciaUtcBase);
    backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'id_disponibilidad': 'disp-futura-tarde',
        'id_profesional': 'prof-aprobado-1',
        'fecha': '2026-11-16',
        'hora_inicio': '14:00',
        'hora_fin': '15:15',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-futura-manana',
        'id_profesional': 'prof-aprobado-1',
        'fecha': '2026-11-16',
        'hora_inicio': '09:00',
        'hora_fin': '09:45',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-bloqueada',
        'id_profesional': 'prof-aprobado-1',
        'fecha': '2026-11-16',
        'hora_inicio': '11:00',
        'hora_fin': '12:00',
        'estado': 'bloqueada',
        'tiene_cita_vinculada': false,
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-reservada',
        'id_profesional': 'prof-aprobado-1',
        'fecha': '2026-11-16',
        'hora_inicio': '16:00',
        'hora_fin': '17:00',
        'estado': 'reservada',
        'tiene_cita_vinculada': true,
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-pasada-hoy',
        'id_profesional': 'prof-aprobado-1',
        'fecha': '2026-11-15',
        'hora_inicio': '09:30',
        'hora_fin': '10:30',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      },
      <String, dynamic>{
        'id_disponibilidad': 'disp-prof-pendiente',
        'id_profesional': 'prof-pendiente-2',
        'fecha': '2026-11-16',
        'hora_inicio': '10:00',
        'hora_fin': '11:00',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      },
    ]);
  });

  group('I3-02 ControladorCitasPaciente y ServicioCitasPaciente', () {
    test('consulta solo horarios disponibles futuros de profesional aprobado ordenados por fecha y hora en America/Guayaquil', () async {
      final controlador = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );

      await controlador.cargarHorariosDisponibles('prof-aprobado-1');

      expect(controlador.mensajeErrorHorarios, isNull);
      expect(controlador.horariosDisponibles.length, 2);
      expect(
        controlador.horariosDisponibles[0].idDisponibilidad,
        'disp-futura-manana',
      );
      expect(controlador.horariosDisponibles[0].duracionMinutos, 45);
      expect(
        controlador.horariosDisponibles[1].idDisponibilidad,
        'disp-futura-tarde',
      );
      expect(controlador.horariosDisponibles[1].duracionMinutos, 75);
    });

    test(
      'excluye y rechaza consulta de horarios de profesionales no aprobados',
      () async {
        final controlador = ControladorCitasPaciente(
          servicio: backend.crearServicioParaUsuario('usr-pac-1'),
        );

        await controlador.cargarHorariosDisponibles('prof-pendiente-2');

        expect(controlador.horariosDisponibles, isEmpty);
        expect(
          controlador.mensajeErrorHorarios,
          contains('no se encuentra disponible'),
        );
      },
    );

    test('envia solicitud valida con estado pendiente, marca disponibilidad como reservada y lista solo citas propias', () async {
      final controladorPac1 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );

      await controladorPac1.cargarHorariosDisponibles('prof-aprobado-1');
      final horarioElegido = controladorPac1.horariosDisponibles.first;
      controladorPac1.seleccionarHorario(horarioElegido);

      final exito = await controladorPac1.enviarSolicitudCita(
        idProfesional: 'prof-aprobado-1',
      );

      expect(exito, isTrue);
      expect(controladorPac1.ultimaCitaSolicitada, isNotNull);
      expect(controladorPac1.ultimaCitaSolicitada!.estado, 'pendiente');
      expect(controladorPac1.ultimaCitaSolicitada!.esPendiente, isTrue);
      expect(
        controladorPac1.ultimaCitaSolicitada!.etiquetaEstado,
        'Pendiente de confirmación',
      );
      expect(
        controladorPac1.ultimaCitaSolicitada!.idPaciente,
        'pac-distinto-101',
      );

      // El horario reservado ya no aparece como disponible
      expect(
        controladorPac1.horariosDisponibles.any(
          (h) => h.idDisponibilidad == horarioElegido.idDisponibilidad,
        ),
        isFalse,
      );

      final filaDisp = backend.filasDisponibilidad.firstWhere(
        (f) => f['id_disponibilidad'] == horarioElegido.idDisponibilidad,
      );
      expect(filaDisp['estado'], 'reservada');

      // Persistencia en Mis citas del paciente 1
      await controladorPac1.cargarCitasPropias();
      expect(controladorPac1.citasPropias.length, 1);
      expect(
        controladorPac1.citasPropias.first.idDisponibilidad,
        horarioElegido.idDisponibilidad,
      );

      // El paciente 2 no ve las citas del paciente 1
      final controladorPac2 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-2'),
      );
      await controladorPac2.cargarCitasPropias();
      expect(controladorPac2.citasPropias, isEmpty);
    });

    test('rechaza cuentas inactivas, falta de sesion y no simula exito si falta la migracion 08', () async {
      final controladorInactivo = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-inactivo'),
      );
      await controladorInactivo.cargarHorariosDisponibles('prof-aprobado-1');
      expect(
        controladorInactivo.mensajeErrorHorarios,
        contains('paciente activo'),
      );

      final controladorSinSesion = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario(null),
      );
      await controladorSinSesion.cargarCitasPropias();
      expect(
        controladorSinSesion.mensajeErrorCitasPropias,
        contains('iniciar sesión como paciente'),
      );

      backend.migracionAplicada = false;
      final controladorSinMigracion = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );
      await controladorSinMigracion.cargarHorariosDisponibles(
        'prof-aprobado-1',
      );
      expect(
        controladorSinMigracion.mensajeErrorHorarios,
        contains('08_solicitud_citas_paciente.sql'),
      );
      expect(backend.filasCitas, isEmpty);
    });

    test('si otro paciente ocupa el horario mientras se ve el resumen, informa lo ocurrido y refresca automaticamente la lista', () async {
      final controladorPac1 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );
      final controladorPac2 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-2'),
      );

      await controladorPac1.cargarHorariosDisponibles('prof-aprobado-1');
      await controladorPac2.cargarHorariosDisponibles('prof-aprobado-1');

      final horarioCompartido = controladorPac1.horariosDisponibles.first;
      controladorPac1.seleccionarHorario(horarioCompartido);
      controladorPac2.seleccionarHorario(horarioCompartido);

      // Paciente 2 envia primero la solicitud y ocupa el horario
      final exitoPac2 = await controladorPac2.enviarSolicitudCita(
        idProfesional: 'prof-aprobado-1',
      );
      expect(exitoPac2, isTrue);

      // Paciente 1 intenta enviar desde su resumen abierto
      final exitoPac1 = await controladorPac1.enviarSolicitudCita(
        idProfesional: 'prof-aprobado-1',
      );
      expect(exitoPac1, isFalse);
      expect(
        controladorPac1.mensajeErrorSolicitud,
        contains('reservado por otro paciente'),
      );
      expect(controladorPac1.horarioSeleccionado, isNull);
      // La lista del paciente 1 se actualizo automaticamente y ya solo queda el otro horario
      expect(controladorPac1.horariosDisponibles.length, 1);
      expect(
        controladorPac1.horariosDisponibles.first.idDisponibilidad,
        'disp-futura-tarde',
      );
    });

    test('revierte completamente la operacion si ocurre un error al actualizar la disponibilidad', () async {
      final controlador = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );
      await controlador.cargarHorariosDisponibles('prof-aprobado-1');
      final horario = controlador.horariosDisponibles.first;
      controlador.seleccionarHorario(horario);

      backend.forzarFalloAlActualizarDisponibilidad = true;
      final exito = await controlador.enviarSolicitudCita(
        idProfesional: 'prof-aprobado-1',
      );

      expect(exito, isFalse);
      expect(controlador.ultimaCitaSolicitada, isNull);
      expect(backend.filasCitas, isEmpty);

      final filaDisp = backend.filasDisponibilidad.firstWhere(
        (f) => f['id_disponibilidad'] == horario.idDisponibilidad,
      );
      expect(filaDisp['estado'], 'disponible');
    });

    test('evita solicitudes duplicadas por doble toque y coordina dos solicitudes simultaneas en el simulador', () async {
      backend.latenciaRpc = const Duration(milliseconds: 20);
      final controladorPac1 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-1'),
      );
      await controladorPac1.cargarHorariosDisponibles('prof-aprobado-1');
      final horario = controladorPac1.horariosDisponibles.first;
      controladorPac1.seleccionarHorario(horario);

      // Doble toque sobre el mismo controlador
      final respuestasDobleToque = await Future.wait<bool>(<Future<bool>>[
        controladorPac1.enviarSolicitudCita(idProfesional: 'prof-aprobado-1'),
        controladorPac1.enviarSolicitudCita(idProfesional: 'prof-aprobado-1'),
      ]);
      expect(respuestasDobleToque.where((r) => r).length, 1);
      expect(backend.filasCitas.length, 1);

      // Dos pacientes intentando reservar simultaneamente el segundo horario
      final segundoHorario = controladorPac1.horariosDisponibles.first;
      final controladorPac2 = ControladorCitasPaciente(
        servicio: backend.crearServicioParaUsuario('usr-pac-2'),
      );
      controladorPac1.seleccionarHorario(segundoHorario);
      controladorPac2.seleccionarHorario(segundoHorario);

      final respuestasSimultaneas = await Future.wait<bool>(<Future<bool>>[
        controladorPac1.enviarSolicitudCita(idProfesional: 'prof-aprobado-1'),
        controladorPac2.enviarSolicitudCita(idProfesional: 'prof-aprobado-1'),
      ]);

      expect(respuestasSimultaneas.where((r) => r).length, 1);
      expect(respuestasSimultaneas.where((r) => !r).length, 1);
      expect(
        backend.filasCitas
            .where(
              (c) => c['id_disponibilidad'] == segundoHorario.idDisponibilidad,
            )
            .length,
        1,
      );
    });
  });

  group('I3-02 Flujo visual del paciente en widgets', () {
    testWidgets(
      'desde perfil publico abre Consultar horarios, muestra resumen, envia solicitud pendiente y navega a Mis citas',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final servicio = backend.crearServicioParaUsuario('usr-pac-1');
        const profesional = Profesional(
          id: 'usr-prof-1',
          idProfesional: 'prof-aprobado-1',
          nombre: 'Dra. Elena Viteri',
          especialidad: 'Psicología Clínica',
          especialidades: <String>['Psicología Clínica'],
          modalidad: 'Presencial',
          descripcion: 'Atención clínica integral en Riobamba.',
          servicios: 'Terapia individual',
          disponibilidadTexto: 'Consulta de perfil disponible',
          distanciaTexto: 'Av. Daniel León Borja, Riobamba',
          direccionConsultorio: 'Av. Daniel León Borja, Riobamba',
          latitud: -1.6635,
          longitud: -78.6547,
          tieneUbicacion: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaPerfilPublicoProfesional(
              profesional: profesional,
              mostrarMapaInteractivo: false,
              servicioCitas: servicio,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final botonConsultar = find.byKey(
          const Key('botonConsultarHorariosProfesional'),
        );
        expect(botonConsultar, findsOneWidget);

        await tester.tap(botonConsultar);
        await tester.pumpAndSettle();

        // Verifica que se muestran los intervalos disponibles futuros y no los bloqueados
        final opcionManana = find.byKey(
          const Key('opcionHorarioDisponible_disp-futura-manana'),
        );
        expect(opcionManana, findsOneWidget);
        expect(
          find.byKey(const Key('opcionHorarioDisponible_disp-bloqueada')),
          findsNothing,
        );

        // Selecciona el intervalo completo 09:00 - 09:45 (45 minutos)
        await tester.tap(opcionManana);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('resumenSolicitudCita')), findsOneWidget);
        expect(find.text('09:00'), findsWidgets);
        expect(find.text('09:45'), findsWidgets);
        expect(find.text('45 min'), findsOneWidget);

        // Envia la solicitud
        await tester.tap(find.byKey(const Key('botonEnviarSolicitudCita')));
        await tester.pumpAndSettle();

        // Muestra confirmacion indicando estado pendiente (nunca confirmada)
        expect(
          find.byKey(const Key('confirmacionSolicitudEnviada')),
          findsOneWidget,
        );
        expect(find.text('Pendiente de confirmación'), findsOneWidget);

        // Abre Mis citas desde la confirmacion
        await tester.tap(
          find.byKey(const Key('botonIrAMisCitasDesdeConfirmacion')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mis citas'), findsWidgets);
        expect(
          find.byKey(const Key('tarjetaCitaPaciente_cita-1')),
          findsOneWidget,
        );
        expect(find.text('Pendiente de confirmación'), findsOneWidget);
      },
    );
  });

  group(
    'Mejora 7 - Organizacion, vencimientos, Ver 5 mas y UI de Mis citas',
    () {
      Map<String, dynamic> crearFilaCita({
        required String id,
        required String fecha,
        required String horaInicio,
        required String horaFin,
        required String estado,
        String nombreProfesional = 'Dra. Elena Viteri',
        String especialidad = 'Psicología Clínica',
        String modalidad = 'Presencial',
        String direccion = 'Av. Daniel León Borja, Riobamba',
        String? fechaSolicitudIso,
      }) {
        return <String, dynamic>{
          'id_cita': id,
          'id_paciente': 'pac-distinto-101',
          'id_profesional': 'prof-aprobado-1',
          'id_disponibilidad': 'disp-$id',
          'nombre_profesional': nombreProfesional,
          'especialidad_profesional': especialidad,
          'modalidad_profesional': modalidad,
          'direccion_consultorio': direccion,
          'fecha': fecha,
          'hora_inicio': horaInicio,
          'hora_fin': horaFin,
          'estado': estado,
          'fecha_solicitud': fechaSolicitudIso ?? '2026-11-10T15:00:00Z',
        };
      }

      test('clasifica correctamente Proximas (incluyendo en curso), Pendientes e Historial (incluyendo vencidas) en America/Guayaquil y ordena cronologicamente', () async {
        // 2026-11-16 02:30 UTC equivale a 2026-11-15 21:30 en America/Guayaquil (UTC-05:00).
        backend.ahoraUtc = DateTime.utc(2026, 11, 16, 2, 30, 0);
        backend.filasCitas.addAll(<Map<String, dynamic>>[
          // Confirmada en curso en Ecuador (21:00 - 22:00 del 15 nov), aunque en UTC ya sea 16 nov.
          crearFilaCita(
            id: 'conf-en-curso',
            fecha: '2026-11-15',
            horaInicio: '21:00',
            horaFin: '22:00',
            estado: 'confirmada',
          ),
          // Confirmada futura mas lejana
          crearFilaCita(
            id: 'conf-futura-2',
            fecha: '2026-11-20',
            horaInicio: '10:00',
            horaFin: '11:00',
            estado: 'confirmada',
          ),
          // Confirmada futura mas cercana
          crearFilaCita(
            id: 'conf-futura-1',
            fecha: '2026-11-17',
            horaInicio: '08:00',
            horaFin: '09:00',
            estado: 'confirmada',
          ),
          // Confirmada ya finalizada -> Historial (conserva estado 'confirmada', no 'completada')
          crearFilaCita(
            id: 'conf-pasada',
            fecha: '2026-11-15',
            horaInicio: '18:00',
            horaFin: '19:00',
            estado: 'confirmada',
          ),
          // Pendiente vigente (termina a las 22:00 en Ecuador)
          crearFilaCita(
            id: 'pend-vigente-1',
            fecha: '2026-11-15',
            horaInicio: '21:00',
            horaFin: '22:00',
            estado: 'pendiente',
          ),
          // Pendiente futura mas lejana
          crearFilaCita(
            id: 'pend-vigente-2',
            fecha: '2026-11-19',
            horaInicio: '15:00',
            horaFin: '16:00',
            estado: 'pendiente',
          ),
          // Pendiente vencida exactamente al minuto de cierre (21:30 == 21:30 Ecuador) -> Historial como Vencida
          crearFilaCita(
            id: 'pend-vencida-exacta',
            fecha: '2026-11-15',
            horaInicio: '20:30',
            horaFin: '21:30',
            estado: 'pendiente',
          ),
          // Rechazada futura -> Historial
          crearFilaCita(
            id: 'rechazada-reciente',
            fecha: '2026-11-18',
            horaInicio: '09:00',
            horaFin: '10:00',
            estado: 'rechazada',
          ),
          // Cancelada antigua -> Historial
          crearFilaCita(
            id: 'cancelada-antigua',
            fecha: '2026-11-10',
            horaInicio: '09:00',
            horaFin: '10:00',
            estado: 'cancelada',
          ),
        ]);

        final controlador = ControladorCitasPaciente(
          servicio: backend.crearServicioParaUsuario('usr-pac-1'),
        );
        await controlador.cargarCitasPropias();

        // Proximas: en curso + futuras, orden ascendente (mas proxima primero)
        expect(
          controlador.citasProximas.map((c) => c.idCita).toList(),
          equals(<String>['conf-en-curso', 'conf-futura-1', 'conf-futura-2']),
        );
        expect(
          controlador.citasProximas.first.estaEnCursoEnEcuador(
            referenciaUtc: backend.ahoraUtc,
          ),
          isTrue,
        );

        // Pendientes: solo vigentes (excluye vencida), orden ascendente
        expect(
          controlador.citasPendientes.map((c) => c.idCita).toList(),
          equals(<String>['pend-vigente-1', 'pend-vigente-2']),
        );

        // Historial: rechazadas, canceladas, pendientes vencidas y confirmadas finalizadas,
        // orden descendente (mas reciente a mas antigua)
        expect(
          controlador.citasHistorial.map((c) => c.idCita).toList(),
          equals(<String>[
            'rechazada-reciente',
            'pend-vencida-exacta',
            'conf-pasada',
            'cancelada-antigua',
          ]),
        );

        // La solicitud vencida conserva estado persistente 'pendiente' pero muestra etiqueta 'Vencida'
        final vencida = controlador.citasHistorial.firstWhere(
          (c) => c.idCita == 'pend-vencida-exacta',
        );
        expect(vencida.estado, equals('pendiente'));
        expect(
          vencida.etiquetaEstadoEnEcuador(referenciaUtc: backend.ahoraUtc),
          equals('Vencida'),
        );

        // La confirmada finalizada conserva etiqueta real 'Confirmada' (nunca 'Completada')
        final confirmadaPasada = controlador.citasHistorial.firstWhere(
          (c) => c.idCita == 'conf-pasada',
        );
        expect(
          confirmadaPasada.etiquetaEstadoEnEcuador(
            referenciaUtc: backend.ahoraUtc,
          ),
          equals('Confirmada'),
        );

        // Si avanza el tiempo 35 min (22:05 Ecuador), tanto conf-en-curso como pend-vigente-1
        // pasan automaticamente a Historial al recalcular sin recargar red.
        backend.ahoraUtc = DateTime.utc(2026, 11, 16, 3, 5, 0);
        final cambioDetectado = controlador.recalcularClasificacionTemporal();
        expect(cambioDetectado, isTrue);
        expect(
          controlador.citasProximas.map((c) => c.idCita).toList(),
          equals(<String>['conf-futura-1', 'conf-futura-2']),
        );
        expect(
          controlador.citasPendientes.map((c) => c.idCita).toList(),
          equals(<String>['pend-vigente-2']),
        );
        expect(
          controlador.citasHistorial.any((c) => c.idCita == 'conf-en-curso'),
          isTrue,
        );
        expect(
          controlador.citasHistorial.any((c) => c.idCita == 'pend-vigente-1'),
          isTrue,
        );
      });

      testWidgets(
        'muestra 5 citas inicialmente, carga 5 mas con Ver 5 mas sin recargar ni duplicar, muestra restante exacto y restablece a 5 al cambiar de seccion',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // 2026-11-15 10:00 Ecuador
          backend.ahoraUtc = DateTime.utc(2026, 11, 15, 15, 0, 0);
          for (var i = 1; i <= 12; i++) {
            final dia = (15 + i).toString().padLeft(2, '0');
            backend.filasCitas.add(
              crearFilaCita(
                id: 'prox-$i',
                fecha: '2026-11-$dia',
                horaInicio: '09:00',
                horaFin: '10:00',
                estado: 'confirmada',
                nombreProfesional: 'Dra. Profesional $i',
              ),
            );
          }
          backend.filasCitas.add(
            crearFilaCita(
              id: 'pend-1',
              fecha: '2026-11-18',
              horaInicio: '14:00',
              horaFin: '15:00',
              estado: 'pendiente',
            ),
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: TemaPsicobloom.obtenerTema(),
              home: PantallaMisCitasPaciente(
                servicioCitas: backend.crearServicioParaUsuario('usr-pac-1'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Encabezado limpio sin tarjeta antigua
          expect(find.text('Mis citas'), findsOneWidget);
          expect(
            find.text('Consulta y organiza tus solicitudes.'),
            findsOneWidget,
          );
          expect(find.text('Solicitudes y citas registradas'), findsNothing);

          // Inicialmente muestra exactamente 5 citas y el boton "Ver 5 más"
          expect(backend.llamadasListarCitasPropias, equals(1));
          for (var i = 1; i <= 5; i++) {
            expect(
              find.byKey(Key('tarjetaCitaPaciente_prox-$i')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_prox-6')),
            findsNothing,
          );
          expect(find.text('Ver 5 más'), findsOneWidget);

          // Pulsa "Ver 5 más" -> muestra 10 citas sin recargar red ni duplicar y ofrece "Ver 2 más"
          final botonVerMas = find.byKey(const Key('botonVerMasCitas'));
          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
          await tester.tap(botonVerMas);
          await tester.pumpAndSettle();

          expect(backend.llamadasListarCitasPropias, equals(1));
          for (var i = 1; i <= 10; i++) {
            expect(
              find.byKey(Key('tarjetaCitaPaciente_prox-$i')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_prox-11')),
            findsNothing,
          );
          expect(find.text('Ver 2 más'), findsOneWidget);

          // Pulsa "Ver 2 más" -> muestra las 12 citas y oculta el boton
          await tester.drag(find.byType(ListView), const Offset(0, -1200));
          await tester.pumpAndSettle();
          await tester.tap(botonVerMas);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('tarjetaCitaPaciente_prox-12')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('botonVerMasCitas')), findsNothing);

          // Cambiar a Pendientes y regresar a Proximas restablece el limite a 5 citas
          await tester.drag(find.byType(ListView), const Offset(0, 2000));
          await tester.pumpAndSettle();
          final pestanaPendientes = find.byKey(
            const Key('pestanaCitasPendientes'),
          );
          await tester.tap(pestanaPendientes);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_pend-1')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const Key('pestanaCitasProximas')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_prox-5')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_prox-6')),
            findsNothing,
          );
          expect(find.text('Ver 5 más'), findsOneWidget);
        },
      );

      testWidgets(
        'muestra estados vacios exactos en las tres secciones, respeta modalidad virtual/hibrida/presencial y funciona en pantalla movil Android',
        (tester) async {
          // Viewport movil Android estandar del proyecto (1080x2400 @ 2.0)
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: TemaPsicobloom.obtenerTema(),
              home: PantallaMisCitasPaciente(
                servicioCitas: backend.crearServicioParaUsuario('usr-pac-1'),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Estados vacios exactos en las 3 pestanas
          expect(find.text('No tienes citas próximas'), findsOneWidget);

          await tester.tap(find.byKey(const Key('pestanaCitasPendientes')));
          await tester.pumpAndSettle();
          expect(find.text('No tienes solicitudes pendientes'), findsOneWidget);

          await tester.tap(find.byKey(const Key('pestanaCitasHistorial')));
          await tester.pumpAndSettle();
          expect(
            find.text('Todavía no tienes historial de citas'),
            findsOneWidget,
          );

          // 2. Agrega citas con modalidades Virtual, Hibrida y vencida y pulsa actualizar
          backend.filasCitas.addAll(<Map<String, dynamic>>[
            crearFilaCita(
              id: 'virtual-en-curso',
              fecha: '2026-11-15',
              horaInicio: '09:30',
              horaFin: '10:30',
              estado: 'confirmada',
              modalidad: 'Virtual',
              direccion: 'Calle Oculta 123, Riobamba',
            ),
            crearFilaCita(
              id: 'hibrida-futura',
              fecha: '2026-11-17',
              horaInicio: '11:00',
              horaFin: '12:00',
              estado: 'confirmada',
              modalidad: 'Híbrida',
              direccion: 'Av. 10 de Agosto, Riobamba',
            ),
            crearFilaCita(
              id: 'solicitud-vencida',
              fecha: '2026-11-14',
              horaInicio: '08:00',
              horaFin: '09:00',
              estado: 'pendiente',
            ),
          ]);

          await tester.tap(find.byKey(const Key('botonActualizarMisCitas')));
          await tester.pumpAndSettle();

          // En Historial aparece la solicitud vencida con etiqueta "Vencida"
          expect(
            find.byKey(const Key('tarjetaCitaPaciente_solicitud-vencida')),
            findsOneWidget,
          );
          expect(find.text('Vencida'), findsOneWidget);

          // En Proximas: la virtual en curso muestra "Confirmada" + "En curso" y NO muestra direccion fisica
          await tester.tap(find.byKey(const Key('pestanaCitasProximas')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('insigniaCitaEnCurso_virtual-en-curso')),
            findsOneWidget,
          );
          expect(find.text('Virtual'), findsOneWidget);
          expect(find.textContaining('Calle Oculta 123'), findsNothing);
          // La hibrida identifica claramente la finalidad de la direccion del consultorio
          expect(
            find.text(
              'Consultorio (si es presencial): Av. 10 de Agosto, Riobamba',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
