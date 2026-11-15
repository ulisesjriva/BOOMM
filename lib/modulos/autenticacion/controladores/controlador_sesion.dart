import 'package:flutter/foundation.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_sesion.dart';

/// Coordina la restauracion de sesion, el estado de acceso por rol y el cierre de sesion.
class ControladorSesion extends ChangeNotifier {
  ControladorSesion({this.servicio = const ServicioSesion()});

  final ServicioSesion servicio;
  bool _estaCargando = false;
  bool _estaCerrandoSesion = false;
  bool _cerrado = false;
  EstadoResolucionSesion _estado = EstadoResolucionSesion.sinSesion;
  PerfilUsuario? _perfilActual;
  String? _mensajeAviso;

  bool get estaCargando => _estaCargando;
  bool get estaCerrandoSesion => _estaCerrandoSesion;
  EstadoResolucionSesion get estado => _estado;
  PerfilUsuario? get perfilActual => _perfilActual;
  String? get mensajeAviso => _mensajeAviso;
  bool get tieneSesionActiva =>
      _estado == EstadoResolucionSesion.autenticado &&
      _perfilActual != null &&
      _perfilActual!.cuentaActiva;

  Future<ResultadoResolucionSesion> verificarSesionInicial() async {
    if (_cerrado) {
      return const ResultadoResolucionSesion.sinSesion();
    }
    if (_estaCargando) {
      return ResultadoResolucionSesion(
        estado: _estado,
        perfil: _perfilActual,
        mensaje: _mensajeAviso,
      );
    }

    _estaCargando = true;
    _mensajeAviso = null;
    notifyListeners();

    try {
      final resultado = await servicio.resolverSesionActual();
      if (_cerrado) {
        return const ResultadoResolucionSesion.sinSesion();
      }
      _estado = resultado.estado;
      _perfilActual = resultado.perfil;
      _mensajeAviso = resultado.mensaje;
      return resultado;
    } catch (_) {
      if (!_cerrado) {
        _estado = EstadoResolucionSesion.errorConexion;
        _perfilActual = null;
        _mensajeAviso = 'No se pudo comprobar tu sesión. Revisa tu conexión e inténtalo nuevamente.';
      }
      return ResultadoResolucionSesion(
        estado: _estado,
        perfil: _perfilActual,
        mensaje: _mensajeAviso,
      );
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  void registrarSesionIniciada(PerfilUsuario perfil) {
    if (_cerrado) return;
    if (!perfil.cuentaActiva) {
      _estado = EstadoResolucionSesion.cuentaInactiva;
      _perfilActual = perfil;
      _mensajeAviso =
          'Tu cuenta está inactiva. Contacta al administrador de PsicoBloom.';
    } else {
      _estado = EstadoResolucionSesion.autenticado;
      _perfilActual = perfil;
      _mensajeAviso = null;
    }
    notifyListeners();
  }

  void actualizarPerfilActual(PerfilUsuario perfil) {
    if (_cerrado) return;
    _perfilActual = perfil;
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    if (_cerrado || _estaCerrandoSesion) return;
    _estaCerrandoSesion = true;
    notifyListeners();
    try {
      await servicio.cerrarSesion();
    } finally {
      if (!_cerrado) {
        _estaCerrandoSesion = false;
        _estado = EstadoResolucionSesion.sinSesion;
        _perfilActual = null;
        _mensajeAviso = null;
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
