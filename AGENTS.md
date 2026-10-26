# Reglas del proyecto PsicoBloom

## Idioma y nombres
- Responde y explica los cambios en español.
- Escribe en español todos los identificadores nuevos que dependan de nosotros: clases, variables, parametros, funciones, metodos, enumeraciones, constantes, archivos y carpetas.
- Usa nombres sencillos, breves y descriptivos; prioriza claridad antes que abreviar.
- No uses tildes ni ñ en los identificadores.
- Evita abreviaturas ambiguas como usr, ctx, tmp, aux o dat.
- Usa un mismo nombre para un mismo concepto en todo el proyecto.
- No traduzcas palabras reservadas, clases del SDK, metodos sobrescritos, parametros de bibliotecas ni campos exigidos por APIs. Conserva, por ejemplo, class, build, initState, dispose y Text.
- No edites archivos generados automaticamente.
- No renombres contratos existentes de base de datos o APIs sin revisar antes sus dependencias.

## Convenciones
- Clases y tipos: UpperCamelCase. Ejemplos: PantallaIngreso, ServicioAutenticacion, PerfilPaciente.
- Variables, parametros, funciones y metodos: lowerCamelCase. Ejemplos: correo, clave, fechaCita, estaCargando, iniciarSesion, guardarPerfil, buscarProfesionales.
- Archivos y carpetas: snake_case. Ejemplos: pantalla_ingreso.dart, servicio_autenticacion.dart.
- Booleanos: nombres que expresen una condicion. Ejemplos: esPaciente, tieneSesion, puedeCancelar.
- Listas: nombres en plural. Ejemplos: citas, profesionales, especialidades.
- Constantes: lowerCamelCase. Ejemplos: colorPrincipal, margenPantalla.

## Claridad
- Usa Flutter y Dart con null safety.
- Prioriza codigo sencillo de explicar en una exposicion.
- Reutiliza componentes sin crear capas innecesarias.
- Separa interfaz, acceso a datos y reglas de negocio siguiendo la estructura existente.
- Evita funciones demasiado largas y codigo duplicado.
- Escribe comentarios breves en español que expliquen decisiones.
- Los textos visibles deben tener ortografia correcta, con tildes.

## Documentos y diseño
- Revisa documentacion antes de implementar una funcionalidad.
- Usa formulacion y formalizacion como referencia del alcance, los requisitos para el comportamiento y la version corregida de E06 para las interfaces.
- Identifica las versiones vigentes; si no es posible, pregunta. No elijas una version solo por su nombre.
- Si hay contradicciones importantes, explicalas y pregunta antes de implementar la parte afectada.
- Respeta el nombre PsicoBloom, su logo, mascota y bocetos aprobados.
- Lema: Tu camino hacia el bienestar comienza con una conexión.
- No agregues funcionalidades ajenas al MVP.
- Cada boton y enlace debe tener una accion o destino definido.
- Identifica claramente cualquier dato o comportamiento simulado.

## Seguridad y servicios
- No incluyas claves privadas ni credenciales administrativas en Flutter, documentos o repositorio.
- Las integraciones que necesitan secretos deben ejecutarse mediante Supabase Edge Functions.
- No confundas ocultar botones con controlar permisos en el backend.
- Verifica documentacion oficial, costos y limites antes de incorporar servicios o paquetes.
- No copies restricciones, tablas ni reglas de Patitas ESPOCH a este proyecto.

## Forma de trabajar
- Revisa el codigo existente antes de modificarlo.
- Trabaja por etapas pequeñas y conserva lo que ya funciona.
- Antes de cambiar codigo, ejecuta flutter analyze y flutter test si el proyecto permite hacerlo; registra los errores previos.
- Despues, formatea el codigo modificado y repite las verificaciones.
- No borres pruebas ni ocultes errores para obtener un resultado limpio.
- Si no puedes ejecutar una comprobacion, indicalo.
- Al terminar cada etapa, explica los archivos modificados, su funcion, como probarlos y lo que queda pendiente.
- No afirmes haber probado en el emulador si no lo hiciste.
- Espera mi revision antes de avanzar a la siguiente etapa.
