# Geoapify en PsicoBloom

## Alcance

Sustituye las cuadrículas dibujadas y la visualización de Google Maps por mapas reales de Geoapify en el directorio, el perfil público y el selector del consultorio. Agrega búsqueda manual de direcciones en la sección Modalidad y consultorio del profesional. Los resultados requieren selección explícita y el botón Guardar conserva las coordenadas mediante los servicios actuales. El centro inicial de Riobamba NO se guarda como ubicación real.

OpenRouteService sigue calculando rutas, distancia y duración. Cloudinary, Telegram y los demás servicios no se vuelven a configurar.

La API externa es Geoapify (Map Tiles API y Geocoding API). flutter_map es la biblioteca de representación y latlong2 la biblioteca de coordenadas. No contar estas bibliotecas como APIs externas. Mostrar ambas atribuciones y sus enlaces.

## Archivos

- lib/nucleo/servicios/servicio_geoapify.dart: geocodificación mediante Supabase y cliente HTTP autenticado de mapas, con caché compartida de memoria de hasta 12 MB/160 imágenes durante un día. No es una función de descarga para uso sin conexión.
- lib/nucleo/componentes/mapa_geoapify.dart: mapa interactivo, zoom, selección, ruta, atribución y avisos.
- lib/modulos/paciente/componentes/mapa_consultorio_ruta.dart: adapta los marcadores y la ruta existente al componente común. Conserva el panel de resultados de OpenRouteService.
- lib/modulos/profesional/vistas/pantalla_perfil_profesional.dart: reemplaza el selector anterior y agrega búsqueda de direcciones, sin autoguardar resultados.
- pubspec.yaml: reemplaza google_maps_flutter por flutter_map 8.3.2, latlong2 0.10.1 y http ^1.6.0. No se modifica supabase_flutter. pubspec.lock debe generarse con flutter pub get y luego guardarse en Git.
- supabase/functions/geoapify/index.ts: única función nueva, con GET para imágenes PNG y POST para direcciones. Verifica sesión con getUser, limita parámetros, consulta presupuesto antes de contactar al proveedor y evita exponer claves o errores internos.
- supabase/sql/19_consumo_geoapify.sql: dos tablas internas con RLS y una función reservada a service_role. No altera las tablas funcionales del proyecto.
- test/servicios/servicio_geoapify_test.dart y test/componentes/mapa_geoapify_test.dart: pruebas de resultados, errores y selección con imágenes simuladas. Actualiza la clave del selector en una prueba existente que anteriormente tocaba una cuadrícula simulada.

## Aplicación local, antes del despliegue

1. Detener la ejecución de Flutter con q o Ctrl+C en su terminal. Mantener el emulador si se va a reutilizar el mismo; no iniciar otro simultáneamente.
2. Extraer todo el ZIP en una carpeta del Escritorio.
3. Ejecutar APLICAR_GEOAPIFY.ps1. Compara los archivos que reemplazará con los recibidos en el ZIP original, admite reaplicación idéntica, se detiene ante cambios posteriores y guarda respaldo fuera del repositorio. No toca secretos. Por defecto utiliza la carpeta BOOMM de Sara; admite -RutaProyecto para otra ubicación.
4. En BOOMM ejecutar flutter pub get; después dart format sobre los siete archivos Dart que aparecen en el paquete, flutter analyze y flutter test. No usar flutter upgrade ni actualizar Supabase a v3 como parte de esta integración.
5. Si alguna comprobación falla, compartir la salida completa antes de subir los cambios o desplegar. Todavía no se puede probar el mapa real hasta completar el servidor.

## Servidor: después de revisar las comprobaciones locales

1. GEOAPIFY_API_KEY ya fue guardada por Sara en Edge Functions > Secrets. No ponerla en Flutter, JSON de conexión ni GitHub. SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY son variables automáticas del servidor, no nuevas claves para copiar al cliente.
2. Ejecutar supabase/sql/19_consumo_geoapify.sql en SQL Editor. Es aditivo y puede ejecutarse otra vez sin reiniciar los contadores.
3. Edge Functions > Deploy a new function > editor. Nombre exacto: geoapify. Reemplazar el contenido de index.ts por TODO supabase/functions/geoapify/index.ts y desplegar.
4. En Settings de geoapify mantener Verify JWT with legacy secret ACTIVADO, como las funciones autenticadas actuales. No modificar telegram-webhook.
5. El instalador agrega solamente [functions.geoapify] verify_jwt = true al config.toml local si no existe esa sección, conservando todas las demás secciones. Para un futuro despliegue CLI usar la versión de CLI ya instalada y revisar su ayuda; no actualizarla como parte de esta integración.
6. No ejecutar otra vez los SQL 16,17,18 ni volver a registrar el bot de Telegram.

## Consumo y presupuesto

