# Diseño del proceso de adelantos, QR bancario, cancelaciones, reprogramación y reembolsos — PsicoBloom

Documento de diseño de la **Primera Etapa** (solo análisis y arquitectura; sin cambios en código ni en SQL remoto).

---

## 1. Estado actual del proyecto (base revisada)
- **Rama actual:** `feature/mapas-multiplataforma-google-oauth` (`8617a28`)
- **Remoto:** `origin` → `https://github.com/ulisesjriva/BOOMM.git`
- **Citas y disponibilidad (`08_solicitud_citas_paciente.sql`, `10_respuesta_citas_profesional.sql`, `14_agenda_semanal_profesional.sql`):**
  - `solicitar_cita_paciente(id_profesional, id_disponibilidad)` crea la fila en `public."Citas"` con estado `'pendiente'` y bloquea `public."Disponibilidad"` como `'reservada'` siguiendo el orden canónico `Profesionales -> Disponibilidad -> Citas`.
  - `responder_solicitud_cita_profesional(id_cita, decision)` pasa `'pendiente'` → `'confirmada'` o `'rechazada'`. Al rechazar, libera el horario a `'disponible'` dentro de la misma transacción.
  - Los triggers actuales prohíben eliminar filas de `public."Citas"` (conservan historial), impiden editar o borrar horarios con citas históricas vinculadas y bloquean liberar manualmente un horario `'reservada'` fuera de contextos autorizados.
  - Existen los estados `'pendiente'`, `'confirmada'`, `'rechazada'`, `'cancelada'` y `'finalizada'` en `public."Citas"`, pero **todavía no existen RPCs** de cancelación (ni por paciente ni por profesional) ni de reprogramación.
- **Precios y `QRTransferencia`:**
  - `public."Servicios"` (`05_perfiles_especialidades_ubicacion.sql`) almacena `nombre_servicio`, `duracion_minutos` y `activo`, **sin columna de precio ni monto de adelanto**.
  - No existe tabla `QRTransferencia` ni registros de cuentas/QR bancarios en los scripts SQL actuales (`01` a `20`).
- **Almacenamiento y Cloudinary:**
  - `supabase/functions/subir-foto-profesional/index.ts` sube fotos de perfil profesional a Cloudinary mediante firma en servidor (URLs públicas `https://res.cloudinary.com/...`).
  - `fotos-profesionales` en Supabase Storage conserva compatibilidad con fotos previas.
  - No existe aún almacenamiento privado para comprobantes bancarios de pacientes o de reembolsos.
- **Avisos, agenda y módulo Administrador:**
  - `16_avisos_telegram_profesional.sql` encola un aviso Telegram en `AFTER INSERT ON public."Citas"` cuando `estado = 'pendiente'`.
  - `20_modulo_administrador.sql` consulta todas las citas por estado (`resumen_administracion`, `listar_citas_administracion`) sin exponer datos clínicos.

---

## 2. Reglas funcionales acordadas

1. **Flujo principal de cita con adelanto:**
   `solicitar` → `profesional acepta` → `paciente paga adelanto` → `profesional verifica ingreso` → `cita confirmada`.
2. **QR bancario del profesional:** El profesional carga su propio QR bancario (y monto/tarifa aplicable según las reglas del servicio).
3. **Privacidad de comprobantes:** Todos los comprobantes de pago y de reembolso son **privados**. Subir un comprobante **no** confirma el pago ni la cita; requiere verificación explícita del profesional.
4. **Cancelación del paciente sin reprogramación previa:**
   - Si faltan **24 horas o más** para la cita: **devolución completa** del adelanto recibido.
   - Si faltan **menos de 24 horas**: **sin devolución**.
5. **Reprogramación única:**
   - Se permite **una sola reprogramación** con el **mismo profesional**, conservando el adelanto ya pagado (sin volver a cobrar adelanto).
6. **Cancelación del paciente después de reprogramar:**
   - **Sin devolución** del adelanto.
7. **Cancelación del profesional:**
   - **Devolución completa** del adelanto recibido, independientemente de la anticipación.
8. **Reembolso manual con trazabilidad:**
   - El reembolso se ejecuta manualmente fuera de pasarela automática, pero con seguimiento de estado en sistema y comprobante privado adjunto.
9. **Confirmaciones claras:**
   - Antes de cancelar o reprogramar, la interfaz debe mostrar explícitamente el **monto real** del adelanto y la consecuencia económica (devolución completa, conservación de adelanto o sin devolución).
10. **Seguridad, integridad e historial:**
    - Validaciones estrictas en servidor (autorización por `auth.uid()` y `_rol_activo()`), prevención de duplicados/doble gasto, orden canónico de bloqueos y conservación íntegra de citas, horarios y registros históricos (sin `DELETE`).
