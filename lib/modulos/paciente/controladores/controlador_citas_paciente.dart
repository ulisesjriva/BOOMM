import 'package:flutter/foundation.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';

import '../modelos/cita_paciente.dart';
import '../servicios/servicio_citas_paciente.dart';

class ControladorCitasPaciente extends ChangeNotifier {
  ControladorCitasPaciente({
    ServicioCitasPaciente? servicio,
    SeccionMisCitas? seccionInicial,
  }) : _servicio = servicio ?? const ServicioCitasPaciente(),
       _seccionSeleccionada = seccionInicial ?? SeccionMisCitas.proximas,
       _usuarioEligioSeccion = seccionInicial != null;

  static const int citasPorBloque = 5;

  final ServicioCitasPaciente _servicio;

  List<HorarioDisponibilidad> _horariosDisponibles =
      const <HorarioDisponibilidad>[];
  HorarioDisponibilidad? _horarioSeleccionado;
  CitaPaciente? _ultimaCitaSolicitada;
  List<CitaPaciente> _citasPropias = const <CitaPaciente>[];

  SeccionMisCitas _seccionSeleccionada;
  bool _usuarioEligioSeccion;
  int _cantidadVisibleActual = citasPorBloque;
  String _huellaTemporalClasificacion = '';

  bool _estaCargandoHorarios = false;
  bool _estaEnviandoSolicitud = false;
  bool _estaCargandoCitasPropias = false;

  String? _mensajeErrorHorarios;
  String? _mensajeErrorSolicitud;
  String? _mensajeErrorCitasPropias;
  String? _mensajeExitoSolicitud;

  List<HorarioDisponibilidad> get horariosDisponibles => _horariosDisponibles;
  HorarioDisponibilidad? get horarioSeleccionado => _horarioSeleccionado;
  CitaPaciente? get ultimaCitaSolicitada => _ultimaCitaSolicitada;
  List<CitaPaciente> get citasPropias => _citasPropias;

  SeccionMisCitas get seccionSeleccionada => _seccionSeleccionada;
  int get cantidadVisibleActual => _cantidadVisibleActual;

  bool get estaCargandoHorarios => _estaCargandoHorarios;
  bool get estaEnviandoSolicitud => _estaEnviandoSolicitud;
  bool get estaCargandoCitasPropias => _estaCargandoCitasPropias;

  String? get mensajeErrorHorarios => _mensajeErrorHorarios;
  String? get mensajeErrorSolicitud => _mensajeErrorSolicitud;
  String? get mensajeErrorCitasPropias => _mensajeErrorCitasPropias;
  String? get mensajeExitoSolicitud => _mensajeExitoSolicitud;

  DateTime obtenerAhoraUtc() => _servicio.obtenerAhoraUtc();

  DateTime obtenerAhoraEnEcuador() {
    return HorarioDisponibilidad.obtenerAhoraEnEcuador(
      referenciaUtc: _servicio.obtenerAhoraUtc(),
    );
  }

  /// Devuelve las citas pertenecientes a [seccion], clasificadas y ordenadas
  /// cronologicamente segun la hora actual en Ecuador continental.
  List<CitaPaciente> obtenerCitasDeSeccion(SeccionMisCitas seccion) {
    final referenciaUtc = _servicio.obtenerAhoraUtc();
    final filtradas = _citasPropias
        .where(
          (cita) =>
              cita.clasificarSeccion(referenciaUtc: referenciaUtc) == seccion,
        )
        .toList();

    filtradas.sort((a, b) {
      if (seccion == SeccionMisCitas.historial) {
        final comparacionInicio = b.fechaHoraInicioEcuador.compareTo(
          a.fechaHoraInicioEcuador,
        );
        if (comparacionInicio != 0) {
          return comparacionInicio;
        }
        final comparacionFin = b.fechaHoraFinEcuador.compareTo(
          a.fechaHoraFinEcuador,
        );
        if (comparacionFin != 0) {
          return comparacionFin;
        }
        final solicitudA = a.fechaSolicitud;
        final solicitudB = b.fechaSolicitud;
        if (solicitudA != null && solicitudB != null) {
          final comparacionSolicitud = solicitudB.compareTo(solicitudA);
          if (comparacionSolicitud != 0) {
            return comparacionSolicitud;
          }
        }
        return b.idCita.compareTo(a.idCita);
      }

      // Proximas y Pendientes: de la mas proxima a la mas lejana.
      final comparacionInicio = a.fechaHoraInicioEcuador.compareTo(
        b.fechaHoraInicioEcuador,
      );
      if (comparacionInicio != 0) {
        return comparacionInicio;
      }
      final comparacionFin = a.fechaHoraFinEcuador.compareTo(
        b.fechaHoraFinEcuador,
      );
      if (comparacionFin != 0) {
        return comparacionFin;
      }
      return a.idCita.compareTo(b.idCita);
    });

    return List<CitaPaciente>.unmodifiable(filtradas);
  }

