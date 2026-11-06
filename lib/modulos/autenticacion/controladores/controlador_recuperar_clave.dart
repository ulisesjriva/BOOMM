import 'package:flutter/foundation.dart';

import 'package:boom/modulos/autenticacion/servicios/servicio_recuperacion_clave.dart';

/// Coordina la solicitud; aceptarla no confirma que exista una cuenta
/// ni que el proveedor haya entregado el correo.
class ControladorRecuperarClave extends ChangeNotifier {
  ControladorRecuperarClave({
    this.servicio = const ServicioRecuperacionClave(),
  });

  final ServicioRecuperacionClave servicio;
  bool _estaEnviando = false;
  bool _cerrado = false;
  String? _mensajeError;

  bool get estaEnviando => _estaEnviando;
  String? get mensajeError => _mensajeError;

  Future<bool> solicitarEnlace(String correo) async {
    if (_cerrado || _estaEnviando) return false;
    _estaEnviando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      await servicio.solicitarEnlace(correo.trim());
      return !_cerrado;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioRecuperacionClave.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaEnviando = false;
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