11. **Compatibilidad retroactiva:**
    - Las citas ya existentes antes de esta funcionalidad **conservarán su funcionamiento actual**; no se les impondrá un adelanto ni bloqueo de pago retroactivamente.

---

## 3. Puntos PENDIENTES de definición (no decididos automáticamente)

- [ ] **Plazos operativos:**
  - Tiempo máximo para que el paciente suba el comprobante tras la aceptación del profesional (y qué ocurre si vence: ¿liberación automática del horario?).
  - Tiempo máximo para que el profesional verifique el ingreso del comprobante.
  - Plazo máximo para efectuar y registrar el reembolso manual.
- [ ] **Reglas de reprogramación:**
  - Anticipación mínima antes de la cita para poder solicitar/realizar la única reprogramación.
  - Si la reprogramación es directa sobre un horario disponible del mismo profesional o requiere aprobación explícita del profesional.
- [ ] **Casos de borde:**
  - Qué ocurre si el profesional no tiene nuevos horarios disponibles para reprogramar.
  - Qué ocurre con el adelanto y el estado de la cita si el paciente **no asiste** (*no-show*).
- [ ] **Saldo restante:**
  - Cómo se gestiona o registra el saldo restante de la consulta (si se acuerda monto total vs. monto de adelanto o porcentaje fijo).
- [ ] **Intervención del administrador ante incidencias:**
  - Qué nivel de acceso y acciones tendrá el administrador (solo lectura/auditoría de comprobantes en disputas o capacidad de resolver un reembolso/incidencia).
- [ ] **Límites anti-abuso propuestos:**
  - Confirmar si se aplican los límites propuestos de **3 solicitudes diarias** y **2 solicitudes pendientes simultáneas** por paciente.

---

## 4. Separación de estados: Cita, Pago y Reembolso

Para no romper las restricciones, triggers ni consultas existentes de `public."Citas"`, se recomienda distinguir explícitamente tres máquinas de estado independientes:

1. **Estado de la cita (`public."Citas".estado` + bandera de flujo):**
   - Estados vigentes conservados: `'pendiente'`, `'confirmada'`, `'rechazada'`, `'cancelada'`, `'finalizada'`.
   - Para soportar el paso intermedio *aceptada esperando pago* sin invalidar citas previas, se evaluará en la etapa de SQL entre:
     - Agregar el estado `'aceptada_pendiente_pago'` (o `'pendiente_pago'`) en `Citas` actualizando triggers y resúmenes, **o** mantener `'pendiente'` con columna aditiva `requiere_adelanto BOOLEAN NOT NULL DEFAULT FALSE` y `aceptada_para_pago_en TIMESTAMPTZ NULL`. La segunda opción minimiza cambios en vistas existentes y garantiza compatibilidad inmediata con citas anteriores (`requiere_adelanto = FALSE`).
2. **Estado del pago/adelanto (`psicobloom_interno.adelantos_citas` o tabla dedicada):**
   - `'no_requerido'` (citas existentes previas a la migración).
   - `'pendiente_pago'` (profesional aceptó; falta comprobante del paciente).
   - `'comprobante_enviado'` (paciente subió comprobante privado; falta verificación del profesional).
   - `'verificado'` (profesional confirmó ingreso real → cita pasa a `'confirmada'`).
   - `'rechazado'` (comprobante inválido/no recibido; permite reintento dentro del plazo o cancelación).
3. **Estado del reembolso (`psicobloom_interno.reembolsos_citas`):**
   - `'no_aplica'` (sin adelanto verificado, o cancelación sin derecho a devolución).
   - `'pendiente_devolucion'` (cancelación elegible: paciente ≥ 24 h sin reprogramar, o cancelación del profesional).
   - `'comprobante_enviado'` / `'completado'` (profesional o responsable registra el reembolso manual con comprobante privado).

---

## 5. Componentes reutilizables y cambios mínimos previstos

### Reutilización existente
- **Autenticación y roles:** `public._rol_activo()`, `public._es_profesional_propio`, `public._es_paciente_propio`, `public._profesional_es_publicable`.
- **Bloqueos e integridad de citas:** Orden canónico `Profesionales -> Disponibilidad -> Citas`, triggers de no-eliminación y zona horaria `America/Guayaquil` (`10_respuesta_citas_profesional.sql`).
- **Carga segura por Edge Function:** Patrón de `subir-foto-profesional` (sesión real + validación de tamaño/magic bytes + timeouts).
- **Auditoría y panel Admin:** `psicobloom_interno.auditoria_administracion` (`20_modulo_administrador.sql`) y `ServicioCitasPaciente` / `ServicioCitasProfesional`.

