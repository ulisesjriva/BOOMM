import 'package:flutter/foundation.dart';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/administrador/modelos/modelos_administracion.dart';
import 'package:boom/modulos/administrador/servicios/servicio_administracion.dart';

/// Coordina todas las secciones del modulo Administrador:
/// Panel general, Usuarios, Profesionales, Especialidades, Citas y Mantenimiento.
class ControladorAdministracion extends ChangeNotifier {
  ControladorAdministracion({this.servicio = const ServicioAdministracion()});

  final ServicioAdministracion servicio;

  // Compatibilidad con flujo previo de pendientes
  List<ProfesionalPendienteRevision> _pendientes = const [];

  // Panel general
  ResumenAdministracion? _resumen;

  // Usuarios (paginado)
  List<UsuarioAdministracion> _usuarios = const [];
  String _busquedaUsuario = '';
  String _filtroRolUsuario = 'todos';
  int _paginaUsuarios = 0;
  int _totalUsuarios = 0;
  static const int tamanoPaginaUsuarios = 20;

  // Profesionales
  List<ProfesionalAdministracion> _profesionales = const [];
  String _filtroEstadoProfesional = 'todos';

  // Especialidades
  List<Especialidad> _especialidades = const [];

  // Citas (paginado)
  List<CitaAdministracion> _citas = const [];
  String _filtroEstadoCita = 'todas';
  String? _fechaDesdeCita;
  String? _fechaHastaCita;
  int _paginaCitas = 0;
  int _totalCitas = 0;
  static const int tamanoPaginaCitas = 25;

  bool _estaCargando = false;
  bool _estaProcesando = false;
  bool _cerrado = false;
  String? _mensajeError;
  String? _mensajeExito;

  List<ProfesionalPendienteRevision> get pendientes => _pendientes;
  ResumenAdministracion? get resumen => _resumen;

  List<UsuarioAdministracion> get usuarios => _usuarios;
  String get busquedaUsuario => _busquedaUsuario;
  String get filtroRolUsuario => _filtroRolUsuario;
  int get totalUsuarios => _totalUsuarios;
  bool get hayMasUsuarios => _usuarios.length < _totalUsuarios;

  List<ProfesionalAdministracion> get profesionales => _profesionales;
  String get filtroEstadoProfesional => _filtroEstadoProfesional;

  List<Especialidad> get especialidades => _especialidades;

  List<CitaAdministracion> get citas => _citas;
  String get filtroEstadoCita => _filtroEstadoCita;
  String? get fechaDesdeCita => _fechaDesdeCita;
  String? get fechaHastaCita => _fechaHastaCita;
  int get totalCitas => _totalCitas;
  bool get hayMasCitas => _citas.length < _totalCitas;

  bool get estaCargando => _estaCargando;
  bool get estaProcesando => _estaProcesando;
  bool get ocupado => _estaCargando || _estaProcesando;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;

  void limpiarMensajes() {
    _mensajeError = null;
    _mensajeExito = null;
  }

