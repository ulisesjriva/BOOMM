/// Perfil obtenido del servidor; el rol nunca se decide por el formulario.
class PerfilUsuario {
  final String id;
  final String nombre;
  final String apellido;
  final String rol;
  final String aprobacion;
  final bool cuentaActiva;

  const PerfilUsuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.rol,
    required this.aprobacion,
    required this.cuentaActiva,
  });

  factory PerfilUsuario.desdeMapa(Map<String, dynamic> datos) {
    if (datos['id'] is! String ||
        datos['nombre'] is! String ||
        datos['apellido'] is! String ||
        datos['cuenta_activa'] is! bool ||
        !['paciente', 'profesional', 'administrador'].contains(datos['rol']) ||
        ![
          'no_aplica',
          'pendiente',
          'aprobado',
          'rechazado',
        ].contains(datos['aprobacion'])) {
      throw const FormatException(
        'El perfil recibido no tiene el formato esperado.',
      );
    }
    return PerfilUsuario(
      id: datos['id'] as String,
      nombre: datos['nombre'] as String,
      apellido: datos['apellido'] as String,
      rol: datos['rol'] as String,
      aprobacion: datos['aprobacion'] as String,
      cuentaActiva: datos['cuenta_activa'] as bool,
    );
  }
}
