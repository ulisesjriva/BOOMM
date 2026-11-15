import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:boom/configuracion/configuracion_supabase.dart';
import 'package:boom/nucleo/utilidades/traductor_errores_supabase.dart';

class ErrorAdministracion implements Exception {
  final String mensaje;
  const ErrorAdministracion(this.mensaje);

  @override
  String toString() => mensaje;
}

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

/// Servicio para las funciones administrativas ya disponibles en el backend.
/// Las RPC verifican en el servidor que el usuario tenga rol `administrador` activo.
class ServicioAdministracion {
  const ServicioAdministracion();

  SupabaseClient get _cliente {
    if (!ConfiguracionSupabase.estaConfigurado) {
      throw const ErrorAdministracion(
        'Falta la configuración de Supabase. Ejecuta la aplicación con la URL y la clave pública.',
      );
    }
    return Supabase.instance.client;
  }

  Future<List<ProfesionalPendienteRevision>>
  listarProfesionalesPendientes() async {
    final respuesta = await _cliente.rpc('listar_profesionales_pendientes');
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
    await _cliente.rpc(
      'aprobar_profesional',
      params: {
        'p_profesional_id': idLimpio,
        'p_decision': aprobar ? 'aprobado' : 'rechazado',
        'p_motivo': motivo?.trim(),
      },
    );
  }

  /// Activa o desactiva una cuenta de paciente o profesional mediante la RPC existente.
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
    await _cliente.rpc(
      'cambiar_estado_cuenta',
      params: {
        'p_usuario_id': idLimpio,
        'p_activo': activo,
        'p_motivo': motivo.trim(),
      },
    );
  }

  static String explicarError(Object error) {
    if (error is ErrorAdministracion) return error.mensaje;
    if (error is PostgrestException) {
      if (error.code == '42501') {
        return 'Acceso denegado: esta operación requiere una cuenta de administrador activa.';
      }
      return TraductorErroresSupabase.traducirErrorBaseDatos(
        error,
        accionPorDefecto: 'No se pudo completar la revisión administrativa en este momento. Inténtalo nuevamente.',
      );
    }
    return TraductorErroresSupabase.traducirErrorBaseDatos(
      error,
      accionPorDefecto: 'No se pudo completar la operación administrativa. Comprueba tu conexión.',
    );
  }
}
