import 'package:flutter/foundation.dart';

import 'package:boom/modelos/perfil_usuario.dart';
import 'package:boom/modulos/autenticacion/servicios/servicio_inicio_sesion.dart';

/// Coordina el acceso sin almacenar credenciales ni depender de la navegacion.
class ControladorInicioSesion extends ChangeNotifier {
  ControladorInicioSesion({this.servicio = const ServicioInicioSesion()});

  final ServicioInicioSesion servicio;
  bool _estaCargando = false;
  bool _cerrado = false;
  String? _mensajeError;

  bool get estaCargando => _estaCargando;
  String? get mensajeError => _mensajeError;

  Future<PerfilUsuario?> iniciarSesion({
    required String correo,
    required String clave,
  }) async {
    if (_cerrado || _estaCargando) return null;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      final perfil = await servicio.iniciarSesionPaciente(
        correo: correo.trim(),
        clave: clave,
      );
      if (_cerrado) return null;
      return perfil;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioInicioSesion.explicarError(error);
      }
      return null;
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
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
