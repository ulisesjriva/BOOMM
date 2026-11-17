import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/administrador/modelos/modelos_administracion.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorAdministracion implements Exception {
  final String mensaje;
  const ErrorAdministracion(this.mensaje);

  @override
  String toString() => mensaje;
}

typedef EjecutorRpcAdministracion = Future<dynamic> Function(
  String nombreFuncion, {
  Map<String, dynamic>? parametros,
});

/// Representa un profesional con solicitud de aprobacion pendiente.
/// Distingue explicitamente `idUsuario` (`public."Usuarios".id_usuario`, usado
/// por `perfiles_compat` y `aprobar_profesional`) de `idProfesional`
/// (`public."Profesionales".id_profesional`).
class ProfesionalPendienteRevision {
  final String id;
  final String? idProfesional;
  final String nombre;
  final String apellido;
  final String correo;
  final String? especialidad;
  final String? numeroRegistro;
  final DateTime? creadoEn;

  const ProfesionalPendienteRevision({
    required this.id,
    this.idProfesional,
    required this.nombre,
    required this.apellido,
    required this.correo,
    this.especialidad,
    this.numeroRegistro,
    this.creadoEn,
  });

  /// Identificador de usuario en `public."Usuarios".id_usuario` / `perfiles_compat.id`.
  String get idUsuario => id;

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  factory ProfesionalPendienteRevision.desdeMapa(Map<String, dynamic> datos) {
    final idUsuarioExtraido =
        (datos['id'] as String?)?.trim() ??
        (datos['id_usuario'] as String?)?.trim() ??
        '';
    final idProfesionalExtraido = (datos['id_profesional'] as String?)?.trim();
    final creadoEnBruto = datos['creado_en'];
    DateTime? fechaCreacion;
    if (creadoEnBruto is String && creadoEnBruto.trim().isNotEmpty) {
      fechaCreacion = DateTime.tryParse(creadoEnBruto.trim());
    } else if (creadoEnBruto is DateTime) {
      fechaCreacion = creadoEnBruto;
    }

    return ProfesionalPendienteRevision(
      id: idUsuarioExtraido.isNotEmpty
          ? idUsuarioExtraido
          : (idProfesionalExtraido ?? ''),
      idProfesional: idProfesionalExtraido,
      nombre: datos['nombre'] as String? ?? datos['nombres'] as String? ?? '',
      apellido:
          datos['apellido'] as String? ?? datos['apellidos'] as String? ?? '',
      correo: datos['correo'] as String? ?? '',
      especialidad: datos['especialidad'] as String?,
      numeroRegistro: datos['numero_registro'] as String?,
      creadoEn: fechaCreacion,
    );
  }
}

/// Servicio para las funciones administrativas en Supabase.
/// Todas las RPC validan en el servidor que el usuario tenga rol `administrador` activo.
class ServicioAdministracion {
  final EjecutorRpcAdministracion? ejecutorRpc;