### Cambios mínimos requeridos (etapas posteriores)
1. **Base de datos (SQL aditivo):**
   - Configuración de precio/adelanto por servicio o profesional (`monto_consulta`, `monto_adelanto`) y tabla de QR bancario del profesional (`qr_transferencia_profesional` con RLS de lectura limitada al profesional titular y al paciente con cita aceptada para pago).
   - Columnas aditivas en `public."Citas"` (`requiere_adelanto`, `reprogramada`, `id_cita_origen` o `veces_reprogramada CHECK (veces_reprogramada IN (0, 1))`) y tabla interna para pagos/adelantos y reembolsos con montos congelados al momento de la solicitud.
   - Nuevas RPC `SECURITY DEFINER`: configurar QR/precio, aceptar para pago, registrar comprobante, verificar pago, cancelar cita (calculando regla de 24 h en `America/Guayaquil`), reprogramar una sola vez y registrar reembolso.
2. **Almacenamiento privado y Edge Functions:**
   - **Bucket privado en Supabase Storage** (ej. `comprobantes-adelantos`, sin acceso público directo) + Edge Function autenticada para subir comprobantes (JPG/PNG/PDF según se defina) y emitir URLs firmadas de corta duración solo al paciente dueño, al profesional titular de la cita y (si se aprueba) al administrador.
   - El QR bancario del profesional puede subirse mediante Edge Function dedicada (`subir-qr-profesional`) validando rol profesional activo.
3. **Flutter (MVC):**
   - **Profesional:** Cargar QR bancario y tarifa en Perfil; aceptar solicitud (habilitando pago), revisar comprobante privado y confirmar ingreso en Citas; cancelar con devolución y adjuntar comprobante de reembolso.
   - **Paciente:** Visualizar monto real de adelanto antes de solicitar/cancelar/reprogramar; ver QR del profesional y subir comprobante privado; cancelar (mostrando si aplica devolución completa o sin devolución) y reprogramar una vez con el mismo profesional.
   - **Administrador:** Consulta de citas/adelantos/reembolsos según el alcance que se defina en los puntos pendientes.

---

## 6. Posibles incompatibilidades detectadas
1. **Trigger `validar_disponibilidad` (`10_respuesta_citas_profesional.sql`):** Actualmente solo permite liberar un horario `'reservada'` → `'disponible'` cuando `psicobloom.contexto_respuesta = 'rechazo_profesional'`. Para soportar **cancelación** y **reprogramación** (liberar el horario anterior y reservar el nuevo), habrá que ampliar la variable de contexto autorizado (ej. `'cancelacion_cita'`, `'reprogramacion_cita'`) sin debilitar el bloqueo contra liberación manual directa.
2. **Restricción única parcial en `public."Citas"(id_disponibilidad)` (`08_solicitud_citas_paciente.sql`):** Permite una sola cita en estado `('pendiente', 'confirmada')` por horario. Al reprogramar, la cita conservará el historial del horario anterior o actualizará `id_disponibilidad` dentro de la misma transacción bloqueando primero ambos horarios en orden determinístico para evitar *deadlocks* y colisiones.
3. **Cola de avisos Telegram (`16_avisos_telegram_profesional.sql`):** Solo encola en `AFTER INSERT` cuando `estado = 'pendiente'`. Si se requieren avisos al subir comprobante o cancelar, se deberán agregar disparadores controlados sin acoplar HTTP a SQL.

---

## 7. Segunda Etapa — Configuración de cobro del profesional (preparada en `feature/adelantos-qr`)

### Fuentes de información y relación con el esquema remoto existente
En la inspección remota previa de Supabase se identificaron dos estructuras preexistentes que **no se modifican ni eliminan** sin auditar antes todas sus dependencias:
1. **`public."Servicios".precio_referencial`:** Campo referencial del catálogo actual de servicios. Se mantiene intacto por compatibilidad, pero **no** se utiliza como fuente para cobrar ni calcular adelantos.
2. **`public."QRTransferencia"`** (`id_qr`, `id_profesional`, `banco`, `titular`, `url_imagen`, `activo`): Tabla vacía de carácter informativo/legado. No almacena tarifa/adelanto ni cuenta con políticas de rutas privadas por carpeta ni inmutabilidad de archivo; permanece intacta sin lecturas ni escrituras desde el flujo de adelantos.
3. **Fuente única de verdad del flujo de adelantos (`psicobloom_interno.configuracion_cobro_profesional`):**
   - Es la **única fuente autoritativa** para `requiere_adelanto`, `moneda ('USD')`, `precio_consulta`, `monto_adelanto`, `ruta_qr_storage` (ruta privada, nunca URL firmada) y datos mínimos del beneficiario (`banco_beneficiario`, `titular_beneficiario`, `tipo_cuenta_beneficiario`, `numero_cuenta_referencia`).
   - De este modo se evitan fuentes contradictorias entre `Servicios.precio_referencial`, `QRTransferencia` y la configuración de adelantos.
   - En etapas posteriores (solicitud/aceptación de citas), los montos vigentes se copiarán (instantánea) en el registro de adelanto de cada cita para que cambios futuros del profesional no alteren citas ya pactadas.

