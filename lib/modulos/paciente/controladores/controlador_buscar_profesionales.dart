import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/modulos/paciente/modelos/ruta_consultorio.dart';
import 'package:boom/modulos/paciente/servicios/servicio_rutas_consultorio.dart';
import 'package:boom/modulos/profesional/servicios/servicio_ubicacion_consultorio.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_supabase.dart';

/// Coordina consultas y filtros; no depende de pantallas ni de navegacion.
class ControladorBuscarProfesionales extends ChangeNotifier {
  ControladorBuscarProfesionales({
    required this._repositorio,
    this.servicioUbicacion = const ServicioUbicacionConsultorio(),
    this.servicioRutas = const ServicioRutasConsultorio(),
  });

  static const int _maximoConsultasRuta = 5;

  final RepositorioProfesionales _repositorio;
  final ServicioUbicacionConsultorio servicioUbicacion;
  final ServicioRutasConsultorio servicioRutas;

  FiltroProfesional _filtro = FiltroProfesional.inicial();
  List<Profesional> _profesionales = const [];
  List<String> _especialidades = const ['Todas'];
  List<String> _modalidades = const ['Todas'];
  List<String> _disponibilidades = const ['Todas'];
  final Map<String, double> _distanciasMetrosPorProfesional =
      <String, double>{};
  final Map<String, RutaConsultorio> _rutasPorProfesional =
      <String, RutaConsultorio>{};

  double? _latitudPaciente;
  double? _longitudPaciente;
  bool _estaCargando = true;
  bool _cerrado = false;
  int _versionBusqueda = 0;
  String? _mensajeError;
  String? _mensajeCercania;

  FiltroProfesional get filtro => _filtro;
  List<Profesional> get profesionales => _profesionales;
  List<String> get especialidades => _especialidades;
  List<String> get modalidades => _modalidades;
  List<String> get disponibilidades => _disponibilidades;
  List<String> get opcionesCercania => FiltroProfesional.opcionesCercania;
  bool get estaCargando => _estaCargando;
  String? get mensajeError => _mensajeError;
  String? get mensajeCercania => _mensajeCercania;

  /// Retorna una etiqueta legible de cercania cuando hay un filtro de cercania
  /// activo y se cuenta con datos de distancia o tiempo de ruta para el profesional.
  String? obtenerResumenCercania(String idProfesional) {
    if (_filtro.cercania == FiltroProfesional.opcionCercaniaTodos) {
      return null;
    }
    final ruta = _rutasPorProfesional[idProfesional];
    if (_filtro.cercania == FiltroProfesional.opcionCercaniaMenorTiempoRuta &&
        ruta != null &&
        ruta.esRutaCalleValida) {
      return '${ruta.tiempoEstimadoTexto} · ${ruta.distanciaTexto}';
    }
    if (_filtro.cercania == FiltroProfesional.opcionCercaniaMenorDistancia &&
        ruta != null &&
        ruta.esRutaCalleValida) {
      return 'Ruta: ${ruta.distanciaTexto}';
    }
    final metros = _distanciasMetrosPorProfesional[idProfesional];
    if (metros == null) return null;
    return _formatearDistanciaAproximada(metros);
  }

  String _formatearDistanciaAproximada(double metros) {
    if (metros < 1000) {
      return 'A ${metros.round()} m (aprox.)';
    }
    return 'A ${(metros / 1000).toStringAsFixed(1)} km (aprox.)';
  }

  Future<void> inicializar() async {
    if (_cerrado) return;
    final repositorio = _repositorio;
    if (repositorio is RepositorioProfesionalesSupabase) {
      repositorio.limpiarCache();
    }
    final version = _versionBusqueda;
    _estaCargando = true;
    _mensajeError = null;
    notifyListeners();
    try {
      final especialidades = await _repositorio.obtenerEspecialidades();
      final modalidades = await _repositorio.obtenerModalidades();
      final disponibilidades = await _repositorio.obtenerDisponibilidades();
      if (_cerrado) return;
      _especialidades = List.unmodifiable(especialidades);
      _modalidades = List.unmodifiable(modalidades);
      _disponibilidades = List.unmodifiable(disponibilidades);
      // Si ya hay otra busqueda, conserva su estado y solo publica los catalogos.
      if (version != _versionBusqueda) {
        notifyListeners();
        return;
      }
      await buscar();
    } catch (_) {
      if (_cerrado || version != _versionBusqueda) return;
      _estaCargando = false;
      _mensajeError = 'No se pudieron cargar los filtros. Inténtalo de nuevo.';
      notifyListeners();
    }
  }