  const ServicioAdministracion({this.ejecutorRpc});

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorAdministracion(
        'Falta la configuración de Supabase. Ejecuta la aplicación con la URL y la clave pública.',
      );
    }
    return Supabase.instance.client;
  }

  Future<dynamic> _invocarRpc(
    String nombreFuncion, {
    Map<String, dynamic>? parametros,
  }) {
    if (ejecutorRpc != null) {
      return ejecutorRpc!(nombreFuncion, parametros: parametros);
    }
    return _cliente.rpc(nombreFuncion, params: parametros);
  }

  Future<ResumenAdministracion> obtenerResumenGeneral() async {
    final respuesta = await _invocarRpc('resumen_administracion');
    if (respuesta is Map) {
      return ResumenAdministracion.desdeMapa(
        Map<String, dynamic>.from(respuesta),
      );
    }
    throw const ErrorAdministracion(
      'No se pudo interpretar el resumen administrativo del servidor.',
    );
  }

  Future<List<UsuarioAdministracion>> listarUsuarios({
    String busqueda = '',
    String rol = 'todos',
    int pagina = 0,
    int tamano = 20,
  }) async {
    final respuesta = await _invocarRpc(
      'listar_usuarios_administracion',
      parametros: {
        'p_busqueda': busqueda.trim().isEmpty ? null : busqueda.trim(),
        'p_rol': rol,
        'p_pagina': pagina,
        'p_tamano': tamano,
      },
    );
    if (respuesta is! List) return const [];
    return respuesta
        .whereType<Map>()
        .map(
          (fila) =>
              UsuarioAdministracion.desdeMapa(Map<String, dynamic>.from(fila)),
        )
        .toList();
  }

  Future<List<ProfesionalAdministracion>> listarProfesionales({
    String estado = 'todos',
  }) async {
    final respuesta = await _invocarRpc(
      'listar_profesionales_administracion',
      parametros: {'p_estado': estado},
    );
    if (respuesta is! List) return const [];
    return respuesta
        .whereType<Map>()
        .map(
          (fila) => ProfesionalAdministracion.desdeMapa(
            Map<String, dynamic>.from(fila),
          ),
        )
        .toList();
  }

  Future<List<ProfesionalPendienteRevision>>
  listarProfesionalesPendientes() async {
    final respuesta = await _invocarRpc('listar_profesionales_pendientes');
    if (respuesta is! List) return const [];
    return respuesta
        .whereType<Map>()
        .map(
          (fila) => ProfesionalPendienteRevision.desdeMapa(
            Map<String, dynamic>.from(fila),
          ),
        )
        .toList();
  }

  Future<void> revisarProfesional({
    required String profesionalId,
    required bool aprobar,
    String? motivo,
  }) async {
    final idLimpio = profesionalId.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorAdministracion(
        'No se identificó la solicitud profesional a revisar.',
      );
    }
    if (!aprobar && (motivo == null || motivo.trim().length < 5)) {
      throw const ErrorAdministracion(
        'Indica un motivo de rechazo de al menos 5 caracteres.',
      );
    }
    await _invocarRpc(
      'aprobar_profesional',
      parametros: {
        'p_profesional_id': idLimpio,
        'p_decision': aprobar ? 'aprobado' : 'rechazado',
        'p_motivo': motivo?.trim(),
      },
    );
  }

  /// Activa o desactiva una cuenta mediante la RPC autorizada.
  /// Nunca aprueba automaticamente un perfil profesional al reactivarlo.
  Future<void> cambiarEstadoCuenta({
    required String usuarioId,
    required bool activo,
    required String motivo,
  }) async {
    final idLimpio = usuarioId.trim();
    if (idLimpio.isEmpty) {
      throw const ErrorAdministracion(
        'Indica el usuario cuyo estado deseas actualizar.',
      );
    }
    if (motivo.trim().length < 5) {
      throw const ErrorAdministracion(
        'Indica un motivo de al menos 5 caracteres para cambiar el estado de la cuenta.',
      );
    }
    await _invocarRpc(
      'cambiar_estado_cuenta',
      parametros: {
        'p_usuario_id': idLimpio,
        'p_activo': activo,
        'p_motivo': motivo.trim(),
      },
    );
  }

  Future<List<Especialidad>> listarEspecialidades() async {
    final respuesta = await _invocarRpc('listar_especialidades_administracion');
    if (respuesta is! List) return const [];
    return respuesta
        .whereType<Map>()
        .map((fila) => Especialidad.desdeMapa(Map<String, dynamic>.from(fila)))
        .toList();
  }

  Future<void> guardarEspecialidad({
    String? idEspecialidad,
    required String nombre,
    String? descripcion,
  }) async {
    final nombreNormalizado = nombre.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nombreNormalizado.length < 3) {
      throw const ErrorAdministracion(
        'El nombre de la especialidad debe tener al menos 3 caracteres.',
      );
    }
    await _invocarRpc(
      'guardar_especialidad_administracion',
      parametros: {
        'p_id_especialidad': idEspecialidad,
        'p_nombre': nombreNormalizado,
        'p_descripcion': descripcion?.trim(),
      },
    );
  }

  Future<void> cambiarEstadoEspecialidad({
    required String idEspecialidad,
    required bool activa,
  }) async {
    if (idEspecialidad.trim().isEmpty) {
      throw const ErrorAdministracion('Especialidad no válida.');
    }
    await _invocarRpc(
      'cambiar_estado_especialidad_administracion',
      parametros: {
        'p_id_especialidad': idEspecialidad.trim(),
        'p_activa': activa,
      },
    );
  }

  Future<List<CitaAdministracion>> listarCitas({
    String estado = 'todas',
    String? fechaDesde,
    String? fechaHasta,
    int pagina = 0,
    int tamano = 25,
  }) async {
    final respuesta = await _invocarRpc(
      'listar_citas_administracion',
      parametros: {
        'p_estado': estado,
        'p_fecha_desde': fechaDesde,
        'p_fecha_hasta': fechaHasta,
        'p_pagina': pagina,
        'p_tamano': tamano,
      },
    );
    if (respuesta is! List) return const [];
    return respuesta
        .whereType<Map>()
        .map(
          (fila) =>
              CitaAdministracion.desdeMapa(Map<String, dynamic>.from(fila)),
        )
        .toList();
  }

  Future<void> corregirDatosUsuario({
    required String usuarioId,
    required String nombre,
    required String apellido,
    String? numeroRegistro,
  }) async {
    if (usuarioId.trim().isEmpty) {
      throw const ErrorAdministracion('Selecciona un usuario válido.');
    }
    if (nombre.trim().length < 2 || apellido.trim().length < 2) {
      throw const ErrorAdministracion(
        'Nombre y apellido deben tener al menos 2 caracteres.',
      );
    }
    await _invocarRpc(
      'corregir_datos_usuario_administracion',
      parametros: {
        'p_usuario_id': usuarioId.trim(),
        'p_nombre': nombre.trim(),
        'p_apellido': apellido.trim(),
        'p_numero_registro': numeroRegistro?.trim(),
      },
    );
  }

  /// Genera un CSV RFC-4180 de las citas visibles y autorizadas sin modificar estados.
  String exportarCitasCsv(List<CitaAdministracion> citas) {
    String escapar(String valor) {
      final limpio = valor.replaceAll('"', '""');
      return '"$limpio"';
    }

    final buffer = StringBuffer()
      ..writeln('Paciente,Profesional,Fecha,Hora inicio,Hora fin,Estado');
    for (final cita in citas) {
      buffer.writeln(
        [
          escapar(cita.pacienteNombre),
          escapar(cita.profesionalNombre),
          escapar(cita.fecha),
          escapar(cita.horaInicio),
          escapar(cita.horaFin),
          escapar(cita.estadoLegible),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  static String explicarError(Object error) {
    if (error is ErrorAdministracion) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'Acceso denegado: esta operación requiere una cuenta de administrador activa.';
      }
      if (error.code == 'PGRST202' || error.code == '42883') {
        return 'Esta función administrativa aún no está habilitada en el servidor. Inténtalo más tarde.';
      }
      if (error.code == '23505') {
        return 'Ya existe un registro con ese nombre.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto:
            'No se pudo completar la operación administrativa en este momento.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto: 'No se pudo completar la operación administrativa. Revisa tu conexión e inténtalo nuevamente.',
    );
  }
}
