import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:boom/modelos/especialidad.dart';
import 'package:boom/modulos/profesional/modelos/perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_avisos_telegram.dart';
import 'package:boom/modulos/profesional/servicios/servicio_perfil_profesional.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/repositorios/repositorio_especialidades.dart';

/// Coordina la carga y edicion del perfil profesional, la carga de su fotografia,
/// el catalogo real de especialidades, los servicios, la modalidad y la ubicacion del consultorio.
class ControladorPerfilProfesional extends ChangeNotifier {
  ControladorPerfilProfesional({
    this.servicio = const ServicioPerfilProfesional(),
    this.repositorioEspecialidades = const RepositorioEspecialidadesSupabase(),
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioTelegram = const ServicioAvisosTelegram(),
    PerfilProfesional? perfilInicial,
  }) : _perfil = perfilInicial {
    if (perfilInicial != null) {
      _especialidadesSeleccionadasIds = Set<String>.from(
        perfilInicial.especialidadesIds,
      );
      _modalidadSeleccionada = perfilInicial.modalidad;
      _latitudSeleccionada = perfilInicial.latitud;
      _longitudSeleccionada = perfilInicial.longitud;
    }
  }

  final ServicioPerfilProfesional servicio;
  final RepositorioEspecialidades repositorioEspecialidades;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioAvisosTelegram servicioTelegram;

  PerfilProfesional? _perfil;
  List<Especialidad> _catalogoEspecialidades = const [];
  Set<String> _especialidadesSeleccionadasIds = <String>{};
  String _modalidadSeleccionada = 'Presencial';
  double? _latitudSeleccionada;
  double? _longitudSeleccionada;
  String? _motivoRechazo;

  bool _estaCargando = false;
  bool _estaGuardando = false;
  bool _estaSubiendoFoto = false;
  bool _estaObteniendoUbicacion = false;
  bool _estaGestionandoTelegram = false;
  bool _cerrado = false;
  String? _mensajeError;
  String? _mensajeExito;
  String? _avisoUbicacion;
  EstadoTelegramProfesional _estadoTelegram = const EstadoTelegramProfesional(
    conectado: false,
    tieneCodigoPendiente: false,
  );

  PerfilProfesional? get perfil => _perfil;
  List<Especialidad> get catalogoEspecialidades => _catalogoEspecialidades;
  Set<String> get especialidadesSeleccionadasIds =>
      Set.unmodifiable(_especialidadesSeleccionadasIds);
  String get modalidadSeleccionada => _modalidadSeleccionada;
  double? get latitudSeleccionada => _latitudSeleccionada;
  double? get longitudSeleccionada => _longitudSeleccionada;
  String? get motivoRechazo => _motivoRechazo;

  bool get estaCargando => _estaCargando;
  bool get estaGuardando => _estaGuardando;
  bool get estaSubiendoFoto => _estaSubiendoFoto;
  bool get estaObteniendoUbicacion => _estaObteniendoUbicacion;
  bool get estaGestionandoTelegram => _estaGestionandoTelegram;
  EstadoTelegramProfesional get estadoTelegram => _estadoTelegram;
  bool get ocupado =>
      _estaCargando ||
      _estaGuardando ||
      _estaSubiendoFoto ||
      _estaObteniendoUbicacion ||
      _estaGestionandoTelegram;
  String? get mensajeError => _mensajeError;
  String? get mensajeExito => _mensajeExito;
  String? get avisoUbicacion => _avisoUbicacion;

  /// Devuelve las opciones que se muestran al profesional:
  /// todas las activas mas aquellas inactivas que ya tuviera vinculadas historicamente.
  List<Especialidad> get especialidadesVisibles {
    return _catalogoEspecialidades.where((esp) {
      return esp.activa || _especialidadesSeleccionadasIds.contains(esp.id);
    }).toList();
  }