### Artefactos preparados y endurecidos en esta etapa
1. **SQL de inspección, migración aditiva y verificación (pendientes de aplicar en remoto):**
   - `supabase/sql/22a_inspeccion_cobro_qr.sql`: consultas de solo lectura sobre `QRTransferencia`, `Servicios`, `Profesionales`, `storage.buckets` y `storage.objects`.
   - `supabase/sql/22_configuracion_cobro_profesional.sql`:
     - Crea `psicobloom_interno.configuracion_cobro_profesional` con RLS y `REVOKE ALL` para `PUBLIC`, `anon` y `authenticated`.
     - Crea el bucket **privado** `qr-cobro-profesionales` (`public = false`, 5 MB, `image/png` y `image/jpeg`) **únicamente con políticas `SELECT` e `INSERT`** limitadas a `<auth.uid()>/...` para profesionales activos. **No existen políticas `UPDATE` ni `DELETE`** desde el cliente, impidiendo sobrescribir o borrar un QR cargado/referenciado. Para cambiar de QR se sube un archivo nuevo con nombre único y se actualiza la referencia mediante la RPC.
     - `guardar_configuracion_cobro_propia(...)` recibe `NUMERIC` sin asumir validación automática de `NUMERIC(10,2)`: rechaza explícitamente `NaN`, `Infinity`, `-Infinity`, valores fuera de `0.01..99999999.99`, fracciones menores a un centavo (`<> trunc(val, 2)`, sin redondeo silencioso), rutas vacías, URLs firmadas, rutas ajenas y **objetos inexistentes en `storage.objects`**; finalmente devuelve mediante `RETURNING` la fila exactamente persistida.
   - `supabase/sql/23_verificacion_cobro_profesional.sql`:
     - Evalúa ambas RPC (`obtener` y `guardar`) y políticas bajo `SET LOCAL ROLE anon` / `SET LOCAL ROLE authenticated` (sin depender de `BYPASSRLS` de `postgres`), probando sin sesión, paciente activo, cuenta inactiva, profesional propietario y otro profesional.
     - No inserta ni borra registros directamente en `storage.objects`.
     - Si falta algún usuario requerido en la base de datos, **no informa éxito completo**: reporta explícitamente `VERIFICACION SQL PARCIAL — REQUISITOS PENDIENTES`.
     - Revierte todo con `ROLLBACK` y deja explícitamente separadas las pruebas SQL de políticas respecto a las pruebas reales mediante la API de Supabase Storage.
2. **Flutter (MVC reutilizando Perfil profesional):**
   - `lib/modulos/profesional/modelos/configuracion_cobro_profesional.dart`: modelo `ConfiguracionCobroProfesional`, `validarMontoUsd` (rechaza `NaN`, infinitos, fuera de rango y fracciones < 1 centavo sin redondeo silencioso) y `parsearMontoUsd`.
   - `lib/modulos/profesional/servicios/servicio_cobro_profesional.dart`: selección sin recorte/compresión, subida con nombre único aleatorio y `upsert: false`, sin borrado automático ante fallos o respuestas de red ambiguas, y verificación de coincidencia entre los valores enviados y los efectivamente persistidos por el servidor.
   - `lib/modulos/profesional/controladores/controlador_perfil_profesional.dart` y `lib/modulos/profesional/vistas/pantalla_perfil_profesional.dart`: sección **Cobro y adelanto (USD)** no bloqueante que conserva la configuración previa ante fallos.
   - `test/servicios/servicio_cobro_profesional_test.dart`: pruebas unitarias, de controlador y de widget (simuladas).

### Pendiente para activar y verificar en entorno real (tras revisión)
- [ ] Ejecutar `supabase/sql/22a_inspeccion_cobro_qr.sql` en Supabase (solo lectura) para confirmar dependencias de `Servicios.precio_referencial` y `QRTransferencia`.
- [ ] Aplicar `supabase/sql/22_configuracion_cobro_profesional.sql` en Supabase.
- [ ] Ejecutar `supabase/sql/23_verificacion_cobro_profesional.sql` en Supabase (con `ROLLBACK`) verificando que existan los 4 perfiles de prueba (2 profesionales activos, 1 paciente activo, 1 cuenta inactiva).
- [ ] Ejecutar pruebas **reales de Storage API** (fuera de SQL): subida real de QR PNG/JPG con `upsert: false`, comprobación de bloqueo ante intento de sobrescritura/borrado, guardado con `requiere_adelanto = TRUE` sobre el objeto real, previsualización con URL firmada temporal por el propietario y rechazo de acceso a otro usuario/anónimo.
- [ ] Etapas siguientes: flujo de pago de adelanto por paciente, verificación del profesional, cancelación (regla de 24 h), reprogramación única y reembolsos manuales.

