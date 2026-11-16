import 'package:flutter_test/flutter_test.dart';
import 'package:boom/modulos/paciente/controladores/controlador_cuestionario_orientacion.dart';
import 'package:boom/modulos/paciente/controladores/gestor_resultado_orientacion.dart';
import 'package:boom/modulos/paciente/datos/preguntas_cuestionario.dart';
import 'package:boom/modulos/paciente/modelos/cuestionario_orientacion.dart';
import 'package:boom/modulos/paciente/servicios/servicio_orientacion_ia.dart';

void main() {
  group('ControladorCuestionarioOrientacion', () {
    late ControladorCuestionarioOrientacion controlador;

    setUp(() {
      GestorResultadoOrientacion.instancia.limpiar();
      controlador = ControladorCuestionarioOrientacion(
        servicio: const ServicioOrientacionIa(),
      );
    });

    tearDown(() {
      controlador.dispose();
      GestorResultadoOrientacion.instancia.limpiar();
    });

    test('Estado inicial es correcto', () {
      expect(controlador.etapaActual, EtapaCuestionario.introduccion);
      expect(controlador.respuestas, isEmpty);
      expect(controlador.estaProcesando, isFalse);
      expect(controlador.resultado, isNull);
      expect(controlador.progreso, 0.0);
      expect(controlador.puedeAvanzar(), isTrue);
    });

    test('Avanza de introduccion a la primera etapa de preguntas', () {
      final pudoAvanzar = controlador.avanzar();
      expect(pudoAvanzar, isTrue);
      expect(controlador.etapaActual, EtapaCuestionario.estadoDeAnimo);
      expect(controlador.progreso, greaterThan(0.0));
      // En estado de animo sin responder no puede avanzar
      expect(controlador.puedeAvanzar(), isFalse);
    });

    test('Registra respuestas Si/No y valida que se completen todas las preguntas de la etapa', () {
      controlador.avanzar(); // Va a estadoDeAnimo
      final preguntas = preguntasPorEtapa[EtapaCuestionario.estadoDeAnimo]!;

      // Responder 9 de 10 preguntas
      for (var i = 0; i < preguntas.length - 1; i++) {
        controlador.responderSiNo(preguntas[i].id, 'No');
      }
      expect(controlador.puedeAvanzar(), isFalse);

      // Responder la ultima pregunta
      controlador.responderSiNo(preguntas.last.id, 'Sí');
      expect(controlador.puedeAvanzar(), isTrue);
      expect(controlador.obtenerRespuesta(preguntas.last.id), 'Sí');
    });

    test('Logica condicional para eventos traumaticos (ET_01 en No omite secundarias)', () {
      // Avanzar hasta experiencias traumaticas
      controlador.avanzar(); // estadoDeAnimo
      for (final p in preguntasPorEtapa[EtapaCuestionario.estadoDeAnimo]!) {
        controlador.responderSiNo(p.id, 'No');
      }
      controlador.avanzar(); // ansiedad
      for (final p in preguntasPorEtapa[EtapaCuestionario.ansiedad]!) {
        controlador.responderSiNo(p.id, 'No');
      }
      controlador.avanzar(); // experienciasTraumaticas
      expect(controlador.etapaActual, EtapaCuestionario.experienciasTraumaticas);

      // Si responde No a ET_01, solo esa es obligatoria
      controlador.responderSiNo('ET_01', 'No');
      expect(controlador.puedeAvanzar(), isTrue);

      // Si cambia a Sí, ahora requiere las demas preguntas
      controlador.responderSiNo('ET_01', 'Sí');
      expect(controlador.puedeAvanzar(), isFalse);

      // Si responde secundarias y luego cambia ET_01 a No, se limpian las secundarias
      controlador.responderSiNo('ET_02', 'Sí');
      expect(controlador.obtenerRespuesta('ET_02'), 'Sí');

      controlador.responderSiNo('ET_01', 'No');
      expect(controlador.obtenerRespuesta('ET_02'), isNull);
      expect(controlador.puedeAvanzar(), isTrue);
    });

    test('Logica condicional para alcohol (AS_01 en No omite AS_02 a AS_04)', () {
      // Llevar el controlador hasta alcohol y otras sustancias (etapa 8)
      while (controlador.etapaActual != EtapaCuestionario.alcoholSustancias) {
        final preguntas = preguntasPorEtapa[controlador.etapaActual];
        if (preguntas != null) {
          for (final p in preguntas) {
            if (p.tipo == TipoPreguntaOrientacion.seleccionMultiple) {
              controlador.alternarOpcionMultiple(p.id, 'Ninguna de las anteriores');
            } else {
              controlador.responderSiNo(p.id, 'No');
            }
          }
        }
        controlador.avanzar();
      }
      expect(controlador.etapaActual, EtapaCuestionario.alcoholSustancias);

      // Responder AS_01 con No y AS_05 con No y AS_09 con Ninguna
      controlador.responderSiNo('AS_01', 'No');
      controlador.responderSiNo('AS_05', 'No');
      controlador.alternarOpcionMultiple('AS_09', 'Ninguna de las anteriores');

      // Puede avanzar porque las secundarias de alcohol y marihuana estan ocultas
      expect(controlador.puedeAvanzar(), isTrue);

      // Si cambia AS_01 a Sí, debe responder AS_02, AS_03, AS_04
      controlador.responderSiNo('AS_01', 'Sí');
      expect(controlador.puedeAvanzar(), isFalse);

      controlador.responderSiNo('AS_02', 'Sí');
      controlador.responderSiNo('AS_03', 'No');
      controlador.responderSiNo('AS_04', 'No');
      expect(controlador.puedeAvanzar(), isTrue);

      // Si cambia de nuevo AS_01 a No, se limpian las secundarias
      controlador.responderSiNo('AS_01', 'No');
      expect(controlador.obtenerRespuesta('AS_02'), isNull);
      expect(controlador.obtenerRespuesta('AS_03'), isNull);
      expect(controlador.obtenerRespuesta('AS_04'), isNull);
      expect(controlador.puedeAvanzar(), isTrue);
    });

    test('Logica condicional para marihuana (AS_05 en No omite AS_06 a AS_08)', () {
      while (controlador.etapaActual != EtapaCuestionario.alcoholSustancias) {
        final preguntas = preguntasPorEtapa[controlador.etapaActual];
        if (preguntas != null) {
          for (final p in preguntas) {
            if (p.tipo == TipoPreguntaOrientacion.seleccionMultiple) {
              controlador.alternarOpcionMultiple(p.id, 'Ninguna de las anteriores');
            } else {
              controlador.responderSiNo(p.id, 'No');
            }
          }
        }
        controlador.avanzar();
      }

      controlador.responderSiNo('AS_01', 'No');
      controlador.responderSiNo('AS_05', 'No');
      controlador.alternarOpcionMultiple('AS_09', 'Ninguna de las anteriores');
      expect(controlador.puedeAvanzar(), isTrue);

      // Si responde Sí a marihuana (AS_05), se activan AS_06 a AS_08
      controlador.responderSiNo('AS_05', 'Sí');
      expect(controlador.puedeAvanzar(), isFalse);

      controlador.responderSiNo('AS_06', 'Sí');
      controlador.responderSiNo('AS_07', 'No');
      controlador.responderSiNo('AS_08', 'No');
      expect(controlador.puedeAvanzar(), isTrue);

      // Si cambia AS_05 a No, se limpian AS_06..AS_08
      controlador.responderSiNo('AS_05', 'No');
      expect(controlador.obtenerRespuesta('AS_06'), isNull);
      expect(controlador.obtenerRespuesta('AS_07'), isNull);
      expect(controlador.obtenerRespuesta('AS_08'), isNull);
      expect(controlador.puedeAvanzar(), isTrue);
    });

    test('Alternancia de opciones multiples y exclusividad con Ninguna de las anteriores', () {
      const idPregunta = 'AS_09';
      const opcion1 = 'Heroína';
      const opcion2 = 'Cocaína o crack';
      const opcionNinguna = 'Ninguna de las anteriores';

      // Agregar dos sustancias
      controlador.alternarOpcionMultiple(idPregunta, opcion1);
      controlador.alternarOpcionMultiple(idPregunta, opcion2);
      var lista = controlador.obtenerRespuesta(idPregunta) as List<String>;
      expect(lista, contains(opcion1));
      expect(lista, contains(opcion2));
      expect(lista.length, 2);

      // Al seleccionar "Ninguna de las anteriores", se deben limpiar las demas
      controlador.alternarOpcionMultiple(idPregunta, opcionNinguna);
      lista = controlador.obtenerRespuesta(idPregunta) as List<String>;
      expect(lista, [opcionNinguna]);

      // Al seleccionar una nueva sustancia, se debe quitar "Ninguna de las anteriores"
      controlador.alternarOpcionMultiple(idPregunta, opcion1);
      lista = controlador.obtenerRespuesta(idPregunta) as List<String>;
      expect(lista, [opcion1]);
      expect(lista, isNot(contains(opcionNinguna)));

      // Desmarcar la opcion remueve la clave
      controlador.alternarOpcionMultiple(idPregunta, opcion1);
      expect(controlador.obtenerRespuesta(idPregunta), isNull);
    });

    test('Retrocede entre etapas correctamente', () {
      controlador.avanzar();
      expect(controlador.etapaActual, EtapaCuestionario.estadoDeAnimo);

      final retrocedio = controlador.retroceder();
      expect(retrocedio, isTrue);
      expect(controlador.etapaActual, EtapaCuestionario.introduccion);

      // No puede retroceder mas alla de la primera etapa
      final noPuedeRetrocederMas = controlador.retroceder();
      expect(noPuedeRetrocederMas, isFalse);
      expect(controlador.etapaActual, EtapaCuestionario.introduccion);
    });

    test('Finalizar y analizar guarda el resultado en GestorResultadoOrientacion', () async {
      // Simular respuestas de un caso con sintomas de animo y ansiedad
      controlador.responderSiNo('EA_01', 'Sí');
      controlador.responderSiNo('EA_02', 'Sí');
      controlador.responderSiNo('EA_03', 'Sí');
      controlador.responderSiNo('EA_05', 'Sí'); // Pregunta sensible de ideacion
      controlador.responderSiNo('AN_01', 'Sí');
      controlador.responderSiNo('AN_02', 'Sí');

      expect(GestorResultadoOrientacion.instancia.tieneResultado, isFalse);

      await controlador.finalizarYAnalizar();

      expect(controlador.etapaActual, EtapaCuestionario.resultado);
      expect(controlador.resultado, isNotNull);
      expect(controlador.resultado!.especialidadSugerida, isNotEmpty);
      expect(controlador.resultado!.centrosRecomendados, isNotEmpty);
      expect(controlador.resultado!.requiereAtencionPrioritaria, isTrue);
      expect(controlador.resultado!.esSimulado, isTrue);

      // Verifica que el gestor de sesion haya almacenado el resultado
      expect(GestorResultadoOrientacion.instancia.tieneResultado, isTrue);
      expect(
        GestorResultadoOrientacion.instancia.resultadoActual?.especialidadRecomendada,
        controlador.resultado!.especialidadRecomendada,
      );

      // Al limpiar la sesion se destruye el resultado
      GestorResultadoOrientacion.instancia.limpiar();
      expect(GestorResultadoOrientacion.instancia.tieneResultado, isFalse);
      expect(GestorResultadoOrientacion.instancia.resultadoActual, isNull);
    });

    test('Reiniciar limpia todas las respuestas y el resultado de la memoria', () async {
      controlador.responderSiNo('EA_01', 'Sí');
      await controlador.finalizarYAnalizar();

      expect(controlador.respuestas, isNotEmpty);
      expect(controlador.resultado, isNotNull);

      controlador.reiniciar();

      expect(controlador.etapaActual, EtapaCuestionario.introduccion);
      expect(controlador.respuestas, isEmpty);
      expect(controlador.resultado, isNull);
      expect(controlador.estaProcesando, isFalse);
    });
  });
}
