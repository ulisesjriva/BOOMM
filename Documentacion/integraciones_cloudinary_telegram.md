# Cloudinary y Telegram en PsicoBloom

## Estado comprobado

- Nuevas fotos del profesional: subida autenticada mediante `subir-foto-profesional` a Cloudinary, URL persistida y visible tanto para profesional como para paciente. Las URLs anteriores de Supabase Storage siguen siendo compatibles. No implementa todavía los QR bancarios.
- Telegram: vinculación opcional del profesional desde Perfil y recepción real de avisos después de una nueva solicitud. Las notificaciones de Telegram no equivalen a notificaciones push de Firebase dentro de PsicoBloom.
- No se envían nombres de pacientes ni información clínica. Mensaje: «PsicoBloom: tienes una nueva solicitud de cita. Abre la app y revisa Solicitudes.»

## Descargar y ejecutar con el backend compartido

1. Guardar o confirmar primero los cambios propios. No ejecutar reset ni sobrescribir trabajo local.
2. Descargar la rama `integracion/sara-agenda-equipo`. Si ya existe localmente, cambiar a ella y actualizar con `git pull --ff-only`; si no existe, crear su seguimiento desde origin después de `git fetch origin`.
3. Ejecutar `flutter pub get`.
4. Conservar el archivo local ignorado `configuracion_supabase.json`, apuntando al backend PSICOBLOOM compartido. Pedir la URL y clave pública por un canal del equipo; nunca usar service_role en Flutter.
5. Ejecutar `flutter run --dart-define-from-file=configuracion_supabase.json`.
6. Con el mismo proyecto Supabase ya configurado, NO repetir migraciones, crear otro bot ni reemplazar secretos para cada computadora.
7. Cada profesional vincula su propia cuenta de Telegram desde Perfil. En un navegador que pierda el parámetro start, abrir el enlace completo en el celular. El código caduca a los diez minutos, es de un solo uso y cada nuevo enlace anula el anterior. No compartirlo públicamente.
8. Crear una solicitud nueva para el profesional conectado, mantenerla pendiente y revisar el Telegram vinculado en el siguiente ciclo del programador.

## Archivos necesarios

- Servicio de fotos y servicio de Telegram en `lib/modulos/profesional/servicios`, controlador y vista de Perfil.
- `pubspec.yaml`, `pubspec.lock` y pruebas pertinentes.
- Funciones: `subir-foto-profesional`, `generar-codigo-telegram`, `telegram-webhook`, `despachar-avisos-telegram`.
- SQL 16 y 17 revisados. SQL 18 documenta la programación FINAL; sustituye el ejemplo comentado al final de 16, que no incluía la clave adicional de despacho.
- `supabase/config.toml`: excepción de JWT únicamente para `telegram-webhook`. Conservar las otras configuraciones locales si las hubiera.

## Configuración exclusiva del servidor

Estos nombres se documentan sin sus valores. No introducir secretos en Flutter, capturas, comandos literales, GitHub ni archivos versionados.

Edge Functions Secrets:

- `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`.
- `TELEGRAM_DISPATCH_SECRET`: clave aleatoria exclusiva del programador.
- Conservar `ORS_API_KEY` de rutas.

Vault (distinto de Edge Functions Secrets):

- `psicobloom_supabase_url`: URL base del proyecto.
- `psicobloom_service_role_key`: clave legacy service_role del mismo proyecto; solo en servidor.
- `psicobloom_telegram_dispatch_secret`: EXACTAMENTE el valor de `TELEGRAM_DISPATCH_SECRET`.

La versión final del despachador conserva JWT activado y además comprueba la cabecera `X-Telegram-Dispatch-Secret`. No autentica al programador comparando literalmente Authorization con la variable interna del runtime. Cloudinary y la vinculación no necesitan cambios por esta corrección.

## Configurar otro proyecto Supabase

Aplicar primero las migraciones base del proyecto en su orden y cotejar el esquema. Después aplicar 16 y comprobar 17 completo (termina con ROLLBACK). No aplicar la migración 16 original y la revisada indistintamente sobre tablas ya existentes; preparar una actualización si se instaló la original.

Desplegar las cuatro funciones. Solo `telegram-webhook` tiene desactivado «Verify JWT with legacy secret», ya que valida el secreto que Telegram entrega en `X-Telegram-Bot-Api-Secret-Token`. El generador y el despachador conservan JWT activado. Registrar el webhook con `setWebhook`, el endpoint de ese proyecto y el mismo `secret_token` guardado en Secrets. No reemplazar el webhook del bot compartido para probar otro backend: un bot admite un único webhook activo.

Habilitar pg_cron y pg_net. Crear los secretos en Vault desde el panel. Ejecutar SQL 18 cuando todo esté preparado. El trabajo revisa cada minuto e invoca la función únicamente si hay eventos pendientes o reservas vencidas. Esta configuración ya está aplicada en el backend compartido; el archivo 18 se añade al repositorio para reproducibilidad.

## Comprobación y límites

- Confirmar `Conectado` en Perfil y recibir el mensaje real tras una nueva solicitud.
- Las solicitudes anteriores a la vinculación no se notifican retroactivamente.
- Desconectar o cambiar de chat invalida los avisos anteriores pendientes. Un envío que ya estaba en curso podría llegar.
- El límite es cinco intentos; los errores de Telegram no deshacen la cita.
- Si la respuesta de Telegram se pierde después de aceptar un mensaje, un reintento podría duplicarlo. No se garantiza entrega exactamente una vez.
- Un cron marcado como exitoso solo confirma que ejecutó su SQL. Consultar también el estado de la cola y el código HTTP del despachador.
- Último diagnóstico corregido: respuesta HTTP 200, un aviso enviado y cero errores de confirmación; recepción confirmada por la usuaria en teléfono y Telegram Web.

## Costos y secretos

La cuenta Cloudinary utilizada mostraba plan Free. Vigilar consumo y mantener desactivadas contrataciones de pago no autorizadas. Revisar por separado las cuotas vigentes del proyecto Supabase. El registro de una cuenta Telegram puede solicitar pago de verificación según número/operador, aunque el uso normal del Bot API sea sin costo; no es necesario registrar una cuenta en cada emulador.

No subir `configuracion_supabase.json`, `.env`, ZIP de revisión, tokens, claves privadas ni exportaciones de Vault. Para publicar, añadir explícitamente los archivos de esta integración y revisar el diff preparado.
