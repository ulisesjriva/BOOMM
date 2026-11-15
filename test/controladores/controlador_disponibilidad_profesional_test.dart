import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';
import 'package:boom/modulos/profesional/controladores/controlador_disponibilidad_profesional.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';
import 'package:boom/modulos/profesional/servicios/servicio_disponibilidad_profesional.dart';
import 'package:boom/modulos/profesional/vistas/pantalla_inicio_profesional.dart';
import 'package:boom/nucleo/tema/tema_psicobloom.dart';

/// Simulador en memoria del contrato RPC de `06_disponibilidad_profesional.sql`,
/// `12_eliminacion_disponibilidad_profesional.sql` y `14_agenda_semanal_profesional.sql`.
/// Permite verificar persistencia entre sesiones, validacion por id_usuario != id_profesional,
/// rechazo de cuentas inactivas, acceso ajeno, proteccion de citas/reservas, creacion por jornada,
/// dias no laborables y repeticion semanal con huella de vista previa.
class _BackendDisponibilidadFalso {
  _BackendDisponibilidadFalso({required this.ahoraUtc});

  DateTime ahoraUtc;
  String? idUsuarioAutenticado = 'usr-prof-1';
  bool migracionAplicada = true;
  bool migracionEliminacionAplicada = true;
  bool migracionAgendaSemanalAplicada = true;

  final Map<String, bool> cuentasActivasPorUsuario = <String, bool>{
    'usr-prof-1': true,
    'usr-prof-2': true,
    'usr-inactivo': false,
  };

  final Map<String, String> idProfesionalPorIdUsuario = <String, String>{
    'usr-prof-1': 'prof-distinto-101',
    'usr-prof-2': 'prof-distinto-202',
    'usr-inactivo': 'prof-distinto-303',
  };

  final List<Map<String, dynamic>> filasDisponibilidad =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> filasDiasNoLaborables =
      <Map<String, dynamic>>[];
  final Map<String, int> citasPendientesPorFecha = <String, int>{};
  final Map<String, int> citasConfirmadasPorFecha = <String, int>{};

  int _secuenciaId = 1;
  int _secuenciaDiaNoLabId = 1;

  ServicioDisponibilidadProfesional crearServicio() {
    return ServicioDisponibilidadProfesional(
      lectorUsuarioActualId: () => idUsuarioAutenticado,
      proveedorAhoraUtc: () => ahoraUtc,
      ejecutorRpc: ejecutarRpc,
    );
  }

  String _resolverIdProfesionalPropioActivo() {
    final uid = idUsuarioAutenticado;
    if (uid == null || uid.isEmpty) {
      throw const PostgrestException(
        message: 'Debes iniciar sesión para gestionar la disponibilidad.',
        code: '42501',
      );
    }
    final activa = cuentasActivasPorUsuario[uid] ?? false;
    if (!activa) {
      throw const PostgrestException(
        message:
            'Tu cuenta se encuentra inactiva. No puedes gestionar horarios.',
        code: '42501',
      );
    }
    final idProf = idProfesionalPorIdUsuario[uid];
    if (idProf == null) {
      throw const PostgrestException(
        message:
            'No se encontró un perfil profesional asociado al usuario actual.',
        code: 'P0002',
      );
    }
    return idProf;
  }

  bool _esDiaNoLaborableServidor(String idProfesional, String fechaIso) {
    return filasDiasNoLaborables.any(
      (f) => f['id_profesional'] == idProfesional && f['fecha'] == fechaIso,
    );
  }

  Future<dynamic> ejecutarRpc(
    String nombreFuncion, [
    Map<String, dynamic>? parametros,
  ]) async {
    if (!migracionAplicada) {
      throw const PostgrestException(
        message: 'Could not find the function public.listar_disponibilidad_profesional_propia in the schema cache',
        code: 'PGRST202',
      );
    }

    final idProf = _resolverIdProfesionalPropioActivo();
    final params = parametros ?? const <String, dynamic>{};

    switch (nombreFuncion) {
      case 'listar_disponibilidad_profesional_propia':
        final propias = filasDisponibilidad
            .where((f) => f['id_profesional'] == idProf)
            .map((f) => Map<String, dynamic>.from(f))
            .toList();
        return propias;

      case 'crear_disponibilidad_profesional_propia':
        final fecha = (params['p_fecha'] ?? '').toString();
        final horaInicio = (params['p_hora_inicio'] ?? '').toString();
        final horaFin = (params['p_hora_fin'] ?? '').toString();
        if (_esDiaNoLaborableServidor(idProf, fecha)) {
          throw const PostgrestException(
            message: 'La fecha seleccionada está marcada como día no laborable. Retira primero la excepción si deseas habilitar horarios.',
            code: '22023',
          );
        }
        _validarSuperposicionServidor(
          idProfesional: idProf,
          fecha: fecha,
          horaInicio: horaInicio,
          horaFin: horaFin,
        );
        final nuevaFila = <String, dynamic>{
          'id_disponibilidad': 'disp-${_secuenciaId++}',
          'id_profesional': idProf,
          'fecha': fecha,
          'hora_inicio': horaInicio,
          'hora_fin': horaFin,
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        };
        filasDisponibilidad.add(nuevaFila);
        return <Map<String, dynamic>>[Map<String, dynamic>.from(nuevaFila)];

      case 'crear_intervalos_jornada_profesional_propia':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.crear_intervalos_jornada_profesional_propia in the schema cache',
            code: 'PGRST202',
          );
        }
        final fecha = (params['p_fecha'] ?? '').toString();
        final horaInicio = (params['p_hora_inicio'] ?? '').toString();
        final horaFin = (params['p_hora_fin'] ?? '').toString();
        final duracion =
            int.tryParse((params['p_duracion_minutos'] ?? '0').toString()) ?? 0;
        final descanso =
            int.tryParse((params['p_descanso_minutos'] ?? '0').toString()) ?? 0;

        if (_esDiaNoLaborableServidor(idProf, fecha)) {
          throw const PostgrestException(
            message: 'La fecha seleccionada está marcada como día no laborable. Retira primero la excepción si deseas agregar horarios.',
            code: '22023',
          );
        }

        final propuestos = HorarioDisponibilidad.generarIntervalosJornada(
          horaInicioJornada: horaInicio,
          horaFinJornada: horaFin,
          duracionMinutos: duracion,
          descansoMinutos: descanso,
        );
        if (propuestos.isEmpty) {
          throw const PostgrestException(
            message:
                'La duración de la cita supera el rango horario seleccionado.',
            code: '22023',
          );
        }
        if (propuestos.length >
            HorarioDisponibilidad.maximoIntervalosPorOperacion) {
          throw const PostgrestException(
            message:
                'Se supera el límite máximo de 24 intervalos por operación.',
            code: '22023',
          );
        }

        // Validacion transaccional: si cualquier intervalo choca, no inserta ninguno.
        final conflictos = <String>[];
        for (final prop in propuestos) {
          final iniMin =
              HorarioDisponibilidad.convertirHoraAMinutos(prop.horaInicio) ?? 0;
          final finMin =
              HorarioDisponibilidad.convertirHoraAMinutos(prop.horaFin) ?? 0;
          final choca = filasDisponibilidad.any((fila) {
            if (fila['id_profesional'] != idProf || fila['fecha'] != fecha) {
              return false;
            }
            final fIni =
                HorarioDisponibilidad.convertirHoraAMinutos(
                  fila['hora_inicio'].toString(),
                ) ??
                0;
            final fFin =
                HorarioDisponibilidad.convertirHoraAMinutos(
                  fila['hora_fin'].toString(),
                ) ??
                0;
            return fIni < finMin && fFin > iniMin;
          });
          if (choca) {
            conflictos.add(prop.rangoCompacto);
          }
        }
        if (conflictos.isNotEmpty) {
          throw PostgrestException(
            message:
                'No se guardaron horarios porque existen intervalos en conflicto en esa fecha: ${conflictos.join(', ')}.',
            code: '23P01',
          );
        }

