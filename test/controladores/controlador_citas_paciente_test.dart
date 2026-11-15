import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/controladores/controlador_citas_paciente.dart';
import 'package:boom/modulos/paciente/servicios/servicio_citas_paciente.dart';
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
}
