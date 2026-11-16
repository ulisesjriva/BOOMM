import 'package:flutter/foundation.dart';

import '../datos/preguntas_cuestionario.dart';
import '../modelos/cuestionario_orientacion.dart';
import '../servicios/servicio_orientacion_ia.dart';
import 'gestor_resultado_orientacion.dart';

/// Controlador que gestiona el estado volátil del cuestionario de orientación,
/// la navegación entre etapas y la validación de respuestas en memoria.
class ControladorCuestionarioOrientacion extends ChangeNotifier {
  final ServicioOrientacionIa servicio;

  ControladorCuestionarioOrientacion({
    this.servicio = const ServicioOrientacionIa(),
  });

  EtapaCuestionario _etapaActual = EtapaCuestionario.introduccion;
  final Map<String, dynamic> _respuestas = <String, dynamic>{};
  bool _estaProcesando = false;
  ResultadoOrientacion? _resultado;

  EtapaCuestionario get etapaActual => _etapaActual;
  Map<String, dynamic> get respuestas => Map.unmodifiable(_respuestas);
  bool get estaProcesando => _estaProcesando;
  ResultadoOrientacion? get resultado => _resultado;

  /// Retorna el progreso general del cuestionario de 0.0 a 1.0.
  double get progreso => (_etapaActual.numero - 1) / 9.0;

  /// Obtiene la respuesta actual asignada a una pregunta.
  dynamic obtenerRespuesta(String idPregunta) => _respuestas[idPregunta];

  /// Registra la respuesta para preguntas de tipo Sí / No.
  void responderSiNo(String idPregunta, String valor) {
    _respuestas[idPregunta] = valor;

    // Si la pregunta ET_01 es respondida con "No", limpiamos las preguntas secundarias de trauma
    if (idPregunta == 'ET_01' && valor == 'No') {
      for (var i = 2; i <= 9; i++) {
        _respuestas.remove('ET_${i.toString().padLeft(2, '0')}');
      }
    }

    // Si la pregunta AS_01 (alcohol) es respondida con "No", limpiamos las secundarias de alcohol
    if (idPregunta == 'AS_01' && valor == 'No') {
      for (var i = 2; i <= 4; i++) {
        _respuestas.remove('AS_${i.toString().padLeft(2, '0')}');
      }
    }

    // Si la pregunta AS_05 (marihuana) es respondida con "No", limpiamos las secundarias de marihuana
    if (idPregunta == 'AS_05' && valor == 'No') {
      for (var i = 6; i <= 8; i++) {
        _respuestas.remove('AS_${i.toString().padLeft(2, '0')}');
      }
    }

    notifyListeners();
  }

  /// Alterna una opcion en preguntas de seleccion multiple, respetando
  /// la regla de exclusividad de "Ninguna de las anteriores".
  void alternarOpcionMultiple(String idPregunta, String opcion) {
    final seleccionActual = List<String>.from(
      (_respuestas[idPregunta] as List<dynamic>?)?.cast<String>() ?? <String>[],
    );

    const opcionNinguna = 'Ninguna de las anteriores';

    if (opcion == opcionNinguna) {
      if (seleccionActual.contains(opcionNinguna)) {
        seleccionActual.clear();
      } else {
        seleccionActual.clear();
        seleccionActual.add(opcionNinguna);
      }
    } else {
      seleccionActual.remove(opcionNinguna);
      if (seleccionActual.contains(opcion)) {
        seleccionActual.remove(opcion);
      } else {
        seleccionActual.add(opcion);
      }
    }

    if (seleccionActual.isEmpty) {
      _respuestas.remove(idPregunta);
    } else {
      _respuestas[idPregunta] = seleccionActual;
    }

    notifyListeners();
  }

  /// Determina si todas las preguntas visibles de la etapa actual estan respondidas.
  bool puedeAvanzar() {
    if (_etapaActual == EtapaCuestionario.introduccion) return true;
    if (_etapaActual == EtapaCuestionario.resultado) return true;

    final preguntas = preguntasPorEtapa[_etapaActual] ?? const [];
    for (final pregunta in preguntas) {
      if (pregunta.estaVisible(_respuestas)) {
        final respuesta = _respuestas[pregunta.id];
        if (respuesta == null) return false;
        if (pregunta.tipo == TipoPreguntaOrientacion.seleccionMultiple) {
          if (respuesta is! List || respuesta.isEmpty) return false;
        }
      }
    }
    return true;
  }

  /// Avanza a la siguiente etapa del cuestionario.
  bool avanzar() {
    if (!puedeAvanzar()) return false;

    final siguienteIndice = _etapaActual.numero + 1;
    if (siguienteIndice <= EtapaCuestionario.values.length) {
      _etapaActual = EtapaCuestionario.values.firstWhere(
        (e) => e.numero == siguienteIndice,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Retrocede a la etapa anterior del cuestionario.
  bool retroceder() {
    final anteriorIndice = _etapaActual.numero - 1;
    if (anteriorIndice >= 1) {
      _etapaActual = EtapaCuestionario.values.firstWhere(
        (e) => e.numero == anteriorIndice,
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Envia las respuestas en memoria para ser analizadas por la IA (o contingencia)
  /// y navega a la etapa de resultados.
  Future<void> finalizarYAnalizar() async {
    _estaProcesando = true;
    notifyListeners();

    try {
      _resultado = await servicio.analizarRespuestas(_respuestas);
      _etapaActual = EtapaCuestionario.resultado;
      if (_resultado != null) {
        GestorResultadoOrientacion.instancia.guardarResultado(_resultado!);
      }
    } finally {
      _estaProcesando = false;
      notifyListeners();
    }
  }

  /// Reinicia el cuestionario y destruye las respuestas temporales de la memoria.
  void reiniciar() {
    _respuestas.clear();
    _resultado = null;
    _etapaActual = EtapaCuestionario.introduccion;
    _estaProcesando = false;
    notifyListeners();
  }
}
