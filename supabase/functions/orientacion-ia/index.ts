// Supabase Edge Function: orientacion-ia
// Analiza de forma confidencial y en memoria volatil las respuestas del cuestionario
// de salud mental mediante un modelo de lenguaje (Gemini / OpenAI / Groq)
// sin almacenar informacion clinica privada en tablas de base de datos.
// Realiza match con profesionales y centros de salud de Riobamba.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function respuestaJson(status: number, cuerpo: Record<string, unknown>): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      ...cabecerasCors,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

interface ProfesionalResumen {
  nombre: string;
  especialidad: string;
  descripcion: string;
  modalidad?: string;
  direccion?: string;
}

const centrosReferencialesRiobamba = [
  'Hospital General Docente de Riobamba - Área de Salud Mental',
  'Centro de Salud Tipo B Lizarzaburu (Atención psicológica ambulatoria)',
  'Centro de Salud Bellavista (Atención primaria en bienestar emocional)',
  'Centro de Salud Tipo C Santa Rosa (Salud mental comunitaria)',
  'Centro de Salud Nro. 1 (La Policlínica, Riobamba)',
];

const profesionalesCatalogoBase: ProfesionalResumen[] = [
  {
    nombre: 'Dra. Ana Demo Prueba Clínica',
    especialidad: 'Psicología Clínica',
    descripcion:
      'Especialista en psicoterapia cognitivo-conductual, depresión, estados de ánimo alterados y crisis emocionales.',
    modalidad: 'Presencial',
    direccion: 'Av. Daniel León Borja y Carlos Zambrano, Riobamba',
  },
  {
    nombre: 'Dr. Carlos Pérez',
    especialidad: 'Psicología General',
    descripcion:
      'Orientación y apoyo en manejo del estrés cotidiano, autoimagen, ansiedad leve y habilidades de afrontamiento.',
    modalidad: 'Presencial',
    direccion: 'Calle 10 de Agosto y Rocafuerte, Riobamba',
  },
  {
    nombre: 'Dra. María López',
    especialidad: 'Psicoterapia y Trauma',
    descripcion:
      'Intervención en experiencias traumáticas, duelo, estrés postraumático y contención en crisis afectivas.',
    modalidad: 'Presencial y Virtual',
    direccion: 'Av. Unidad Nacional y Carabobo, Riobamba',
  },
  {
    nombre: 'Dr. Juan Morales',
    especialidad: 'Neuropsicología y Atención',
    descripcion:
      'Evaluación neuropsicológica, dificultades de concentración, déficit de atención y rendimiento académico/laboral.',
    modalidad: 'Presencial',
    direccion: 'Av. Antonio José de Sucre y Primera Constituyente, Riobamba',
  },
];

async function obtenerProfesionalesRegistrados(
  url: string,
  key: string,
): Promise<ProfesionalResumen[]> {
  try {
    const supabase = createClient(url, key);
    const { data, error } = await supabase.rpc(
      'directorio_profesionales_completo',
    );

    if (!error && Array.isArray(data) && data.length > 0) {
      return data.map((item: any) => ({
        nombre: `${item.nombre ?? ''} ${item.apellido ?? ''}`.trim() || 'Profesional de la salud',
        especialidad: item.especialidad ?? 'Psicología General',
        descripcion: item.descripcion ?? 'Atención psicológica y acompañamiento terapéutico.',
        modalidad: item.modalidad ?? 'Presencial',
        direccion: item.direccion_consultorio ?? 'Riobamba, Ecuador',
      }));
    }
  } catch (_) {
    // Si la llamada RPC no está disponible, usamos los profesionales referenciales
  }
  return profesionalesCatalogoBase;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cabecerasCors });
  }

  if (req.method !== 'POST') {
    return respuestaJson(405, { error: 'Método no permitido. Utiliza POST.' });
  }

  try {
    const cuerpo = await req.json();
    const respuestas = (cuerpo?.respuestas as Record<string, unknown>) ?? {};

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

    // Claves de proveedores de IA configuradas en Supabase Secrets
    const geminiKey =
      Deno.env.get('GEMINI_API_KEY') ??
      Deno.env.get('AI_API_KEY') ??
      Deno.env.get('GOOGLE_AI_API_KEY');
    const openAiKey = Deno.env.get('OPENAI_API_KEY');
    const groqKey = Deno.env.get('GROQ_API_KEY');

    const listaProfesionales = await obtenerProfesionalesRegistrados(
      supabaseUrl,
      supabaseAnonKey,
    );

    // Detección de alerta prioritaria (ideación suicida en EA_05)
    const requiereAtencionPrioritaria = respuestas['EA_05'] === 'Sí';

    // Si hay una API Key configurada, invocamos el modelo de IA
    if (geminiKey) {
      const resultadoIa = await consultarGemini(
        geminiKey,
        respuestas,
        listaProfesionales,
        requiereAtencionPrioritaria,
      );
      if (resultadoIa) return respuestaJson(200, resultadoIa);
    } else if (openAiKey) {
      const resultadoIa = await consultarOpenAi(
        openAiKey,
        respuestas,
        listaProfesionales,
        requiereAtencionPrioritaria,
      );
      if (resultadoIa) return respuestaJson(200, resultadoIa);
    } else if (groqKey) {
      const resultadoIa = await consultarGroq(
        groqKey,
        respuestas,
        listaProfesionales,
        requiereAtencionPrioritaria,
      );
      if (resultadoIa) return respuestaJson(200, resultadoIa);
    }

    // Análisis heurístico de contingencia local si la IA no está configurada o falló
    const resultadoContingencia = generarOrientacionContingencia(
      respuestas,
      listaProfesionales,
      requiereAtencionPrioritaria,
    );
    return respuestaJson(200, resultadoContingencia);
  } catch (error) {
    return respuestaJson(500, {
      error: 'Error interno al procesar la orientación.',
      detalle: error instanceof Error ? error.message : String(error),
    });
  }
});