        final insertados = <Map<String, dynamic>>[];
        for (final prop in propuestos) {
          final nuevaFila = <String, dynamic>{
            'id_disponibilidad': 'disp-${_secuenciaId++}',
            'id_profesional': idProf,
            'fecha': fecha,
            'hora_inicio': prop.horaInicio,
            'hora_fin': prop.horaFin,
            'estado': 'disponible',
            'tiene_cita_vinculada': false,
          };
          filasDisponibilidad.add(nuevaFila);
          insertados.add(Map<String, dynamic>.from(nuevaFila));
        }
        return insertados;

      case 'actualizar_disponibilidad_profesional_propia':
        final idDisp = (params['p_id_disponibilidad'] ?? '').toString();
        final fecha = (params['p_fecha'] ?? '').toString();
        final horaInicio = (params['p_hora_inicio'] ?? '').toString();
        final horaFin = (params['p_hora_fin'] ?? '').toString();
        final indice = filasDisponibilidad.indexWhere(
          (f) => f['id_disponibilidad'] == idDisp,
        );
        if (indice < 0) {
          throw const PostgrestException(
            message: 'No se encontró el horario indicado.',
            code: 'P0002',
          );
        }
        final actual = filasDisponibilidad[indice];
        if (actual['id_profesional'] != idProf) {
          throw const PostgrestException(
            message: 'No tienes permisos para modificar el horario de otro profesional.',
            code: '42501',
          );
        }
        if (_esDiaNoLaborableServidor(idProf, actual['fecha'].toString()) ||
            _esDiaNoLaborableServidor(idProf, fecha)) {
          throw const PostgrestException(
            message:
                'La fecha seleccionada está marcada como día no laborable.',
            code: '22023',
          );
        }
        if (actual['estado'] == 'reservada' ||
            actual['tiene_cita_vinculada'] == true) {
          throw const PostgrestException(
            message: 'No se puede editar un horario reservado o vinculado a una cita.',
            code: '22023',
          );
        }
        if (actual['estado'] != 'disponible') {
          throw const PostgrestException(
            message:
                'Solo se pueden editar horarios futuros en estado disponible.',
            code: '22023',
          );
        }
        _validarSuperposicionServidor(
          idProfesional: idProf,
          fecha: fecha,
          horaInicio: horaInicio,
          horaFin: horaFin,
          idExcluir: idDisp,
        );
        actual['fecha'] = fecha;
        actual['hora_inicio'] = horaInicio;
        actual['hora_fin'] = horaFin;
        return <Map<String, dynamic>>[Map<String, dynamic>.from(actual)];

      case 'cambiar_estado_disponibilidad_profesional_propia':
        final idDisp = (params['p_id_disponibilidad'] ?? '').toString();
        final nuevoEstado = (params['p_nuevo_estado'] ?? '').toString();
        if (nuevoEstado == 'reservada') {
          throw const PostgrestException(
            message: 'El estado "reservada" está reservado para el agendamiento de citas.',
            code: '22023',
          );
        }
        final indice = filasDisponibilidad.indexWhere(
          (f) => f['id_disponibilidad'] == idDisp,
        );
        if (indice < 0) {
          throw const PostgrestException(
            message: 'No se encontró el horario indicado.',
            code: 'P0002',
          );
        }
        final actual = filasDisponibilidad[indice];
        if (actual['id_profesional'] != idProf) {
          throw const PostgrestException(
            message: 'No tienes permisos para modificar el horario de otro profesional.',
            code: '42501',
          );
        }
        if (actual['estado'] == 'reservada') {
          throw const PostgrestException(
            message: 'No se puede bloquear ni desbloquear un horario reservado o vinculado a una cita.',
            code: '22023',
          );
        }
        if (nuevoEstado == 'disponible' &&
            _esDiaNoLaborableServidor(idProf, actual['fecha'].toString())) {
          throw const PostgrestException(
            message: 'No se puede desbloquear un horario en una fecha marcada como día no laborable.',
            code: '22023',
          );
        }
        actual['estado'] = nuevoEstado;
        return <Map<String, dynamic>>[Map<String, dynamic>.from(actual)];

