/// Modelo que representa a un profesional de la salud mental en PsicoBloom.
/// Diseñado para cumplir con el alcance del MVP y compatible con las RPC
/// `directorio_profesionales_completo` y `directorio_profesionales` en Supabase.
class Profesional {
  final String id;
  final String? idProfesional;
  final String nombre;
  final String especialidad;
  final List<String> especialidades;
  final String modalidad;
  final String descripcion;
  final String servicios;
  final int? aniosExperiencia;
  final String? fotoUrl;
  final String disponibilidadTexto;
  final String distanciaTexto;
  final String direccionConsultorio;
  final double latitud;
  final double longitud;
  final bool tieneUbicacion;
  final double calificacion;
  final bool estaDisponible;
  final bool esDestacado;

  const Profesional({
    required this.id,
    this.idProfesional,
    required this.nombre,
    required this.especialidad,
    this.especialidades = const [],
    required this.modalidad,
    this.descripcion = '',
    this.servicios = '',
    this.aniosExperiencia,
    this.fotoUrl,
    required this.disponibilidadTexto,
    required this.distanciaTexto,
    required this.direccionConsultorio,
    required this.latitud,
    required this.longitud,
    this.tieneUbicacion = true,
    this.calificacion = 5.0,
    this.estaDisponible = true,
    this.esDestacado = false,
  });

  /// Identificador de la tabla `public."Profesionales"` cuando difiere de `id_usuario`.
  String get idProfesionalEfectivo {
    final limpio = idProfesional?.trim();
    if (limpio != null && limpio.isNotEmpty) {
      return limpio;
    }
    return id.trim();
  }

  /// Indica si el profesional cuenta con coordenadas reales validas para mostrar en mapa.
  bool get tieneCoordenadasValidas =>
      tieneUbicacion &&
      (latitud != 0.0 || longitud != 0.0) &&
      latitud >= -90.0 &&
      latitud <= 90.0 &&
      longitud >= -180.0 &&
      longitud <= 180.0;

  /// Constructor de fabrica para instanciar a partir de un mapa, compatible
  /// con `directorio_profesionales_completo`, `directorio_profesionales` y
  /// `public."Profesionales"`.
  factory Profesional.desdeMapa(Map<String, dynamic> mapa) {
    final nombreBase = ((mapa['nombre'] ?? mapa['nombres']) as String? ?? '')
        .trim();
    final apellidoBase =
        ((mapa['apellido'] ?? mapa['apellidos']) as String? ?? '').trim();
    final nombreCompleto = apellidoBase.isNotEmpty
        ? '$nombreBase $apellidoBase'.trim()
        : nombreBase;

    final listaEsp = (mapa['especialidades'] is List)
        ? (mapa['especialidades'] as List)
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];

    final especialidadPrincipal =
        (mapa['especialidad'] as String?)?.trim().isNotEmpty == true
        ? (mapa['especialidad'] as String).trim()
        : (listaEsp.isNotEmpty ? listaEsp.join(', ') : 'Psicología General');

    final latitudNum = (mapa['latitud'] as num?)?.toDouble();
    final longitudNum = (mapa['longitud'] as num?)?.toDouble();
    final tieneCoordenadas = latitudNum != null && longitudNum != null;

    final direccion = (mapa['direccion_consultorio'] as String?)?.trim() ?? '';
    final distanciaMapa = (mapa['distancia_texto'] as String?)?.trim() ?? '';
    final distanciaMostrada = distanciaMapa.isNotEmpty
        ? distanciaMapa
        : (direccion.isNotEmpty
              ? direccion
              : (tieneCoordenadas
                    ? 'Riobamba (ubicación en mapa)'
                    : 'Ubicación de consultorio por confirmar'));

    final disponibilidadMapa =
        (mapa['disponibilidad_texto'] as String?)?.trim() ?? '';
    final disponibilidadMostrada = disponibilidadMapa.isNotEmpty
        ? disponibilidadMapa
        : 'Consulta de perfil disponible';

    final idResuelto =
        (mapa['id'] ?? mapa['id_profesional'] ?? mapa['id_usuario'])
            as String? ??
        '';
    final idProfesionalMapa = (mapa['id_profesional'] as String?)?.trim();
    final idProfesionalResuelto =
        idProfesionalMapa != null && idProfesionalMapa.isNotEmpty
        ? idProfesionalMapa
        : idResuelto;

    return Profesional(
      id: idResuelto,
      idProfesional: idProfesionalResuelto,
      nombre: nombreCompleto,
      especialidad: especialidadPrincipal,
      especialidades: listaEsp.isNotEmpty ? listaEsp : [especialidadPrincipal],
      modalidad: (mapa['modalidad'] as String?)?.trim().isNotEmpty == true
          ? (mapa['modalidad'] as String).trim()
          : 'Presencial',
      descripcion: (mapa['descripcion'] as String?)?.trim() ?? '',
      servicios: (mapa['servicios'] as String?)?.trim() ?? '',
      aniosExperiencia: (mapa['anios_experiencia'] as num?)?.toInt(),
      fotoUrl: (mapa['foto_url'] as String?)?.trim(),
      disponibilidadTexto: disponibilidadMostrada,
      distanciaTexto: distanciaMostrada,
      direccionConsultorio: direccion,
      latitud: latitudNum ?? 0.0,
      longitud: longitudNum ?? 0.0,
      tieneUbicacion: tieneCoordenadas,
      calificacion: (mapa['calificacion'] as num?)?.toDouble() ?? 5.0,
      estaDisponible: mapa['esta_disponible'] as bool? ?? true,
      esDestacado: mapa['es_destacado'] as bool? ?? false,
    );
  }

  /// Convierte el modelo a un mapa para serializacion o almacenamiento local.
  Map<String, dynamic> aMapa() {
    return {
      'id': id,
      'id_profesional': idProfesionalEfectivo,
      'nombre': nombre,
      'especialidad': especialidad,
      'especialidades': especialidades,
      'modalidad': modalidad,
      'descripcion': descripcion,
      'servicios': servicios,
      'anios_experiencia': aniosExperiencia,
      'foto_url': fotoUrl,
      'disponibilidad_texto': disponibilidadTexto,
      'distancia_texto': distanciaTexto,
      'direccion_consultorio': direccionConsultorio,
      'latitud': latitud,
      'longitud': longitud,
      'tiene_ubicacion': tieneUbicacion,
      'calificacion': calificacion,
      'esta_disponible': estaDisponible,
      'es_destacado': esDestacado,
    };
  }
}