  Future<void> cargarPendientes() async {
    if (_cerrado || _estaCargando) return;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final lista = await servicio.listarProfesionalesPendientes();
      if (_cerrado) return;
      _pendientes = List.unmodifiable(lista);
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarResumen() async {
    if (_cerrado || _estaCargando) return;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final resultado = await servicio.obtenerResumenGeneral();
      if (_cerrado) return;
      _resumen = resultado;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarUsuarios({
    String? busqueda,
    String? rol,
    bool reiniciar = true,
  }) async {
    if (_cerrado || _estaCargando) return;
    if (busqueda != null) _busquedaUsuario = busqueda;
    if (rol != null) _filtroRolUsuario = rol;
    if (reiniciar) {
      _paginaUsuarios = 0;
    } else {
      _paginaUsuarios += 1;
    }

    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final pagina = await servicio.listarUsuarios(
        busqueda: _busquedaUsuario,
        rol: _filtroRolUsuario,
        pagina: _paginaUsuarios,
        tamano: tamanoPaginaUsuarios,
      );
      if (_cerrado) return;

      final total = pagina.isNotEmpty
          ? pagina.first.totalRegistros
          : (reiniciar ? 0 : _totalUsuarios);
      _totalUsuarios = total;
      _usuarios = List.unmodifiable(
        reiniciar ? pagina : [..._usuarios, ...pagina],
      );
    } catch (error) {
      if (!_cerrado) {
        if (!reiniciar && _paginaUsuarios > 0) _paginaUsuarios -= 1;
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarProfesionales({String? estado}) async {
    if (_cerrado || _estaCargando) return;
    if (estado != null) _filtroEstadoProfesional = estado;

    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final lista = await servicio.listarProfesionales(
        estado: _filtroEstadoProfesional,
      );
      if (_cerrado) return;
      _profesionales = List.unmodifiable(lista);
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarEspecialidades() async {
    if (_cerrado || _estaCargando) return;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final lista = await servicio.listarEspecialidades();
      if (_cerrado) return;
      _especialidades = List.unmodifiable(lista);
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<void> cargarCitas({
    String? estado,
    String? fechaDesde,
    String? fechaHasta,
    bool limpiarFechas = false,
    bool reiniciar = true,
  }) async {
    if (_cerrado || _estaCargando) return;
    if (estado != null) _filtroEstadoCita = estado;
    if (limpiarFechas) {
      _fechaDesdeCita = null;
      _fechaHastaCita = null;
    } else {
      if (fechaDesde != null) _fechaDesdeCita = fechaDesde;
      if (fechaHasta != null) _fechaHastaCita = fechaHasta;
    }

    if (reiniciar) {
      _paginaCitas = 0;
    } else {
      _paginaCitas += 1;
    }

    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();

    try {
      final pagina = await servicio.listarCitas(
        estado: _filtroEstadoCita,
        fechaDesde: _fechaDesdeCita,
        fechaHasta: _fechaHastaCita,
        pagina: _paginaCitas,
        tamano: tamanoPaginaCitas,
      );
      if (_cerrado) return;

      final total = pagina.isNotEmpty
          ? pagina.first.totalRegistros
          : (reiniciar ? 0 : _totalCitas);
      _totalCitas = total;
      _citas = List.unmodifiable(reiniciar ? pagina : [..._citas, ...pagina]);
    } catch (error) {
      if (!_cerrado) {
        if (!reiniciar && _paginaCitas > 0) _paginaCitas -= 1;
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> decidirSolicitud({
    required String profesionalId,
    required bool aprobar,
    String? motivo,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.revisarProfesional(
        profesionalId: profesionalId,
        aprobar: aprobar,
        motivo: motivo,
      );
      if (_cerrado) return false;
      _pendientes = List.unmodifiable(
        _pendientes.where(
          (item) =>
              item.idUsuario != profesionalId &&
              item.id != profesionalId &&
              item.idProfesional != profesionalId,
        ),
      );
      _profesionales = List.unmodifiable(
        _profesionales.map((p) {
          if (p.idUsuario != profesionalId &&
              p.idProfesional != profesionalId) {
            return p;
          }
          return ProfesionalAdministracion(
            idUsuario: p.idUsuario,
            idProfesional: p.idProfesional,
            nombre: p.nombre,
            apellido: p.apellido,
            correo: p.correo,
            aprobacion: aprobar ? 'aprobado' : 'rechazado',
            cuentaActiva: p.cuentaActiva,
            especialidad: p.especialidad,
            numeroRegistro: p.numeroRegistro,
            descripcion: p.descripcion,
            aniosExperiencia: p.aniosExperiencia,
            telefonoContacto: p.telefonoContacto,
            modalidad: p.modalidad,
            direccionConsultorio: p.direccionConsultorio,
            fotoUrl: p.fotoUrl,
            motivoRechazo: aprobar ? null : motivo?.trim(),
            creadoEn: p.creadoEn,
          );
        }),
      );
      _mensajeExito = aprobar
          ? 'Solicitud profesional aprobada.'
          : 'Solicitud profesional rechazada con su motivo registrado.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> cambiarEstadoCuenta({
    required String usuarioId,
    required bool activo,
    required String motivo,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.cambiarEstadoCuenta(
        usuarioId: usuarioId,
        activo: activo,
        motivo: motivo,
      );
      if (_cerrado) return false;

      _usuarios = List.unmodifiable(
        _usuarios.map(
          (u) => u.id == usuarioId
              ? UsuarioAdministracion(
                  id: u.id,
                  nombre: u.nombre,
                  apellido: u.apellido,
                  correo: u.correo,
                  rol: u.rol,
                  cuentaActiva: activo,
                  aprobacion: u.aprobacion,
                  fotoUrl: u.fotoUrl,
                  creadoEn: u.creadoEn,
                  totalRegistros: u.totalRegistros,
                )
              : u,
        ),
      );
      _profesionales = List.unmodifiable(
        _profesionales.map(
          (p) => p.idUsuario == usuarioId
              ? ProfesionalAdministracion(
                  idUsuario: p.idUsuario,
                  idProfesional: p.idProfesional,
                  nombre: p.nombre,
                  apellido: p.apellido,
                  correo: p.correo,
                  aprobacion: p.aprobacion,
                  cuentaActiva: activo,
                  especialidad: p.especialidad,
                  numeroRegistro: p.numeroRegistro,
                  descripcion: p.descripcion,
                  aniosExperiencia: p.aniosExperiencia,
                  telefonoContacto: p.telefonoContacto,
                  modalidad: p.modalidad,
                  direccionConsultorio: p.direccionConsultorio,
                  fotoUrl: p.fotoUrl,
                  motivoRechazo: p.motivoRechazo,
                  creadoEn: p.creadoEn,
                )
              : p,
        ),
      );
      _mensajeExito = activo
          ? 'Cuenta reactivada correctamente.'
          : 'Cuenta deshabilitada correctamente.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> guardarEspecialidad({
    String? idEspecialidad,
    required String nombre,
    String? descripcion,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.guardarEspecialidad(
        idEspecialidad: idEspecialidad,
        nombre: nombre,
        descripcion: descripcion,
      );
      if (_cerrado) return false;
      final lista = await servicio.listarEspecialidades();
      if (_cerrado) return false;
      _especialidades = List.unmodifiable(lista);
      _mensajeExito = idEspecialidad == null
          ? 'Especialidad creada correctamente.'
          : 'Especialidad actualizada correctamente.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> cambiarEstadoEspecialidad({
    required String idEspecialidad,
    required bool activa,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.cambiarEstadoEspecialidad(
        idEspecialidad: idEspecialidad,
        activa: activa,
      );
      if (_cerrado) return false;
      _especialidades = List.unmodifiable(
        _especialidades.map(
          (e) => e.id == idEspecialidad
              ? Especialidad(
                  id: e.id,
                  nombre: e.nombre,
                  descripcion: e.descripcion,
                  activa: activa,
                )
              : e,
        ),
      );
      _mensajeExito = activa ? 'Especialidad activada.' : 'Especialidad desactivada (se conservan sus relaciones históricas).';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> corregirDatosUsuario({
    required String usuarioId,
    required String nombre,
    required String apellido,
    String? numeroRegistro,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaProcesando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicio.corregirDatosUsuario(
        usuarioId: usuarioId,
        nombre: nombre,
        apellido: apellido,
        numeroRegistro: numeroRegistro,
      );
      if (_cerrado) return false;
      _mensajeExito = 'Información actualizada y auditada correctamente.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAdministracion.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaProcesando = false;
        notifyListeners();
      }
    }
  }

  String generarCsvCitas() => servicio.exportarCitasCsv(_citas);

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
