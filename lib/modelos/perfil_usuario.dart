/// Perfil obtenido del servidor mediante `perfil_del_usuario_actual()`
/// o `obtener_perfil_paciente_propio()`; el rol nunca se decide por el formulario.
class PerfilUsuario {
  final String id;
  final String nombre;
  final String apellido;
  final String correo;
  final String rol;
  final String aprobacion;
  final bool cuentaActiva;
  final String? fotoUrl;
  final bool tieneFotoPersonalizada;

  const PerfilUsuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.correo = '',
    required this.rol,
    required this.aprobacion,
    required this.cuentaActiva,
    this.fotoUrl,
    this.tieneFotoPersonalizada = false,
  });

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  PerfilUsuario copiarCon({
    String? nombre,
    String? apellido,
    String? correo,
    String? rol,
    String? aprobacion,
    bool? cuentaActiva,
    String? fotoUrl,
    bool? tieneFotoPersonalizada,
    bool limpiarFotoUrl = false,
  }) {
    return PerfilUsuario(
      id: id,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      correo: correo ?? this.correo,
      rol: rol ?? this.rol,
      aprobacion: aprobacion ?? this.aprobacion,
      cuentaActiva: cuentaActiva ?? this.cuentaActiva,
      fotoUrl: limpiarFotoUrl ? null : (fotoUrl ?? this.fotoUrl),
      tieneFotoPersonalizada: limpiarFotoUrl
          ? false
          : (tieneFotoPersonalizada ?? this.tieneFotoPersonalizada),
    );
  }

  /// Instancia desde la respuesta de `perfil_del_usuario_actual()`,
  /// `obtener_perfil_paciente_propio()` o columnas equivalentes de `public."Usuarios"`.
  factory PerfilUsuario.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id'] ?? datos['id_usuario'] ?? datos['id_paciente']);
    final nombre = (datos['nombre'] ?? datos['nombres']);
    final apellido = (datos['apellido'] ?? datos['apellidos']);
    final cuentaActiva = (datos['cuenta_activa'] ?? datos['activo']);
    final rol = (datos['rol'] ?? datos['nombre_rol']);
    final aprobacion = datos['aprobacion'] ?? 'no_aplica';
    final fotoBruta =
        datos['foto_url'] ?? datos['avatar_url'] ?? datos['picture'];
    final fotoLimpia = fotoBruta is String && fotoBruta.trim().isNotEmpty
        ? fotoBruta.trim()
        : null;
    final tienePersonalizada =
        datos['tiene_foto_personalizada'] == true && fotoLimpia != null;

    if (id is! String ||
        nombre is! String ||
        apellido is! String ||
        cuentaActiva is! bool ||
        !['paciente', 'profesional', 'administrador'].contains(rol) ||
        ![
          'no_aplica',
          'pendiente',
          'aprobado',
          'rechazado',
        ].contains(aprobacion)) {
      throw const FormatException(
        'El perfil recibido no tiene el formato esperado.',
      );
    }
    return PerfilUsuario(
      id: id,
      nombre: nombre,
      apellido: apellido,
      correo: datos['correo'] is String ? datos['correo'] as String : '',
      rol: rol as String,
      aprobacion: aprobacion as String,
      cuentaActiva: cuentaActiva,
      fotoUrl: fotoLimpia,
      tieneFotoPersonalizada: tienePersonalizada,
    );
  }
}
