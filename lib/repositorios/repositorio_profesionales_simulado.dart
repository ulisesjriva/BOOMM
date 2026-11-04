import '../modelos/profesional.dart';
import '../modelos/filtro_profesional.dart';
import '../datos/profesionales_simulados.dart';
import 'repositorio_profesionales.dart';

/// Implementacion en memoria del contrato de repositorio de profesionales.
/// Proporciona busqueda textual y filtrado multicriterio sobre los registros
/// de prueba locales, simulando operaciones asincronas para una facil migracion a Supabase.
class RepositorioProfesionalesSimulado implements RepositorioProfesionales {
  final List<Profesional> _fuenteDatos;

  RepositorioProfesionalesSimulado({List<Profesional>? fuenteDatos})
    : _fuenteDatos = fuenteDatos ?? profesionalesSimulados;

  @override
  Future<List<Profesional>> obtenerProfesionales() async {
    // Retorna una copia de la lista simulada
    return List<Profesional>.from(_fuenteDatos);
  }

  @override
  Future<List<Profesional>> buscarProfesionales(
    FiltroProfesional filtro,
  ) async {
    final textoLimpio = _normalizarTexto(filtro.textoBusqueda.trim());
    final especialidadLimpia = _normalizarTexto(filtro.especialidad.trim());
    final modalidadLimpia = _normalizarTexto(filtro.modalidad.trim());
    final disponibilidadLimpia = _normalizarTexto(filtro.disponibilidad.trim());

    final resultados = _fuenteDatos.where((profesional) {
      // 1. Filtro por busqueda textual (nombre o especialidad)
      if (textoLimpio.isNotEmpty) {
        final nombreLimpio = _normalizarTexto(profesional.nombre);
        final especialidadProfLimpia = _normalizarTexto(
          profesional.especialidad,
        );
        final coincideTexto =
            nombreLimpio.contains(textoLimpio) ||
            especialidadProfLimpia.contains(textoLimpio);
        if (!coincideTexto) return false;
      }

      // 2. Filtro por especialidad
      if (especialidadLimpia.isNotEmpty && especialidadLimpia != 'todas') {
        final especialidadProfLimpia = _normalizarTexto(
          profesional.especialidad,
        );
        if (especialidadProfLimpia != especialidadLimpia) return false;
      }

      // 3. Filtro por modalidad de atencion
      if (modalidadLimpia.isNotEmpty && modalidadLimpia != 'todas') {
        final modalidadProfLimpia = _normalizarTexto(profesional.modalidad);
        if (modalidadProfLimpia != modalidadLimpia) return false;
      }

      // 4. Filtro por disponibilidad
      if (disponibilidadLimpia.isNotEmpty &&
          disponibilidadLimpia != 'todas' &&
          disponibilidadLimpia != 'cualquiera') {
        final disponibilidadProfLimpia = _normalizarTexto(
          profesional.disponibilidadTexto,
        );
        if (!disponibilidadProfLimpia.contains(disponibilidadLimpia)) {
          return false;
        }
      }

      return true;
    }).toList();

    // 5. Ordenamiento segun el criterio seleccionado
    switch (filtro.ordenamiento) {
      case CriterioOrdenamiento.nombreAscendente:
        resultados.sort((a, b) => a.nombre.compareTo(b.nombre));
        break;
      case CriterioOrdenamiento.calificacionDescendente:
        resultados.sort((a, b) => b.calificacion.compareTo(a.calificacion));
        break;
      case CriterioOrdenamiento.especialidadAscendente:
        resultados.sort((a, b) => a.especialidad.compareTo(b.especialidad));
        break;
    }

    return resultados;
  }

  @override
  Future<Profesional?> obtenerProfesionalPorId(String id) async {
    try {
      return _fuenteDatos.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> obtenerEspecialidades() async {
    final conjunto = <String>{'Todas'};
    for (final p in _fuenteDatos) {
      if (p.especialidad.isNotEmpty) {
        conjunto.add(p.especialidad);
      }
    }
    return conjunto.toList();
  }

  @override
  Future<List<String>> obtenerModalidades() async {
    return const ['Todas', 'Presencial', 'Virtual', 'Híbrida'];
  }

  @override
  Future<List<String>> obtenerDisponibilidades() async {
    return const ['Todas', 'Hoy', 'Mañana', 'Esta semana'];
  }

  /// Elimina tildes, dieresis y pasa a minusculas para comparaciones insensibles.
  String _normalizarTexto(String entrada) {
    var resultado = entrada.toLowerCase();
    resultado = resultado.replaceAll(RegExp(r'[áàäâ]'), 'a');
    resultado = resultado.replaceAll(RegExp(r'[éèëê]'), 'e');
    resultado = resultado.replaceAll(RegExp(r'[íìïî]'), 'i');
    resultado = resultado.replaceAll(RegExp(r'[óòöô]'), 'o');
    resultado = resultado.replaceAll(RegExp(r'[úùüû]'), 'u');
    return resultado;
  }
}
