-- =============================================================================
-- SCRIPT 25 — VERIFICACION CONTROLADA DE INFO ECONOMICA AL PACIENTE (ROLLBACK)
-- Ejecutar en Supabase > SQL Editor DESPUES de 24_info_economica_profesional_paciente.sql
--
-- Comprueba:
--   1. Que la firma de public.obtener_info_economica_profesional(UUID) NO
--      exponga columnas bancarias, QR ni rutas de Storage.
--   2. Que anon y authenticated sigan sin acceso directo a la tabla interna.
--   3. Rechazo a anon y cuenta inactiva usando SET LOCAL ROLE.
--   4. Profesional no visible/no aprobado devuelve 0 filas.
--   5. Profesional visible sin configuracion devuelve tiene_configuracion = FALSE
--      y precio_consulta = NULL (sin asumir gratuidad).
--   6. Profesional visible con requiere_adelanto = FALSE y monto_adelanto previo
--      conservado devuelve monto_adelanto_exigible = 0.00 y saldo = precio.
--   7. Si existe un profesional visible con requiere_adelanto = TRUE ya
--      configurado en remoto, verifica el calculo exacto del saldo; si no,
--      reporta el requisito pendiente sin insertar filas falsas en storage.objects.
--   8. Revierte cualquier cambio temporal mediante ROLLBACK.
-- =============================================================================
BEGIN;

DO $$
DECLARE
    v_columnas_prohibidas INTEGER;
    v_paciente_id UUID;
    v_inactivo_id UUID;
    v_prof_publicable_id UUID;
    v_prof_no_publicable_id UUID;
    v_prof_con_adelanto_id UUID;
    v_pendientes TEXT[] := ARRAY[]::TEXT[];
    v_fila RECORD;
    v_conteo INTEGER;
