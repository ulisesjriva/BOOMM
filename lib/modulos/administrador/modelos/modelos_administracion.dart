/// Evento real reciente mostrado en el panel general del administrador.
class EventoActividadAdmin {
  final String tipo;
  final String titulo;
  final String detalle;
  final DateTime? fecha;

  const EventoActividadAdmin({
    required this.tipo,
    required this.titulo,
    required this.detalle,
    this.fecha,
  });

  factory EventoActividadAdmin.desdeMapa(Map<String, dynamic> datos) {
    final fechaRaw = datos['fecha'];
    DateTime? fecha;
    if (fechaRaw is String && fechaRaw.trim().isNotEmpty) {
      fecha = DateTime.tryParse(fechaRaw.trim());
    } else if (fechaRaw is DateTime) {
      fecha = fechaRaw;
    }
    return EventoActividadAdmin(
      tipo: datos['tipo'] as String? ?? 'evento',
      titulo: datos['titulo'] as String? ?? 'Actividad',
      detalle: datos['detalle'] as String? ?? '',
      fecha: fecha,
    );
  }
}

/// Indicadores reales del panel general calculados sobre todos los registros autorizados.
class ResumenAdministracion {
  final int usuariosRegistrados;
  final int profesionalesActivosAprobados;
  final int profesionalesPendientes;
  final int citasPendientes;
  final int citasConfirmadas;
  final int citasCanceladas;
  final int citasRechazadas;
  final int citasFinalizadas;
  final List<EventoActividadAdmin> actividadReciente;

  const ResumenAdministracion({
    required this.usuariosRegistrados,
    required this.profesionalesActivosAprobados,
    required this.profesionalesPendientes,
    required this.citasPendientes,
    required this.citasConfirmadas,
    required this.citasCanceladas,
    required this.citasRechazadas,
    required this.citasFinalizadas,
    this.actividadReciente = const [],
  });

  int get totalCitas =>
      citasPendientes +
      citasConfirmadas +
      citasCanceladas +
      citasRechazadas +
      citasFinalizadas;

