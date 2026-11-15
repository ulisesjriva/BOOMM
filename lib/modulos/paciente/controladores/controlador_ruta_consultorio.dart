import 'package:flutter/foundation.dart';

import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';

/// Controlador MVC que coordina la obtencion de la ubicacion actual del paciente
/// (con solicitud de permiso en primer plano) y el calculo de la ruta vial,
/// distancia y tiempo estimado hacia el consultorio del profesional.
class ControladorRutaConsultorio extends ChangeNotifier {
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioRutasConsultorio servicioRutas;

  ControladorRutaConsultorio({
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioRutas = const ServicioRutasConsultorio(),
  });

  EstadoCalculoRuta _estado = EstadoCalculoRuta.inicial;
  RutaConsultorio? _ruta;
  CoordenadaMapa? _ubicacionPaciente;
  String? _mensajeEstado;
  bool _cerrado = false;

  EstadoCalculoRuta get estado => _estado;
  bool get estaCalculando => _estado == EstadoCalculoRuta.calculando;
  RutaConsultorio? get ruta => _ruta;
  CoordenadaMapa? get ubicacionPaciente => _ubicacionPaciente;
  String? get mensajeEstado => _mensajeEstado;

  /// Solicita la ubicacion de origen del paciente y calcula la ruta vial
  /// hacia las coordenadas guardadas del consultorio.
  Future<bool> calcularRutaHaciaConsultorio({
    required double? destinoLatitud,
    required double? destinoLongitud,
  }) async {
    if (_cerrado || estaCalculando) return false;

    if (destinoLatitud == null ||
        destinoLongitud == null ||
        !CoordenadaMapa(
          latitud: destinoLatitud,
          longitud: destinoLongitud,
        ).esValida) {
      _estado = EstadoCalculoRuta.coordenadasDestinoIncompletas;
      _ruta = null;
      _mensajeEstado = 'El profesional aún no ha registrado coordenadas válidas del consultorio para calcular la ruta.';
      _notificar();
      return false;
    }

    _estado = EstadoCalculoRuta.calculando;
    _mensajeEstado = null;
    _notificar();

    try {
      // 1. Obtener ubicacion de origen con permiso del usuario
      final resultadoUbicacion = await servicioUbicacion
          .obtenerUbicacionActual();
      if (_cerrado) return false;

      if (resultadoUbicacion.estado != EstadoUbicacionDispositivo.obtenida ||
          resultadoUbicacion.latitud == null ||
          resultadoUbicacion.longitud == null) {
        _estado = EstadoCalculoRuta.sinUbicacionOrigen;
        _ruta = null;
        _mensajeEstado =
            resultadoUbicacion.mensaje ??
            'No se pudo obtener tu ubicación actual para calcular la ruta.';
        _notificar();
        return false;
      }

      _ubicacionPaciente = CoordenadaMapa(
        latitud: resultadoUbicacion.latitud!,
        longitud: resultadoUbicacion.longitud!,
      );

      // 2. Consultar ruta vial real, distancia y tiempo estimado al proveedor
      final resultadoRuta = await servicioRutas.calcularRuta(
        origenLatitud: _ubicacionPaciente!.latitud,
        origenLongitud: _ubicacionPaciente!.longitud,
        destinoLatitud: destinoLatitud,
        destinoLongitud: destinoLongitud,
      );
      if (_cerrado) return false;

      if (resultadoRuta.fueExitoso && resultadoRuta.ruta != null) {
        _estado = EstadoCalculoRuta.rutaObtenida;
        _ruta = resultadoRuta.ruta;
        _mensajeEstado = null;
        _notificar();
        return true;
      }

      _estado = resultadoRuta.estado;
      _ruta = null;
      _mensajeEstado =
          resultadoRuta.mensaje ??
          'No se pudo calcular la ruta hacia el consultorio.';
      _notificar();
      return false;
    } catch (_) {
      if (_cerrado) return false;
      _estado = EstadoCalculoRuta.errorProveedor;
      _ruta = null;
      _mensajeEstado =
          'No se pudo completar el cálculo de la ruta. Inténtalo nuevamente.';
      _notificar();
      return false;
    }
  }

  void limpiarRuta() {
    if (_cerrado) return;
    _estado = EstadoCalculoRuta.inicial;
    _ruta = null;
    _mensajeEstado = null;
    _notificar();
  }

  void _notificar() {
    if (!_cerrado) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