function construirPromptOrientacion(
  respuestas: Record<string, unknown>,
  profesionales: ProfesionalResumen[],
  requiereAtencionPrioritaria: boolean,
): string {
  return `Actúa como PsicoBloom IA, un sistema de triage y orientación psicológica preventiva para la ciudad de Riobamba, Ecuador.
Tu tarea es analizar las respuestas a un cuestionario de cribado de salud mental y sugerir el camino de apoyo profesional más adecuado.

REGLAS OBLIGATORIAS:
1. NO emitas diagnósticos médicos o psiquiátricos definitivos. Habla de síntomas observados, patrones de afectación y focos de atención prioritarios.
2. Explica de forma clara, empática y comprensible qué puede estar experimentando la persona en su día a día (feedback detallado).
3. Revisa la lista de profesionales y centros disponibles y selecciona el que tenga mayor afinidad o "match" con el cuadro del paciente, justificando la elección en "razon_match".
4. Si requiere atención prioritaria (${requiereAtencionPrioritaria ? 'SÍ, SE DETECTÓ RIESGO' : 'No'}), resáltalo con delicadeza recordando la línea 171 (Opción 6) y ECU 911.
5. Devuelve ÚNICAMENTE un objeto JSON sin markdown exterior con el siguiente formato exacto:

{
  "especialidad_recomendada": "Nombre de la especialidad (ej. Psicología Clínica, Neuropsicología, etc.)",
  "descripcion": "Feedback empático y comprensible explicando lo que puede estar ocurriendo y recomendaciones iniciales.",
  "categorias_detectadas": ["Área 1", "Área 2"],
  "profesional_sugerido": "Nombre y especialidad del profesional más afín",
  "razon_match": "Justificación concisa de por qué este profesional o centro se adapta a su caso según su descripción y especialidad.",
  "centros_recomendados": ["Centro 1", "Centro 2"],
  "requiere_atencion_prioritaria": ${requiereAtencionPrioritaria}
}

RESPUESTAS DEL CUESTIONARIO DEL PACIENTE:
${JSON.stringify(respuestas, null, 2)}

PROFESIONALES Y CENTROS DISPONIBLES:
${JSON.stringify(profesionales, null, 2)}

CENTROS DE SALUD PÚBLICOS EN RIOBAMBA:
${JSON.stringify(centrosReferencialesRiobamba, null, 2)}`;
}

async function consultarGemini(
  apiKey: string,
  respuestas: Record<string, unknown>,
  profesionales: ProfesionalResumen[],
  requiereAtencionPrioritaria: boolean,
): Promise<Record<string, unknown> | null> {
  try {
    const prompt = construirPromptOrientacion(
      respuestas,
      profesionales,
      requiereAtencionPrioritaria,
    );
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;

    const respuesta = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          response_mime_type: 'application/json',
          temperature: 0.3,
        },
      }),
    });

    if (!respuesta.ok) return null;
    const datos = await respuesta.json();
    const textoRespuesta =
      datos?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (textoRespuesta) {
      return JSON.parse(textoRespuesta);
    }
  } catch (_) {}
  return null;
}