  Future<void> inicializar() async {
    if (_cerrado || _estaCargando) return;
    _estaCargando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final catalogo = await repositorioEspecialidades
          .obtenerCatalogoEspecialidades();
      if (_cerrado) return;
      _catalogoEspecialidades = List.unmodifiable(catalogo);

      final perfilServidor = await servicio.obtenerPerfilPropio();
      if (_cerrado) return;
      _aplicarPerfilCargado(perfilServidor);

      if (perfilServidor.aprobacion == 'rechazado') {
        _motivoRechazo = await servicio.consultarMotivoRechazoPropio();
      } else {
        _motivoRechazo = null;
      }

      try {
        final estado = await servicioTelegram.obtenerEstado();
        if (!_cerrado) {
          _estadoTelegram = estado;
        }
      } catch (_) {
        // Los avisos por Telegram son opcionales y no bloquean la carga del perfil.
      }
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilProfesional.explicarError(error);
      }
    } finally {
      if (!_cerrado) {
        _estaCargando = false;
        notifyListeners();
      }
    }
  }

  void _aplicarPerfilCargado(PerfilProfesional perfilServidor) {
    _perfil = perfilServidor;
    _especialidadesSeleccionadasIds = Set<String>.from(
      perfilServidor.especialidadesIds,
    );
    if (_especialidadesSeleccionadasIds.isEmpty &&
        perfilServidor.especialidadTexto != null) {
      final nombresPrevios = perfilServidor.especialidadTexto!
          .split(',')
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final esp in _catalogoEspecialidades) {
        if (nombresPrevios.contains(esp.nombre.toLowerCase())) {
          _especialidadesSeleccionadasIds.add(esp.id);
        }
      }
    }
    _modalidadSeleccionada = perfilServidor.modalidad;
    _latitudSeleccionada = perfilServidor.latitud;
    _longitudSeleccionada = perfilServidor.longitud;
  }

  void alternarEspecialidad(Especialidad especialidad) {
    if (_cerrado || ocupado) return;
    final yaSeleccionada = _especialidadesSeleccionadasIds.contains(
      especialidad.id,
    );
    if (!yaSeleccionada && !especialidad.activa) {
      // No se ofrecen ni permiten seleccionar opciones desactivadas para nuevas relaciones.
      _mensajeError =
          'La especialidad "${especialidad.nombre}" está desactivada para nuevas selecciones.';
      notifyListeners();
      return;
    }

    final nuevoConjunto = Set<String>.from(_especialidadesSeleccionadasIds);
    if (yaSeleccionada) {
      nuevoConjunto.remove(especialidad.id);
    } else {
      nuevoConjunto.add(especialidad.id);
    }
    _especialidadesSeleccionadasIds = nuevoConjunto;
    _mensajeError = null;
    notifyListeners();
  }

  void cambiarModalidad(String nuevaModalidad) {
    if (_cerrado || ocupado) return;
    if (!['Presencial', 'Virtual', 'Híbrida'].contains(nuevaModalidad)) {
      return;
    }
    _modalidadSeleccionada = nuevaModalidad;
    notifyListeners();
  }

  void seleccionarCoordenadasManuales(double latitud, double longitud) {
    if (_cerrado || ocupado) return;
    if (latitud < -90.0 ||
        latitud > 90.0 ||
        longitud < -180.0 ||
        longitud > 180.0) {
      _mensajeError = 'Las coordenadas seleccionadas están fuera de rango.';
      notifyListeners();
      return;
    }
    _latitudSeleccionada = double.parse(latitud.toStringAsFixed(6));
    _longitudSeleccionada = double.parse(longitud.toStringAsFixed(6));
    _avisoUbicacion = null;
    _mensajeError = null;
    notifyListeners();
  }

  void limpiarCoordenadas() {
    if (_cerrado || ocupado) return;
    _latitudSeleccionada = null;
    _longitudSeleccionada = null;
    _avisoUbicacion = null;
    notifyListeners();
  }

  Future<bool> usarUbicacionActualDispositivo() async {
    if (_cerrado || ocupado) return false;
    _estaObteniendoUbicacion = true;
    _avisoUbicacion = null;
    _mensajeError = null;
    notifyListeners();

    try {
      final resultado = await servicioUbicacion.obtenerUbicacionActual();
      if (_cerrado) return false;

      if (resultado.estado == EstadoUbicacionDispositivo.obtenida &&
          resultado.latitud != null &&
          resultado.longitud != null) {
        _latitudSeleccionada = double.parse(
          resultado.latitud!.toStringAsFixed(6),
        );
        _longitudSeleccionada = double.parse(
          resultado.longitud!.toStringAsFixed(6),
        );
        _avisoUbicacion =
            'Ubicación del dispositivo aplicada al marcador del consultorio.';
        return true;
      } else {
        _avisoUbicacion = resultado.mensaje;
        return false;
      }
    } finally {
      if (!_cerrado) {
        _estaObteniendoUbicacion = false;
        notifyListeners();
      }
    }
  }

  Future<bool> seleccionarYSubirFotografia({
    ImageSource origen = ImageSource.gallery,
  }) async {
    if (_cerrado || ocupado) return false;
    _estaSubiendoFoto = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final archivo = await servicio.seleccionarFotografia(origen: origen);
      if (_cerrado) return false;
      if (archivo == null) {
        // Usuario cancelo la seleccion; no es un error
        return false;
      }

      final nuevaUrl = await servicio.subirYGuardarFotografia(archivo);
      if (_cerrado) return false;
      if (nuevaUrl.trim().isEmpty) {
        throw const ErrorPerfilProfesional(
          'Se subió la imagen, pero la fotografía no quedó asociada a tu perfil profesional.',
        );
      }

      if (_perfil != null) {
        _perfil = _perfil!.copiarCon(fotoUrl: nuevaUrl);
      }
      _mensajeExito = 'Fotografía de perfil actualizada y guardada.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilProfesional.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaSubiendoFoto = false;
        notifyListeners();
      }
    }
  }

  Future<bool> guardarPerfil({
    required String nombre,
    required String apellido,
    String? numeroRegistro,
    String? descripcion,
    String? textoAniosExperiencia,
    String? telefonoContacto,
    String? servicios,
    String? direccionConsultorio,
    String? textoLatitud,
    String? textoLongitud,
  }) async {
    if (_cerrado || ocupado) return false;

    final nombreLimpio = nombre.trim();
    final apellidoLimpio = apellido.trim();
    if (nombreLimpio.length < 2 || apellidoLimpio.length < 2) {
      _mensajeError =
          'El nombre y el apellido requieren al menos 2 caracteres.';
      _mensajeExito = null;
      notifyListeners();
      return false;
    }

    int? aniosExperiencia;
    final expLimpia = textoAniosExperiencia?.trim() ?? '';
    if (expLimpia.isNotEmpty) {
      aniosExperiencia = int.tryParse(expLimpia);
      if (aniosExperiencia == null ||
          aniosExperiencia < 0 ||
          aniosExperiencia > 70) {
        _mensajeError =
            'Ingresa un número válido de años de experiencia (0 a 70).';
        _mensajeExito = null;
        notifyListeners();
        return false;
      }
    }

    double? latitudFinal = _latitudSeleccionada;
    double? longitudFinal = _longitudSeleccionada;

    if (textoLatitud != null && textoLongitud != null) {
      final errorCoords = ServicioUbicacionConsultorio.validarCoordenadas(
        textoLatitud: textoLatitud,
        textoLongitud: textoLongitud,
      );
      if (errorCoords != null) {
        _mensajeError = errorCoords;
        _mensajeExito = null;
        notifyListeners();
        return false;
      }
      final latTexto = textoLatitud.trim();
      final lngTexto = textoLongitud.trim();
      if (latTexto.isEmpty && lngTexto.isEmpty) {
        latitudFinal = null;
        longitudFinal = null;
      } else {
        latitudFinal = double.parse(latTexto.replaceAll(',', '.'));
        longitudFinal = double.parse(lngTexto.replaceAll(',', '.'));
      }
    }

    final nombresSeleccionados = _catalogoEspecialidades
        .where((esp) => _especialidadesSeleccionadasIds.contains(esp.id))
        .map((esp) => esp.nombre)
        .toList();

    _estaGuardando = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final actualizado = await servicio.guardarPerfilCompleto(
        nombre: nombreLimpio,
        apellido: apellidoLimpio,
        especialidadesIds: _especialidadesSeleccionadasIds.toList(),
        especialidadesNombres: nombresSeleccionados,
        numeroRegistro: numeroRegistro,
        descripcion: descripcion,
        aniosExperiencia: aniosExperiencia,
        telefonoContacto: telefonoContacto,
        modalidad: _modalidadSeleccionada,
        servicios: servicios,
        direccionConsultorio: direccionConsultorio,
        latitud: latitudFinal,
        longitud: longitudFinal,
      );
      if (_cerrado) return false;
      _aplicarPerfilCargado(actualizado);
      _mensajeExito = 'Perfil profesional, especialidades y ubicación guardados correctamente.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioPerfilProfesional.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGuardando = false;
        notifyListeners();
      }
    }
  }

  Future<bool> conectarTelegram() async {
    if (_cerrado || ocupado) return false;
    _estaGestionandoTelegram = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final enlace = await servicioTelegram.generarEnlaceVinculacion();
      if (_cerrado) return false;
      await servicioTelegram.abrirEnlaceVinculacion(enlace.enlaceTelegram);
      if (_cerrado) return false;

      _estadoTelegram = EstadoTelegramProfesional(
        conectado: _estadoTelegram.conectado,
        conectadoEn: _estadoTelegram.conectadoEn,
        tieneCodigoPendiente: true,
        codigoExpiraEn: enlace.expiraEn,
      );
      _mensajeExito = 'Se abrió Telegram. Toca «Iniciar» en el bot y luego pulsa «Comprobar conexión».';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAvisosTelegram.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGestionandoTelegram = false;
        notifyListeners();
      }
    }
  }

  Future<bool> comprobarConexionTelegram() async {
    if (_cerrado || ocupado) return false;
    _estaGestionandoTelegram = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      final estado = await servicioTelegram.obtenerEstado();
      if (_cerrado) return false;
      _estadoTelegram = estado;
      _mensajeExito = estado.conectado ? 'Telegram conectado correctamente.' : 'Aún no se confirma la conexión. Toca «Iniciar» en el bot de Telegram e inténtalo nuevamente.';
      return estado.conectado;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAvisosTelegram.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGestionandoTelegram = false;
        notifyListeners();
      }
    }
  }

  Future<bool> desconectarTelegram() async {
    if (_cerrado || ocupado) return false;
    _estaGestionandoTelegram = true;
    _mensajeError = null;
    _mensajeExito = null;
    notifyListeners();

    try {
      await servicioTelegram.desconectar();
      if (_cerrado) return false;
      _estadoTelegram = const EstadoTelegramProfesional(
        conectado: false,
        tieneCodigoPendiente: false,
      );
      _mensajeExito = 'Avisos por Telegram desconectados.';
      return true;
    } catch (error) {
      if (!_cerrado) {
        _mensajeError = ServicioAvisosTelegram.explicarError(error);
      }
      return false;
    } finally {
      if (!_cerrado) {
        _estaGestionandoTelegram = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
