/// Perfil obtenido del servidor mediante `perfil_del_usuario_actual()`;
/// el rol nunca se decide por el formulario.
class PerfilUsuario {
  final String id;
  final String nombre;
  final String apellido;
  final String correo;
  final String rol;
  final String aprobacion;
  final bool cuentaActiva;

  const PerfilUsuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.correo = '',
    required this.rol,
    required this.aprobacion,
    required this.cuentaActiva,
  });

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  PerfilUsuario copiarCon({
    String? nombre,
    String? apellido,
    String? correo,
    String? rol,
    String? aprobacion,
    bool? cuentaActiva,
  }) {
    return PerfilUsuario(
      id: id,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      correo: correo ?? this.correo,
      rol: rol ?? this.rol,
      aprobacion: aprobacion ?? this.aprobacion,
      cuentaActiva: cuentaActiva ?? this.cuentaActiva,
    );
  }

  /// Instancia desde la respuesta de `perfil_del_usuario_actual()` o las columnas
  /// equivalentes de `public."Usuarios"` (`id_usuario`, `nombres`, `apellidos`, `activo`).
  factory PerfilUsuario.desdeMapa(Map<String, dynamic> datos) {
    final id = (datos['id'] ?? datos['id_usuario'] ?? datos['id_paciente']);
    final nombre = (datos['nombre'] ?? datos['nombres']);
    final apellido = (datos['apellido'] ?? datos['apellidos']);
    final cuentaActiva = (datos['cuenta_activa'] ?? datos['activo']);
    final rol = (datos['rol'] ?? datos['nombre_rol']);
    final aprobacion = datos['aprobacion'] ?? 'no_aplica';

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
    );
  }
}