async function consultarOpenAi(
  apiKey: string,
  respuestas: Record<string, unknown>,
  profesionales: ProfesionalResumen[],
  requiereAtencionPrioritaria: boolean,
): Promise<Record<string, unknown> | null> {
  try {
    const prompt = construirPromptOrientacion(
      respuestas,
      profesionales,
      requiereAtencionPrioritaria,
    );
    const respuesta = await fetch(
      'https://api.openai.com/v1/chat/completions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content:
                'Eres PsicoBloom IA, asistente de orientación psicológica en Riobamba. Responde únicamente en JSON válido.',
            },
            { role: 'user', content: prompt },
          ],
          response_format: { type: 'json_object' },
          temperature: 0.3,
        }),
      },
    );

    if (!respuesta.ok) return null;
    const datos = await respuesta.json();
    const contenido = datos?.choices?.[0]?.message?.content;
    if (contenido) {
      return JSON.parse(contenido);
    }
  } catch (_) {}
  return null;
}

async function consultarGroq(
  apiKey: string,
  respuestas: Record<string, unknown>,
  profesionales: ProfesionalResumen[],
  requiereAtencionPrioritaria: boolean,
): Promise<Record<string, unknown> | null> {
  try {
    const prompt = construirPromptOrientacion(
      respuestas,
      profesionales,
      requiereAtencionPrioritaria,
    );
    const respuesta = await fetch(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'llama-3.3-70b-versatile',
          messages: [
            {
              role: 'system',
              content:
                'Eres PsicoBloom IA, asistente de orientación psicológica en Riobamba. Responde únicamente en JSON válido.',
            },
            { role: 'user', content: prompt },
          ],
          response_format: { type: 'json_object' },
          temperature: 0.3,
        }),
      },
    );

    if (!respuesta.ok) return null;
    const datos = await respuesta.json();
    const contenido = datos?.choices?.[0]?.message?.content;
    if (contenido) {
      return JSON.parse(contenido);
    }
  } catch (_) {}
  return null;
}

function generarOrientacionContingencia(
  respuestas: Record<string, unknown>,
  profesionales: ProfesionalResumen[],
  requiereAtencionPrioritaria: boolean,
): Record<string, unknown> {
  const categorias: string[] = [];
  let sintomasAnimo = 0;
  let sintomasAnsiedad = 0;
  let sintomasTrauma = respuestas['ET_01'] === 'Sí';
  let sintomasAtencion = 0;

  for (let i = 1; i <= 10; i++) {
    const k = `EA_${String(i).padStart(2, '0')}`;
    if (respuestas[k] === 'Sí') sintomasAnimo++;
  }
  for (let i = 1; i <= 12; i++) {
    const k = `AN_${String(i).padStart(2, '0')}`;
    if (respuestas[k] === 'Sí') sintomasAnsiedad++;
  }
  for (let i = 1; i <= 5; i++) {
    const k = `AT_${String(i).padStart(2, '0')}`;
    if (respuestas[k] === 'Sí') sintomasAtencion++;
  }

  if (sintomasAnimo >= 3) categorias.push('Estado de Ánimo y Afectividad');
  if (sintomasAnsiedad >= 3) categorias.push('Manejo del Estrés y Ansiedad');
  if (sintomasTrauma) categorias.push('Abordaje de Experiencias Traumáticas');
  if (sintomasAtencion >= 3) categorias.push('Concentración y Atención');

  let especialidad = 'Psicología Clínica';
  let profesionalElegido = profesionales[0];

  if (sintomasTrauma) {
    especialidad = 'Psicoterapia y Trauma';
    profesionalElegido =
      profesionales.find((p) => p.especialidad.toLowerCase().includes('trauma')) ??
      profesionales[0];
  } else if (sintomasAtencion >= 3 && sintomasAnimo < 3) {
    especialidad = 'Neuropsicología';
    profesionalElegido =
      profesionales.find((p) =>
        p.especialidad.toLowerCase().includes('neuro') ||
        p.especialidad.toLowerCase().includes('atención'),
      ) ?? profesionales[0];
  } else if (sintomasAnsiedad > sintomasAnimo) {
    especialidad = 'Psicología General y Manejo de Estrés';
    profesionalElegido =
      profesionales.find((p) => p.especialidad.toLowerCase().includes('general')) ??
      profesionales[0];
  }

  return {
    especialidad_recomendada: especialidad,
    descripcion:
      'Tus respuestas reflejan una carga emocional que podría beneficiarse de acompañamiento psicológico profesional para el manejo de tus pensamientos y emociones cotidianas.',
    categorias_detectadas:
      categorias.length > 0 ? categorias : ['Bienestar Emocional General'],
    profesional_sugerido: `${profesionalElegido.nombre} (${profesionalElegido.especialidad})`,
    razon_match: `Su perfil y experiencia en ${profesionalElegido.descripcion} se alinean estrechamente con las áreas prioritarias detectadas.`,
    centros_recomendados: centrosReferencialesRiobamba.slice(0, 3),
    requiere_atencion_prioritaria: requiereAtencionPrioritaria,
  };
}
