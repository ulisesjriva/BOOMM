/// Tipos de preguntas admitidas en el cuestionario de orientacion.
enum TipoPreguntaOrientacion {
  siNo,
  seleccionMultiple,
}

/// Representa una pregunta individual dentro del cuestionario de salud mental.
class PreguntaOrientacion {
  final String id;
  final String texto;
  final TipoPreguntaOrientacion tipo;
  final String? contexto;
  final String? textoExplicativo;
  final List<String> opciones;
  final String? idCondicional;
  final dynamic valorCondicional;
  final bool esSensible;

  const PreguntaOrientacion({
    required this.id,
    required this.texto,
    this.tipo = TipoPreguntaOrientacion.siNo,
    this.contexto,
    this.textoExplicativo,
    this.opciones = const <String>['Sí', 'No'],
    this.idCondicional,
    this.valorCondicional,
    this.esSensible = false,
  });

  /// Indica si la pregunta debe ser visible segun las respuestas acumuladas en memoria.
  bool estaVisible(Map<String, dynamic> respuestas) {
    if (idCondicional == null) return true;
    return respuestas[idCondicional] == valorCondicional;
  }
}

/// Define cada una de las 10 etapas del cuestionario de orientacion de PsicoBloom.
enum EtapaCuestionario {
  introduccion(1, 'Introducción y Consentimiento'),
  estadoDeAnimo(2, 'Estado de ánimo'),
  ansiedad(3, 'Ansiedad'),
  experienciasTraumaticas(4, 'Experiencias traumáticas'),
  atencion(5, 'Atención'),
  inquietudesComida(6, 'Inquietudes sobre la comida'),
  cambiosPercepcion(7, 'Cambios de percepción'),
  alcoholSustancias(8, 'Alcohol y otras sustancias'),
  otrasAdicciones(9, 'Otras adicciones'),
  resultado(10, 'Orientación y Recomendación');

  final int numero;
  final String titulo;
  const EtapaCuestionario(this.numero, this.titulo);
}

/// Resultado de la evaluacion generado por el analisis de orientacion.
class ResultadoOrientacion {
  final String especialidadRecomendada;
  final String descripcion;
  final List<String> categoriasDetectadas;
  final List<String> centrosRecomendadosRiobamba;
  final bool requiereAtencionPrioritaria;
  final String? profesionalSugerido;
  final String? razonMatch;

  const ResultadoOrientacion({
    required this.especialidadRecomendada,
    required this.descripcion,
    required this.categoriasDetectadas,
    required this.centrosRecomendadosRiobamba,
    this.requiereAtencionPrioritaria = false,
    this.profesionalSugerido,
    this.razonMatch,
  });
}
