-- =============================================================================
-- SCRIPT 23 — VERIFICACION CONTROLADA DE CONFIGURACION DE COBRO Y QR (ROLLBACK)
-- Ejecutar en Supabase > SQL Editor DESPUES de 22_configuracion_cobro_profesional.sql
--
-- ALCANCE DE ESTE SCRIPT (PRUEBAS SQL DE POLITICAS Y RPC):
--   - Comprueba RLS, privilegios y bucket privado.
--   - Comprueba autorizacion de AMBAS RPC (obtener y guardar) con:
--       1) sin sesion (anon)
--       2) paciente activo
--       3) cuenta inactiva
--       4) profesional propietario activo
--       5) otro profesional activo
--   - Ejecuta consultas bajo el rol efectivo `authenticated` y `anon`
--     (SET LOCAL ROLE) para validar politicas reales, sin depender de BYPASSRLS.
--   - Valida rechazos monetarios estrictos (NaN, Infinity, <= 0, fuera de rango,
--     fracciones < 1 centavo) y rechazo de objeto QR inexistente o ajeno.
--   - NO inserta ni borra registros directamente en storage.objects.
--   - Si falta algun usuario requerido, NO informa exito completo: reporta los
--     requisitos pendientes.
--   - Revierte todos los cambios de prueba mediante ROLLBACK al final.
--
-- PRUEBAS REALES PENDIENTES FUERA DE SQL (MEDIANTE API DE SUPABASE STORAGE):
--   1. Subir un QR PNG/JPG real al bucket privado con upsert = false.
--   2. Comprobar que intentar sobrescribir la misma ruta o borrar el objeto
--      falla con error de permisos/conflicto.
--   3. Guardar configuracion con requiere_adelanto = TRUE usando esa ruta real
--      y comprobar que la fila devuelta coincide con la persistida.
--   4. Generar URL firmada temporal desde el propietario y comprobar que otro
--      usuario autenticado o anonimo NO puede leer ni descargar el objeto.
-- =============================================================================
BEGIN;

DO $$
DECLARE
    v_rls BOOLEAN;
    v_bucket_publico BOOLEAN;
    v_politicas_mutacion INTEGER;
    v_prof_id UUID;
    v_prof_otro_id UUID;
    v_paciente_id UUID;
    v_inactivo_id UUID;
    v_pendientes TEXT[] := ARRAY[]::TEXT[];
    v_guardada RECORD;
    v_leida RECORD;
    v_objetos_visibles INTEGER;
    v_acceso_directo_bloqueado BOOLEAN;
