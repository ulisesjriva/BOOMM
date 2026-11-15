/// Representa un registro del catalogo persistente public."Especialidades" en Supabase.
class Especialidad {
  final String id;
  final String nombre;
  final String descripcion;
  final bool activa;

  const Especialidad({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    this.activa = true,
  });

  /// Construye una instancia aceptando tanto `id_especialidad` (clave primaria
  /// real en public."Especialidades") como `id`.
  factory Especialidad.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id_especialidad'] ?? datos['id']) as String?;
    final nombre = datos['nombre'] as String?;
    if (id == null ||
        id.trim().isEmpty ||
        nombre == null ||
        nombre.trim().isEmpty) {
      throw const FormatException(
        'La especialidad recibida no tiene un identificador o nombre válido.',
      );
    }
    return Especialidad(
      id: id.trim(),
      nombre: nombre.trim(),
      descripcion: (datos['descripcion'] as String?)?.trim() ?? '',
      activa: datos['activa'] as bool? ?? true,
    );
  }

  Map<String, dynamic> aMapa() {
    return {
      'id_especialidad': id,
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'activa': activa,
    };
  }
}
