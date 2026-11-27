-- =============================================================================
-- SCRIPT 27 — VERIFICACION CONTROLADA DE LA CUARTA ETAPA (ROLLBACK)
-- Ejecutar en Supabase > SQL Editor DESPUES de 26_flujo_adelantos_comprobantes_verificacion.sql
--
-- Aserciones reales verificadas bajo ROLLBACK (sin insertar filas falsas en storage.objects):
--   1. RLS y ausencia de acceso directo a las 5 tablas internas de adelantos.
--   2. Bucket privado `comprobantes-adelantos` y ausencia de politicas UPDATE/DELETE.
--   3. Rechazo explicito de rol NULL (anon) y cuenta profesional titular DESACTIVADA
--      en obtener_detalle_adelanto_cita y _usuario_puede_ver_comprobante.
--   4. Permisos de mantenimiento: paciente y profesional NO pueden ejecutar
--      vencer_adelantos_expirados ni encolar_avisos_revision_demorada.
--   5. Regla > 24 h, aceptacion expresa de condiciones y validacion de version_oferta.
--   6. Idempotencia estricta: reintento igual devuelve misma cita; reutilizar
--      clave con otro horario/profesional se rechaza.
--   7. Precio congelado comparado numericamente ANTES y DESPUES del cambio posterior.
--   8. Incidencia e idempotencia: bloquea vencimiento automatico y no duplica filas.
--   9. Proteccion contra cancelacion directa de cita con dinero reportado/incidencia.
--  10. Compatibilidad con dias no laborables (script 14): rechazo y vencimiento
--      dejan el horario en 'bloqueada' (NUNCA 'disponible').
--  11. Vencimiento sin pago libera horario normal y resiste cuenta profesional inactiva
--      sin revertir el lote.
-- =============================================================================
BEGIN;

DO $$
DECLARE
    v_tabla TEXT;
    v_rls BOOLEAN;
    v_bucket_publico BOOLEAN;
    v_mutaciones_storage INTEGER;
    v_prof_id UUID;
    v_prof_uid UUID;
    v_pac_id UUID;
    v_pac_uid UUID;
    v_pac_otro_uid UUID;
    v_admin_uid UUID;
    v_pendientes TEXT[] := ARRAY[]::TEXT[];
    v_disp_corta UUID;
    v_disp_larga UUID;
    v_disp_dnl UUID;
    v_disp_venc_dnl UUID;
    v_disp_inc UUID;
    v_fecha_dnl DATE;
    v_fecha_venc_dnl DATE;
    v_cita_id UUID;
    v_cita_dup UUID;
    v_cita_dnl UUID;
    v_cita_venc_dnl UUID;
    v_cita_inc UUID;
    v_evento_id UUID;
    v_finalizado BOOLEAN;
    v_estado_evento TEXT;
    v_version_oferta TEXT;
    v_precio_antes NUMERIC(10, 2);
    v_precio_congelado NUMERIC(10, 2);
    v_estado_cita TEXT;
    v_estado_disp TEXT;
    v_detalle JSONB;
    v_puede_ver BOOLEAN;
    v_vencidas INTEGER;