BEGIN
    -- -------------------------------------------------------------------------
    -- 1. Verificar RLS, privilegios minimos y bucket privado (como postgres)
    -- -------------------------------------------------------------------------
    SELECT c.relrowsecurity
    INTO v_rls
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'psicobloom_interno'
      AND c.relname = 'configuracion_cobro_profesional';

    IF v_rls IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Falta RLS en psicobloom_interno.configuracion_cobro_profesional.';
    END IF;

    IF has_table_privilege('anon', 'psicobloom_interno.configuracion_cobro_profesional', 'SELECT')
       OR has_table_privilege('authenticated', 'psicobloom_interno.configuracion_cobro_profesional', 'SELECT')
       OR has_table_privilege('authenticated', 'psicobloom_interno.configuracion_cobro_profesional', 'INSERT')
       OR has_table_privilege('authenticated', 'psicobloom_interno.configuracion_cobro_profesional', 'UPDATE')
       OR has_table_privilege('authenticated', 'psicobloom_interno.configuracion_cobro_profesional', 'DELETE') THEN
        RAISE EXCEPTION 'anon/authenticated no deben tener privilegios directos sobre configuracion_cobro_profesional.';
    END IF;

    SELECT b.public
    INTO v_bucket_publico
    FROM storage.buckets b
    WHERE b.id = 'qr-cobro-profesionales';

    IF v_bucket_publico IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'El bucket qr-cobro-profesionales debe existir y ser privado (public = FALSE).';
    END IF;

    -- Verificar que NO existan politicas UPDATE ni DELETE en storage.objects
    -- para el bucket qr-cobro-profesionales.
    SELECT count(*)
    INTO v_politicas_mutacion
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND cmd IN ('UPDATE', 'DELETE')
      AND (
          coalesce(qual, '') ILIKE '%qr-cobro-profesionales%'
          OR coalesce(with_check, '') ILIKE '%qr-cobro-profesionales%'
      );

    IF v_politicas_mutacion > 0 THEN
        RAISE EXCEPTION 'No deben existir politicas UPDATE/DELETE sobre qr-cobro-profesionales para evitar sobrescribir o borrar QRs.';
    END IF;

    -- Localizar usuarios reales existentes (sin crear cuentas falsas)
    SELECT p.id INTO v_prof_id
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    WHERE p.rol = 'profesional' AND p.cuenta_activa = TRUE
    ORDER BY p.id
    LIMIT 1;

    SELECT p.id INTO v_prof_otro_id
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    WHERE p.rol = 'profesional'
      AND p.cuenta_activa = TRUE
      AND p.id IS DISTINCT FROM v_prof_id
    ORDER BY p.id
    LIMIT 1;

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

    -- -------------------------------------------------------------------------
    -- 2. Pruebas como usuario SIN SESION (rol efectivo: anon)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    SET LOCAL ROLE anon;

    BEGIN
        PERFORM * FROM public.obtener_configuracion_cobro_propia();
        RAISE EXCEPTION 'anon no debe poder ejecutar obtener_configuracion_cobro_propia.';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        PERFORM * FROM public.guardar_configuracion_cobro_propia(
            FALSE, 35.00, 10.00, NULL, 'Banco Pichincha', 'Usuario Anonimo', NULL, NULL
        );
        RAISE EXCEPTION 'anon no debe poder ejecutar guardar_configuracion_cobro_propia.';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    SELECT count(*) INTO v_objetos_visibles
    FROM storage.objects
    WHERE bucket_id = 'qr-cobro-profesionales';
    IF v_objetos_visibles <> 0 THEN
        RAISE EXCEPTION 'anon no debe ver ningun objeto en qr-cobro-profesionales.';
    END IF;

    RESET ROLE;

    -- -------------------------------------------------------------------------
    -- 3. Pruebas como PACIENTE activo (rol efectivo: authenticated)
    -- -------------------------------------------------------------------------
    IF v_paciente_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un usuario paciente activo para validar rechazo de RPC y politicas Storage.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_paciente_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object('sub', v_paciente_id::TEXT, 'role', 'authenticated')::TEXT,
            true
        );
        SET LOCAL ROLE authenticated;

        BEGIN
            PERFORM * FROM public.obtener_configuracion_cobro_propia();
            RAISE EXCEPTION 'Un paciente no debe poder ejecutar obtener_configuracion_cobro_propia.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 35.00, 10.00, NULL, 'Banco Pichincha', 'Paciente Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Un paciente no debe poder ejecutar guardar_configuracion_cobro_propia.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        SELECT count(*) INTO v_objetos_visibles
        FROM storage.objects
        WHERE bucket_id = 'qr-cobro-profesionales';
        IF v_objetos_visibles <> 0 THEN
            RAISE EXCEPTION 'Un paciente no debe ver objetos en qr-cobro-profesionales.';
        END IF;

        RESET ROLE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 4. Pruebas como CUENTA INACTIVA (rol efectivo: authenticated)
    -- -------------------------------------------------------------------------
    IF v_inactivo_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta una cuenta inactiva (cuenta_activa = FALSE) para validar rechazo de RPC y Storage.');
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
            PERFORM * FROM public.obtener_configuracion_cobro_propia();
            RAISE EXCEPTION 'Una cuenta inactiva no debe poder consultar configuracion de cobro.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 35.00, 10.00, NULL, 'Banco Pichincha', 'Cuenta Inactiva', NULL, NULL
            );
            RAISE EXCEPTION 'Una cuenta inactiva no debe poder guardar configuracion de cobro.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        SELECT count(*) INTO v_objetos_visibles
        FROM storage.objects
        WHERE bucket_id = 'qr-cobro-profesionales';
        IF v_objetos_visibles <> 0 THEN
            RAISE EXCEPTION 'Una cuenta inactiva no debe ver objetos en qr-cobro-profesionales.';
        END IF;

        RESET ROLE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 5. Pruebas como PROFESIONAL PROPIETARIO (rol efectivo: authenticated)
    -- -------------------------------------------------------------------------
    IF v_prof_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un profesional activo para probar validaciones monetarias, rutas QR y persistencia.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_prof_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object('sub', v_prof_id::TEXT, 'role', 'authenticated')::TEXT,
            true
        );
        SET LOCAL ROLE authenticated;

        -- Comprobar que authenticated no tiene SELECT directo a la tabla interna
        v_acceso_directo_bloqueado := FALSE;
        BEGIN
            PERFORM count(*) FROM psicobloom_interno.configuracion_cobro_profesional;
        EXCEPTION
            WHEN insufficient_privilege THEN
                v_acceso_directo_bloqueado := TRUE;
        END;
        IF NOT v_acceso_directo_bloqueado THEN
            RAISE EXCEPTION 'authenticated no debe poder consultar directamente psicobloom_interno.configuracion_cobro_profesional.';
        END IF;

        -- Validaciones monetarias: NaN, Infinity, <= 0, fuera de rango, < 1 centavo
        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 'NaN'::NUMERIC, NULL, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar precio NaN.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 'Infinity'::NUMERIC, NULL, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar precio Infinity.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 100000000.00, NULL, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar precio fuera de rango (> 99999999.99).';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 35.005, 10.00, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar fraccion menor a un centavo (35.005) sin redondear.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 35.00, 10.123, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar adelanto con fraccion menor a un centavo (10.123).';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 20.00, 25.00, NULL, NULL, NULL, NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar adelanto mayor al precio total.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        -- Validaciones de ruta QR: vacia, URL firmada, ajena y objeto inexistente
        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 40.00, 15.00, '   ', 'Banco Pichincha', 'Dra. Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar ruta QR vacia.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                TRUE, 40.00, 15.00, NULL, 'Banco Pichincha', 'Dra. Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar activar adelanto sin QR.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 40.00, 15.00, 'https://ejemplo.supabase.co/storage/v1/object/sign/qr.png',
                'Banco Pichincha', 'Dra. Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar URL firmada.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 40.00, 15.00, gen_random_uuid()::TEXT || '/qr_ajeno.png',
                'Banco Pichincha', 'Dra. Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar ruta QR ajena.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                TRUE, 40.00, 15.00, v_prof_id::TEXT || '/qr_inexistente_' || gen_random_uuid()::TEXT || '.png',
                'Banco Pichincha', 'Dra. Prueba', NULL, NULL
            );
            RAISE EXCEPTION 'Debio rechazar objeto QR inexistente en storage.objects.';
        EXCEPTION
            WHEN invalid_parameter_value THEN NULL;
        END;

        -- Guardado valido sin QR (requiere_adelanto = FALSE): comprueba que
        -- el valor devuelto por la RPC coincide exactamente con el persistido.
        SELECT *
        INTO v_guardada
        FROM public.guardar_configuracion_cobro_propia(
            FALSE, 40.25, 15.50, NULL, 'Banco Pichincha', 'Dra. Prueba', 'Ahorros', '22001234'
        );

        SELECT *
        INTO v_leida
        FROM public.obtener_configuracion_cobro_propia();

        IF v_guardada.precio_consulta IS DISTINCT FROM 40.25
           OR v_guardada.monto_adelanto IS DISTINCT FROM 15.50
           OR v_leida.precio_consulta IS DISTINCT FROM v_guardada.precio_consulta
           OR v_leida.monto_adelanto IS DISTINCT FROM v_guardada.monto_adelanto
           OR v_leida.banco_beneficiario IS DISTINCT FROM 'Banco Pichincha' THEN
            RAISE EXCEPTION 'Los valores devueltos por guardar_configuracion_cobro_propia no coinciden con los persistidos.';
        END IF;

        RESET ROLE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 6. Pruebas como OTRO PROFESIONAL activo (rol efectivo: authenticated)
    -- -------------------------------------------------------------------------
    IF v_prof_id IS NULL OR v_prof_otro_id IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un segundo profesional activo para probar aislamiento entre profesionales.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_prof_otro_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        PERFORM set_config(
            'request.jwt.claims',
            json_build_object('sub', v_prof_otro_id::TEXT, 'role', 'authenticated')::TEXT,
            true
        );
        SET LOCAL ROLE authenticated;

        -- No debe poder referenciar la carpeta del primer profesional
        BEGIN
            PERFORM * FROM public.guardar_configuracion_cobro_propia(
                FALSE, 40.00, 15.00, v_prof_id::TEXT || '/qr_otro.png',
                'Banco Pichincha', 'Otro Profesional', NULL, NULL
            );
            RAISE EXCEPTION 'Otro profesional no debe poder referenciar un QR ajeno.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;

        -- No debe ver objetos de la carpeta del primer profesional en storage.objects
        SELECT count(*) INTO v_objetos_visibles
        FROM storage.objects
        WHERE bucket_id = 'qr-cobro-profesionales'
          AND (storage.foldername(name))[1] = v_prof_id::TEXT;

        IF v_objetos_visibles <> 0 THEN
            RAISE EXCEPTION 'Otro profesional no debe ver objetos privados del primer profesional.';
        END IF;

        RESET ROLE;
    END IF;

    -- -------------------------------------------------------------------------
    -- 7. Reporte final honesto (nunca informar exito completo si hay pendientes)
    -- -------------------------------------------------------------------------
    IF array_length(v_pendientes, 1) IS NOT NULL THEN
        RAISE NOTICE 'VERIFICACION SQL PARCIAL — REQUISITOS PENDIENTES: %', array_to_string(v_pendientes, ' | ');
    ELSE
        RAISE NOTICE 'VERIFICACION SQL DE POLITICAS Y RPC COMPLETA (todos los perfiles requeridos presentes). Pendiente: prueba real de subida/descarga/URL firmada via API de Supabase Storage.';
    END IF;
END $$;

ROLLBACK;
