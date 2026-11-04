/// Criterios disponibles para ordenar los resultados de profesionales.
enum CriterioOrdenamiento {
  nombreAscendente('Nombre (A-Z)'),
  calificacionDescendente('Mayor calificación'),
  especialidadAscendente('Especialidad (A-Z)');

  final String etiqueta;
  const CriterioOrdenamiento(this.etiqueta);
}

/// Representa el conjunto de filtros y criterios de ordenamiento aplicables
/// a la busqueda interactiva de profesionales en PsicoBloom.
class FiltroProfesional {
  final String textoBusqueda;
  final String especialidad;
  final String disponibilidad;
  final String modalidad;
  final CriterioOrdenamiento ordenamiento;

  const FiltroProfesional({
    this.textoBusqueda = '',
    this.especialidad = 'Todas',
    this.disponibilidad = 'Todas',
    this.modalidad = 'Todas',
    this.ordenamiento = CriterioOrdenamiento.nombreAscendente,
  });

  /// Estado inicial sin filtros restrictivos.
  factory FiltroProfesional.inicial() {
    return const FiltroProfesional();
  }

  /// Indica si existe algun criterio de busqueda o filtro activo.
  bool get tieneFiltrosActivos {
    return textoBusqueda.trim().isNotEmpty ||
        especialidad != 'Todas' ||
        disponibilidad != 'Todas' ||
        modalidad != 'Todas' ||
        ordenamiento != CriterioOrdenamiento.nombreAscendente;
  }

  /// Retorna una copia con los valores modificados especificados.
  FiltroProfesional copiarCon({
    String? textoBusqueda,
    String? especialidad,
    String? disponibilidad,
    String? modalidad,
    CriterioOrdenamiento? ordenamiento,
  }) {
    return FiltroProfesional(
      textoBusqueda: textoBusqueda ?? this.textoBusqueda,
      especialidad: especialidad ?? this.especialidad,
      disponibilidad: disponibilidad ?? this.disponibilidad,
      modalidad: modalidad ?? this.modalidad,
      ordenamiento: ordenamiento ?? this.ordenamiento,
    );
  }
}