  Future<void> buscar() async {
    if (_cerrado) return;
    final version = ++_versionBusqueda;
    final filtroConsulta = _filtro;
    _estaCargando = true;
    _mensajeError = null;
    if (filtroConsulta.cercania == FiltroProfesional.opcionCercaniaTodos) {
      _mensajeCercania = null;
    }
    notifyListeners();
    try {
      final resultadosBase = await _repositorio.buscarProfesionales(
        filtroConsulta,
      );
      if (_cerrado || version != _versionBusqueda) return;
      final resultadosFinales = await _aplicarCercaniaSiCorresponde(
        resultadosBase,
        filtroConsulta.cercania,
        version,
      );
      if (_cerrado || version != _versionBusqueda) return;
      _profesionales = List.unmodifiable(resultadosFinales);
    } catch (_) {
      if (_cerrado || version != _versionBusqueda) return;
      _profesionales = const [];
      _mensajeError =
          'No se pudieron buscar profesionales. Inténtalo de nuevo.';
    }
    if (_cerrado || version != _versionBusqueda) return;
    _estaCargando = false;
    notifyListeners();
  }

  Future<List<Profesional>> _aplicarCercaniaSiCorresponde(
    List<Profesional> resultados,
    String cercania,
    int version,
  ) async {
    if (cercania == FiltroProfesional.opcionCercaniaTodos ||
        resultados.isEmpty) {
      _mensajeCercania = null;
      return resultados;
    }

    if (_latitudPaciente == null || _longitudPaciente == null) {
      final ubicacion = await servicioUbicacion.obtenerUbicacionActual();
      if (_cerrado || version != _versionBusqueda) return resultados;
      if (ubicacion.estado != EstadoUbicacionDispositivo.obtenida ||
          ubicacion.latitud == null ||
          ubicacion.longitud == null) {
        _mensajeCercania = _explicarFalloUbicacionPaciente(ubicacion.estado);
        return resultados;
      }
      _latitudPaciente = ubicacion.latitud;
      _longitudPaciente = ubicacion.longitud;
    }

    final origenLat = _latitudPaciente!;
    final origenLng = _longitudPaciente!;

    final conCoordenadas = <Profesional>[];
    final sinCoordenadas = <Profesional>[];
    for (final profesional in resultados) {
      if (profesional.tieneCoordenadasValidas) {
        conCoordenadas.add(profesional);
        _distanciasMetrosPorProfesional[profesional.id] =
            Geolocator.distanceBetween(
              origenLat,
              origenLng,
              profesional.latitud,
              profesional.longitud,
            );
      } else {
        sinCoordenadas.add(profesional);
      }
    }

    if (conCoordenadas.isEmpty) {
      _mensajeCercania = 'Los profesionales mostrados aún no tienen ubicación registrada para ordenar por cercanía.';
      return resultados;
    }

    conCoordenadas.sort((a, b) {
      final distanciaA = _distanciaEfectivaMetros(a, cercania);
      final distanciaB = _distanciaEfectivaMetros(b, cercania);
      return distanciaA.compareTo(distanciaB);
    });

    if (cercania == FiltroProfesional.opcionCercaniaMenorTiempoRuta) {
      var rutasCalculadasExitosas = 0;
      final candidatosRuta = conCoordenadas.take(_maximoConsultasRuta);
      for (final profesional in candidatosRuta) {
        if (_cerrado || version != _versionBusqueda) return resultados;
        final rutaExistente = _rutasPorProfesional[profesional.id];
        if (rutaExistente != null && rutaExistente.esRutaCalleValida) {
          rutasCalculadasExitosas++;
          continue;
        }
        final resultadoRuta = await servicioRutas.calcularRuta(
          origenLatitud: origenLat,
          origenLongitud: origenLng,
          destinoLatitud: profesional.latitud,
          destinoLongitud: profesional.longitud,
          medioTransporte: MedioTransporte.auto,
        );
        if (_cerrado || version != _versionBusqueda) return resultados;
        if (resultadoRuta.fueExitoso && resultadoRuta.ruta != null) {
          _rutasPorProfesional[profesional.id] = resultadoRuta.ruta!;
          rutasCalculadasExitosas++;
        }
      }

      if (rutasCalculadasExitosas > 0) {
        _mensajeCercania = null;
        conCoordenadas.sort((a, b) {
          final rutaA = _rutasPorProfesional[a.id];
          final rutaB = _rutasPorProfesional[b.id];
          if (rutaA != null && rutaB != null) {
            return rutaA.duracionEstimadaSegundos.compareTo(
              rutaB.duracionEstimadaSegundos,
            );
          }
          if (rutaA != null) return -1;
          if (rutaB != null) return 1;
          return (_distanciasMetrosPorProfesional[a.id] ?? double.infinity)
              .compareTo(
                _distanciasMetrosPorProfesional[b.id] ?? double.infinity,
              );
        });
      } else {
        _mensajeCercania = 'No se pudo calcular el tiempo de ruta vial en este momento. Se muestran ordenados por cercanía aproximada.';
      }
    } else {
      _mensajeCercania = null;
    }

    return <Profesional>[...conCoordenadas, ...sinCoordenadas];
  }