  List<CitaPaciente> get citasProximas =>
      obtenerCitasDeSeccion(SeccionMisCitas.proximas);

  List<CitaPaciente> get citasPendientes =>
      obtenerCitasDeSeccion(SeccionMisCitas.pendientes);

  List<CitaPaciente> get citasHistorial =>
      obtenerCitasDeSeccion(SeccionMisCitas.historial);

  List<CitaPaciente> get citasSeccionActual =>
      obtenerCitasDeSeccion(_seccionSeleccionada);

  /// Subconjunto visible de la seccion activa segun el limite incremental (5 en 5).
  List<CitaPaciente> get citasVisiblesSeccionActual {
    final todas = citasSeccionActual;
    if (todas.length <= _cantidadVisibleActual) {
      return todas;
    }
    return List<CitaPaciente>.unmodifiable(todas.take(_cantidadVisibleActual));
  }

  int get citasRestantesSeccionActual {
    final total = citasSeccionActual.length;
    return total > _cantidadVisibleActual ? total - _cantidadVisibleActual : 0;
  }

  bool get tieneMasCitasEnSeccionActual => citasRestantesSeccionActual > 0;

  int get cantidadProximoBloque {
    final restantes = citasRestantesSeccionActual;
    return restantes >= citasPorBloque ? citasPorBloque : restantes;
  }

  String get textoBotonVerMas {
    final cantidad = cantidadProximoBloque;
    if (cantidad <= 0) {
      return '';
    }
    return 'Ver $cantidad más';
  }

  /// Cambia de seccion y restablece siempre el limite inicial a 5 citas.
  void seleccionarSeccion(SeccionMisCitas nuevaSeccion) {
    _usuarioEligioSeccion = true;
    final cambioSeccion = _seccionSeleccionada != nuevaSeccion;
    final cambioLimite = _cantidadVisibleActual != citasPorBloque;
    _seccionSeleccionada = nuevaSeccion;
    _cantidadVisibleActual = citasPorBloque;
    if (cambioSeccion || cambioLimite) {
      notifyListeners();
    }
  }

  /// Amplia hasta 5 citas adicionales dentro de la seccion activa sin recargar red.
  void mostrarMasCitas() {
    if (!tieneMasCitasEnSeccionActual) {
      return;
    }
    _cantidadVisibleActual += citasPorBloque;
    notifyListeners();
  }

  /// Calcula cuanto falta para el proximo hito temporal real (inicio o fin de una
  /// cita confirmada o fin de una solicitud pendiente) en Ecuador continental.
  /// Devuelve null si no hay cambios previstos en las proximas 24 horas.
  Duration? calcularTiempoHastaProximoCambioEstado() {
    if (_citasPropias.isEmpty) {
      return null;
    }
    final ahoraEcuador = obtenerAhoraEnEcuador();
    DateTime? proximoHito;

    void registrarHito(DateTime candidato) {
      if (!candidato.isAfter(ahoraEcuador)) {
        return;
      }
      if (proximoHito == null || candidato.isBefore(proximoHito!)) {
        proximoHito = candidato;
      }
    }

    for (final cita in _citasPropias) {
      if (cita.esConfirmada) {
        registrarHito(cita.fechaHoraInicioEcuador);
        registrarHito(cita.fechaHoraFinEcuador);
      } else if (cita.esPendiente) {
        registrarHito(cita.fechaHoraFinEcuador);
      }
    }

    if (proximoHito == null) {
      return null;
    }

    final espera = proximoHito!.difference(ahoraEcuador);
    if (espera > const Duration(hours: 24)) {
      return null;
    }
    return espera + const Duration(seconds: 1);
  }

  /// Reevalua la clasificacion y estado "en curso" cuando avanza el tiempo.
  /// Solo notifica a la vista si efectivamente hubo un cambio visual.
  bool recalcularClasificacionTemporal() {
    final nuevaHuella = _calcularHuellaTemporal();
    if (nuevaHuella == _huellaTemporalClasificacion) {
      return false;
    }
    _huellaTemporalClasificacion = nuevaHuella;
    notifyListeners();
    return true;
  }

  String _calcularHuellaTemporal() {
    final referenciaUtc = _servicio.obtenerAhoraUtc();
    final buffer = StringBuffer();
    for (final cita in _citasPropias) {
      final seccion = cita.clasificarSeccion(referenciaUtc: referenciaUtc);
      final enCurso = cita.estaEnCursoEnEcuador(referenciaUtc: referenciaUtc);
      final vencida = cita.esSolicitudPendienteVencida(
        referenciaUtc: referenciaUtc,
      );
      buffer.write('${cita.idCita}:${seccion.index}:$enCurso:$vencida|');
    }
    return buffer.toString();
  }

  void limpiarMensajesSolicitud() {
    _mensajeErrorSolicitud = null;
    _mensajeExitoSolicitud = null;
    notifyListeners();
  }

  void seleccionarHorario(HorarioDisponibilidad? horario) {
    if (_estaEnviandoSolicitud) {
      return;
    }
    _horarioSeleccionado = horario;
    _mensajeErrorSolicitud = null;
    _mensajeExitoSolicitud = null;
    _ultimaCitaSolicitada = null;
    notifyListeners();
  }

