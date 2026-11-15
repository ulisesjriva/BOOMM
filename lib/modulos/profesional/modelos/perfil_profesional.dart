/// Modelo tipado para la gestion del perfil propio del profesional en PsicoBloom.
/// Compatible con la RPC `obtener_perfil_profesional_propio` y con las tablas
/// reales `public."Usuarios"` y `public."Profesionales"`.
class PerfilProfesional {
  final String id;
  final String idProfesional;
  final String nombre;
  final String apellido;
  final String correo;
  final String aprobacion;
  final bool cuentaActiva;
  final String? especialidadTexto;
  final List<String> especialidadesIds;
  final List<String> especialidadesNombres;
  final String? numeroRegistro;
  final String? descripcion;
  final int? aniosExperiencia;
  final String? telefonoContacto;
  final String? fotoUrl;
  final String modalidad;
  final String? servicios;
  final String? direccionConsultorio;
  final double? latitud;
  final double? longitud;

  const PerfilProfesional({
    required this.id,
    String? idProfesional,
    required this.nombre,
    required this.apellido,
    required this.correo,
    required this.aprobacion,
    required this.cuentaActiva,
    this.especialidadTexto,
    this.especialidadesIds = const [],
    this.especialidadesNombres = const [],
    this.numeroRegistro,
    this.descripcion,
    this.aniosExperiencia,
    this.telefonoContacto,
    this.fotoUrl,
    this.modalidad = 'Presencial',
    this.servicios,
    this.direccionConsultorio,
    this.latitud,
    this.longitud,
  }) : idProfesional = idProfesional ?? id;

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  bool get tieneUbicacionValida =>
      latitud != null &&
      longitud != null &&
      latitud! >= -90.0 &&
      latitud! <= 90.0 &&
      longitud! >= -180.0 &&
      longitud! <= 180.0;

  PerfilProfesional copiarCon({
    String? idProfesional,
    String? nombre,
    String? apellido,
    String? correo,
    String? aprobacion,
    bool? cuentaActiva,
    String? especialidadTexto,
    List<String>? especialidadesIds,
    List<String>? especialidadesNombres,
    String? numeroRegistro,
    String? descripcion,
    int? aniosExperiencia,
    String? telefonoContacto,
    String? fotoUrl,
    String? modalidad,
    String? servicios,
    String? direccionConsultorio,
    double? latitud,
    double? longitud,
    bool limpiarUbicacion = false,
  }) {
    return PerfilProfesional(
      id: id,
      idProfesional: idProfesional ?? this.idProfesional,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      correo: correo ?? this.correo,
      aprobacion: aprobacion ?? this.aprobacion,
      cuentaActiva: cuentaActiva ?? this.cuentaActiva,
      especialidadTexto: especialidadTexto ?? this.especialidadTexto,
      especialidadesIds: especialidadesIds ?? this.especialidadesIds,
      especialidadesNombres:
          especialidadesNombres ?? this.especialidadesNombres,
      numeroRegistro: numeroRegistro ?? this.numeroRegistro,
      descripcion: descripcion ?? this.descripcion,
      aniosExperiencia: aniosExperiencia ?? this.aniosExperiencia,
      telefonoContacto: telefonoContacto ?? this.telefonoContacto,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      modalidad: modalidad ?? this.modalidad,
      servicios: servicios ?? this.servicios,
      direccionConsultorio: direccionConsultorio ?? this.direccionConsultorio,
      latitud: limpiarUbicacion ? null : (latitud ?? this.latitud),
      longitud: limpiarUbicacion ? null : (longitud ?? this.longitud),
    );
  }

  factory PerfilProfesional.desdeMapa(Map<String, dynamic> datos) {
    final ids = (datos['especialidades_ids'] is List)
        ? (datos['especialidades_ids'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    final nombres = (datos['especialidades_nombres'] is List)
        ? (datos['especialidades_nombres'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];

    final idUsuario =
        (datos['id'] ?? datos['id_usuario'] ?? datos['id_profesional'])
            as String? ??
        '';
    final idProf = (datos['id_profesional'] as String?)?.trim();

    return PerfilProfesional(
      id: idUsuario,
      idProfesional: (idProf != null && idProf.isNotEmpty) ? idProf : idUsuario,
      nombre: (datos['nombre'] ?? datos['nombres']) as String? ?? '',
      apellido: (datos['apellido'] ?? datos['apellidos']) as String? ?? '',
      correo: datos['correo'] as String? ?? '',
      aprobacion: datos['aprobacion'] as String? ?? 'pendiente',
      cuentaActiva:
          (datos['cuenta_activa'] ?? datos['activo']) as bool? ?? true,
      especialidadTexto: datos['especialidad'] as String?,
      especialidadesIds: ids,
      especialidadesNombres: nombres,
      numeroRegistro: datos['numero_registro'] as String?,
      descripcion: datos['descripcion'] as String?,
      aniosExperiencia: (datos['anios_experiencia'] as num?)?.toInt(),
      telefonoContacto:
          (datos['telefono_contacto'] ?? datos['telefono']) as String?,
      fotoUrl: datos['foto_url'] as String?,
      modalidad: (datos['modalidad'] as String?)?.trim().isNotEmpty == true
          ? (datos['modalidad'] as String).trim()
          : 'Presencial',
      servicios: datos['servicios'] as String?,
      direccionConsultorio: datos['direccion_consultorio'] as String?,
      latitud: (datos['latitud'] as num?)?.toDouble(),
      longitud: (datos['longitud'] as num?)?.toDouble(),
    );
  }
}
