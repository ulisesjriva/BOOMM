import 'package:flutter/foundation.dart';

import '../modelos/cita_profesional.dart';
import '../modelos/horario_disponibilidad.dart';
import '../servicios/servicio_citas_profesional.dart';

class ControladorCitasProfesional extends ChangeNotifier {
  ControladorCitasProfesional({ServicioCitasProfesional? servicio})
    : _servicio = servicio ?? const ServicioCitasProfesional();

  final ServicioCitasProfesional _servicio;

  List<CitaProfesional> _citas = const <CitaProfesional>[];
  FiltroEstadoCitaProfesional _filtroSeleccionado =
      FiltroEstadoCitaProfesional.pendientes;

  bool _estaCargando = false;
  bool _estaProcesandoRespuesta = false;
  String? _idCitaEnProceso;

  String? _mensajeErrorCarga;
  String? _mensajeErrorOperacion;
  String? _mensajeExito;

  List<CitaProfesional> get citas => _citas;
  FiltroEstadoCitaProfesional get filtroSeleccionado => _filtroSeleccionado;

  List<CitaProfesional> get citasFiltradas {
    final estadoFiltro = _filtroSeleccionado.valorEstado;
    return List<CitaProfesional>.unmodifiable(
      _citas
          .where((cita) => cita.estado.trim().toLowerCase() == estadoFiltro)
          .toList(),
    );
  }

  int get totalPendientes => _citas.where((c) => c.esPendiente).length;
  int get totalConfirmadas => _citas.where((c) => c.esConfirmada).length;
  int get totalRechazadas => _citas.where((c) => c.esRechazada).length;

  bool get estaCargando => _estaCargando;
  bool get estaProcesandoRespuesta => _estaProcesandoRespuesta;
  String? get idCitaEnProceso => _idCitaEnProceso;

  String? get mensajeErrorCarga => _mensajeErrorCarga;
  String? get mensajeErrorOperacion => _mensajeErrorOperacion;
  String? get mensajeExito => _mensajeExito;

  DateTime obtenerAhoraUtc() => _servicio.obtenerAhoraUtc();

  DateTime obtenerAhoraEnEcuador() {
    return HorarioDisponibilidad.obtenerAhoraEnEcuador(
      referenciaUtc: _servicio.obtenerAhoraUtc(),
    );
  }

  void limpiarMensajesOperacion() {
    _mensajeErrorOperacion = null;
    _mensajeExito = null;
    notifyListeners();
  }

  void cambiarFiltro(FiltroEstadoCitaProfesional nuevoFiltro) {
    if (_filtroSeleccionado == nuevoFiltro) {
      return;
    }
    _filtroSeleccionado = nuevoFiltro;
    _mensajeErrorOperacion = null;
    _mensajeExito = null;
    notifyListeners();
  }

  Future<void> cargarCitasPropias({
    bool conservarMensajesOperacion = false,
  }) async {
    _estaCargando = true;
    _mensajeErrorCarga = null;
    if (!conservarMensajesOperacion) {
      _mensajeErrorOperacion = null;
      _mensajeExito = null;
    }
    notifyListeners();

    try {
      final lista = await _servicio.listarCitasPropias();
      _citas = List<CitaProfesional>.unmodifiable(lista);
    } on ErrorCitasProfesional catch (error) {
      _mensajeErrorCarga = error.mensaje;
    } catch (_) {
      _mensajeErrorCarga =
          'No se pudieron cargar las solicitudes de citas. Inténtalo de nuevo.';
    } finally {
      _estaCargando = false;
      notifyListeners();
    }
  }

  Future<bool> aceptarSolicitud(String idCita) {
    return _responderSolicitud(idCita: idCita, decision: 'confirmada');
  }

  Future<bool> rechazarSolicitud(String idCita) {
    return _responderSolicitud(idCita: idCita, decision: 'rechazada');
  }

  Future<bool> _responderSolicitud({
    required String idCita,
    required String decision,
  }) async {
    if (_estaProcesandoRespuesta) {
      return false;
    }

    final idLimpio = idCita.trim();
    final indice = _citas.indexWhere((c) => c.idCita == idLimpio);
    if (indice < 0) {
      _mensajeErrorOperacion =
          'No se encontró la solicitud de cita seleccionada.';
      notifyListeners();
      return false;
    }

    final citaActual = _citas[indice];
    if (!citaActual.esPendiente) {
      _mensajeErrorOperacion = 'Esta solicitud ya fue respondida anteriormente y no puede modificarse.';
      notifyListeners();
      return false;
    }

    final sigueEnFuturo = citaActual.esFuturoEnEcuador(
      referenciaUtc: _servicio.obtenerAhoraUtc(),
    );
    if (!sigueEnFuturo) {
      _mensajeErrorOperacion = 'No puedes responder una solicitud cuyo horario ya ha comenzado (hora de Ecuador continental).';
      notifyListeners();
      return false;
    }

    _estaProcesandoRespuesta = true;
    _idCitaEnProceso = idLimpio;
    _mensajeErrorOperacion = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final citaActualizada = await _servicio.responderSolicitudCita(
        idCita: idLimpio,
        decision: decision,
      );

      final nuevaLista = List<CitaProfesional>.from(_citas);
      final posicion = nuevaLista.indexWhere(
        (c) => c.idCita == citaActualizada.idCita,
      );
      if (posicion >= 0) {
        nuevaLista[posicion] = citaActualizada;
      }
      _citas = List<CitaProfesional>.unmodifiable(nuevaLista);

      final decisionNormalizada = decision.trim().toLowerCase();
      final esAceptacion =
          decisionNormalizada == 'confirmada' ||
          decisionNormalizada == 'aceptar' ||
          decisionNormalizada == 'aceptada';

      String? mensajeResultado;
      if (citaActualizada.esConfirmada) {
        mensajeResultado = 'Solicitud aceptada. La cita quedó confirmada y el horario permanece reservado.';
      } else if (citaActualizada.esRechazada) {
        mensajeResultado = 'Solicitud rechazada. La cita se conservó en el historial y el horario quedó nuevamente disponible.';
      } else if (citaActualizada.esPendiente && esAceptacion) {
        mensajeResultado = 'Solicitud aceptada. Quedó pendiente de adelanto y el horario permanece reservado mientras el paciente envía su comprobante.';
      } else {
        _mensajeErrorOperacion =
            'El servidor devolvió un estado inesperado (${citaActualizada.estado}) al registrar tu respuesta. Actualiza las solicitudes para verificar el estado real.';
        _estaProcesandoRespuesta = false;
        _idCitaEnProceso = null;
        notifyListeners();
        await cargarCitasPropias(conservarMensajesOperacion: true);
        return false;
      }

      _mensajeExito = mensajeResultado;
      _estaProcesandoRespuesta = false;
      _idCitaEnProceso = null;
      notifyListeners();

      await cargarCitasPropias(conservarMensajesOperacion: true);
      return true;
    } on ErrorCitasProfesional catch (error) {
      _mensajeErrorOperacion = error.mensaje;
      _estaProcesandoRespuesta = false;
      _idCitaEnProceso = null;
      if (error.esSolicitudYaRespondida) {
        notifyListeners();
        await cargarCitasPropias(conservarMensajesOperacion: true);
      } else {
        notifyListeners();
      }
      return false;
    } catch (_) {
      _mensajeErrorOperacion = 'No se pudo registrar tu respuesta sobre la solicitud. Inténtalo nuevamente.';
      _estaProcesandoRespuesta = false;
      _idCitaEnProceso = null;
      notifyListeners();
      return false;
    }
  }
}