---

## 8. Tercera Etapa — Información económica visible para el paciente (preparada en `feature/adelantos-qr`)

### Estado previo confirmado
- Los scripts SQL `22_configuracion_cobro_profesional.sql` y `23_verificacion_cobro_profesional.sql` ya fueron aplicados y probados en Supabase (subida del QR privado, guardado y recuperación desde el perfil profesional).
- `psicobloom_interno.configuracion_cobro_profesional` se mantiene como única fuente de verdad para la información económica.

### Artefactos preparados en la Tercera Etapa
1. **Backend SQL aditivo (sin modificar los SQL 22 ni 23 ya aplicados):**
   - `supabase/sql/24_info_economica_profesional_paciente.sql`:
     - Crea la RPC `SECURITY DEFINER` `public.obtener_info_economica_profesional(p_id_profesional UUID)` con `SET search_path = pg_catalog, pg_temp`.
     - Valida sesión/rol activo mediante `public._rol_activo()` y reutiliza la regla de visibilidad del directorio `public._profesional_es_publicable(UUID)` (solo profesionales visibles, activos y aprobados).
     - Devuelve **únicamente**: `tiene_configuracion`, `moneda`, `precio_consulta`, `requiere_adelanto`, `monto_adelanto_exigible` y `saldo_despues_adelanto` (calculado en `NUMERIC(10,2)`).
     - **No expone** QR, `ruta_qr_storage`, banco, titular, número de cuenta ni URLs firmadas, ni otorga `SELECT` directo sobre `psicobloom_interno.configuracion_cobro_profesional`.
     - Si el profesional no tiene configuración o precio cargado, devuelve `tiene_configuracion = FALSE` con montos `NULL` (sin inventar valores ni asumir gratuidad).
     - Si `requiere_adelanto = FALSE`, devuelve `monto_adelanto_exigible = 0.00` y `saldo_despues_adelanto = precio_consulta` aunque exista un monto anterior conservado en la tabla.
   - `supabase/sql/25_verificacion_info_economica_paciente.sql`:
     - Verifica ausencia de columnas sensibles, privilegios mínimos, rechazo a `anon` y cuentas inactivas con `SET LOCAL ROLE`, ocultamiento de profesionales no publicables, escenario sin configuración, escenario con adelanto desactivado y cálculo exacto con adelanto activo; revierte sus cambios temporales con `ROLLBACK`.
2. **Flutter (MVC reutilizando pantallas del paciente):**
   - `lib/modulos/paciente/modelos/info_economica_profesional.dart`: representa los importes en **centavos enteros exactos (`int`)** para evitar errores de punto flotante (`double`), valida moneda `USD`, rango admitido (`0.01..99999999.99`), adelanto válido cuando `requiere_adelanto = TRUE` (sin degradarlo silenciosamente a "no requiere adelanto") y coincidencia exacta de `saldo_despues_adelanto` (sin sustituirlo silenciosamente).
   - `lib/modulos/paciente/servicios/servicio_info_economica_profesional.dart`: consume `obtener_info_economica_profesional`, interpreta lista vacía como profesional no disponible y trata cualquier estructura malformada o inconsistente como error recuperable.
   - `lib/modulos/paciente/controladores/controlador_info_economica_profesional.dart`: gestiona carga, error, reintento y control de secuencia para evitar mezclar importes antiguos al cambiar de profesional.
   - `lib/modulos/paciente/componentes/tarjeta_info_economica_profesional.dart`: tarjeta compacta reutilizable que muestra:
     - Con adelanto activo: `Valor de consulta: $XX.XX`, `Adelanto: $XX.XX` y `Saldo después del adelanto: $XX.XX`.
     - Sin adelanto: `Valor de consulta: $XX.XX` y `Este profesional no requiere adelanto`.
     - Sin precio configurado: `Precio por confirmar con el profesional`.
     - En el resumen previo de solicitud de cita incluye el aviso: «Puedes enviar tu solicitud sin realizar una transferencia. El pago desde esta pantalla aún no está disponible.» (sin botones de pago, comprobantes, QR ni datos bancarios).
   - Integrada en `PantallaPerfilPublicoProfesional` y en el resumen previo de `PantallaHorariosProfesionalPaciente`, conservando intacto el flujo actual de solicitud, aceptación y confirmación de citas.
   - `test/servicios/servicio_info_economica_profesional_test.dart`: pruebas unitarias, de controlador y de widget (simuladas).

