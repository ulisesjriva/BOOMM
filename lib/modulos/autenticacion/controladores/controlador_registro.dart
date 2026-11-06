import 'package:flutter/foundation.dart';

import 'package:boom/modulos/autenticacion/servicios/servicio_registro.dart';

/// Coordina el registro publico. Una respuesta aceptada no confirma el correo.
class ControladorRegistro extends ChangeNotifier {
  ControladorRegistro({this.servicio = const ServicioRegistro()});

  final ServicioRegistro servicio;
  bool _estaRegistrando = false;
  bool _registroAceptado = false;
  bool _cerrado = false;
  String? _mensajeError;

  bool get estaRegistrando => _estaRegistrando;
  bool get registroAceptado => _registroAceptado;
  String? get mensajeError => _mensajeError;

  Future<bool> registrar({
    required String nombre,
    required String apellido,
    required String correo,
    required String clave,
    required bool esProfesional,
    required bool aceptaTerminos,
  }) async {
    if (_cerrado || _estaRegistrando || _registroAceptado) {
      return false;
    }
    _mensajeError = null;
    if (!aceptaTerminos) {
      _mensajeError =
          'Debes aceptar los términos y condiciones para continuar.';
      notifyListeners();
      return false;
    }
    _estaRegistrando = true;
    notifyListeners();
    try {
      await servicio.registrar(
        nombre: nombre.trim(),
        apellido: apellido.trim(),
        correo: correo.trim(),
        clave: clave,
        esProfesional: esProfesional,
      );
      if (_cerrado) {
        return false;
      }
      _registroAceptado = true;
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioRegistro.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaRegistrando = false;
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
