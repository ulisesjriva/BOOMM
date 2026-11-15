import 'package:geolocator/geolocator.dart';

/// Estados posibles al solicitar la ubicacion actual del dispositivo.
enum EstadoUbicacionDispositivo {
  obtenida,
  servicioDesactivado,
  permisoRechazado,
  permisoRechazadoPermanente,
  errorLectura,
}

/// Resultado tipado de la consulta de ubicacion para el consultorio.
class ResultadoUbicacionDispositivo {
  final EstadoUbicacionDispositivo estado;
  final double? latitud;
  final double? longitud;
  final String? mensaje;

  const ResultadoUbicacionDispositivo({
    required this.estado,
    this.latitud,
    this.longitud,
    this.mensaje,
  });

  const ResultadoUbicacionDispositivo.obtenida({
    required double this.latitud,
    required double this.longitud,
  }) : estado = EstadoUbicacionDispositivo.obtenida,
       mensaje = null;

  const ResultadoUbicacionDispositivo.fallo(this.estado, String this.mensaje)
    : latitud = null,
      longitud = null;
}

/// Servicio para obtener opcionalmente la ubicacion en primer plano del dispositivo
/// y validar coordenadas del consultorio en Riobamba.
/// Nunca solicita ubicacion en segundo plano ni bloquea el flujo manual.
class ServicioUbicacionConsultorio {
  const ServicioUbicacionConsultorio();

  /// Coordenadas referenciales del centro de Riobamba (Parque Maldonado)
  /// usadas unicamente como centro inicial de camara del selector cuando
  /// aun no hay ubicacion guardada, nunca guardadas automaticamente como reales.
  static const double latitudReferenciaRiobamba = -1.67098;
  static const double longitudReferenciaRiobamba = -78.64712;

  static String? validarCoordenadas({
    required String textoLatitud,
    required String textoLongitud,
  }) {
    final latLimpia = textoLatitud.trim();
    final lngLimpia = textoLongitud.trim();

    if (latLimpia.isEmpty && lngLimpia.isEmpty) {
      return null; // Ubicacion opcional si aun no la registra
    }
    if (latLimpia.isEmpty || lngLimpia.isEmpty) {
      return 'Ingresa tanto la latitud como la longitud del consultorio.';
    }

    final lat = double.tryParse(latLimpia.replaceAll(',', '.'));
    final lng = double.tryParse(lngLimpia.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      return 'Las coordenadas deben ser números decimales válidos (ej. -1.67098).';
    }
    if (lat < -90.0 || lat > 90.0) {
      return 'La latitud debe estar entre -90 y 90 grados.';
    }
    if (lng < -180.0 || lng > 180.0) {
      return 'La longitud debe estar entre -180 y 180 grados.';
    }
    if (lat == 0.0 && lng == 0.0) {
      return 'Selecciona una ubicación válida en el mapa o escribe coordenadas reales.';
    }
    return null;
  }

  Future<ResultadoUbicacionDispositivo> obtenerUbicacionActual() async {
    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        return const ResultadoUbicacionDispositivo.fallo(
          EstadoUbicacionDispositivo.servicioDesactivado,
          'El servicio de ubicación (GPS) está desactivado en tu dispositivo. Puedes activarlo o seleccionar la ubicación manualmente en el mapa.',
        );
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          return const ResultadoUbicacionDispositivo.fallo(
            EstadoUbicacionDispositivo.permisoRechazado,
            'Permiso de ubicación rechazado. Puedes seleccionar la ubicación del consultorio manualmente tocando el mapa o ingresando las coordenadas.',
          );
        }
      }

      if (permiso == LocationPermission.deniedForever) {
        return const ResultadoUbicacionDispositivo.fallo(
          EstadoUbicacionDispositivo.permisoRechazadoPermanente,
          'El permiso de ubicación fue rechazado permanentemente. Habilítalo en los ajustes del sistema o selecciona el consultorio manualmente.',
        );
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return ResultadoUbicacionDispositivo.obtenida(
        latitud: posicion.latitude,
        longitud: posicion.longitude,
      );
    } catch (_) {
      return const ResultadoUbicacionDispositivo.fallo(
        EstadoUbicacionDispositivo.errorLectura,
        'No se pudo obtener la ubicación actual del dispositivo. Selecciona el punto manualmente en el mapa.',
      );
    }
  }
}
