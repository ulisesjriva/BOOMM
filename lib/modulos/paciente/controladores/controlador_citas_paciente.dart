import 'package:flutter/foundation.dart';
import 'package:boom/modulos/profesional/modelos/horario_disponibilidad.dart';

import '../modelos/cita_paciente.dart';
import '../servicios/servicio_citas_paciente.dart';

class ControladorCitasPaciente extends ChangeNotifier {
  ControladorCitasPaciente({ServicioCitasPaciente? servicio})
    : _servicio = servicio ?? const ServicioCitasPaciente();

  final ServicioCitasPaciente _servicio;

  List<HorarioDisponibilidad> _horariosDisponibles =
      const <HorarioDisponibilidad>[];
  HorarioDisponibilidad? _horarioSeleccionado;
  CitaPaciente? _ultimaCitaSolicitada;
  List<CitaPaciente> _citasPropias = const <CitaPaciente>[];

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

  bool get estaCargandoHorarios => _estaCargandoHorarios;
  bool get estaEnviandoSolicitud => _estaEnviandoSolicitud;
  bool get estaCargandoCitasPropias => _estaCargandoCitasPropias;

  String? get mensajeErrorHorarios => _mensajeErrorHorarios;
  String? get mensajeErrorSolicitud => _mensajeErrorSolicitud;
  String? get mensajeErrorCitasPropias => _mensajeErrorCitasPropias;
  String? get mensajeExitoSolicitud => _mensajeExitoSolicitud;

  DateTime obtenerAhoraEnEcuador() {
    return HorarioDisponibilidad.obtenerAhoraEnEcuador(
      referenciaUtc: _servicio.obtenerAhoraUtc(),
    );
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
