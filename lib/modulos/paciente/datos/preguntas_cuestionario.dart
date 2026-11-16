import '../modelos/cuestionario_orientacion.dart';

/// Catalogo completo de preguntas para el cuestionario de orientacion de PsicoBloom,
/// organizadas por etapas del 2 al 9 de acuerdo con las especificaciones tecnicas.
const Map<EtapaCuestionario, List<PreguntaOrientacion>> preguntasPorEtapa = {
  // --- ETAPA 2: ESTADO DE ÁNIMO ---
  EtapaCuestionario.estadoDeAnimo: [
    PreguntaOrientacion(
      id: 'EA_01',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando nada te haya divertido y simplemente nada te interesara?',
    ),
    PreguntaOrientacion(
      id: 'EA_02',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando hacer hasta las pequeñas cosas te haya cansado mucho?',
    ),
    PreguntaOrientacion(
      id: 'EA_03',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando te hayas sentido muy triste, deprimido/a, o abatido/a?',
    ),
    PreguntaOrientacion(
      id: 'EA_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Hubo algún periodo en el que te molestaras o irritaras fácilmente, o en el que estuvieras de mal humor con frecuencia, al punto de que hasta las cosas pequeñas te hacían enojar?',
    ),
    PreguntaOrientacion(
      id: 'EA_05',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún momento cuando hayas pensado seriamente en suicidarte?',
      esSensible: true,
      textoExplicativo:
          'Nota: Pregunta de apoyo prioritario. Si estás pasando por un momento de crisis, recuerda que dispones de apoyo profesional inmediato y confidencial.',
    ),
    PreguntaOrientacion(
      id: 'EA_06',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido un periodo cuando te hayas sentido muy inquieto/a, tanto que tuvieras que caminar o moverte constantemente?',
    ),
    PreguntaOrientacion(
      id: 'EA_07',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido un periodo en el que hayas hablado demasiado, o demasiado rápido?',
    ),
    PreguntaOrientacion(
      id: 'EA_08',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando hayas pensado que poseías habilidades o poderes especiales que te hicieran más fuerte, más inteligente o mejor que la mayoría de las personas?',
    ),
    PreguntaOrientacion(
      id: 'EA_09',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando hayas sentido a menudo que tu mente corriera demasiado rápido de un pensamiento a otro?',
    ),
    PreguntaOrientacion(
      id: 'EA_10',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido algún periodo cuando te hayas sentido tan eufórico/a, emocionado/a, en la cima del mundo o hiperactivo/a que te metieras en problemas o que otras personas pensaran que no eras tú mismo/a?',
    ),
  ],

  // --- ETAPA 3: ANSIEDAD ---
  EtapaCuestionario.ansiedad: [
    PreguntaOrientacion(
      id: 'AN_01',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Te ha resultado difícil dejar de preocuparte?',
    ),
    PreguntaOrientacion(
      id: 'AN_02',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿La preocupación te ha impedido realizar tu trabajo, ocuparte de las tareas domésticas, o llevarte bien con los demás?',
    ),
    PreguntaOrientacion(
      id: 'AN_03',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Eres de esas personas que suelen estar muy tensas o que les cuesta mucho relajarse?',
    ),
    PreguntaOrientacion(
      id: 'AN_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has sentido a menudo muy nervioso/a o incómodo/a cuando has estado con un grupo de personas (por ejemplo, en un almuerzo o en una fiesta)?',
    ),
    PreguntaOrientacion(
      id: 'AN_05',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has evitado a menudo las situaciones sociales porque te daban nervios?',
    ),
    PreguntaOrientacion(
      id: 'AN_06',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido que contar algunas cosas una y otra vez, o has tenido que obligarte a hacer algunas cosas un cierto número de veces?',
    ),
    PreguntaOrientacion(
      id: 'AN_07',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Hubo algún periodo en el que te lavaras las manos o el cuerpo una y otra vez, o te cambiaras de ropa muchas veces al día porque pensabas que estaban sucias?',
    ),
    PreguntaOrientacion(
      id: 'AN_08',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has sentido a menudo la necesidad de revisar las cosas una y otra vez? Por ejemplo, comprobar que la puerta principal esté cerrada con llave, que la estufa esté apagada, o que hayas hecho algo aunque sepas que ya lo habías hecho?',
    ),
    PreguntaOrientacion(
      id: 'AN_09',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te ha venido a la mente una y otra vez algún pensamiento, impulso, o imagen del que no pudieras deshacerte?',
    ),
    PreguntaOrientacion(
      id: 'AN_10',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has pasado mucho tiempo cada día haciendo cosas como contar, revisar o lavar las cosas una y otra vez... digamos, hasta por una hora?',
    ),
    PreguntaOrientacion(
      id: 'AN_11',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has deseado poder dejar de hacer cosas como contar, revisar o lavar las cosas una y otra vez?',
    ),
    PreguntaOrientacion(
      id: 'AN_12',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has experimentado alguna de las siguientes sensaciones, a veces de forma repentina?',
      textoExplicativo:
          'Ejemplos: palpitaciones; dificultad para respirar; sudoroso/a, mareado/a o tembloroso/a; sensación de peligro inminente o terror repentino.',
    ),
  ],

  // --- ETAPA 4: EXPERIENCIAS TRAUMÁTICAS ---
  EtapaCuestionario.experienciasTraumaticas: [
    PreguntaOrientacion(
      id: 'ET_01',
      contexto: 'Historia personal',
      texto:
          '¿Alguna vez has experimentado o presenciado un evento inusualmente aterrador, horrible o traumático?',
      textoExplicativo:
          'Por ejemplo, ser lastimado gravemente o presenciar que alguien sea lastimado gravemente.',
    ),
    PreguntaOrientacion(
      id: 'ET_02',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido muchas pesadillas o te ha costado dormir por lo que pasó?',
    ),
    PreguntaOrientacion(
      id: 'ET_03',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has esforzado mucho para no pensar en lo que pasó y para evitar escuchar o hablar sobre ello?',
    ),
    PreguntaOrientacion(
      id: 'ET_04',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has dejado de ir a lugares, ver a personas, o hacer cosas que te hagan pensar en lo que pasó?',
    ),
    PreguntaOrientacion(
      id: 'ET_05',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has sentido muy alterado/a, asustado/a o triste cuando algo te ha hecho pensar en lo que pasó?',
    ),
    PreguntaOrientacion(
      id: 'ET_06',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido pensamientos o imágenes perturbadores de lo que sucedió, cuando no querías que vinieran a la mente?',
    ),
    PreguntaOrientacion(
      id: 'ET_07',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has sentido incapaz de sentir emociones, o te has sentido alejado de las personas, de las actividades o de tu entorno?',
    ),
    PreguntaOrientacion(
      id: 'ET_08',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido creencias negativas sobre ti mismo/a, los demás, o el mundo por lo que pasó?',
      textoExplicativo:
          'Por ejemplo: "Fue mi culpa. No puedo confiar en nadie. El mundo es peligroso."',
    ),
    PreguntaOrientacion(
      id: 'ET_09',
      idCondicional: 'ET_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has estado frecuentemente a la defensiva o vigilante, o te has asustado fácilmente?',
    ),
  ],

  // --- ETAPA 5: ATENCIÓN ---
  EtapaCuestionario.atencion: [
    PreguntaOrientacion(
      id: 'AT_01',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿La mayoría de las veces, te ha costado concentrarte en lo que estás haciendo, especialmente cuando algo es aburrido o cuando hay otras cosas sucediendo a tu alrededor?',
    ),
    PreguntaOrientacion(
      id: 'AT_02',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has olvidado a menudo lo que debías hacer o lo que habías planeado hacer?',
    ),
    PreguntaOrientacion(
      id: 'AT_03',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has intentado a menudo evitar hacer cosas que te requieran prestar atención durante mucho tiempo?',
    ),
    PreguntaOrientacion(
      id: 'AT_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has cometido muchos errores porque te cuesta hacer las cosas con cuidado?',
    ),
    PreguntaOrientacion(
      id: 'AT_05',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te has sentido a menudo físicamente inquieto/a, o que siempre hayas tenido que estar moviéndote o haciendo algo? ¿Te ha costado sentarte por mucho tiempo?',
    ),
  ],

  // --- ETAPA 6: INQUIETUDES SOBRE LA COMIDA ---
  EtapaCuestionario.inquietudesComida: [
    PreguntaOrientacion(
      id: 'IC_01',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Alguien se ha preocupado porque te ha visto demasiado delgado/a?',
    ),
    PreguntaOrientacion(
      id: 'IC_02',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿A menudo te has sentido mal contigo mismo/a porque pensabas que estabas gordo/a o con sobrepeso?',
    ),
    PreguntaOrientacion(
      id: 'IC_03',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido períodos en los que hayas pensado casi todo el tiempo en la comida o en comer?',
    ),
    PreguntaOrientacion(
      id: 'IC_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Evitas ciertos o muchos alimentos por temor o experiencias negativas asociadas con la comida, y no porque estabas tratando de bajar de peso?',
    ),
    PreguntaOrientacion(
      id: 'IC_05',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has hecho alguno de los siguientes para controlar tu peso y tu forma: hacerte vomitar, usar diuréticos o laxantes, hacer ejercicio excesivamente, o ayunar?',
    ),
    PreguntaOrientacion(
      id: 'IC_06',
      contexto: 'En los últimos 3 meses...',
      texto: 'En los últimos 3 meses, ¿te has dado un atracón así?',
      textoExplicativo:
          'Un atracón significa que has comido una cantidad de comida que la mayoría consideraría más de lo común y has sentido pérdida de control.',
    ),
  ],

  // --- ETAPA 7: CAMBIOS DE PERCEPCIÓN ---
  EtapaCuestionario.cambiosPercepcion: [
    PreguntaOrientacion(
      id: 'CP_01',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Alguna vez has escuchado la voz de alguien hablando que otras personas no pueden oír?',
    ),
    PreguntaOrientacion(
      id: 'CP_02',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Alguna vez has sentido que alguien estaba jugando con tu mente?',
    ),
    PreguntaOrientacion(
      id: 'CP_03',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Alguna vez te ha parecido irreal un entorno familiar?',
    ),
    PreguntaOrientacion(
      id: 'CP_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Alguna vez has visto cosas que otras personas no pueden ver o no parecen ver?',
    ),
  ],

  // --- ETAPA 8: ALCOHOL Y OTRAS SUSTANCIAS ---
  EtapaCuestionario.alcoholSustancias: [
    PreguntaOrientacion(
      id: 'AS_01',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Has bebido alcohol?',
    ),
    PreguntaOrientacion(
      id: 'AS_02',
      idCondicional: 'AS_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Beber alcohol te ha causado problemas en la escuela o en el trabajo?',
    ),
    PreguntaOrientacion(
      id: 'AS_03',
      idCondicional: 'AS_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido discusiones con tu familia o con tus amigos por causa del alcohol?',
    ),
    PreguntaOrientacion(
      id: 'AS_04',
      idCondicional: 'AS_01',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido momentos cuando hayas bebido alcohol más o durante más tiempo de lo que querías?',
    ),
    PreguntaOrientacion(
      id: 'AS_05',
      contexto: 'En los últimos 3 meses...',
      texto: '¿Has consumido marihuana de alguna forma?',
    ),
    PreguntaOrientacion(
      id: 'AS_06',
      idCondicional: 'AS_05',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Consumir marihuana te ha causado problemas en la escuela o en el trabajo?',
    ),
    PreguntaOrientacion(
      id: 'AS_07',
      idCondicional: 'AS_05',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido discusiones con tu familia o con tus amigos por causa de la marihuana?',
    ),
    PreguntaOrientacion(
      id: 'AS_08',
      idCondicional: 'AS_05',
      valorCondicional: 'Sí',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido momentos cuando hayas consumido marihuana más o durante más tiempo de lo que querías?',
    ),
    PreguntaOrientacion(
      id: 'AS_09',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has utilizado alguna de las siguientes sustancias para experimentar sus efectos intoxicantes?',
      textoExplicativo:
          'Selecciona todas las opciones que correspondan o "Ninguna de las anteriores".',
      tipo: TipoPreguntaOrientacion.seleccionMultiple,
      opciones: [
        'Heroína',
        'Opiatos (oxicodona, fentanilo, Percocet, codeína, etc.)',
        'Psicodélicos o alucinógenos (LSD, psilocibina/hongos, ketamina, etc.)',
        'Estimulantes o anfetaminas (Adderall, Ritalin, met, etc.)',
        'Cocaína o crack',
        'Sedantes (Xanax, Valium, Rohypnol, etc.)',
        'Éxtasis, molly o MDMA',
        'Inhalantes (pegamento, disolvente, gasolina, etc.)',
        'Jarabe para la tos con DXM',
        'Ninguna de las anteriores',
      ],
    ),
  ],

  // --- ETAPA 9: OTRAS ADICCIONES ---
  EtapaCuestionario.otrasAdicciones: [
    PreguntaOrientacion(
      id: 'OA_01',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Te ha preocupado el uso o la dependencia excesivos de alguna de las siguientes actividades?',
      textoExplicativo: 'Selecciona todas las opciones que apliquen.',
      tipo: TipoPreguntaOrientacion.seleccionMultiple,
      opciones: [
        'Autolesiones (cortarse, quemarse, golpearse, etc.)',
        'Videojuegos',
        'Internet (redes sociales, videos, scroll compulsivo, etc.)',
        'Alimentación (comida chatarra, atracones, etc.)',
        'Sexo o preocupaciones relacionadas',
        'Compras compulsivas',
        'El juego / apuestas',
        'Otros hábitos repetitivos',
        'Ninguna de las anteriores',
      ],
    ),
    PreguntaOrientacion(
      id: 'OA_02',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Alguno de estos comportamientos te ha causado problemas en la escuela o en el trabajo?',
    ),
    PreguntaOrientacion(
      id: 'OA_03',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Has tenido discusiones con tu familia o con tus amigos por causa de alguno de estos comportamientos?',
    ),
    PreguntaOrientacion(
      id: 'OA_04',
      contexto: 'En los últimos 3 meses...',
      texto:
          '¿Ha habido momentos cuando hayas hecho alguno de estos comportamientos más o durante más tiempo de lo que querías?',
    ),
  ],
};