### Pendiente para activar y continuar en etapas siguientes
- [x] Aplicar `supabase/sql/24_info_economica_profesional_paciente.sql` y `25_verificacion_info_economica_paciente.sql` en Supabase (aplicados antes de la Cuarta Etapa).

---

## 9. Cuarta Etapa — Solicitud con adelanto, acceso privado al QR, comprobante y verificación (preparada en `feature/adelantos-qr`)

### Reglas aplicadas (solo nuevas solicitudes con adelanto)
- **Compatibilidad:** Las citas anteriores y las nuevas citas de profesionales **sin adelanto** conservan exactamente su flujo actual.
- **Flujo con adelanto:** `solicitar (> 24 h)` → `profesional acepta (> 24 h; NO confirma cita, mantiene horario reservado)` → `pendiente_adelanto (límite exacto = inicio - 24 h)` → `comprobante_en_revision (12 h para revisar; > 12 h muestra «Revisión demorada» sin confirmar ni cancelar automáticamente)` → `profesional verifica ingreso` → `cita confirmada`.
- **Instantánea inmutable:** Al crear la solicitud se copian precio, adelanto, saldo, condiciones aceptadas, ruta privada del QR y datos bancarios del beneficiario; cambios posteriores del profesional no alteran solicitudes ya creadas.
- **Privacidad y evidencia inmutable:**
  - El QR del profesional (`qr-cobro-profesionales`) solo es legible por el paciente titular de una cita aceptada (`_paciente_puede_ver_qr_cobro`), sin lectura general del bucket.
  - Los comprobantes (PNG/JPG <= 5 MB) se almacenan en el bucket privado separado `comprobantes-adelantos` con rutas únicas (`<id_cita>/<uid>/comp_...`), `upsert: false` y sin políticas `UPDATE` ni `DELETE`.
  - Se conserva el historial completo de comprobantes, observaciones del profesional (motivo obligatorio >= 5 caracteres, permite aclaración sin exigir nueva transferencia automáticamente) e incidencias («Ya transferí y tuve un problema al adjuntar»).
- **Vencimiento seguro e incidencias:**
  - `vencer_adelantos_expirados()` vence y libera únicamente solicitudes en `pendiente_adelanto` con `now() > limite_pago_en` y sin comprobantes ni incidencias, serializando carreras bajo bloqueo.
  - Reportar incidencia tras vencimiento no promete recuperar automáticamente un horario ya asignado a otra persona.
- **Protección de cancelación y Telegram:**
  - El trigger de `public."Citas"` bloquea cancelar directamente una cita con adelanto reportado o verificado mientras no se implemente el tratamiento de reembolsos.
  - Los eventos de aviso (`comprobante_enviado`, `revision_demorada`, `incidencia_pago`) se encolan en `psicobloom_interno.eventos_avisos_adelanto` sin HTTP en SQL y sin datos bancarios ni comprobantes.

### Artefactos preparados y endurecidos
- **SQL (sin modificar 22 a 25):**
  - `supabase/sql/26_flujo_adelantos_comprobantes_verificacion.sql`:
    - Rechazo explícito de `v_rol IS NULL` y cuentas desactivadas (incluyendo profesional titular desactivado) en `obtener_detalle_adelanto_cita` y `_usuario_puede_ver_comprobante`.
    - Funciones de mantenimiento y despacho (`vencer_adelantos_expirados`, `encolar_avisos_revision_demorada`, `reclamar_eventos_avisos_adelanto`, `finalizar_evento_aviso_adelanto`) sin depender de `current_user`, revocadas a `PUBLIC`, `anon` y `authenticated` y otorgadas exclusivamente a `service_role`.
    - `vencer_adelantos_expirados` aísla errores por fila para que una cuenta profesional desactivada no revierta el lote completo.
    - Compatibilidad completa con días no laborables (`14_agenda_semanal_profesional.sql`): tras rechazo o vencimiento en día no laborable, el horario pasa a `'bloqueada'` (nunca `'disponible'`).
    - Oferta versionada (`obtener_oferta_adelanto_profesional`) y exigencia en servidor de aceptación expresa de condiciones y coincidencia de `version_oferta` (`40001` si cambió la configuración), además de verificación estricta de idempotencia por paciente, profesional y horario.
  - `supabase/sql/27_verificacion_flujo_adelantos.sql`: aserciones reales con `ROLLBACK` sobre rol `NULL`, profesional titular inactivo, permisos de mantenimiento, precio congelado antes/después, incidencias e idempotencia, protección de cancelación con dinero reportado, días no laborables y vencimiento sin pago vs. conservación con pago reportado.
  - `supabase/sql/28_programacion_vencimiento_y_avisos_adelantos.sql`: programación `pg_cron` (sin secretos en el script, usando Vault) para ejecutar cada 5 minutos `vencer_adelantos_expirados()` y `encolar_avisos_revision_demorada()` y activar el despachador Telegram ante eventos pendientes de adelantos.
