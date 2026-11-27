import 'package:flutter/foundation.dart';

import 'package:boom/modulos/paciente/modelos/info_economica_profesional.dart';
import 'package:boom/modulos/paciente/servicios/servicio_info_economica_profesional.dart';

/// Controlador de lectura de la informacion economica de un profesional.
/// Protege contra respuestas tardias o cambios de profesional para no mezclar
/// importes antiguos de otro profesional.
class ControladorInfoEconomicaProfesional extends ChangeNotifier {
  final ServicioInfoEconomicaProfesional _servicio;

  ControladorInfoEconomicaProfesional({
    ServicioInfoEconomicaProfesional? servicio,
  }) : _servicio = servicio ?? const ServicioInfoEconomicaProfesional();

  InfoEconomicaProfesional? _info;
  String? _idProfesionalActual;
  String? _mensajeError;
  bool _estaCargando = false;
  bool _cerrado = false;
  int _secuenciaConsulta = 0;

  InfoEconomicaProfesional? get info => _info;
  String? get idProfesionalActual => _idProfesionalActual;
  String? get mensajeError => _mensajeError;
  bool get estaCargando => _estaCargando;

  /// Carga la informacion economica del profesional indicado.
  /// Limpia de inmediato los datos previos si cambia el profesional (o al reintentar)
  /// y descarta respuestas que lleguen fuera de orden.
  Future<void> cargar(String idProfesional) async {
    if (_cerrado) return;
    final idLimpio = idProfesional.trim();
    final int secuenciaLocal = ++_secuenciaConsulta;

    _idProfesionalActual = idLimpio;
    _info = null;
    _mensajeError = null;
    _estaCargando = true;
    notifyListeners();

    if (idLimpio.isEmpty) {
      if (_cerrado || secuenciaLocal != _secuenciaConsulta) return;
      _info = const InfoEconomicaProfesional.noDisponible();
      _estaCargando = false;
      notifyListeners();
      return;
    }

    try {
      final resultado = await _servicio.obtenerInfoEconomicaProfesional(
        idProfesional: idLimpio,
      );
      if (_cerrado || secuenciaLocal != _secuenciaConsulta) return;
      _info = resultado;
      _mensajeError = null;
    } catch (error) {
      if (_cerrado || secuenciaLocal != _secuenciaConsulta) return;
      _info = null;
      _mensajeError = ServicioInfoEconomicaProfesional.explicarError(error);
    } finally {
      if (!_cerrado && secuenciaLocal == _secuenciaConsulta) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> reintentar() async {
    final id = _idProfesionalActual;
    if (id == null) return;
    await cargar(id);
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
