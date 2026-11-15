import 'package:flutter/foundation.dart';

import 'package:boom/modelos/filtro_profesional.dart';
import 'package:boom/modelos/profesional.dart';
import 'package:boom/repositorios/repositorio_profesionales.dart';
import 'package:boom/repositorios/repositorio_profesionales_supabase.dart';

/// Coordina consultas y filtros; no depende de pantallas ni de navegacion.
class ControladorBuscarProfesionales extends ChangeNotifier {
  ControladorBuscarProfesionales({required this._repositorio});

  final RepositorioProfesionales _repositorio;
  FiltroProfesional _filtro = FiltroProfesional.inicial();
  List<Profesional> _profesionales = const [];
  List<String> _especialidades = const ['Todas'];
  List<String> _modalidades = const ['Todas'];
  List<String> _disponibilidades = const ['Todas'];
  bool _estaCargando = true;
  bool _cerrado = false;
  int _versionBusqueda = 0;
  String? _mensajeError;

  FiltroProfesional get filtro => _filtro;
  List<Profesional> get profesionales => _profesionales;
  List<String> get especialidades => _especialidades;
  List<String> get modalidades => _modalidades;
  List<String> get disponibilidades => _disponibilidades;
  bool get estaCargando => _estaCargando;
  String? get mensajeError => _mensajeError;

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
    notifyListeners();
    try {
      final resultados = await _repositorio.buscarProfesionales(filtroConsulta);
      if (_cerrado || version != _versionBusqueda) return;
      _profesionales = List.unmodifiable(resultados);
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

  Future<void> cambiarOrdenamiento(CriterioOrdenamiento ordenamiento) {
    _filtro = _filtro.copiarCon(ordenamiento: ordenamiento);
    return buscar();
  }

  Future<void> limpiarFiltros() {
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