  Future<void> cargarHorariosDisponibles(
    String idProfesional, {
    bool conservarErrorSolicitud = false,
  }) async {
    _estaCargandoHorarios = true;
    _mensajeErrorHorarios = null;
    if (!conservarErrorSolicitud) {
      _mensajeErrorSolicitud = null;
    }
    notifyListeners();

    try {
      final lista = await _servicio.listarHorariosDisponiblesProfesional(
        idProfesional: idProfesional,
      );
      _horariosDisponibles = List<HorarioDisponibilidad>.unmodifiable(lista);

      if (_horarioSeleccionado != null) {
        final sigueDisponible = _horariosDisponibles.any(
          (item) =>
              item.idDisponibilidad == _horarioSeleccionado!.idDisponibilidad,
        );
        if (!sigueDisponible) {
          _horarioSeleccionado = null;
        }
      }
    } on ErrorCitasPaciente catch (error) {
      _mensajeErrorHorarios = error.mensaje;
    } catch (_) {
      _mensajeErrorHorarios = 'No se pudieron cargar los horarios disponibles del profesional. Inténtalo de nuevo.';
    } finally {
      _estaCargandoHorarios = false;
      notifyListeners();
    }
  }

  Future<bool> enviarSolicitudCita({required String idProfesional}) async {
    if (_estaEnviandoSolicitud) {
      return false;
    }

    final seleccionado = _horarioSeleccionado;
    if (seleccionado == null) {
      _mensajeErrorSolicitud =
          'Selecciona un horario disponible antes de enviar la solicitud.';
      notifyListeners();
      return false;
    }

    final sigueEnFuturo = seleccionado.esFuturoEnEcuador(
      referenciaUtc: _servicio.obtenerAhoraUtc(),
    );
    if (!sigueEnFuturo) {
      _horarioSeleccionado = null;
      _mensajeErrorSolicitud = 'El horario seleccionado ya inició o venció según la hora de Ecuador continental. Selecciona un horario futuro.';
      notifyListeners();
      await cargarHorariosDisponibles(
        idProfesional,
        conservarErrorSolicitud: true,
      );
      return false;
    }

    _estaEnviandoSolicitud = true;
    _mensajeErrorSolicitud = null;
    _mensajeExitoSolicitud = null;
    notifyListeners();

    try {
      final cita = await _servicio.solicitarCita(
        idProfesional: idProfesional,
        idDisponibilidad: seleccionado.idDisponibilidad,
      );
      _ultimaCitaSolicitada = cita;
      _horarioSeleccionado = null;
      _horariosDisponibles = List<HorarioDisponibilidad>.unmodifiable(
        _horariosDisponibles
            .where((item) => item.idDisponibilidad != cita.idDisponibilidad)
            .toList(),
      );
      _mensajeExitoSolicitud = 'Solicitud enviada correctamente. Tu cita quedó registrada en estado pendiente de confirmación por el profesional.';
      _estaEnviandoSolicitud = false;
      notifyListeners();
      return true;
    } on ErrorCitasPaciente catch (error) {
      _mensajeErrorSolicitud = error.mensaje;
      _estaEnviandoSolicitud = false;
      if (error.esConflictoHorarioOcupado || error.esSolicitudDuplicada) {
        _horarioSeleccionado = null;
        notifyListeners();
        await cargarHorariosDisponibles(
          idProfesional,
          conservarErrorSolicitud: true,
        );
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      _mensajeErrorSolicitud =
          'No se pudo enviar la solicitud de cita. Inténtalo nuevamente.';
      _estaEnviandoSolicitud = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> cargarCitasPropias() async {
    _estaCargandoCitasPropias = true;
    _mensajeErrorCitasPropias = null;
    notifyListeners();

    try {
      final lista = await _servicio.listarCitasPropias();
      _citasPropias = List<CitaPaciente>.unmodifiable(lista);
      _huellaTemporalClasificacion = _calcularHuellaTemporal();

      // Si el usuario aun no selecciono pestana manualmente y no hay citas proximas
      // pero si solicitudes pendientes vigentes, abre directamente en Pendientes.
      if (!_usuarioEligioSeccion) {
        if (citasProximas.isNotEmpty) {
          _seccionSeleccionada = SeccionMisCitas.proximas;
        } else if (citasPendientes.isNotEmpty) {
          _seccionSeleccionada = SeccionMisCitas.pendientes;
        } else {
          _seccionSeleccionada = SeccionMisCitas.proximas;
        }
      }
    } on ErrorCitasPaciente catch (error) {
      _mensajeErrorCitasPropias = error.mensaje;
    } catch (_) {
      _mensajeErrorCitasPropias =
          'No se pudieron cargar tus solicitudes de cita. Inténtalo de nuevo.';
    } finally {
      _estaCargandoCitasPropias = false;
      notifyListeners();
    }
  }
}
