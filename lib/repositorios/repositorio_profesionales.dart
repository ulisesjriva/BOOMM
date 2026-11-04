import '../modelos/profesional.dart';
import '../modelos/filtro_profesional.dart';

/// Contrato abstracto que define las operaciones de consulta y busqueda
/// de profesionales en PsicoBloom. Diseñado para desacoplar la interfaz grafica
/// de la fuente de datos (inicialmente simulada, y posteriormente Supabase).
abstract class RepositorioProfesionales {
  /// Retorna el listado completo de profesionales disponibles.
  Future<List<Profesional>> obtenerProfesionales();

  /// Filtra y ordena los profesionales segun los criterios proporcionados.
  Future<List<Profesional>> buscarProfesionales(FiltroProfesional filtro);

  /// Retorna un profesional por su identificador unico, o null si no existe.
  Future<Profesional?> obtenerProfesionalPorId(String id);

  /// Obtiene el catalogo de especialidades disponibles para filtrar.
  Future<List<String>> obtenerEspecialidades();

  /// Obtiene las modalidades de atencion disponibles para filtrar.
  Future<List<String>> obtenerModalidades();

  /// Obtiene los periodos de disponibilidad disponibles para filtrar.
  Future<List<String>> obtenerDisponibilidades();
}