- **Edge Function (preparada, pendiente de redespliegue):**
  - `supabase/functions/despachar-avisos-telegram/index.ts`: integra la cola `eventos_avisos_adelanto` conservando `verify_jwt`, `X-Telegram-Dispatch-Secret`, timeouts y reintentos con backoff, enviando únicamente avisos neutros (sin comprobantes ni datos bancarios). **Los avisos de adelanto NO están operativos hasta aplicar `26`, `28` y redesplegar la función.**
- **Flutter:**
  - `lib/modelos/adelanto_cita.dart`: validación estricta de `id_cita`, estados conocidos, moneda `USD`, montos positivos, `adelanto <= precio` y saldo exacto (sin convertir inválidos en 0 ni reconstruir saldos faltantes).
  - `lib/nucleo/servicios/servicio_adelantos_citas.dart`: `listarResumenAdelantosVisibles` lanza errores recuperables ante fallos de permisos, red o formato (nunca los disfraza como «sin adelanto»).
  - `lib/modulos/paciente/controladores/controlador_citas_paciente.dart` y `lib/modulos/paciente/vistas/pantalla_horarios_profesional_paciente.dart`: clave de idempotencia persistida en reintentos, aceptación expresa obligatoria de condiciones y recarga automática si la oferta cambia (`40001`).
  - `lib/nucleo/componentes/hoja_detalle_adelanto_cita.dart`: conserva ruta ya subida y clave de idempotencia en memoria por cita (incluso al cerrar y reabrir la pantalla), recupera estado del servidor antes de reintentar el registro sin volver a subir el archivo y diferencia reintentar de enviar una corrección nueva.
  - `PantallaMisCitasPaciente`, `PantallaCitasProfesional` y `PantallaInicioAdministrador`: distinguen carga, vacío y error de adelantos y recargan citas + adelantos juntos desde todos los botones de actualización.
  - `test/servicios/servicio_adelantos_citas_test.dart`: pruebas unitarias, de servicio/modelo con respuestas malformadas y de interfaz con respuestas perdidas/reintentos.

### Pendiente para activar y comprobar en entorno real (detenido antes de SQL remoto/despliegue)
- [ ] Aplicar `supabase/sql/26_flujo_adelantos_comprobantes_verificacion.sql` en Supabase.
- [ ] Ejecutar `supabase/sql/27_verificacion_flujo_adelantos.sql` en Supabase (con `ROLLBACK`).
- [ ] Redesplegar `supabase/functions/despachar-avisos-telegram` con `--no-verify-jwt=false` (mantener `verify_jwt = true`) y aplicar `supabase/sql/28_programacion_vencimiento_y_avisos_adelantos.sql`.
- [ ] Ejecutar pruebas **reales contra Supabase Storage API** (fuera de SQL): subida real PNG/JPG a `comprobantes-adelantos` con `upsert: false`, lectura autorizada por paciente y profesional titular, rechazo a otro usuario / administrador / profesional titular inactivo, y bloqueo de sobrescritura y borrado.
- [x] Cierre manual e idempotente de incidencias de carga de comprobantes (`29_cierre_incidencias_adelanto.sql` y `30_verificacion_cierre_incidencias_adelanto.sql`):
  - Nueva RPC `public.resolver_incidencia_adelanto(p_id_cita, p_id_incidencia, p_motivo_resolucion)` reservada exclusivamente al profesional titular activo y aprobado (rechaza sesión ausente, rol `NULL`, pacientes, otros profesionales, administradores y cuentas inactivas).
  - Exige motivo de resolución de 5 a 500 caracteres, registra `motivo_resolucion`, `resuelto_por` y `resuelto_en` con hora del servidor, conserva el detalle original y todo el historial, y es estrictamente idempotente (repetir la llamada no duplica ni sobrescribe una resolución previa).
  - Exige comprobante registrado y estado `comprobante_en_revision`, `observado` o `verificado`; rechaza incidencias con `horario_ya_liberado = TRUE` (requieren tratamiento posterior).
  - Resolver una incidencia de carga **no** verifica el ingreso, **no** confirma ni cancela la cita, **no** modifica disponibilidad ni importes y **no** registra reembolsos.
  - En la interfaz (`HojaDetalleAdelantoCita`), el profesional ve **Resolver incidencia** con confirmación explícita («Resolver esta incidencia no verifica el pago ni confirma la cita»); tanto paciente como profesional ven estados legibles (`Pendiente de revisión`, `En revisión`, `Resuelta`), motivo y fecha de resolución, sin exponer códigos internos.
