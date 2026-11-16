import 'package:flutter/foundation.dart';
import '../modelos/cuestionario_orientacion.dart';

/// Gestor en memoria volátil para preservar el resultado de la orientación psicológica
/// durante la sesión activa del usuario, sin persistir datos en Supabase.
///
/// Si el usuario cierra sesión, el resultado se destruye llamando a [limpiar].
class GestorResultadoOrientacion extends ChangeNotifier {
  static final GestorResultadoOrientacion instancia =
      GestorResultadoOrientacion._interno();

  GestorResultadoOrientacion._interno();

  ResultadoOrientacion? _resultadoActual;
  DateTime? _fechaRealizacion;

  /// Retorna el resultado de orientación guardado en la sesión actual, o null si no se ha realizado.
  ResultadoOrientacion? get resultadoActual => _resultadoActual;

  /// Retorna la fecha y hora en que se completó el cuestionario.
  DateTime? get fechaRealizacion => _fechaRealizacion;

  /// Indica si el usuario ya completó el cuestionario en esta sesión.
  bool get tieneResultado => _resultadoActual != null;

  /// Guarda el resultado analizado en memoria volátil y notifica a los escuchas.
  void guardarResultado(ResultadoOrientacion resultado) {
    _resultadoActual = resultado;
    _fechaRealizacion = DateTime.now();
    notifyListeners();
  }

  /// Limpia el resultado en memoria (utilizado al cerrar sesión o al repetir el cuestionario).
  void limpiar() {
    _resultadoActual = null;
    _fechaRealizacion = null;
    notifyListeners();
  }
}