      case 'eliminar_disponibilidad_profesional_propia':
        if (!migracionEliminacionAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.eliminar_disponibilidad_profesional_propia in the schema cache',
            code: 'PGRST202',
          );
        }
        final idDisp = (params['p_id_disponibilidad'] ?? '').toString();
        final indice = filasDisponibilidad.indexWhere(
          (f) => f['id_disponibilidad'] == idDisp,
        );
        if (indice < 0) {
          throw const PostgrestException(
            message: 'No se encontró el horario indicado.',
            code: 'P0002',
          );
        }
        final actual = filasDisponibilidad[indice];
        if (actual['id_profesional'] != idProf) {
          throw const PostgrestException(
            message: 'No tienes permisos para eliminar el horario de otro profesional.',
            code: '42501',
          );
        }
        if (actual['estado'] == 'reservada' ||
            actual['tiene_cita_vinculada'] == true) {
          throw const PostgrestException(
            message: 'No se puede eliminar un horario reservado o con historial de citas vinculadas.',
            code: '22023',
          );
        }
        filasDisponibilidad.removeAt(indice);
        return <Map<String, dynamic>>[
          <String, dynamic>{'id_disponibilidad': idDisp},
        ];

      case 'listar_dias_no_laborables_profesional_propios':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.listar_dias_no_laborables_profesional_propios in the schema cache',
            code: 'PGRST202',
          );
        }
        return filasDiasNoLaborables
            .where((f) => f['id_profesional'] == idProf)
            .map((f) {
              final fechaIso = f['fecha'].toString();
              final bloqueados = filasDisponibilidad
                  .where(
                    (d) =>
                        d['id_profesional'] == idProf &&
                        d['fecha'] == fechaIso &&
                        d['estado'] == 'bloqueada',
                  )
                  .length;
              return <String, dynamic>{
                ...f,
                'intervalos_bloqueados': bloqueados,
                'citas_pendientes': citasPendientesPorFecha[fechaIso] ?? 0,
                'citas_confirmadas': citasConfirmadasPorFecha[fechaIso] ?? 0,
              };
            })
            .toList();

      case 'registrar_dia_no_laborable_profesional_propio':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.registrar_dia_no_laborable_profesional_propio in the schema cache',
            code: 'PGRST202',
          );
        }
        final fecha = (params['p_fecha'] ?? '').toString();
        final motivo = (params['p_motivo'] ?? '').toString().trim();

        var bloqueados = 0;
        for (final fila in filasDisponibilidad) {
          if (fila['id_profesional'] == idProf &&
              fila['fecha'] == fecha &&
              fila['estado'] == 'disponible') {
            fila['estado'] = 'bloqueada';
            bloqueados++;
          }
        }

        final existenteIdx = filasDiasNoLaborables.indexWhere(
          (f) => f['id_profesional'] == idProf && f['fecha'] == fecha,
        );
        Map<String, dynamic> registro;
        if (existenteIdx >= 0) {
          filasDiasNoLaborables[existenteIdx]['motivo'] = motivo;
          registro = Map<String, dynamic>.from(
            filasDiasNoLaborables[existenteIdx],
          );
        } else {
          registro = <String, dynamic>{
            'id_dia_no_laborable': 'dnl-${_secuenciaDiaNoLabId++}',
            'id_profesional': idProf,
            'fecha': fecha,
            'motivo': motivo,
          };
          filasDiasNoLaborables.add(registro);
        }

        return <Map<String, dynamic>>[
          <String, dynamic>{
            ...registro,
            'intervalos_bloqueados': bloqueados,
            'citas_pendientes': citasPendientesPorFecha[fecha] ?? 0,
            'citas_confirmadas': citasConfirmadasPorFecha[fecha] ?? 0,
          },
        ];

      case 'retirar_dia_no_laborable_profesional_propio':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.retirar_dia_no_laborable_profesional_propio in the schema cache',
            code: 'PGRST202',
          );
        }
        final fecha = (params['p_fecha'] ?? '').toString();
        final idx = filasDiasNoLaborables.indexWhere(
          (f) => f['id_profesional'] == idProf && f['fecha'] == fecha,
        );
        if (idx < 0) {
          throw const PostgrestException(
            message:
                'La fecha indicada no estaba registrada como día no laborable.',
            code: 'P0002',
          );
        }
        final eliminado = filasDiasNoLaborables.removeAt(idx);
        return <Map<String, dynamic>>[
          <String, dynamic>{
            'id_dia_no_laborable': eliminado['id_dia_no_laborable'],
            'fecha': fecha,
          },
        ];

      case 'previsualizar_repeticion_semana_profesional_propia':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.previsualizar_repeticion_semana_profesional_propia in the schema cache',
            code: 'PGRST202',
          );
        }
        final fechaLunes = (params['p_lunes_origen'] ?? '').toString();
        final semanas =
            int.tryParse((params['p_semanas_posteriores'] ?? '1').toString()) ??
            1;
        return _calcularVistaPreviaRepeticionServidor(
          idProfesional: idProf,
          fechaLunesOrigenIso: fechaLunes,
          semanasPosteriores: semanas,
        );

      case 'confirmar_repeticion_semana_profesional_propia':
        if (!migracionAgendaSemanalAplicada) {
          throw const PostgrestException(
            message: 'Could not find the function public.confirmar_repeticion_semana_profesional_propia in the schema cache',
            code: 'PGRST202',
          );
        }
        final fechaLunes = (params['p_lunes_origen'] ?? '').toString();
        final semanas =
            int.tryParse((params['p_semanas_posteriores'] ?? '1').toString()) ??
            1;
        final huellaRecibida = (params['p_huella_vista_previa'] ?? '')
            .toString();

        final previewActual = _calcularVistaPreviaRepeticionServidor(
          idProfesional: idProf,
          fechaLunesOrigenIso: fechaLunes,
          semanasPosteriores: semanas,
        );
        final huellaActual = previewActual.isNotEmpty
            ? previewActual.first['huella_vista_previa'].toString()
            : '';

        if (huellaActual.isEmpty) {
          throw const PostgrestException(
            message: 'La semana seleccionada no tiene intervalos futuros válidos para repetir.',
            code: '22023',
          );
        }
        if (huellaActual != huellaRecibida) {
          throw const PostgrestException(
            message: 'La agenda cambió desde que se generó la vista previa. Actualiza la vista previa antes de confirmar.',
            code: '23P01',
          );
        }

        final aCrear = previewActual
            .where((item) => item['accion'] == 'crear')
            .toList();
        if (aCrear.isEmpty) {
          throw const PostgrestException(
            message: 'No hay intervalos válidos para crear en las semanas seleccionadas.',
            code: '22023',
          );
        }

        final creados = <Map<String, dynamic>>[];
        for (final item in aCrear) {
          final nueva = <String, dynamic>{
            'id_disponibilidad': 'disp-${_secuenciaId++}',
            'id_profesional': idProf,
            'fecha': item['fecha_destino'],
            'hora_inicio': item['hora_inicio'],
            'hora_fin': item['hora_fin'],
            'estado': 'disponible',
            'tiene_cita_vinculada': false,
          };
          filasDisponibilidad.add(nueva);
          creados.add(Map<String, dynamic>.from(nueva));
        }
        return creados;

      default:
        throw PostgrestException(
          message: 'Función no soportada: $nombreFuncion',
          code: 'PGRST202',
        );
    }
  }

  List<Map<String, dynamic>> _calcularVistaPreviaRepeticionServidor({
    required String idProfesional,
    required String fechaLunesOrigenIso,
    required int semanasPosteriores,
  }) {
    final lunes = HorarioDisponibilidad.obtenerLunesDeSemana(
      HorarioDisponibilidad.parsearFechaIso(fechaLunesOrigenIso),
    );
    final domingo = DateTime(lunes.year, lunes.month, lunes.day + 6);
    final lunesIso = HorarioDisponibilidad.formatearFechaIso(lunes);
    final domingoIso = HorarioDisponibilidad.formatearFechaIso(domingo);

    final plantillas = filasDisponibilidad.where((fila) {
      if (fila['id_profesional'] != idProfesional) return false;
      final fIso = fila['fecha'].toString();
      if (fIso.compareTo(lunesIso) < 0 || fIso.compareTo(domingoIso) > 0) {
        return false;
      }
      final estado = fila['estado'].toString();
      if (estado != 'disponible' && estado != 'reservada') return false;
      if (_esDiaNoLaborableServidor(idProfesional, fIso)) return false;
      return HorarioDisponibilidad.esIntervaloEnFuturoEcuador(
        fecha: HorarioDisponibilidad.parsearFechaIso(fIso),
        horaInicio: fila['hora_inicio'].toString(),
        referenciaUtc: ahoraUtc,
      );
    }).toList();

    plantillas.sort((a, b) {
      final cmpF = a['fecha'].toString().compareTo(b['fecha'].toString());
      if (cmpF != 0) return cmpF;
      return a['hora_inicio'].toString().compareTo(b['hora_inicio'].toString());
    });

    final preliminares = <Map<String, dynamic>>[];
    for (var offset = 1; offset <= semanasPosteriores; offset++) {
      for (final base in plantillas) {
        final fechaOrig = HorarioDisponibilidad.parsearFechaIso(
          base['fecha'].toString(),
        );
        final fechaDest = DateTime(
          fechaOrig.year,
          fechaOrig.month,
          fechaOrig.day + (offset * 7),
        );
        final fechaDestIso = HorarioDisponibilidad.formatearFechaIso(fechaDest);
        final hIni = base['hora_inicio'].toString();
        final hFin = base['hora_fin'].toString();
        final iniMin = HorarioDisponibilidad.convertirHoraAMinutos(hIni) ?? 0;
        final finMin = HorarioDisponibilidad.convertirHoraAMinutos(hFin) ?? 0;

        String accion;
        String motivo;

        if (_esDiaNoLaborableServidor(idProfesional, fechaDestIso)) {
          accion = 'omitido';
          motivo = 'Día marcado como no laborable';
        } else if (filasDisponibilidad.any(
          (d) =>
              d['id_profesional'] == idProfesional &&
              d['fecha'] == fechaDestIso &&
              d['hora_inicio'] == hIni &&
              d['hora_fin'] == hFin,
        )) {
          accion = 'omitido';
          motivo = 'Ya existe un intervalo idéntico en esa fecha';
        } else if (filasDisponibilidad.any((d) {
          if (d['id_profesional'] != idProfesional ||
              d['fecha'] != fechaDestIso) {
            return false;
          }
          final dIni =
              HorarioDisponibilidad.convertirHoraAMinutos(
                d['hora_inicio'].toString(),
              ) ??
              0;
          final dFin =
              HorarioDisponibilidad.convertirHoraAMinutos(
                d['hora_fin'].toString(),
              ) ??
              0;
          return dIni < finMin && dFin > iniMin;
        })) {
          accion = 'omitido';
          motivo = 'Se superpone con otro horario existente en esa fecha';
        } else {
          accion = 'crear';
          motivo = 'Disponible para crear';
        }

        preliminares.add(<String, dynamic>{
          'semana_offset': offset,
          'fecha_origen': base['fecha'].toString(),
          'fecha_destino': fechaDestIso,
          'hora_inicio': hIni,
          'hora_fin': hFin,
          'accion': accion,
          'motivo': motivo,
        });
      }
    }

    final huella = preliminares
        .map(
          (i) =>
              '${i['semana_offset']}|${i['fecha_destino']}|${i['hora_inicio']}-${i['hora_fin']}|${i['accion']}|${i['motivo']}',
        )
        .join(';');

    return preliminares
        .map((i) => <String, dynamic>{...i, 'huella_vista_previa': huella})
        .toList();
  }

  void _validarSuperposicionServidor({
    required String idProfesional,
    required String fecha,
    required String horaInicio,
    required String horaFin,
    String? idExcluir,
  }) {
    final inicioMin =
        HorarioDisponibilidad.convertirHoraAMinutos(horaInicio) ?? 0;
    final finMin = HorarioDisponibilidad.convertirHoraAMinutos(horaFin) ?? 0;
    for (final fila in filasDisponibilidad) {
      if (fila['id_profesional'] != idProfesional) continue;
      if (idExcluir != null && fila['id_disponibilidad'] == idExcluir) continue;
      if (fila['fecha'] != fecha) continue;
      final filaInicio =
          HorarioDisponibilidad.convertirHoraAMinutos(
            fila['hora_inicio'].toString(),
          ) ??
          0;
      final filaFin =
          HorarioDisponibilidad.convertirHoraAMinutos(
            fila['hora_fin'].toString(),
          ) ??
          0;
      if (filaInicio < finMin && filaFin > inicioMin) {
        throw const PostgrestException(
          message: 'El intervalo seleccionado se superpone con otro horario ya registrado para esa misma fecha.',
          code: '23P01',
        );
      }
    }
  }
}

