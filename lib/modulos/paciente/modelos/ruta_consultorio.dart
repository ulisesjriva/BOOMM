/// Representa un punto geografico validado para el mapa y el trazado de rutas.
class CoordenadaMapa {
  final double latitud;
  final double longitud;

  const CoordenadaMapa({required this.latitud, required this.longitud});

  bool get esValida =>
      !latitud.isNaN &&
      !longitud.isNaN &&
      latitud >= -90.0 &&
      latitud <= 90.0 &&
      longitud >= -180.0 &&
      longitud <= 180.0 &&
      !(latitud == 0.0 && longitud == 0.0);

  factory CoordenadaMapa.desdeMapa(Map<String, dynamic> mapa) {
    final lat = mapa['latitud'] ?? mapa['lat'] ?? mapa['latitude'];
    final lng = mapa['longitud'] ?? mapa['lng'] ?? mapa['longitude'];
    return CoordenadaMapa(
      latitud: lat is num
          ? lat.toDouble()
          : double.tryParse(lat?.toString() ?? '') ?? double.nan,
      longitud: lng is num
          ? lng.toDouble()
          : double.tryParse(lng?.toString() ?? '') ?? double.nan,
    );
  }
}

/// Modelo que representa el recorrido vial real entre la ubicacion del paciente
/// y el consultorio del profesional seleccionado en Riobamba.
/// Distingue explicitamente el tiempo estimado de traslado frente al trafico en vivo.
class RutaConsultorio {
  final CoordenadaMapa origen;
  final CoordenadaMapa destino;
  final List<CoordenadaMapa> puntosPolilinea;
  final double distanciaMetros;
  final int duracionEstimadaSegundos;
  final bool incluyeTraficoTiempoReal;
  final String proveedor;

  const RutaConsultorio({
    required this.origen,
    required this.destino,
    required this.puntosPolilinea,
    required this.distanciaMetros,
    required this.duracionEstimadaSegundos,
    this.incluyeTraficoTiempoReal = false,
    this.proveedor = 'openrouteservice',
  });

  /// Verifica que la ruta contenga geometria vial valida y metricas reales.
  bool get esRutaCalleValida =>
      origen.esValida &&
      destino.esValida &&
      puntosPolilinea.length >= 2 &&
      puntosPolilinea.every((p) => p.esValida) &&
      distanciaMetros > 0 &&
      duracionEstimadaSegundos > 0;

  /// Formatea la distancia vial real en metros o kilometros.
  String get distanciaTexto {
    if (distanciaMetros < 1000) {
      return '${distanciaMetros.round()} m';
    }
    final kilometros = (distanciaMetros / 100.0).round() / 10.0;
    return '${kilometros.toStringAsFixed(1)} km';
  }

  /// Formatea la duracion estimada de recorrido en minutos u horas.
  String get tiempoEstimadoTexto {
    final minutosTotales = (duracionEstimadaSegundos / 60.0).ceil();
    final minutos = minutosTotales < 1 ? 1 : minutosTotales;
    if (minutos < 60) {
      return '$minutos min aprox.';
    }
    final horas = minutos ~/ 60;
    final minutosRestantes = minutos % 60;
    if (minutosRestantes == 0) {
      return '$horas h aprox.';
    }
    return '$horas h $minutosRestantes min aprox.';
  }

  /// Aviso explicito para distinguir tiempo estimado vs trafico en tiempo real.
  String get avisoNaturalezaTiempo => incluyeTraficoTiempoReal
      ? 'Tiempo calculado con condiciones de tráfico en tiempo real.'
      : 'Tiempo estimado según la vía (no incluye tráfico en tiempo real).';

  /// Decodifica una polilinea en formato estandar Google / OpenRouteService (precision 1e-5).
  static List<CoordenadaMapa> decodificarPolilinea(String cadenaCodificada) {
    final puntos = <CoordenadaMapa>[];
    var indice = 0;
    var lat = 0;
    var lng = 0;

    while (indice < cadenaCodificada.length) {
      var b = 0;
      var desplazamiento = 0;
      var resultado = 0;
      do {
        b = cadenaCodificada.codeUnitAt(indice++) - 63;
        resultado |= (b & 0x1f) << desplazamiento;
        desplazamiento += 5;
      } while (b >= 0x20 && indice < cadenaCodificada.length);
      final deltaLat = (resultado & 1) != 0
          ? ~(resultado >> 1)
          : (resultado >> 1);
      lat += deltaLat;

      desplazamiento = 0;
      resultado = 0;
      do {
        b = cadenaCodificada.codeUnitAt(indice++) - 63;
        resultado |= (b & 0x1f) << desplazamiento;
        desplazamiento += 5;
      } while (b >= 0x20 && indice < cadenaCodificada.length);
      final deltaLng = (resultado & 1) != 0
          ? ~(resultado >> 1)
          : (resultado >> 1);
      lng += deltaLng;

      puntos.add(CoordenadaMapa(latitud: lat / 1e5, longitud: lng / 1e5));
    }

    return puntos;
  }
}
