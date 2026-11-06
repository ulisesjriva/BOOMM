import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';

/// Coordina la recuperacion con un servicio temporal propio de esta pantalla.
class ControladorNuevaClave extends ChangeNotifier {
  ControladorNuevaClave({ServicioEnlaceAutenticacion? servicio})
    : _servicio = servicio ?? ServicioEnlaceAutenticacion();

  final ServicioEnlaceAutenticacion _servicio;
  bool _enlaceValidado = false;
  bool _estaValidando = false;
  bool _estaGuardando = false;
  bool _claveActualizada = false;
  bool _cerrado = false;
  String? _mensajeEnlace;
  Future<void>? _cierre;

  bool get enlaceValidado => _enlaceValidado;
  bool get estaValidando => _estaValidando;
  bool get estaGuardando => _estaGuardando;
  bool get ocupado => _estaValidando || _estaGuardando;
  bool get claveActualizada => _claveActualizada;
  String? get mensajeEnlace => _mensajeEnlace;

  static String? validarClave(String? clave) =>
      ServicioEnlaceAutenticacion.validarClave(clave);

  Future<bool> validarEnlace(EnlaceAutenticacion? enlace) async {
    if (_cerrado || ocupado || _claveActualizada) return false;
    // No consumir otra vez un token que ya valido este controlador.
    if (_enlaceValidado) return true;
    if (enlace == null ||
        enlace.tipo != TipoEnlaceAutenticacion.recuperacion ||
        enlace.tokenHash == null) {
      _mensajeEnlace = 'Abre un enlace de recuperación válido desde tu correo.';
      notifyListeners();
      return false;
    }
    _estaValidando = true;
    _mensajeEnlace = null;
    notifyListeners();
    try {
      await _servicio.validarRecuperacion(enlace);
      if (_cerrado) return false;
      _enlaceValidado = true;
      _mensajeEnlace = 'Enlace validado. Ya puedes crear una contraseña nueva.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeEnlace = ServicioEnlaceAutenticacion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaValidando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> guardarClave(String clave) async {
    if (_cerrado || ocupado || _claveActualizada) return false;
    if (!_enlaceValidado) {
      _mensajeEnlace = 'Primero valida el enlace de recuperación.';
      notifyListeners();
      return false;
    }
    final errorClave = validarClave(clave);
    if (errorClave != null) {
      _mensajeEnlace = errorClave;
      notifyListeners();
      return false;
    }
    _estaGuardando = true;
    _mensajeEnlace = null;
    notifyListeners();
    try {
      await _servicio.guardarClave(clave);
      if (_cerrado) return false;
      _enlaceValidado = false;
      _claveActualizada = true;
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeEnlace = ServicioEnlaceAutenticacion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGuardando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cerrar() {
    if (_cerrado) return _cierre ?? Future<void>.value();
    _cerrado = true;
    _enlaceValidado = false;
    return _cierre = _servicio.cerrar();
  }

  @override
  void dispose() {
    unawaited(cerrar());
    super.dispose();
  }
}