BEGIN
    -- 1. Comprobar que la RPC no expone columnas sensibles ni bancarias
    SELECT count(*)
    INTO v_columnas_prohibidas
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL unnest(coalesce(p.proargnames, ARRAY[]::TEXT[])) AS arg(nombre)
    WHERE n.nspname = 'public'
      AND p.proname = 'obtener_info_economica_profesional'
      AND arg.nombre IN (
          'ruta_qr_storage',
          'banco_beneficiario',
          'titular_beneficiario',
          'tipo_cuenta_beneficiario',
          'numero_cuenta_referencia',
          'url_imagen',
          'url_qr'
      );

    IF v_columnas_prohibidas > 0 THEN
        RAISE EXCEPTION 'La RPC obtener_info_economica_profesional no debe exponer datos bancarios ni rutas de QR.';
    END IF;

    -- 2. Confirmar que no hay acceso directo a la tabla interna
    IF has_table_privilege('anon', 'psicobloom_interno.configuracion_cobro_profesional', 'SELECT')
       OR has_table_privilege('authenticated', 'psicobloom_interno.configuracion_cobro_profesional', 'SELECT') THEN
        RAISE EXCEPTION 'anon/authenticated no deben tener SELECT directo sobre configuracion_cobro_profesional.';
    END IF;

    -- Localizar usuarios y profesionales reales existentes
    SELECT p.id INTO v_paciente_id
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.rol = 'paciente' AND p.cuenta_activa = TRUE
    ORDER BY p.id
    LIMIT 1;

    SELECT p.id INTO v_inactivo_id
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.cuenta_activa = FALSE
    ORDER BY p.id
    LIMIT 1;

    SELECT pr.id_profesional INTO v_prof_publicable_id
    FROM public."Profesionales" pr
    WHERE public._profesional_es_publicable(pr.id_profesional)
    ORDER BY pr.id_profesional
    LIMIT 1;

    SELECT pr.id_profesional INTO v_prof_no_publicable_id
    FROM public."Profesionales" pr
    WHERE NOT public._profesional_es_publicable(pr.id_profesional)
    ORDER BY pr.id_profesional
    LIMIT 1;

    SELECT c.id_profesional INTO v_prof_con_adelanto_id
    FROM psicobloom_interno.configuracion_cobro_profesional c
    WHERE c.requiere_adelanto = TRUE
      AND public._profesional_es_publicable(c.id_profesional)
    ORDER BY c.id_profesional
    LIMIT 1;

    -- 3. Probar rechazo como anon (rol efectivo)
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    SET LOCAL ROLE anon;

    BEGIN
        PERFORM * FROM public.obtener_info_economica_profesional(gen_random_uuid());
        RAISE EXCEPTION 'anon no debe poder ejecutar obtener_info_economica_profesional.';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    RESET ROLE;

    -- 4. Probar rechazo como cuenta inactiva (rol efectivo: authenticated)
    IF v_inactivo_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta una cuenta inactiva (cuenta_activa = FALSE) para verificar rechazo de acceso.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_inactivo_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object('sub', v_inactivo_id::TEXT, 'role', 'authenticated')::TEXT,
            true
        );
        SET LOCAL ROLE authenticated;

        BEGIN
            PERFORM * FROM public.obtener_info_economica_profesional(gen_random_uuid());
            RAISE EXCEPTION 'Una cuenta inactiva no debe poder consultar informacion economica.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        RESET ROLE;
    END IF;

    -- 5. Pruebas como paciente activo (rol efectivo: authenticated)
    IF v_paciente_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un paciente activo para probar consultas economicas.');
    ELSE
        -- 5a. Profesional inexistente / no publicable => 0 filas
        PERFORM set_config('request.jwt.claim.sub', v_paciente_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object('sub', v_paciente_id::TEXT, 'role', 'authenticated')::TEXT,
            true
        );
        SET LOCAL ROLE authenticated;

        SELECT count(*) INTO v_conteo
        FROM public.obtener_info_economica_profesional(gen_random_uuid());
        IF v_conteo <> 0 THEN
            RAISE EXCEPTION 'Un profesional inexistente debe devolver 0 filas.';
        END IF;

        IF v_prof_no_publicable_id IS NULL THEN
            v_pendientes := array_append(v_pendientes, 'Falta un profesional no publicable (pendiente/inactivo) para validar ocultamiento.');
        ELSE
            SELECT count(*) INTO v_conteo
            FROM public.obtener_info_economica_profesional(v_prof_no_publicable_id);
            IF v_conteo <> 0 THEN
                RAISE EXCEPTION 'Un profesional no publicable debe devolver 0 filas.';
            END IF;
        END IF;

        -- 5b. Si ya existe un profesional publicable con adelanto activo, verificar saldo exacto
        IF v_prof_con_adelanto_id IS NULL THEN
            v_pendientes := array_append(v_pendientes, 'Falta un profesional publicable con requiere_adelanto = TRUE para verificar calculo real con adelanto activo.');
        ELSE
            SELECT * INTO v_fila
            FROM public.obtener_info_economica_profesional(v_prof_con_adelanto_id);

            IF v_fila.tiene_configuracion IS DISTINCT FROM TRUE
               OR v_fila.requiere_adelanto IS DISTINCT FROM TRUE
               OR v_fila.precio_consulta IS NULL
               OR v_fila.monto_adelanto_exigible IS NULL
               OR v_fila.saldo_despues_adelanto IS DISTINCT FROM (v_fila.precio_consulta - v_fila.monto_adelanto_exigible) THEN
                RAISE EXCEPTION 'Calculo incorrecto para profesional con adelanto activo.';
            END IF;
        END IF;

        RESET ROLE;

        -- 5c. Probar escenarios sin configuracion y con adelanto desactivado
        -- (modificacion temporal revertida por ROLLBACK al final)
        IF v_prof_publicable_id IS NULL THEN
            v_pendientes := array_append(v_pendientes, 'Falta un profesional publicable para probar escenarios sin configuracion y sin adelanto.');
        ELSE
            DELETE FROM psicobloom_interno.configuracion_cobro_profesional
            WHERE id_profesional = v_prof_publicable_id;

            PERFORM set_config('request.jwt.claim.sub', v_paciente_id::TEXT, true);
            PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
            PERFORM set_config(
                'request.jwt.claims',
                json_build_object('sub', v_paciente_id::TEXT, 'role', 'authenticated')::TEXT,
                true
            );
            SET LOCAL ROLE authenticated;

            SELECT * INTO v_fila
            FROM public.obtener_info_economica_profesional(v_prof_publicable_id);

            IF v_fila.tiene_configuracion IS DISTINCT FROM FALSE
               OR v_fila.precio_consulta IS NOT NULL
               OR v_fila.monto_adelanto_exigible IS NOT NULL
               OR v_fila.saldo_despues_adelanto IS NOT NULL THEN
                RAISE EXCEPTION 'Un profesional sin configuracion debe devolver tiene_configuracion = FALSE y montos NULL.';
            END IF;

            RESET ROLE;

            -- Insertar configuracion con requiere_adelanto = FALSE pero monto_adelanto previo conservado
            INSERT INTO psicobloom_interno.configuracion_cobro_profesional (
                id_profesional,
                requiere_adelanto,
                moneda,
                precio_consulta,
                monto_adelanto,
                ruta_qr_storage,
                banco_beneficiario,
                titular_beneficiario
            )
            VALUES (
                v_prof_publicable_id,
                FALSE,
                'USD',
                42.50,
                15.25,
                NULL,
                'Banco Prueba',
                'Titular Prueba'
            );

            SET LOCAL ROLE authenticated;

            SELECT * INTO v_fila
            FROM public.obtener_info_economica_profesional(v_prof_publicable_id);

            IF v_fila.tiene_configuracion IS DISTINCT FROM TRUE
               OR v_fila.requiere_adelanto IS DISTINCT FROM FALSE
               OR v_fila.precio_consulta IS DISTINCT FROM 42.50
               OR v_fila.monto_adelanto_exigible IS DISTINCT FROM 0.00
               OR v_fila.saldo_despues_adelanto IS DISTINCT FROM 42.50 THEN
                RAISE EXCEPTION 'Con requiere_adelanto = FALSE el adelanto exigible debe ser 0.00 y el saldo igual al precio total.';
            END IF;

            RESET ROLE;
        END IF;
    END IF;

    IF array_length(v_pendientes, 1) IS NOT NULL THEN
        RAISE NOTICE 'VERIFICACION SQL PARCIAL — REQUISITOS PENDIENTES: %', array_to_string(v_pendientes, ' | ');
    ELSE
        RAISE NOTICE 'VERIFICACION SQL COMPLETA para obtener_info_economica_profesional (todos los perfiles y escenarios validados; cambios revertidos con ROLLBACK).';
    END IF;
END $$;

ROLLBACK;
