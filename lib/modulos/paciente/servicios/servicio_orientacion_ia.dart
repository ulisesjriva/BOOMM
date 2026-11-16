import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../configuracion/configuracion_supabase.dart';
import '../modelos/cuestionario_orientacion.dart';

/// Servicio responsable de procesar las respuestas del cuestionario y generar
/// una recomendacion de orientacion y especialidad utilizando IA (Gemini via Edge Function)
/// o un analizador de contingencia determinista cuando no hay conexion.
///
/// IMPORTANTE: No persiste las respuestas individuales en la base de datos,
/// protegiendo la confidencialidad y respetando el principio de minimizacion.
class ServicioOrientacionIa {
  const ServicioOrientacionIa();

  /// Procesa las respuestas acumuladas en memoria y retorna el resultado de orientacion.
  Future<ResultadoOrientacion> analizarRespuestas(
    Map<String, dynamic> respuestas,
  ) async {
    // 1. Si Supabase esta configurado, intentamos invocar la Edge Function segura
    if (ConfiguracionSupabase.estaConfigurado) {
      try {
        final respuesta = await Supabase.instance.client.functions.invoke(
          'orientacion-ia',
          body: {'respuestas': respuestas},
        );

        if (respuesta.status == 200 && respuesta.data is Map<String, dynamic>) {
          final datos = respuesta.data as Map<String, dynamic>;
          return ResultadoOrientacion(
            especialidadRecomendada:
                datos['especialidad_recomendada'] as String? ??
                'Psicología Clínica',
            descripcion:
                datos['descripcion'] as String? ??
                'Se recomienda valoración por un profesional de la salud mental.',
            categoriasDetectadas:
                (datos['categorias_detectadas'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[],
            centrosRecomendadosRiobamba:
                (datos['centros_recomendados'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const <String>[
                  'Centro de Salud Nro. 1 (La Policlínica, Riobamba)',
                  'Hospital General Docente de Riobamba - Área de Salud Mental',
                ],
            requiereAtencionPrioritaria:
                datos['requiere_atencion_prioritaria'] as bool? ?? false,
            profesionalSugerido: datos['profesional_sugerido'] as String?,
            razonMatch: datos['razon_match'] as String?,
          );
        }
      } catch (_) {
        // En caso de que la Edge Function no este desplegada aun,
        // pasamos al analizador local de orientacion para no bloquear la experiencia.
      }
    }

    // 2. Analizador heuristico local de contingencia
    return _analizarLocalmente(respuestas);
  }

  /// Analiza de forma determinista las respuestas en memoria para sugerir
  /// especialidades y centros de atencion en Riobamba.
  ResultadoOrientacion _analizarLocalmente(Map<String, dynamic> respuestas) {
    final categorias = <String>[];
    var puntuacionAnimo = 0;
    var puntuacionAnsiedad = 0;
    var puntuacionAtencion = 0;
    var puntuacionComida = 0;
    var puntuacionSustancias = 0;
    var requiereAtencionPrioritaria = false;

    // Evaluacion de ideacion suicida (EA_05)
    if (respuestas['EA_05'] == 'Sí') {
      requiereAtencionPrioritaria = true;
      categorias.add('Atención y Acompañamiento Prioritario');
    }

    // Estado de animo (EA)
    for (var i = 1; i <= 10; i++) {
      final clave = 'EA_${i.toString().padLeft(2, '0')}';
      if (respuestas[clave] == 'Sí') puntuacionAnimo++;
    }
    if (puntuacionAnimo >= 3) {
      categorias.add('Estado de Ánimo y Afectividad');
    }

    // Ansiedad (AN)
    for (var i = 1; i <= 12; i++) {
      final clave = 'AN_${i.toString().padLeft(2, '0')}';
      if (respuestas[clave] == 'Sí') puntuacionAnsiedad++;
    }
    if (puntuacionAnsiedad >= 3) {
      categorias.add('Manejo del Estrés y Ansiedad');
    }

    // Traumas (ET)
    if (respuestas['ET_01'] == 'Sí') {
      categorias.add('Abordaje de Experiencias Traumáticas');
    }

    // Atencion (AT)
    for (var i = 1; i <= 5; i++) {
      final clave = 'AT_${i.toString().padLeft(2, '0')}';
      if (respuestas[clave] == 'Sí') puntuacionAtencion++;
    }
    if (puntuacionAtencion >= 3) {
      categorias.add('Concentración y Atención');
    }

    // Comida (IC)
    for (var i = 1; i <= 6; i++) {
      final clave = 'IC_${i.toString().padLeft(2, '0')}';
      if (respuestas[clave] == 'Sí') puntuacionComida++;
    }
    if (puntuacionComida >= 2) {
      categorias.add('Conducta Alimentaria y Autoimagen');
    }

    // Sustancias y adicciones (AS y OA)
    for (var i = 1; i <= 8; i++) {
      final clave = 'AS_${i.toString().padLeft(2, '0')}';
      if (respuestas[clave] == 'Sí') puntuacionSustancias++;
    }
    final drogas = respuestas['AS_09'];
    if (drogas is List &&
        drogas.isNotEmpty &&
        !drogas.contains('Ninguna de las anteriores')) {
      puntuacionSustancias += 2;
    }
    if (puntuacionSustancias >= 2) {
      categorias.add('Uso de Sustancias y Prevención');
    }

    // Determinar la especialidad y centros recomendados
    String especialidad;
    String descripcion;

    if (puntuacionAnimo >= 3 && puntuacionAnsiedad >= 3) {
      especialidad = 'Psicología Clínica y Psicoterapia';
      descripcion =
          'Tus respuestas señalan inquietudes compartidas entre el estado de ánimo y la tensión o ansiedad. Un especialista en Psicología Clínica o Psicoterapia Cognitiva puede brindarte herramientas adaptadas para recuperar el equilibrio.';
    } else if (puntuacionAnsiedad >= 3) {
      especialidad = 'Psicoterapia Cognitiva';
      descripcion =
          'Se identifican manifestaciones asociadas a preocupaciones recurrentes o tensión. La Psicoterapia Cognitivo-Conductual es idónea para gestionar pensamientos intrusivos y el estrés diario.';
    } else if (puntuacionAnimo >= 3) {
      especialidad = 'Psicología Clínica';
      descripcion =
          'Tus respuestas sugieren variaciones en el interés, motivación y ánimo. Te sugerimos consultar con un psicólogo clínico para una orientación personalizada.';
    } else if (puntuacionComida >= 2) {
      especialidad = 'Psicología de la Alimentación y Autoimagen';
      descripcion =
          'Tus respuestas muestran preocupaciones en torno a la alimentación o el peso. Un profesional especializado te orientará con empatía hacia una relación saludable con tu cuerpo.';
    } else if (puntuacionAtencion >= 3) {
      especialidad = 'Psicología Educativa / Neuropsicología';
      descripcion =
          'Identificamos dificultades para mantener la atención o inquietud física. Profesionales en orientación psicológica o evaluación cognitiva te ayudarán con técnicas de organización y enfoque.';
    } else {
      especialidad = 'Psicología General y Bienestar';
      descripcion =
          'Este cuestionario sirve como punto de partida. Una sesión de valoración general te permitirá profundizar en tus inquietudes con un profesional colegiado.';
    }

    final centrosRiobamba = <String>[
      'Centro de Salud Tipo C Espoch - Lizarzaburu (Riobamba)',
      'Hospital General Docente de Riobamba - Consulta Externa de Psicología',
      'Centro de Salud Nro. 1 (Sector La Policlínica, Riobamba)',
      'Consultorios privados del directorio PsicoBloom en Riobamba',
    ];

    String profesionalSugerido;
    String razonMatch;

    if (puntuacionAnimo >= 3) {
      profesionalSugerido = 'Dra. Ana Demo Prueba Clínica (Psicología Clínica)';
      razonMatch =
          'Su experiencia en evaluación clínica y acompañamiento en desánimo y motivación concuerda con las necesidades identificadas.';
    } else if (puntuacionAnsiedad >= 3) {
      profesionalSugerido = 'Dr. Carlos Pérez (Psicología General)';
      razonMatch =
          'Su enfoque en reducción de estrés, manejo de preocupaciones y técnicas de respiración se adapta a tu perfil.';
    } else if (respuestas['ET_01'] == 'Sí') {
      profesionalSugerido = 'Dra. María López (Psicoterapia y Trauma)';
      razonMatch =
          'Su perfil clínico se especializa en intervención de experiencias estresantes o eventos traumáticos.';
    } else {
      profesionalSugerido = 'Dra. Ana Demo Prueba Clínica (Psicología Clínica)';
      razonMatch =
          'Recomendada por su cercanía y cobertura integral en valoración inicial para pacientes en Riobamba.';
    }

    return ResultadoOrientacion(
      especialidadRecomendada: especialidad,
      descripcion: descripcion,
      categoriasDetectadas:
          categorias.isEmpty ? const ['Orientación General'] : categorias,
      centrosRecomendadosRiobamba: centrosRiobamba,
      requiereAtencionPrioritaria: requiereAtencionPrioritaria,
      profesionalSugerido: profesionalSugerido,
      razonMatch: razonMatch,
    );
  }
}
