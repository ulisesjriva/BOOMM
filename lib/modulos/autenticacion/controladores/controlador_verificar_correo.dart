import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/modelos/enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_enlace_autenticacion.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';

/// Coordina confirmacion, consulta y reenvio sin confundir sus resultados.
class ControladorVerificarCorreo extends ChangeNotifier {
  ControladorVerificarCorreo({
    this.servicio = const ServicioRegistro(),
    ServicioEnlaceAutenticacion? servicioEnlace,
    bool iniciarEspera = true,
  }) : _servicioEnlace = servicioEnlace ?? ServicioEnlaceAutenticacion() {
    if (iniciarEspera) {
      _iniciarEsperaReenvio();
    }
  }

  final ServicioRegistro servicio;
  final ServicioEnlaceAutenticacion _servicioEnlace;
  bool _estaComprobando = false;
  bool _estaReenviando = false;
  bool _confirmadoDesdeEnlace = false;
  bool _cerrado = false;
  int _segundosReenvio = 0;
  String? _mensajeEnlace;
  String? _mensajeError;
  Timer? _relojReenvio;
  Future<void>? _cierre;

  bool get estaComprobando => _estaComprobando;
  bool get estaReenviando => _estaReenviando;
  bool get confirmadoDesdeEnlace => _confirmadoDesdeEnlace;
  bool get ocupado => _estaComprobando || _estaReenviando;
  int get segundosReenvio => _segundosReenvio;
  String? get mensajeEnlace => _mensajeEnlace;
  String? get mensajeError => _mensajeError;

  void _iniciarEsperaReenvio() {
    _relojReenvio?.cancel();
    _segundosReenvio = 60;
    _relojReenvio = Timer.periodic(const Duration(seconds: 1), (reloj) {
      if (_cerrado) {
        reloj.cancel();
        return;
      }
      _segundosReenvio--;
      if (_segundosReenvio <= 0) {
        reloj.cancel();
      }
      notifyListeners();
    });
  }

  /// null sin mensajeError significa ausencia de sesion confirmada local,
  /// no ausencia de confirmacion en otro navegador o dispositivo.
  Future<PerfilUsuario?> comprobarConfirmacion(String correo) async {
    if (_cerrado || ocupado) {
      return null;
    }
    _estaComprobando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      final perfil = await servicio.comprobarConfirmacion(correo.trim());
      return _cerrado ? null : perfil;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioRegistro.explicarError(error);
      }
      return null;
    } finally {
      if (!_cerrado) {
        _estaComprobando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> reenviarEnlace(String correo) async {
    if (_cerrado || ocupado || _segundosReenvio > 0) {
      return false;
    }
    _estaReenviando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      await servicio.reenviarEnlace(correo.trim());
      if (_cerrado) {
        return false;
      }
      _iniciarEsperaReenvio();
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioRegistro.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaReenviando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> confirmarEnlace(EnlaceAutenticacion? enlace) async {
    if (_cerrado || ocupado) {
      return false;
    }
    if (_confirmadoDesdeEnlace) {
      return true;
    }
    if (enlace == null ||
        enlace.tipo != TipoEnlaceAutenticacion.confirmacion ||
        enlace.tokenHash == null) {
      _mensajeEnlace = 'Abre un enlace de confirmación válido desde tu correo.';
      notifyListeners();
      return false;
    }
    _estaComprobando = true;
    _mensajeEnlace = null;
    notifyListeners();
    try {
      final correo = await _servicioEnlace.confirmarCorreo(enlace);
      if (_cerrado) {
        return false;
      }
      _confirmadoDesdeEnlace = true;
      _mensajeEnlace = correo.isEmpty
          ? 'Tu correo electrónico ha sido confirmado. Ya puedes iniciar sesión.'
          : 'Tu correo $correo ha sido confirmado. Ya puedes iniciar sesión.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeEnlace = ServicioEnlaceAutenticacion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaComprobando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cerrar() {
    if (_cerrado) {
      return _cierre ?? Future<void>.value();
    }
    _cerrado = true;
    _relojReenvio?.cancel();
    return _cierre = _servicioEnlace.cerrar();
  }

  @override
  void dispose() {
    unawaited(cerrar());
    super.dispose();
  }
}