class _ServicioSesionFalso extends ServicioSesion {
  const _ServicioSesionFalso();

  @override
  Future<void> cerrarSesion() async {}
}

void main() {
  // Referencia fija: 2026-11-14 15:00:00 UTC -> 2026-11-14 10:00:00 en America/Guayaquil (UTC-05:00).
  final referenciaUtcFija = DateTime.utc(2026, 11, 14, 15, 0, 0);

  group('I3-01 ControladorDisponibilidadProfesional y Servicio', () {
    test('crea horarios con duracion libre, los ordena por fecha/hora y persiste al reingresar', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      final controladorPrimeraSesion = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );

      final creadoTarde = await controladorPrimeraSesion.crearHorario(
        fecha: DateTime(2026, 11, 16),
        horaInicio: '14:30',
        horaFin: '15:15',
      );
      final creadoManana = await controladorPrimeraSesion.crearHorario(
        fecha: DateTime(2026, 11, 15),
        horaInicio: '08:00',
        horaFin: '09:30',
      );

      expect(creadoTarde, isTrue);
      expect(creadoManana, isTrue);
      expect(controladorPrimeraSesion.horarios, hasLength(2));
      expect(controladorPrimeraSesion.horarios.first.fechaIso, '2026-11-15');
      expect(
        controladorPrimeraSesion.horarios.first.idProfesional,
        'prof-distinto-101',
      );
      expect(controladorPrimeraSesion.horarios.last.duracionMinutos, 45);
      controladorPrimeraSesion.dispose();

      final controladorReingreso = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      final cargaExitosa = await controladorReingreso.cargarHorarios();

      expect(cargaExitosa, isTrue);
      expect(controladorReingreso.horarios, hasLength(2));
      expect(
        controladorReingreso.horarios[0].rangoHorarioTexto,
        '08:00 - 09:30',
      );
      expect(
        controladorReingreso.horarios[1].rangoHorarioTexto,
        '14:30 - 15:15',
      );
      controladorReingreso.dispose();
    });

    test('permite intervalos contiguos (09:00-10:00 y 10:00-11:00) y rechaza superposiciones', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );

      final primero = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 18),
        horaInicio: '09:00',
        horaFin: '10:00',
      );
      final contiguo = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 18),
        horaInicio: '10:00',
        horaFin: '11:00',
      );
      final superpuesto = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 18),
        horaInicio: '09:30',
        horaFin: '10:30',
      );

      expect(primero, isTrue);
      expect(contiguo, isTrue);
      expect(superpuesto, isFalse);
      expect(controlador.mensajeError, contains('se superpone'));
      expect(controlador.horarios, hasLength(2));
      controlador.dispose();
    });

    test('rechaza fechas u horas pasadas en America/Guayaquil (UTC-05:00) y hora_fin <= hora_inicio', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );

      final horaPasadaHoy = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 14),
        horaInicio: '09:30',
        horaFin: '10:30',
      );
      expect(horaPasadaHoy, isFalse);
      expect(controlador.mensajeError, contains('fechas u horas pasadas'));

      final finInvalido = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 20),
        horaInicio: '11:00',
        horaFin: '10:00',
      );
      expect(finInvalido, isFalse);
      expect(
        controlador.mensajeError,
        contains('posterior a la hora de inicio'),
      );

      final horaFuturaHoy = await controlador.crearHorario(
        fecha: DateTime(2026, 11, 14),
        horaInicio: '10:30',
        horaFin: '11:15',
      );
      expect(horaFuturaHoy, isTrue);
      controlador.dispose();
    });

    test(
      'permite bloquear, desbloquear y editar horarios disponibles propios',
      () async {
        final backend = _BackendDisponibilidadFalso(
          ahoraUtc: referenciaUtcFija,
        );
        final controlador = ControladorDisponibilidadProfesional(
          servicio: backend.crearServicio(),
        );

        await controlador.crearHorario(
          fecha: DateTime(2026, 11, 19),
          horaInicio: '09:00',
          horaFin: '10:00',
        );
        final idCreado = controlador.horarios.single.idDisponibilidad;

        final editado = await controlador.editarHorario(
          idDisponibilidad: idCreado,
          fecha: DateTime(2026, 11, 19),
          horaInicio: '09:15',
          horaFin: '10:15',
        );
        expect(editado, isTrue);
        expect(controlador.horarios.single.rangoHorarioTexto, '09:15 - 10:15');

        final bloqueado = await controlador.alternarBloqueoHorario(
          controlador.horarios.single,
        );
        expect(bloqueado, isTrue);
        expect(controlador.horarios.single.esBloqueada, isTrue);

        final intentoEditarBloqueado = await controlador.editarHorario(
          idDisponibilidad: idCreado,
          fecha: DateTime(2026, 11, 19),
          horaInicio: '11:00',
          horaFin: '12:00',
        );
        expect(intentoEditarBloqueado, isFalse);

        final desbloqueado = await controlador.alternarBloqueoHorario(
          controlador.horarios.single,
        );
        expect(desbloqueado, isTrue);
        expect(controlador.horarios.single.esDisponible, isTrue);
        controlador.dispose();
      },
    );

    test('protege horarios reservados o con cita vinculada e impide pasar manualmente a reservada', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'id_disponibilidad': 'disp-reservada-1',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-21',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'reservada',
          'tiene_cita_vinculada': true,
        },
        <String, dynamic>{
          'id_disponibilidad': 'disp-libre-2',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-21',
          'hora_inicio': '10:00',
          'hora_fin': '11:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        },
      ]);

      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      await controlador.cargarHorarios();

      final intentoEditarReservada = await controlador.editarHorario(
        idDisponibilidad: 'disp-reservada-1',
        fecha: DateTime(2026, 11, 21),
        horaInicio: '08:00',
        horaFin: '09:00',
      );
      expect(intentoEditarReservada, isFalse);
      expect(
        controlador.mensajeError,
        contains('reservado o vinculado a una cita'),
      );

      final intentoBloquearReservada = await controlador.cambiarEstadoHorario(
        idDisponibilidad: 'disp-reservada-1',
        nuevoEstado: 'bloqueada',
      );
      expect(intentoBloquearReservada, isFalse);
      expect(
        controlador.mensajeError,
        contains('reservado o vinculado a una cita'),
      );

      final intentoMarcarReservadaManual = await controlador
          .cambiarEstadoHorario(
            idDisponibilidad: 'disp-libre-2',
            nuevoEstado: 'reservada',
          );
      expect(intentoMarcarReservadaManual, isFalse);
      expect(
        controlador.mensajeError,
        contains('exclusivamente para el flujo de agendamiento'),
      );
      controlador.dispose();
    });

    test('rechaza cuenta inactiva, acceso ajeno y migracion ausente sin simular exito', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      backend.filasDisponibilidad.add(<String, dynamic>{
        'id_disponibilidad': 'disp-prof-1',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-22',
        'hora_inicio': '09:00',
        'hora_fin': '10:00',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      });

      backend.idUsuarioAutenticado = 'usr-prof-2';
      final controladorOtro = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      await controladorOtro.cargarHorarios();
      expect(controladorOtro.horarios, isEmpty);

      final intentoModificarAjeno = await controladorOtro.cambiarEstadoHorario(
        idDisponibilidad: 'disp-prof-1',
        nuevoEstado: 'bloqueada',
      );
      expect(intentoModificarAjeno, isFalse);
      expect(controladorOtro.mensajeError, contains('otro profesional'));
      controladorOtro.dispose();

      backend.idUsuarioAutenticado = 'usr-inactivo';
      final controladorInactivo = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      final cargaInactivo = await controladorInactivo.cargarHorarios();
      expect(cargaInactivo, isFalse);
      expect(controladorInactivo.mensajeError, contains('inactiva'));
      controladorInactivo.dispose();

      backend.idUsuarioAutenticado = 'usr-prof-1';
      backend.migracionAplicada = false;
      final controladorSinMigracion = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      final creadoSinMigracion = await controladorSinMigracion.crearHorario(
        fecha: DateTime(2026, 11, 23),
        horaInicio: '09:00',
        horaFin: '10:00',
      );
      expect(creadoSinMigracion, isFalse);
      expect(
        controladorSinMigracion.mensajeError,
        contains('06_disponibilidad_profesional.sql'),
      );
      expect(controladorSinMigracion.horarios, isEmpty);
      controladorSinMigracion.dispose();
    });

    test('permite eliminar horario propio sin citas y rechaza eliminar reservado, con historial, ajeno o sin migracion 12', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'id_disponibilidad': 'disp-libre-eliminar',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-16',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        },
        <String, dynamic>{
          'id_disponibilidad': 'disp-reservada-no-eliminar',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-16',
          'hora_inicio': '10:00',
          'hora_fin': '11:00',
          'estado': 'reservada',
          'tiene_cita_vinculada': true,
        },
        <String, dynamic>{
          'id_disponibilidad': 'disp-historial-rechazada',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-16',
          'hora_inicio': '11:00',
          'hora_fin': '12:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': true,
        },
        <String, dynamic>{
          'id_disponibilidad': 'disp-ajeno-prof-2',
          'id_profesional': 'prof-distinto-202',
          'fecha': '2026-11-16',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        },
      ]);

      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      await controlador.cargarHorarios();
      expect(controlador.horarios, hasLength(3));

      final horarioReservado = controlador.horarios.firstWhere(
        (h) => h.idDisponibilidad == 'disp-reservada-no-eliminar',
      );
      expect(horarioReservado.puedeEliminar, isFalse);
      final elimReservado = await controlador.eliminarHorario(horarioReservado);
      expect(elimReservado, isFalse);
      expect(
        controlador.mensajeError,
        contains('reservado o con historial de citas'),
      );

      final horarioHistorial = controlador.horarios.firstWhere(
        (h) => h.idDisponibilidad == 'disp-historial-rechazada',
      );
      expect(horarioHistorial.puedeEliminar, isFalse);
      expect(
        horarioHistorial.puedeEditar(referenciaUtc: referenciaUtcFija),
        isFalse,
      );
      expect(
        horarioHistorial.puedeCambiarBloqueo(referenciaUtc: referenciaUtcFija),
        isTrue,
      );
      final elimHistorial = await controlador.eliminarHorario(horarioHistorial);
      expect(elimHistorial, isFalse);
      expect(
        controlador.mensajeError,
        contains('reservado o con historial de citas'),
      );

      final elimAjeno = await controlador.eliminarHorarioPorId(
        'disp-ajeno-prof-2',
      );
      expect(elimAjeno, isFalse);
      expect(controlador.mensajeError, contains('otro profesional'));

      backend.migracionEliminacionAplicada = false;
      final horarioLibre = controlador.horarios.firstWhere(
        (h) => h.idDisponibilidad == 'disp-libre-eliminar',
      );
      expect(horarioLibre.puedeEliminar, isTrue);
      final elimSinMigracion = await controlador.eliminarHorario(horarioLibre);
      expect(elimSinMigracion, isFalse);
      expect(
        controlador.mensajeError,
        contains('12_eliminacion_disponibilidad_profesional.sql'),
      );
      expect(controlador.horarios, hasLength(3));

      backend.migracionEliminacionAplicada = true;
      final elimExitoso = await controlador.eliminarHorario(horarioLibre);
      expect(elimExitoso, isTrue);
      expect(controlador.mensajeExito, contains('eliminado correctamente'));
      expect(
        controlador.horarios.any(
          (h) => h.idDisponibilidad == 'disp-libre-eliminar',
        ),
        isFalse,
      );
      controlador.dispose();
    });

    test('crea varios intervalos por jornada con duracion y descanso, sin generar cita incompleta, y hace rollback completo si alguno choca', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );

      // 1. Con descanso de 15 min entre 09:00 y 12:00 (citas de 60 min):
      //    genera 09:00–10:00 y 10:15–11:15, sin crear intervalo incompleto en los 45 min restantes.
      final exitoDescanso = await controlador.crearHorariosEnJornada(
        fecha: DateTime(2026, 11, 16),
        horaInicio: '09:00',
        horaFin: '12:00',
        duracionMinutos: 60,
        descansoMinutos: 15,
      );
      expect(exitoDescanso, isTrue);
      final lunes16 = controlador.horariosPorFecha(DateTime(2026, 11, 16));
      expect(
        lunes16.map((h) => h.rangoHorarioCompacto).toList(),
        equals(<String>['09:00–10:00', '10:15–11:15']),
      );

      // 2. En martes 2026-11-17 existe ya 10:00–11:00; al intentar crear tanda 09:00–12:00 (60 min, 0 descanso),
      //    el segundo intervalo (10:00–11:00) choca -> NO guarda parcialmente ni 09:00–10:00 ni 11:00–12:00.
      await controlador.crearHorario(
        fecha: DateTime(2026, 11, 17),
        horaInicio: '10:00',
        horaFin: '11:00',
      );
      final exitoTandaConConflicto = await controlador.crearHorariosEnJornada(
        fecha: DateTime(2026, 11, 17),
        horaInicio: '09:00',
        horaFin: '12:00',
        duracionMinutos: 60,
        descansoMinutos: 0,
      );
      expect(exitoTandaConConflicto, isFalse);
      expect(controlador.mensajeError, contains('10:00–11:00'));
      expect(
        controlador.horariosPorFecha(DateTime(2026, 11, 17)),
        hasLength(1),
      );
      controlador.dispose();
    });

    test('gestiona dia no laborable: bloquea intervalos libres, conserva reservados/citas activas, impide crear o desbloquear y al retirar no desbloquea automaticamente', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      final fechaMiercoles = DateTime(2026, 11, 18);
      backend.citasPendientesPorFecha['2026-11-18'] = 1;
      backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
        <String, dynamic>{
          'id_disponibilidad': 'disp-mier-libre',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-18',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        },
        <String, dynamic>{
          'id_disponibilidad': 'disp-mier-reservado',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-18',
          'hora_inicio': '10:00',
          'hora_fin': '11:00',
          'estado': 'reservada',
          'tiene_cita_vinculada': true,
        },
      ]);

      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      await controlador.cargarHorarios();
      expect(controlador.contarDisponiblesEnFecha(fechaMiercoles), 1);

      final marcado = await controlador.registrarDiaNoLaborable(
        fecha: fechaMiercoles,
        motivo: 'Congreso nacional',
      );
      expect(marcado, isTrue);
      expect(controlador.esDiaNoLaborable(fechaMiercoles), isTrue);
      final infoDia = controlador.obtenerDiaNoLaborable(fechaMiercoles)!;
      expect(infoDia.intervalosBloqueados, 1);
      expect(infoDia.tieneCitasPorGestionar, isTrue);

      // El horario libre paso a bloqueado y el reservado se conservo intacto.
      final horariosMiercoles = controlador.horariosPorFecha(fechaMiercoles);
      expect(
        horariosMiercoles
            .firstWhere((h) => h.idDisponibilidad == 'disp-mier-libre')
            .esBloqueada,
        isTrue,
      );
      expect(
        horariosMiercoles
            .firstWhere((h) => h.idDisponibilidad == 'disp-mier-reservado')
            .esReservada,
        isTrue,
      );

      // Impide crear horarios o desbloquear en fecha no laborable.
      final intentoCrearEnNoLab = await controlador.crearHorario(
        fecha: fechaMiercoles,
        horaInicio: '14:00',
        horaFin: '15:00',
      );
      expect(intentoCrearEnNoLab, isFalse);
      expect(controlador.mensajeError, contains('día no laborable'));

      final intentoDesbloquearEnNoLab = await controlador.cambiarEstadoHorario(
        idDisponibilidad: 'disp-mier-libre',
        nuevoEstado: 'disponible',
      );
      expect(intentoDesbloquearEnNoLab, isFalse);
      expect(controlador.mensajeError, contains('día no laborable'));

      // Al retirar la excepcion, no desbloquea automaticamente los intervalos bloqueados.
      final retirado = await controlador.retirarDiaNoLaborable(fechaMiercoles);
      expect(retirado, isTrue);
      expect(controlador.esDiaNoLaborable(fechaMiercoles), isFalse);
      expect(
        controlador
            .horariosPorFecha(fechaMiercoles)
            .firstWhere((h) => h.idDisponibilidad == 'disp-mier-libre')
            .esBloqueada,
        isTrue,
      );
      controlador.dispose();
    });

    test('repite semana con vista previa: copia disponibles y reservados como disponibles, excluye bloqueados y dias no laborables, omite conflictos y exige vista previa actualizada', () async {
      final backend = _BackendDisponibilidadFalso(ahoraUtc: referenciaUtcFija);
      // Semana origen: lunes 2026-11-16 a domingo 2026-11-22
      backend.filasDisponibilidad.addAll(<Map<String, dynamic>>[
        // Lunes 16: disponible 09:00-10:00 y reservado 10:00-11:00 (ambos aportan su hora)
        <String, dynamic>{
          'id_disponibilidad': 'orig-disp-1',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-16',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        },
        <String, dynamic>{
          'id_disponibilidad': 'orig-res-2',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-16',
          'hora_inicio': '10:00',
          'hora_fin': '11:00',
          'estado': 'reservada',
          'tiene_cita_vinculada': true,
        },
        // Martes 17: bloqueado 14:00-15:00 (NO se copia)
        <String, dynamic>{
          'id_disponibilidad': 'orig-bloq-3',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-17',
          'hora_inicio': '14:00',
          'hora_fin': '15:00',
          'estado': 'bloqueada',
          'tiene_cita_vinculada': false,
        },
        // En la semana destino 1 (lunes 2026-11-23) ya existe 09:00-10:00 (debe omitirse por identico)
        <String, dynamic>{
          'id_disponibilidad': 'dest-existente-1',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-23',
          'hora_inicio': '09:00',
          'hora_fin': '10:00',
          'estado': 'bloqueada',
          'tiene_cita_vinculada': false,
        },
      ]);
      // En la semana destino 2, el lunes 2026-11-30 es dia no laborable (debe omitirse).
      backend.filasDiasNoLaborables.add(<String, dynamic>{
        'id_dia_no_laborable': 'dnl-dest-2',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-30',
        'motivo': 'Feriado',
      });

      final controlador = ControladorDisponibilidadProfesional(
        servicio: backend.crearServicio(),
      );
      await controlador.cargarHorarios();

      final lunesOrigen = DateTime(2026, 11, 16);
      final vistaPrevia = await controlador.previsualizarRepeticionSemana(
        lunesOrigen: lunesOrigen,
        semanasPosteriores: 2,
      );
      expect(vistaPrevia, isNotNull);
      // Semana +1 (2026-11-23): 09:00-10:00 omitido (identico), 10:00-11:00 crear.
      // Semana +2 (2026-11-30): ambos omitidos por dia no laborable.
      expect(vistaPrevia!.totalCrear, 1);
      expect(vistaPrevia.totalOmitidos, 3);
      expect(
        vistaPrevia.itemsACrear.single.rangoHorarioCompacto,
        '10:00–11:00',
      );
      expect(vistaPrevia.itemsACrear.single.fechaDestinoIso, '2026-11-23');

      // Si cambia la agenda antes de confirmar (p. ej. se agrega un horario que altera la huella),
      // el servidor rechaza la huella desactualizada y exige refrescar la vista previa.
      backend.filasDisponibilidad.add(<String, dynamic>{
        'id_disponibilidad': 'cambio-externo',
        'id_profesional': 'prof-distinto-101',
        'fecha': '2026-11-18',
        'hora_inicio': '16:00',
        'hora_fin': '17:00',
        'estado': 'disponible',
        'tiene_cita_vinculada': false,
      });

      final confirmacionConHuellaVieja = await controlador
          .confirmarRepeticionSemana(
            lunesOrigen: lunesOrigen,
            semanasPosteriores: 2,
            huellaVistaPrevia: vistaPrevia.huellaVistaPrevia,
          );
      expect(confirmacionConHuellaVieja, isFalse);
      expect(controlador.mensajeError, contains('Actualiza la vista previa'));

      // Refrescamos vista previa y confirmamos:
      final vistaPreviaActualizada = await controlador
          .previsualizarRepeticionSemana(
            lunesOrigen: lunesOrigen,
            semanasPosteriores: 2,
          );
      expect(vistaPreviaActualizada, isNotNull);
      expect(vistaPreviaActualizada!.totalCrear, 3);

      final confirmacionExitosa = await controlador.confirmarRepeticionSemana(
        lunesOrigen: lunesOrigen,
        semanasPosteriores: 2,
        huellaVistaPrevia: vistaPreviaActualizada.huellaVistaPrevia,
      );
      expect(confirmacionExitosa, isTrue);

      // El horario copiado desde el reservado 10:00-11:00 se creo como 'disponible' y sin cita vinculada.
      final creadosEn23 = controlador.horariosPorFecha(DateTime(2026, 11, 23));
      final nuevo10a11 = creadosEn23.firstWhere(
        (h) => h.rangoHorarioCompacto == '10:00–11:00',
      );
      expect(nuevo10a11.esDisponible, isTrue);
      expect(nuevo10a11.tieneCitaVinculada, isFalse);
      controlador.dispose();
    });
  });

  group('I3-01 Interfaz de Disponibilidad Semanal y Panel del Profesional', () {
    testWidgets(
      'Agenda semanal muestra Mis horarios, selector de semana, 7 dias lunes-domingo, creacion por jornada, detalle y eliminacion con confirmacion',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final backend = _BackendDisponibilidadFalso(
          ahoraUtc: referenciaUtcFija,
        );
        backend.filasDisponibilidad.add(<String, dynamic>{
          'id_disponibilidad': 'disp-protegido-1',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-15',
          'hora_inicio': '15:00',
          'hora_fin': '16:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': true,
        });

        const perfilPendiente = PerfilUsuario(
          id: 'usr-prof-1',
          nombre: 'Elena',
          apellido: 'Ríos',
          correo: 'elena@psicobloom.ec',
          rol: 'profesional',
          aprobacion: 'pendiente',
          cuentaActiva: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioProfesional(
              perfilInicial: perfilPendiente,
              servicioSesion: const _ServicioSesionFalso(),
              servicioDisponibilidad: backend.crearServicio(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('estadoErrorCitasInicioProfesional')),
          findsOneWidget,
        );
        expect(
          find.text('No tienes citas confirmadas para este día'),
          findsNothing,
        );

        final pestanaAgenda = find.byKey(
          const Key('pestanaProfesional_agenda'),
        );
        expect(pestanaAgenda, findsOneWidget);

        await tester.tap(pestanaAgenda);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('tituloMisHorariosAgenda')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('avisoDisponibilidadProfesionalPendiente')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('selectorSemanaAgenda')), findsOneWidget);
        expect(
          find.byKey(const Key('botonSemanaAnteriorAgenda')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonSemanaSiguienteAgenda')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('botonSemanaHoyAgenda')), findsOneWidget);
        expect(find.byKey(const Key('botonRepetirEstaSemana')), findsOneWidget);

        // En semana actual (sabado 2026-11-14), los dias pasados quedan ocultos.
        final fechasPasadasSemanaActual = <String>[
          '2026-11-09',
          '2026-11-10',
          '2026-11-11',
          '2026-11-12',
          '2026-11-13',
        ];
        for (final fechaIso in fechasPasadasSemanaActual) {
          expect(find.byKey(Key('tarjetaDiaAgenda_$fechaIso')), findsNothing);
        }
        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-14')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-15')),
          findsOneWidget,
        );
        expect(find.text('Sábado 14'), findsOneWidget);
        expect(find.text('Domingo 15'), findsOneWidget);
        expect(find.text('Lunes 9'), findsNothing);
        expect(find.text('Lunes, 9 de noviembre de 2026'), findsNothing);
        expect(find.text('Domingo, 15 de noviembre de 2026'), findsNothing);
        expect(find.text('+ Agregar'), findsNothing);
        expect(find.text('× Quitar'), findsNothing);
        expect(
          find.byKey(const Key('botonAgregarHorarioDia_2026-11-15')),
          findsOneWidget,
        );

        // La flecha hacia semanas pasadas esta deshabilitada en la semana actual.
        final botonSemanaAnteriorActual = tester.widget<IconButton>(
          find.byKey(const Key('botonSemanaAnteriorAgenda')),
        );
        expect(botonSemanaAnteriorActual.onPressed, isNull);

        expect(
          find.byKey(const Key('iconoCandadoHorario_disp-protegido-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonEliminarHorario_disp-protegido-1')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('botonSemanaSiguienteAgenda')));
        await tester.pumpAndSettle();
        final fechasSemanaFutura = <String>[
          '2026-11-16',
          '2026-11-17',
          '2026-11-18',
          '2026-11-19',
          '2026-11-20',
          '2026-11-21',
          '2026-11-22',
        ];
        for (final fechaIso in fechasSemanaFutura) {
          expect(find.byKey(Key('tarjetaDiaAgenda_$fechaIso')), findsOneWidget);
        }
        expect(find.text('Lunes 16'), findsOneWidget);
        expect(find.text('Lunes, 16 de noviembre de 2026'), findsNothing);

        // Desde una semana futura debe poder regresarse hasta la semana actual.
        final botonSemanaAnteriorFutura = tester.widget<IconButton>(
          find.byKey(const Key('botonSemanaAnteriorAgenda')),
        );
        expect(botonSemanaAnteriorFutura.onPressed, isNotNull);
        await tester.tap(find.byKey(const Key('botonSemanaAnteriorAgenda')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-15')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('botonSemanaAnteriorAgenda')),
              )
              .onPressed,
          isNull,
        );

        // Vamos a semana siguiente y regresamos con "Hoy".
        await tester.tap(find.byKey(const Key('botonSemanaSiguienteAgenda')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('botonSemanaHoyAgenda')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-15')),
          findsOneWidget,
        );

        // Pulsa "+" en el domingo 2026-11-15 (preselecciona esa fecha).
        final botonAgregarDomingo = find.byKey(
          const Key('botonAgregarHorarioDia_2026-11-15'),
        );
        await tester.ensureVisible(botonAgregarDomingo);
        await tester.pumpAndSettle();
        await tester.tap(botonAgregarDomingo);
        await tester.pumpAndSettle();

        final campoFecha = tester.widget<TextFormField>(
          find.byKey(const Key('campoFechaHorario')),
        );
        expect(campoFecha.controller?.text, '2026-11-15');
        expect(find.text('Agregar horarios al domingo'), findsOneWidget);
        expect(
          find.byKey(const Key('vistaPreviaIntervalosJornada')),
          findsOneWidget,
        );

        // Error de validacion dentro del modal: no debe duplicarse detras.
        await tester.enterText(
          find.byKey(const Key('campoHoraFinHorario')),
          '08:00',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('botonGuardarHorarioDisponibilidad')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'La hora de finalización debe ser posterior a la hora de inicio.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('bannerErrorDisponibilidad')),
          findsNothing,
        );

        // Al cancelar el formulario tras un error, se limpia el aviso antiguo.
        await tester.tap(
          find.byKey(const Key('botonCancelarFormularioHorario')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('bannerErrorDisponibilidad')),
          findsNothing,
        );
        expect(
          find.text(
            'La hora de finalización debe ser posterior a la hora de inicio.',
          ),
          findsNothing,
        );

        // Reabrimos "+" en domingo 2026-11-15 para continuar con la creacion valida.
        await tester.ensureVisible(botonAgregarDomingo);
        await tester.pumpAndSettle();
        await tester.tap(botonAgregarDomingo);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'La hora de finalización debe ser posterior a la hora de inicio.',
          ),
          findsNothing,
        );

        await tester.enterText(
          find.byKey(const Key('campoHoraInicioHorario')),
          '09:00',
        );
        await tester.enterText(
          find.byKey(const Key('campoHoraFinHorario')),
          '10:00',
        );
        await tester.pumpAndSettle();

        final botonGuardar = find.byKey(
          const Key('botonGuardarHorarioDisponibilidad'),
        );
        await tester.ensureVisible(botonGuardar);
        await tester.pumpAndSettle();
        await tester.tap(botonGuardar);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('tarjetaHorario_disp-1')), findsOneWidget);
        expect(find.text('09:00–10:00'), findsOneWidget);
        expect(
          find.byKey(const Key('botonEliminarHorario_disp-1')),
          findsOneWidget,
        );

        final tarjetaDisp1 = find.byKey(const Key('tarjetaHorario_disp-1'));
        await tester.ensureVisible(tarjetaDisp1);
        await tester.pumpAndSettle();
        await tester.tap(tarjetaDisp1);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('modalDetalleHorario_disp-1')),
          findsOneWidget,
        );
        expect(find.text('09:00–10:00 (60 min)'), findsOneWidget);

        await tester.tap(find.byKey(const Key('botonBloqueoHorario_disp-1')));
        await tester.pumpAndSettle();
        expect(find.text('Bloqueado'), findsOneWidget);

        await tester.tap(tarjetaDisp1);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('botonBloqueoHorario_disp-1')));
        await tester.pumpAndSettle();

        await tester.tap(tarjetaDisp1);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('botonEditarHorario_disp-1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('campoHoraFinHorario')),
          '10:30',
        );
        await tester.tap(botonGuardar);
        await tester.pumpAndSettle();
        expect(find.text('09:00–10:30'), findsOneWidget);

        final botonEliminarDisp1 = find.byKey(
          const Key('botonEliminarHorario_disp-1'),
        );
        await tester.ensureVisible(botonEliminarDisp1);
        await tester.pumpAndSettle();
        await tester.tap(botonEliminarDisp1);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('dialogoConfirmarEliminacionHorario')),
          findsOneWidget,
        );
        expect(find.textContaining('09:00–10:30'), findsAtLeastNWidgets(1));
        expect(
          find.textContaining('Domingo, 15 de noviembre de 2026'),
          findsAtLeastNWidgets(1),
        );

        await tester.tap(
          find.byKey(const Key('botonConfirmarEliminacionHorario')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('tarjetaHorario_disp-1')), findsNothing);
        expect(
          find.byKey(const Key('bannerExitoDisponibilidad')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'permite agregar multiples horarios (09:00 a 12:00, 60 min, 0 min), marcar/retirar dia no laborable con acceso a Solicitudes y repetir esta semana',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final backend = _BackendDisponibilidadFalso(
          ahoraUtc: referenciaUtcFija,
        );
        // En miercoles 2026-11-18 hay una cita confirmada en horario reservado
        backend.citasConfirmadasPorFecha['2026-11-18'] = 1;
        backend.filasDisponibilidad.add(<String, dynamic>{
          'id_disponibilidad': 'disp-mier-res',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-18',
          'hora_inicio': '10:00',
          'hora_fin': '11:00',
          'estado': 'reservada',
          'tiene_cita_vinculada': true,
        });

        const perfilAprobado = PerfilUsuario(
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
            home: PantallaInicioProfesional(
              perfilInicial: perfilAprobado,
              servicioSesion: const _ServicioSesionFalso(),
              servicioDisponibilidad: backend.crearServicio(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Vamos a Agenda y avanzamos a la semana del 16 al 22 de noviembre de 2026.
        await tester.tap(find.byKey(const Key('pestanaProfesional_agenda')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('botonSemanaSiguienteAgenda')));
        await tester.pumpAndSettle();

        // 1. En lunes 2026-11-16 pulsamos "+" -> por defecto 09:00 a 12:00, 60 min, 0 min -> crea 3 intervalos.
        final botonMasLunes = find.byKey(
          const Key('botonAgregarHorarioDia_2026-11-16'),
        );
        await tester.ensureVisible(botonMasLunes);
        await tester.pumpAndSettle();
        await tester.tap(botonMasLunes);
        await tester.pumpAndSettle();

        expect(find.text('Agregar horarios al lunes'), findsOneWidget);
        expect(find.text('09:00–10:00'), findsOneWidget);
        expect(find.text('10:00–11:00'), findsAtLeastNWidgets(1));
        expect(find.text('11:00–12:00'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('botonGuardarHorarioDisponibilidad')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('tarjetaHorario_disp-1')), findsOneWidget);
        expect(find.byKey(const Key('tarjetaHorario_disp-2')), findsOneWidget);
        expect(find.byKey(const Key('tarjetaHorario_disp-3')), findsOneWidget);

        // 2. Tocamos el encabezado del miercoles 2026-11-18 para marcarlo como dia no laborable.
        final encabezadoMiercoles = find.byKey(
          const Key('encabezadoDiaAgenda_2026-11-18'),
        );
        await tester.ensureVisible(encabezadoMiercoles);
        await tester.pumpAndSettle();
        await tester.tap(encabezadoMiercoles);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('modalDiaNoLaborable_2026-11-18')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Citas activas (pendientes o confirmadas): 1'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('campoMotivoDiaNoLaborable')),
          'Capacitación clínica',
        );
        await tester.tap(find.byKey(const Key('botonConfirmarDiaNoLaborable')));
        await tester.pumpAndSettle();

        // Muestra "Día no laborable · Citas por gestionar" y boton "Ver Solicitudes".
        expect(
          find.byKey(const Key('insigniaDiaNoLaborableCitas_2026-11-18')),
          findsOneWidget,
        );
        expect(
          find.text('Día no laborable · Citas por gestionar'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('botonIrASolicitudesDiaNoLaborable_2026-11-18')),
          findsOneWidget,
        );

        // 3. Pulsamos "Repetir esta semana", previsualizamos 1 semana posterior y confirmamos.
        final botonRepetir = find.byKey(const Key('botonRepetirEstaSemana'));
        await tester.ensureVisible(botonRepetir);
        await tester.pumpAndSettle();
        await tester.tap(botonRepetir);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('modalRepetirEstaSemana')), findsOneWidget);
        expect(
          find.byKey(const Key('contenedorVistaPreviaRepeticion')),
          findsOneWidget,
        );
        // En la semana origen: lunes tiene 3 horarios disponibles; miercoles es dia no laborable (se excluye).
        expect(find.text('Horarios que se agregarán (3):'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('botonConfirmarRepeticionSemana')),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Se copiaron 3 horario(s) disponible(s)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'propone hora futura en hoy, deshabilita agregar al final del dia, restringe fecha pasada y actualiza al cambiar de dia tras reanudar',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Referencia mutable: empieza el sabado 2026-11-14 a las 10:00 (UTC-5).
        final backend = _BackendDisponibilidadFalso(
          ahoraUtc: DateTime.utc(2026, 11, 14, 15, 0),
        );
        backend.filasDisponibilidad.add(<String, dynamic>{
          'id_disponibilidad': 'disp-hoy-historico',
          'id_profesional': 'prof-distinto-101',
          'fecha': '2026-11-14',
          'hora_inicio': '08:00',
          'hora_fin': '09:00',
          'estado': 'disponible',
          'tiene_cita_vinculada': false,
        });

        const perfilAprobado = PerfilUsuario(
          id: 'usr-prof-1',
          nombre: 'Elena',
          apellido: 'Ríos',
          correo: 'elena@psicobloom.ec',
          rol: 'profesional',
          aprobacion: 'aprobado',
          cuentaActiva: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: TemaPsicobloom.obtenerTema(),
            home: PantallaInicioProfesional(
              perfilInicial: perfilAprobado,
              servicioSesion: const _ServicioSesionFalso(),
              servicioDisponibilidad: backend.crearServicio(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pestanaProfesional_agenda')));
        await tester.pumpAndSettle();

        // 1. Al abrir "+" en hoy (10:00), propone una hora futura valida (11:00).
        await tester.tap(
          find.byKey(const Key('botonAgregarHorarioDia_2026-11-14')),
        );
        await tester.pumpAndSettle();
        final campoHoraInicio = tester.widget<TextFormField>(
          find.byKey(const Key('campoHoraInicioHorario')),
        );
        expect(campoHoraInicio.controller?.text, '11:00');

        // Intentar escribir manualmente una fecha pasada muestra error claro y no guarda.
        await tester.enterText(
          find.byKey(const Key('campoFechaHorario')),
          '2026-11-13',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('botonGuardarHorarioDisponibilidad')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No puedes seleccionar una fecha anterior a hoy.'),
          findsOneWidget,
        );

        // Cancelar limpia el error.
        await tester.tap(
          find.byKey(const Key('botonCancelarFormularioHorario')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('No puedes seleccionar una fecha anterior a hoy.'),
          findsNothing,
        );

        // 2. Cuando ya no cabe un horario hoy (23:35 en Ecuador -> 04:35 UTC del dia siguiente),
        // se deshabilita "+" hoy y se muestra el aviso correspondiente.
        backend.ahoraUtc = DateTime.utc(2026, 11, 15, 4, 35);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        final botonAgregarHoyTarde = tester.widget<IconButton>(
          find.byKey(const Key('botonAgregarHorarioDia_2026-11-14')),
        );
        expect(botonAgregarHoyTarde.onPressed, isNull);
        expect(
          find.text(
            'Ya no quedan horas disponibles para agregar hoy. Elige otro día.',
          ),
          findsOneWidget,
        );

        // 3. Si cambia el dia a domingo 2026-11-15 (10:00 Ecuador) y se reanuda la app,
        // sabado 14 se oculta pero su horario historico se conserva en el backend.
        backend.ahoraUtc = DateTime.utc(2026, 11, 15, 15, 0);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-14')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('tarjetaDiaAgenda_2026-11-15')),
          findsOneWidget,
        );
        expect(
          backend.filasDisponibilidad.any(
            (fila) => fila['id_disponibilidad'] == 'disp-hoy-historico',
          ),
          isTrue,
        );
      },
    );
  });
}