- [ ] Verificación HTTP real de Storage API con cuentas de prueba autenticadas mediante `herramientas/verificar_storage_api_adelantos.ps1` (sin `service_role`, sin exponer tokens ni borrar comprobantes existentes).
- [ ] Etapas posteriores: cancelaciones con tratamiento de adelanto (24 h), reprogramación única, reembolsos manuales, inasistencia y límites diarios.


## 12. Cancelaciones y devolución manual — implementación preparada (31/32)

**Estado:** archivos preparados para revisión. SQL validado en PostgreSQL dentro de
una transacción deshecha al terminar; NO aplicado permanentemente. Flutter y
prueba HTTP del nuevo bucket pendientes. Telegram no se modifica.

### Reglas confirmadas
- Paciente sin reprogramación: devolución completa del adelanto recibido si cancela
  con al menos 24 horas; con menos de 24 horas no corresponde devolución.
- Paciente que ya reprogramó: no corresponde devolución al cancelar.
- Profesional que cancela: corresponde devolver el adelanto recibido.
- La hora de cancelación y su consecuencia se congelan en servidor. Verificar el
  ingreso posteriormente no vuelve a calcular la regla con una fecha diferente.
- Cancelar con comprobante/incidencia pendiente libera el horario y conserva el
  ingreso pendiente de verificación. Verificar ese ingreso NUNCA reconfirma la cita.
- Si hubo transferencia sin comprobante/incidencia, se debe marcar ese hecho antes
  de confirmar la cancelación; queda pendiente de revisión profesional.
- El profesional hace la transferencia fuera de la app y registra referencia y
  comprobante privado. «Devolución registrada por el profesional» no equivale a una
  verificación automática del banco ni a una confirmación de recepción del paciente.
- La reprogramación será única, con el mismo profesional y anticipación mínima
  de 24 horas (aprobado en conversación). Su operación todavía NO está implementada;
  la columna `veces_reprogramada` queda protegida contra modificación directa.

### Archivos y cambios
- `31_cancelacion_y_devoluciones.sql`: tabla interna con RLS y sin acceso directo,
  RPCs de consulta, cancelación, verificación posterior del ingreso y registro de
  devolución; bucket privado `comprobantes-devoluciones` (PNG/JPG, 5 MB).
- No se conceden políticas UPDATE/DELETE para los comprobantes de devolución.
  Rutas `<id_cita>/<uid_profesional>/<nombre_unico>`, lectura solo por titulares
  activos, carga solo por profesional autorizado y con devolución pendiente.
- Se conserva `Citas.estado=cancelada`; el adelanto pasa a `cancelado`. El estado
  del ingreso y la devolución se conservan por separado en `cancelaciones_citas`.
- Se mantienen precios/adelantos/saldos y registros históricos. Los días no laborables
  continúan bloqueados; solo se libera un horario sin otra cita activa.
- La vista del profesional incorpora Canceladas. Paciente y profesional pueden
  abrir «Cancelación y devolución» desde la tarjeta de cita y el detalle del adelanto.
- `32_verificacion_cancelacion_y_devoluciones.sql`: pruebas bajo roles reales,
  fixtures por el flujo existente y ROLLBACK, sin insertar objetos ficticios Storage.
- `servicio_cancelaciones_citas_test.dart`: pruebas de modelo, servicio e interfaz
  para ejecutar con el SDK Flutter del proyecto; no ejecutadas en el entorno de entrega.

### Límites de esta etapa
No hay devolución bancaria automática. No se define un plazo máximo de reembolso,
penalización por inasistencia, cambios en Telegram ni límites diarios de solicitudes.
Una discrepancia posterior con una verificación bancaria ya cerrada requiere una
etapa de gestión de disputas; no se ofrece una edición destructiva del resultado.

### Pruebas manuales después de validar/aplicar
1. Cancelar una solicitud aceptada sin pago: queda cancelada y horario disponible.
2. Cancelar con comprobante/incidencia: horario liberado; ingreso pendiente.
3. Profesional verifica ingreso en la cita cancelada: sigue cancelada y se conserva
   el criterio económico calculado al cancelar.
4. Registrar devolución con comprobante real solo sobre una cita de prueba elegible;
   paciente y profesional pueden verlo; una cuenta ajena/anónima no puede leerlo.
5. Comprobar rechazo de reemplazo/borrado solo sobre objetos desechables propios.
   Las pruebas HTTP previas del bucket de adelantos NO prueban este nuevo bucket.