  double _distanciaEfectivaMetros(Profesional profesional, String cercania) {
    if (cercania == FiltroProfesional.opcionCercaniaMenorDistancia) {
      final ruta = _rutasPorProfesional[profesional.id];
      if (ruta != null && ruta.esRutaCalleValida) {
        return ruta.distanciaMetros;
      }
    }
    return _distanciasMetrosPorProfesional[profesional.id] ?? double.infinity;
  }

  String _explicarFalloUbicacionPaciente(EstadoUbicacionDispositivo estado) {
    switch (estado) {
      case EstadoUbicacionDispositivo.servicioDesactivado:
        return 'Activa el GPS de tu dispositivo para ordenar por cercanía. Puedes seguir usando los demás filtros.';
      case EstadoUbicacionDispositivo.permisoRechazado:
        return 'Sin permiso de ubicación no podemos ordenar por cercanía. Puedes seguir usando los demás filtros.';
      case EstadoUbicacionDispositivo.permisoRechazadoPermanente:
        return 'El permiso de ubicación está desactivado en ajustes. Habilítalo para usar cercanía o continúa con los demás filtros.';
      case EstadoUbicacionDispositivo.errorLectura:
      case EstadoUbicacionDispositivo.obtenida:
        return 'No pudimos obtener tu ubicación actual para ordenar por cercanía. Puedes seguir usando los demás filtros.';
    }
  }

  Future<void> actualizarTexto(String texto) {
    _filtro = _filtro.copiarCon(textoBusqueda: texto);
    return buscar();
  }

  Future<void> cambiarEspecialidad(String especialidad) {
    _filtro = _filtro.copiarCon(especialidad: especialidad);
    return buscar();
  }

  Future<void> cambiarModalidad(String modalidad) {
    _filtro = _filtro.copiarCon(modalidad: modalidad);
    return buscar();
  }

  Future<void> cambiarDisponibilidad(String disponibilidad) {
    _filtro = _filtro.copiarCon(disponibilidad: disponibilidad);
    return buscar();
  }

  Future<void> cambiarCercania(String cercania) {
    _filtro = _filtro.copiarCon(cercania: cercania);
    return buscar();
  }

  Future<void> cambiarOrdenamiento(CriterioOrdenamiento ordenamiento) {
    _filtro = _filtro.copiarCon(ordenamiento: ordenamiento);
    return buscar();
  }

  Future<void> limpiarFiltros() {
    _mensajeCercania = null;
    _filtro = FiltroProfesional.inicial();
    return buscar();
  }

  @override
  void dispose() {
    _cerrado = true;
    _versionBusqueda++;
    super.dispose();
  }
}