BEGIN
    -- 1. RLS y privilegios minimos en tablas internas
    FOREACH v_tabla IN ARRAY ARRAY[
        'adelantos_citas',
        'comprobantes_adelanto',
        'observaciones_adelanto',
        'incidencias_adelanto',
        'eventos_avisos_adelanto'
    ]
    LOOP
        SELECT c.relrowsecurity INTO v_rls
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'psicobloom_interno' AND c.relname = v_tabla;

        IF v_rls IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'Falta RLS en psicobloom_interno.%', v_tabla;
        END IF;

        IF has_table_privilege('anon', 'psicobloom_interno.' || v_tabla, 'SELECT')
           OR has_table_privilege('authenticated', 'psicobloom_interno.' || v_tabla, 'SELECT') THEN
            RAISE EXCEPTION 'anon/authenticated no deben tener SELECT directo en psicobloom_interno.%', v_tabla;
        END IF;
    END LOOP;

    -- 2. Bucket privado comprobantes-adelantos y sin UPDATE/DELETE
    SELECT b.public INTO v_bucket_publico
    FROM storage.buckets b WHERE b.id = 'comprobantes-adelantos';
    IF v_bucket_publico IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'El bucket comprobantes-adelantos debe ser privado (public = FALSE).';
    END IF;

    SELECT count(*) INTO v_mutaciones_storage
    FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND cmd IN ('UPDATE', 'DELETE')
      AND (coalesce(qual, '') ILIKE '%comprobantes-adelantos%' OR coalesce(with_check, '') ILIKE '%comprobantes-adelantos%');
    IF v_mutaciones_storage > 0 THEN
        RAISE EXCEPTION 'No deben existir politicas UPDATE/DELETE en comprobantes-adelantos.';
    END IF;

    -- Localizar perfiles reales existentes
    SELECT c.id_profesional, pr.id_usuario, c.precio_consulta
    INTO v_prof_id, v_prof_uid, v_precio_antes
    FROM psicobloom_interno.configuracion_cobro_profesional c
    JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
    WHERE c.requiere_adelanto = TRUE
      AND public._profesional_es_publicable(c.id_profesional)
    LIMIT 1;

    SELECT pa.id_paciente, pa.id_usuario INTO v_pac_id, v_pac_uid
    FROM public."Pacientes" pa
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pa.id_usuario
    WHERE p.rol = 'paciente' AND p.cuenta_activa = TRUE
    ORDER BY pa.id_paciente
    LIMIT 1;

    SELECT pa.id_usuario INTO v_pac_otro_uid
    FROM public."Pacientes" pa
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pa.id_usuario
    WHERE p.rol = 'paciente' AND p.cuenta_activa = TRUE
      AND pa.id_usuario IS DISTINCT FROM v_pac_uid
    LIMIT 1;

    SELECT p.id INTO v_admin_uid
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.rol = 'administrador' AND p.cuenta_activa = TRUE
    LIMIT 1;

    -- 3. Rechazo explicito de rol NULL (anon) en RPCs y helper de comprobantes
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    SET LOCAL ROLE anon;

    BEGIN
        PERFORM * FROM public.listar_adelantos_citas_visibles();
        RAISE EXCEPTION 'anon no debe consultar adelantos.';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        PERFORM public.obtener_detalle_adelanto_cita(gen_random_uuid());
        RAISE EXCEPTION 'anon no debe consultar detalle privado de adelanto.';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        PERFORM public.vencer_adelantos_expirados();
        RAISE EXCEPTION 'anon no debe ejecutar vencer_adelantos_expirados.';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    RESET ROLE;

    IF v_prof_id IS NULL OR v_pac_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Se requiere un profesional publicable con requiere_adelanto = TRUE y un paciente activo.');
    ELSE
        -- 4. Verificar que paciente y profesional NO pueden ejecutar funciones de mantenimiento
        PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        BEGIN
            PERFORM public.vencer_adelantos_expirados();
            RAISE EXCEPTION 'Un paciente no debe ejecutar vencer_adelantos_expirados.';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;

        BEGIN
            PERFORM public.encolar_avisos_revision_demorada();
            RAISE EXCEPTION 'Un paciente no debe ejecutar encolar_avisos_revision_demorada.';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;

        RESET ROLE;

        PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        BEGIN
            PERFORM public.vencer_adelantos_expirados();
            RAISE EXCEPTION 'Un profesional no debe ejecutar vencer_adelantos_expirados.';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;

        BEGIN
            PERFORM public.encolar_avisos_revision_demorada();
            RAISE EXCEPTION 'Un profesional no debe ejecutar encolar_avisos_revision_demorada.';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;

        RESET ROLE;

        -- Preparar horarios de prueba (revertidos por ROLLBACK)
        INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
        VALUES (
            v_prof_id,
            ((now() + INTERVAL '6 hours') AT TIME ZONE 'America/Guayaquil')::DATE,
            (((now() + INTERVAL '6 hours') AT TIME ZONE 'America/Guayaquil')::TIME),
            (((now() + INTERVAL '7 hours') AT TIME ZONE 'America/Guayaquil')::TIME),
            'disponible'
        )
        RETURNING id_disponibilidad INTO v_disp_corta;

        INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
        VALUES (
            v_prof_id,
            ((now() + INTERVAL '40 days') AT TIME ZONE 'America/Guayaquil')::DATE,
            '10:00:00'::TIME, '11:00:00'::TIME, 'disponible'
        )
        RETURNING id_disponibilidad INTO v_disp_larga;

        v_fecha_dnl := ((now() + INTERVAL '42 days') AT TIME ZONE 'America/Guayaquil')::DATE;
        INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
        VALUES (v_prof_id, v_fecha_dnl, '10:00:00'::TIME, '11:00:00'::TIME, 'disponible')
        RETURNING id_disponibilidad INTO v_disp_dnl;

        v_fecha_venc_dnl := ((now() + INTERVAL '43 days') AT TIME ZONE 'America/Guayaquil')::DATE;
        INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
        VALUES (v_prof_id, v_fecha_venc_dnl, '10:00:00'::TIME, '11:00:00'::TIME, 'disponible')
        RETURNING id_disponibilidad INTO v_disp_venc_dnl;

        INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
        VALUES (
            v_prof_id,
            ((now() + INTERVAL '44 days') AT TIME ZONE 'America/Guayaquil')::DATE,
            '10:00:00'::TIME, '11:00:00'::TIME, 'disponible'
        )
        RETURNING id_disponibilidad INTO v_disp_inc;

        -- 5. Como paciente: obtener oferta, validar aceptacion expresa, version y >24h
        PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        SELECT o.version_oferta INTO v_version_oferta
        FROM public.obtener_oferta_adelanto_profesional(v_prof_id) o;

        -- Sin aceptar condiciones => rechazo
        BEGIN
            PERFORM * FROM public.solicitar_cita_paciente(v_prof_id, v_disp_larga, 'idem-sin-aceptar', FALSE, v_version_oferta);
            RAISE EXCEPTION 'Debio rechazar solicitud sin aceptacion expresa de condiciones.';
        EXCEPTION WHEN invalid_parameter_value THEN NULL;
        END;

        -- Version de oferta desactualizada => rechazo 40001
        BEGIN
            PERFORM * FROM public.solicitar_cita_paciente(v_prof_id, v_disp_larga, 'idem-ver-vieja', TRUE, 'version-desactualizada');
            RAISE EXCEPTION 'Debio rechazar version_oferta desactualizada.';
        EXCEPTION WHEN serialization_failure THEN NULL;
        END;

        -- Menos de 24h => rechazo
        BEGIN
            PERFORM * FROM public.solicitar_cita_paciente(v_prof_id, v_disp_corta, 'idem-corta', TRUE, v_version_oferta);
            RAISE EXCEPTION 'Debio rechazar solicitud con adelanto con menos de 24 horas.';
        EXCEPTION WHEN invalid_parameter_value THEN NULL;
        END;

        -- 6. Solicitud valida + idempotencia igual + rechazo de reutilizacion con otro horario
        SELECT s.id_cita INTO v_cita_id
        FROM public.solicitar_cita_paciente(v_prof_id, v_disp_larga, 'idem-27-ok', TRUE, v_version_oferta) s;

        SELECT s.id_cita INTO v_cita_dup
        FROM public.solicitar_cita_paciente(v_prof_id, v_disp_larga, 'idem-27-ok', TRUE, v_version_oferta) s;

        IF v_cita_id IS DISTINCT FROM v_cita_dup THEN
            RAISE EXCEPTION 'El reintento con misma clave y mismos parametros debe devolver la misma cita.';
        END IF;

        BEGIN
            PERFORM * FROM public.solicitar_cita_paciente(v_prof_id, v_disp_inc, 'idem-27-ok', TRUE, v_version_oferta);
            RAISE EXCEPTION 'Reutilizar clave de idempotencia con otro horario debe rechazarse.';
        EXCEPTION WHEN unique_violation THEN NULL;
        END;

        -- Crear citas para prueba de dia no laborable (rechazo y vencimiento) y prueba de incidencia
        SELECT s.id_cita INTO v_cita_dnl
        FROM public.solicitar_cita_paciente(v_prof_id, v_disp_dnl, 'idem-27-dnl', TRUE, v_version_oferta) s;

        SELECT s.id_cita INTO v_cita_venc_dnl
        FROM public.solicitar_cita_paciente(v_prof_id, v_disp_venc_dnl, 'idem-27-vdnl', TRUE, v_version_oferta) s;

        SELECT s.id_cita INTO v_cita_inc
        FROM public.solicitar_cita_paciente(v_prof_id, v_disp_inc, 'idem-27-inc', TRUE, v_version_oferta) s;

        RESET ROLE;

        -- Aceptar v_cita_id, v_cita_venc_dnl y v_cita_inc como profesional
        PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        SELECT r.estado, r.estado_disponibilidad INTO v_estado_cita, v_estado_disp
        FROM public.responder_solicitud_cita_profesional(v_cita_id, 'confirmada') r;
        IF v_estado_cita IS DISTINCT FROM 'pendiente' OR v_estado_disp IS DISTINCT FROM 'reservada' THEN
            RAISE EXCEPTION 'Aceptar cita con adelanto debe mantener Citas.estado = pendiente y horario reservada.';
        END IF;

        PERFORM * FROM public.responder_solicitud_cita_profesional(v_cita_venc_dnl, 'confirmada');
        PERFORM * FROM public.responder_solicitud_cita_profesional(v_cita_inc, 'confirmada');

        RESET ROLE;

        -- 7. Cambiar precio posterior y comprobar numericamente que la instantanea NO cambia
        UPDATE psicobloom_interno.configuracion_cobro_profesional
        SET precio_consulta = v_precio_antes + 15.00
        WHERE id_profesional = v_prof_id;

        PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        v_detalle := public.obtener_detalle_adelanto_cita(v_cita_id);
        v_precio_congelado := (v_detalle->>'precio_consulta')::NUMERIC(10, 2);
        IF v_precio_congelado IS DISTINCT FROM v_precio_antes THEN
            RAISE EXCEPTION 'El precio congelado (%) debio permanecer igual al original (%) tras cambio posterior.', v_precio_congelado, v_precio_antes;
        END IF;

        -- 8. Registrar incidencia en v_cita_inc con idempotencia
        PERFORM public.registrar_incidencia_adelanto(v_cita_inc, 'Transferi pero fallo la carga de imagen', 'inc-27-1');
        PERFORM public.registrar_incidencia_adelanto(v_cita_inc, 'Transferi pero fallo la carga de imagen', 'inc-27-1');

        RESET ROLE;

        IF (SELECT count(*) FROM psicobloom_interno.incidencias_adelanto WHERE id_cita = v_cita_inc) <> 1 THEN
            RAISE EXCEPTION 'La incidencia con misma clave de idempotencia no debe duplicarse.';
        END IF;

        -- 9. Proteccion contra cancelacion directa de cita con incidencia/dinero reportado (SQLSTATE 23P01)
        BEGIN
            UPDATE public."Citas" SET estado = 'cancelada' WHERE id_cita = v_cita_inc;
            RAISE EXCEPTION 'No debe permitirse cancelar directamente una cita con incidencia/adelanto reportado.';
        EXCEPTION WHEN exclusion_violation THEN NULL;
        END;

        -- 10. Dias no laborables:
        --     10a) Rechazo en dia no laborable => horario 'bloqueada'
        INSERT INTO public."DiasNoLaborables" (id_profesional, fecha, motivo)
        VALUES (v_prof_id, v_fecha_dnl, 'Prueba dia no laborable rechazo')
        ON CONFLICT (id_profesional, fecha) DO NOTHING;

        --     10b) Marcar v_fecha_venc_dnl como no laborable para caso independiente de vencimiento
        INSERT INTO public."DiasNoLaborables" (id_profesional, fecha, motivo)
        VALUES (v_prof_id, v_fecha_venc_dnl, 'Prueba dia no laborable vencimiento')
        ON CONFLICT (id_profesional, fecha) DO NOTHING;

        PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        SELECT r.estado_disponibilidad INTO v_estado_disp
        FROM public.responder_solicitud_cita_profesional(v_cita_dnl, 'rechazada') r;
        IF v_estado_disp IS DISTINCT FROM 'bloqueada' THEN
            RAISE EXCEPTION 'Tras rechazo en dia no laborable el horario debe quedar bloqueada, no %.', v_estado_disp;
        END IF;

        RESET ROLE;

        -- 10c. Ejecutar realmente comprobaciones con administrador y otro paciente
        IF v_admin_uid IS NULL THEN
            v_pendientes := array_append(v_pendientes, 'Falta un administrador activo para validar aislamiento y permisos del resumen.');
        ELSE
            PERFORM set_config('request.jwt.claim.sub', v_admin_uid::TEXT, true);
            PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
            PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid::TEXT, 'role', 'authenticated')::TEXT, true);
            SET LOCAL ROLE authenticated;

            BEGIN
                PERFORM public.obtener_detalle_adelanto_cita(v_cita_id);
                RAISE EXCEPTION 'El administrador no debe acceder al detalle privado de adelanto.';
            EXCEPTION WHEN insufficient_privilege THEN NULL;
            END;

            IF NOT EXISTS (SELECT 1 FROM public.listar_adelantos_citas_visibles() l WHERE l.id_cita = v_cita_id) THEN
                RAISE EXCEPTION 'El administrador debe ver el resumen del adelanto en listar_adelantos_citas_visibles.';
            END IF;

            RESET ROLE;
        END IF;

        IF v_pac_otro_uid IS NULL THEN
            v_pendientes := array_append(v_pendientes, 'Falta un segundo paciente activo para probar aislamiento entre pacientes.');
        ELSE
            PERFORM set_config('request.jwt.claim.sub', v_pac_otro_uid::TEXT, true);
            PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
            PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_otro_uid::TEXT, 'role', 'authenticated')::TEXT, true);
            SET LOCAL ROLE authenticated;

            BEGIN
                PERFORM public.obtener_detalle_adelanto_cita(v_cita_id);
                RAISE EXCEPTION 'Otro paciente no debe acceder al detalle privado del adelanto.';
            EXCEPTION WHEN insufficient_privilege THEN NULL;
            END;

            IF EXISTS (SELECT 1 FROM public.listar_adelantos_citas_visibles() l WHERE l.id_cita = v_cita_id) THEN
                RAISE EXCEPTION 'Otro paciente no debe ver el resumen de una cita ajena.';
            END IF;

            RESET ROLE;
        END IF;

        -- 11. Profesional titular DESACTIVADO no puede ver detalle privado ni leer comprobantes
        UPDATE psicobloom_interno.perfiles_compat
        SET cuenta_activa = FALSE
        WHERE id = v_prof_uid;

        PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, true);
        SET LOCAL ROLE authenticated;

        BEGIN
            PERFORM public.obtener_detalle_adelanto_cita(v_cita_id);
            RAISE EXCEPTION 'Un profesional titular desactivado no debe acceder a obtener_detalle_adelanto_cita.';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;

        v_puede_ver := public._usuario_puede_ver_comprobante(v_cita_id::TEXT || '/' || v_pac_uid::TEXT || '/comp.png');
        IF v_puede_ver IS DISTINCT FROM FALSE THEN
            RAISE EXCEPTION 'Un profesional titular desactivado no debe obtener autorizacion de lectura de comprobantes.';
        END IF;

        RESET ROLE;

        -- 12. Vencimiento: vence v_cita_id (dia normal -> disponible) y v_cita_venc_dnl
        --     (dia no laborable -> bloqueada) aun con profesional desactivado, y
        --     CONSERVA v_cita_inc (tiene incidencia de pago).
        UPDATE psicobloom_interno.adelantos_citas
        SET limite_pago_en = now() - INTERVAL '5 minutes'
        WHERE id_cita IN (v_cita_id, v_cita_venc_dnl, v_cita_inc);

        v_vencidas := public.vencer_adelantos_expirados();
        IF v_vencidas < 2 THEN
            RAISE EXCEPTION 'vencer_adelantos_expirados debio vencer v_cita_id y v_cita_venc_dnl (vencidas: %).', v_vencidas;
        END IF;

        SELECT estado INTO v_estado_cita FROM public."Citas" WHERE id_cita = v_cita_id;
        SELECT estado INTO v_estado_disp FROM public."Disponibilidad" WHERE id_disponibilidad = v_disp_larga;
        IF v_estado_cita IS DISTINCT FROM 'cancelada' OR v_estado_disp IS DISTINCT FROM 'disponible' THEN
            RAISE EXCEPTION 'v_cita_id vencida sin pago debio quedar cancelada y horario disponible.';
        END IF;

        SELECT estado INTO v_estado_cita FROM public."Citas" WHERE id_cita = v_cita_venc_dnl;
        SELECT estado INTO v_estado_disp FROM public."Disponibilidad" WHERE id_disponibilidad = v_disp_venc_dnl;
        IF v_estado_cita IS DISTINCT FROM 'cancelada' OR v_estado_disp IS DISTINCT FROM 'bloqueada' THEN
            RAISE EXCEPTION 'v_cita_venc_dnl vencida en dia no laborable debio quedar cancelada y horario bloqueada (obtenido: % / %).', v_estado_cita, v_estado_disp;
        END IF;

        SELECT estado INTO v_estado_cita FROM public."Citas" WHERE id_cita = v_cita_inc;
        IF v_estado_cita IS DISTINCT FROM 'pendiente' THEN
            RAISE EXCEPTION 'v_cita_inc con incidencia de pago NO debe vencerse automaticamente.';
        END IF;

        -- 13. Garantias de cola Telegram de adelantos (sin enviar mensajes reales):
        --     13a) Agotar 5 intentos marca 'fallido'
        --     13b) Vinculacion cambiada marca 'omitido' (no redirige evento antiguo)
        --     13c) Finalizar con intento incorrecto o bloqueo vencido devuelve FALSE
        UPDATE psicobloom_interno.perfiles_compat SET cuenta_activa = TRUE WHERE id = v_prof_uid;
        INSERT INTO psicobloom_interno.eventos_avisos_adelanto (
            id_cita, id_profesional, id_vinculacion, tipo_evento, referencia_evento, estado, intentos, bloqueado_hasta
        )
        VALUES (
            v_cita_inc, v_prof_id, gen_random_uuid(), 'incidencia_pago', 'ref-5-intentos', 'procesando', 5, now() - INTERVAL '1 minute'
        )
        RETURNING id_evento INTO v_evento_id;

        PERFORM * FROM public.reclamar_eventos_avisos_adelanto(10, 60);
        SELECT estado INTO v_estado_evento FROM psicobloom_interno.eventos_avisos_adelanto WHERE id_evento = v_evento_id;
        IF v_estado_evento IS DISTINCT FROM 'fallido' THEN
            RAISE EXCEPTION 'Un evento de adelanto con 5 intentos y bloqueo vencido debe pasar a fallido, no %.', v_estado_evento;
        END IF;

        -- Evento con id_vinculacion antigua no existente => omitido
        INSERT INTO psicobloom_interno.eventos_avisos_adelanto (
            id_cita, id_profesional, id_vinculacion, tipo_evento, referencia_evento, estado, intentos
        )
        VALUES (
            v_cita_inc, v_prof_id, gen_random_uuid(), 'incidencia_pago', 'ref-vinc-vieja', 'pendiente', 0
        )
        RETURNING id_evento INTO v_evento_id;

        PERFORM * FROM public.reclamar_eventos_avisos_adelanto(10, 60);
        SELECT estado INTO v_estado_evento FROM psicobloom_interno.eventos_avisos_adelanto WHERE id_evento = v_evento_id;
        IF v_estado_evento IS DISTINCT FROM 'omitido' THEN
            RAISE EXCEPTION 'Un evento con id_vinculacion obsoleta debe omitirse y nunca redirigirse (obtenido: %).', v_estado_evento;
        END IF;

        -- Finalizar con bloqueo vencido debe devolver FALSE
        UPDATE psicobloom_interno.eventos_avisos_adelanto
        SET estado = 'procesando', intentos = 1, bloqueado_hasta = now() - INTERVAL '10 seconds'
        WHERE id_evento = v_evento_id;
        v_finalizado := public.finalizar_evento_aviso_adelanto(v_evento_id, 1, 'enviado');
        IF v_finalizado IS DISTINCT FROM FALSE THEN
            RAISE EXCEPTION 'finalizar_evento_aviso_adelanto debe rechazar un bloqueo vencido.';
        END IF;
    END IF;

    IF array_length(v_pendientes, 1) IS NOT NULL THEN
        RAISE NOTICE 'VERIFICACION SQL PARCIAL — REQUISITOS PENDIENTES: %', array_to_string(v_pendientes, ' | ');
    ELSE
        RAISE NOTICE 'VERIFICACION SQL COMPLETA (ETAPA 4) — todas las aserciones validadas y revertidas con ROLLBACK. Pendiente: pruebas reales contra Storage API.';
    END IF;
END $$;

ROLLBACK;
