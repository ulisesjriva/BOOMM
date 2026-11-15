import 'package:flutter/foundation.dart';

import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';

/// Coordina la consulta y revision de solicitudes de profesionales pendientes.
class ControladorAdministracion extends ChangeNotifier {
  ControladorAdministracion({this.servicio = const ServicioAdministracion()});

  final ServicioAdministracion servicio;

  List<ProfesionalPendienteRevision> _pendientes = const [];
  bool _estaCargando = false;
  bool _estaProcesando = false;
  bool _cerrado = false;
  String? _mensajeError;
  String? _mensajeExito;

  List<ProfesionalPendienteRevision> get pendientes => _pendientes;
  bool get estaCargando => _estaCargando;
  bool get estaProcesando => _estaProcesando;
  bool get ocupado => _estaCargando || _estaProcesando;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;

  Future<void> cargarPendientes() async {
    if (_cerrado || _estaCargando) return;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final lista = await servicio.listarProfesionalesPendientes();
      if (_cerrado) return;
      _pendientes = List.unmodifiable(lista);
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> decidirSolicitud({
    required String profesionalId,
    required bool aprobar,
    String? motivo,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.revisarProfesional(
        profesionalId: profesionalId,
        aprobar: aprobar,
        motivo: motivo,
      );
      if (_cerrado) return false;
      _pendientes = List.unmodifiable(
        _pendientes.where(
          (item) =>
              item.idUsuario != profesionalId &&
              item.id != profesionalId &&
              item.idProfesional != profesionalId,
        ),
      );
      _mensajeExito = aprobar
          ? 'Solicitud profesional aprobada.'
          : 'Solicitud profesional rechazada con su motivo registrado.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
