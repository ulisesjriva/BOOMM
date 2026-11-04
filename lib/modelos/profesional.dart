/// Modelo que representa a un profesional de la salud mental en PsicoBloom.
/// Diseñado para cumplir con el alcance del MVP y facilitar la transicion
/// directa hacia consultas en Supabase.
class Profesional {
  final String id;
  final String nombre;
  final String especialidad;
  final String modalidad;
  final String disponibilidadTexto;
  final String distanciaTexto;
  final String direccionConsultorio;
  final double latitud;
  final double longitud;
  final double calificacion;
  final bool estaDisponible;
  final bool esDestacado;

  const Profesional({
    required this.id,
    required this.nombre,
    required this.especialidad,
    required this.modalidad,
    required this.disponibilidadTexto,
    required this.distanciaTexto,
    required this.direccionConsultorio,
    required this.latitud,
    required this.longitud,
    this.calificacion = 5.0,
    this.estaDisponible = true,
    this.esDestacado = false,
  });

  /// Constructor de fabrica para instanciar a partir de un mapa,
  /// compatible con la futura respuesta JSON de Supabase.
  factory Profesional.desdeMapa(Map<String, dynamic> mapa) {
    return Profesional(
      id: mapa['id'] as String? ?? '',
      nombre: mapa['nombre'] as String? ?? '',
      especialidad: mapa['especialidad'] as String? ?? '',
      modalidad: mapa['modalidad'] as String? ?? 'Presencial',
      disponibilidadTexto: mapa['disponibilidad_texto'] as String? ?? '',
      distanciaTexto: mapa['distancia_texto'] as String? ?? '',
      direccionConsultorio: mapa['direccion_consultorio'] as String? ?? '',
      latitud: (mapa['latitud'] as num?)?.toDouble() ?? 0.0,
      longitud: (mapa['longitud'] as num?)?.toDouble() ?? 0.0,
      calificacion: (mapa['calificacion'] as num?)?.toDouble() ?? 5.0,
      estaDisponible: mapa['esta_disponible'] as bool? ?? true,
      esDestacado: mapa['es_destacado'] as bool? ?? false,
    );
  }

  /// Convierte el modelo a un mapa para serializacion o almacenamiento local.
  Map<String, dynamic> aMapa() {
    return {
      'id': id,
      'nombre': nombre,
      'especialidad': especialidad,
      'modalidad': modalidad,
      'disponibilidad_texto': disponibilidadTexto,
      'distancia_texto': distanciaTexto,
      'direccion_consultorio': direccionConsultorio,
      'latitud': latitud,
      'longitud': longitud,
      'calificacion': calificacion,
      'esta_disponible': estaDisponible,
      'es_destacado': esDestacado,
    };
  }
}