  factory ResumenAdministracion.desdeMapa(Map<String, dynamic> datos) {
    final actividadBruta = datos['actividad_reciente'];
    final eventos = actividadBruta is List
        ? actividadBruta
              .whereType<Map>()
              .map(
                (item) => EventoActividadAdmin.desdeMapa(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <EventoActividadAdmin>[];

    return ResumenAdministracion(
      usuariosRegistrados:
          (datos['usuarios_registrados'] as num?)?.toInt() ?? 0,
      profesionalesActivosAprobados:
          (datos['profesionales_activos_aprobados'] as num?)?.toInt() ?? 0,
      profesionalesPendientes:
          (datos['profesionales_pendientes'] as num?)?.toInt() ?? 0,
      citasPendientes: (datos['citas_pendientes'] as num?)?.toInt() ?? 0,
      citasConfirmadas: (datos['citas_confirmadas'] as num?)?.toInt() ?? 0,
      citasCanceladas: (datos['citas_canceladas'] as num?)?.toInt() ?? 0,
      citasRechazadas: (datos['citas_rechazadas'] as num?)?.toInt() ?? 0,
      citasFinalizadas: (datos['citas_finalizadas'] as num?)?.toInt() ?? 0,
      actividadReciente: eventos,
    );
  }
}

/// Usuario registrado consultado en la gestion de usuarios.
class UsuarioAdministracion {
  final String id;
  final String nombre;
  final String apellido;
  final String correo;
  final String rol;
  final bool cuentaActiva;
  final String? aprobacion;
  final String? fotoUrl;
  final DateTime? creadoEn;
  final int totalRegistros;

  const UsuarioAdministracion({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.correo,
    required this.rol,
    required this.cuentaActiva,
    this.aprobacion,
    this.fotoUrl,
    this.creadoEn,
    this.totalRegistros = 0,
  });

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  String get rolLegible {
    switch (rol) {
      case 'profesional':
        return 'Profesional';
      case 'paciente':
        return 'Paciente';
      case 'administrador':
        return 'Administrador';
      default:
        return rol;
    }
  }

  factory UsuarioAdministracion.desdeMapa(Map<String, dynamic> datos) {
    final creadoRaw = datos['creado_en'];
    DateTime? creadoEn;
    if (creadoRaw is String && creadoRaw.trim().isNotEmpty) {
      creadoEn = DateTime.tryParse(creadoRaw.trim());
    } else if (creadoRaw is DateTime) {
      creadoEn = creadoRaw;
    }

    return UsuarioAdministracion(
      id: (datos['id'] as String? ?? '').trim(),
      nombre: (datos['nombre'] as String? ?? '').trim(),
      apellido: (datos['apellido'] as String? ?? '').trim(),
      correo: (datos['correo'] as String? ?? '').trim(),
      rol: (datos['rol'] as String? ?? 'paciente').trim(),
      cuentaActiva: datos['cuenta_activa'] as bool? ?? true,
      aprobacion: (datos['aprobacion'] as String?)?.trim(),
      fotoUrl: (datos['foto_url'] as String?)?.trim(),
      creadoEn: creadoEn,
      totalRegistros: (datos['total_registros'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Profesional listado en la gestion administrativa con detalle completo de revision.
class ProfesionalAdministracion {
  final String idUsuario;
  final String? idProfesional;
  final String nombre;
  final String apellido;
  final String correo;
  final String aprobacion;
  final bool cuentaActiva;
  final String especialidad;
  final String? numeroRegistro;
  final String? descripcion;
  final int? aniosExperiencia;
  final String? telefonoContacto;
  final String modalidad;
  final String? direccionConsultorio;
  final String? fotoUrl;
  final String? motivoRechazo;
  final DateTime? creadoEn;

  const ProfesionalAdministracion({
    required this.idUsuario,
    this.idProfesional,
    required this.nombre,
    required this.apellido,
    required this.correo,
    required this.aprobacion,
    required this.cuentaActiva,
    required this.especialidad,
    this.numeroRegistro,
    this.descripcion,
    this.aniosExperiencia,
    this.telefonoContacto,
    this.modalidad = 'Presencial',
    this.direccionConsultorio,
    this.fotoUrl,
    this.motivoRechazo,
    this.creadoEn,
  });

  String get nombreCompleto => '${nombre.trim()} ${apellido.trim()}'.trim();

  String get etiquetaEstado {
    if (!cuentaActiva) return 'Deshabilitado';
    switch (aprobacion) {
      case 'aprobado':
        return 'Aprobado';
      case 'rechazado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }

  factory ProfesionalAdministracion.desdeMapa(Map<String, dynamic> datos) {
    final creadoRaw = datos['creado_en'];
    DateTime? creadoEn;
    if (creadoRaw is String && creadoRaw.trim().isNotEmpty) {
      creadoEn = DateTime.tryParse(creadoRaw.trim());
    } else if (creadoRaw is DateTime) {
      creadoEn = creadoRaw;
    }

    return ProfesionalAdministracion(
      idUsuario:
          (datos['id_usuario'] as String? ?? datos['id'] as String? ?? '')
              .trim(),
      idProfesional: (datos['id_profesional'] as String?)?.trim(),
      nombre: (datos['nombre'] as String? ?? '').trim(),
      apellido: (datos['apellido'] as String? ?? '').trim(),
      correo: (datos['correo'] as String? ?? '').trim(),
      aprobacion: (datos['aprobacion'] as String? ?? 'pendiente').trim(),
      cuentaActiva: datos['cuenta_activa'] as bool? ?? true,
      especialidad:
          (datos['especialidad'] as String?)?.trim().isNotEmpty == true
          ? (datos['especialidad'] as String).trim()
          : 'Psicología General',
      numeroRegistro: (datos['numero_registro'] as String?)?.trim(),
      descripcion: (datos['descripcion'] as String?)?.trim(),
      aniosExperiencia: (datos['anios_experiencia'] as num?)?.toInt(),
      telefonoContacto: (datos['telefono_contacto'] as String?)?.trim(),
      modalidad: (datos['modalidad'] as String?)?.trim().isNotEmpty == true
          ? (datos['modalidad'] as String).trim()
          : 'Presencial',
      direccionConsultorio: (datos['direccion_consultorio'] as String?)?.trim(),
      fotoUrl: (datos['foto_url'] as String?)?.trim(),
      motivoRechazo: (datos['motivo_rechazo'] as String?)?.trim(),
      creadoEn: creadoEn,
    );
  }
}

/// Cita supervisada por el administrador (solo lectura autorizada).
class CitaAdministracion {
  final String idCita;
  final String pacienteNombre;
  final String profesionalNombre;
  final String fecha;
  final String horaInicio;
  final String horaFin;
  final String estado;
  final DateTime? fechaSolicitud;
  final String? motivoRespuesta;
  final int totalRegistros;

  const CitaAdministracion({
    required this.idCita,
    required this.pacienteNombre,
    required this.profesionalNombre,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.estado,
    this.fechaSolicitud,
    this.motivoRespuesta,
    this.totalRegistros = 0,
  });

  String get estadoLegible {
    switch (estado) {
      case 'pendiente':
        return 'Pendiente';
      case 'confirmada':
        return 'Confirmada';
      case 'rechazada':
        return 'Rechazada';
      case 'cancelada':
        return 'Cancelada';
      case 'finalizada':
        return 'Finalizada';
      default:
        return estado;
    }
  }

  factory CitaAdministracion.desdeMapa(Map<String, dynamic> datos) {
    final fechaSolRaw = datos['fecha_solicitud'];
    DateTime? fechaSol;
    if (fechaSolRaw is String && fechaSolRaw.trim().isNotEmpty) {
      fechaSol = DateTime.tryParse(fechaSolRaw.trim());
    } else if (fechaSolRaw is DateTime) {
      fechaSol = fechaSolRaw;
    }

    return CitaAdministracion(
      idCita: (datos['id_cita'] as String? ?? '').trim(),
      pacienteNombre: (datos['paciente_nombre'] as String? ?? '').trim(),
      profesionalNombre: (datos['profesional_nombre'] as String? ?? '').trim(),
      fecha: (datos['fecha'] ?? '').toString().trim(),
      horaInicio: (datos['hora_inicio'] as String? ?? '').trim(),
      horaFin: (datos['hora_fin'] as String? ?? '').trim(),
      estado: (datos['estado'] as String? ?? '').trim(),
      fechaSolicitud: fechaSol,
      motivoRespuesta: (datos['motivo_respuesta'] as String?)?.trim(),
      totalRegistros: (datos['total_registros'] as num?)?.toInt() ?? 0,
    );
  }
}