El plan Free publicado por Geoapify ofrece 3000 créditos diarios sin tarjeta. Un PNG normal de 256px consume 0,25 créditos; una geocodificación simple consume 1. No se usan formatos de alta resolución ni búsquedas automáticas por cada letra.

Esta implementación reserva unidades ANTES de cada intento externo: una por PNG y cuatro por búsqueda. El presupuesto global es de 10000 unidades (2500 créditos estimados), dentro de una ventana conservadora de al menos 24 horas, calculada en intervalos horarios. Los intentos fallidos también descuentan; nunca se reembolsa un intento que pudo haber llegado al proveedor. Las reservas usan bloqueo transaccional para impedir que varias instancias superen el contador simultáneamente. No es un contador de facturación de Geoapify.

También restringe las reservas globales a 16 unidades por segundo y las de cada usuario a 240 unidades y 6 búsquedas por minuto. El cliente limita inicios a 8 imágenes por segundo, deduplica solicitudes activas y no reintenta fallos automáticamente. Al llegar al techo, el mapa muestra un aviso y deja de consultar al proveedor. Las imágenes ya conservadas pueden seguir apareciendo.

Estos límites protegen SOLO las llamadas realizadas por esta función. Las pruebas manuales del panel Geoapify, otras aplicaciones o claves de la misma cuenta pueden consumir la cuota adicional. Revisar Usage & statistics y permanecer en Free. No agregar tarjeta ni contratar un plan para esta prueba. El proxy consume invocaciones y transferencia de Supabase: su uso también debe revisarse en el panel; no es infraestructura ilimitada. La caché de memoria se pierde al cerrar la app.

La búsqueda filtra Ecuador y una zona de Riobamba y alrededores (longitudes -78.85 a -78.45, latitudes -1.90 a -1.45); no define un límite administrativo oficial. Se muestran hasta cinco candidatos, que el profesional debe comprobar. La cobertura y precisión reales de direcciones concretas aún deben probarse.

## Prueba manual completa

1. Ejecutar flutter run --dart-define-from-file=configuracion_supabase.json con el mismo archivo que ya funciona. No agregar la clave Geoapify al archivo.
2. Profesional > Perfil > Modalidad y consultorio: escribir una dirección de Riobamba y pulsar Buscar dirección en Riobamba.
3. Elegir un resultado, revisar el marcador, ajustar tocando una calle en el mapa y pulsar Guardar. Salir y volver a entrar para comprobar persistencia. Si no encuentra una dirección, usar el mapa, coordenadas o GPS; nunca se guarda automáticamente el centro predeterminado.
4. Paciente > Mapa: comprobar calles y marcadores; seleccionar un profesional. Revisar también su perfil público.
5. Calcular Cómo llegar con permiso GPS y comprobar que la línea sigue las calles, con distancia y tiempo de OpenRouteService.
6. Probar sin permiso GPS: el mapa y los consultorios deben seguir disponibles; la ruta comunica el estado del permiso.
7. Probar sin conexión y cerrar/reabrir la sesión. Debe aparecer un aviso en vez de simular calles. El reintento es manual.
8. Verificar atribuciones visibles con enlaces. Ver en Edge Functions > geoapify > Logs los códigos de respuesta, sin pegar tokens ni claves.
9. Confirmar que las fotos Cloudinary y la conexión Telegram siguen funcionando.

## Validación disponible al preparar el paquete

- 24 casos de Edge Function con Node 24 y TypeScript eliminado, autenticación/RPC/HTTP simulados: aprobados. No equivalen a deno check ni a pruebas reales del proveedor.
- 19 comprobaciones del SQL en PostgreSQL WASM con esquema mínimo: aprobadas. Incluyen límites, ventana temporal, idempotencia del script, RLS y privilegios. No hubo prueba entre conexiones independientes ni escritura remota.
- Sintaxis de todos los Dart del paquete comprobada mediante tree-sitter-dart y referencias locales revisadas.
- No fue posible ejecutar dart format, flutter analyze, flutter test, Deno ni el emulador en el entorno de preparación. Las pruebas Flutter incluidas deben ejecutarse en la computadora del equipo; NO se afirma que hayan pasado.
- No se desplegó esta integración en el proyecto remoto. La clave real no fue leída ni utilizada durante la preparación.

## Fuentes oficiales consultadas

- https://www.geoapify.com/pricing/
- https://www.geoapify.com/terms-and-conditions/
- https://apidocs.geoapify.com/docs/maps/
- https://apidocs.geoapify.com/docs/geocoding/forward-geocoding/
- https://pub.dev/packages/flutter_map/versions/8.3.2
- https://pub.dev/packages/latlong2/versions/0.10.1
- https://pub.dev/documentation/flutter_map/latest/flutter_map/NetworkTileProvider-class.html

El cambio de proveedor debe reflejarse en la tabla de APIs del documento académico, conservando el alcance de mapa, consultorios y rutas de PsicoBloom.
