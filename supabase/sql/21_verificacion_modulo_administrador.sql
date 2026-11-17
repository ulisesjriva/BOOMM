-- =============================================================================
-- SCRIPT 21 — VERIFICACION CONTROLADA DEL MODULO ADMINISTRADOR (CON ROLLBACK)
-- Ejecutar despues de 20_modulo_administrador.sql en Supabase > SQL Editor
-- =============================================================================
BEGIN;

DO $$
DECLARE
    v_tiene_rls BOOLEAN;
    v_permiso_anon BOOLEAN;
    v_permiso_auth BOOLEAN;
    v_admin_id UUID;
    v_paciente_id UUID;
    v_prof_id UUID;
    v_resumen JSONB;
    v_suma_citas BIGINT;
    v_id_esp UUID;
    v_activa_esp BOOLEAN;
BEGIN
    -- 1. Verificar RLS y ausencia de acceso directo en auditoria_administracion
    SELECT c.relrowsecurity
    INTO v_tiene_rls
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'psicobloom_interno'
      AND c.relname = 'auditoria_administracion';

    IF v_tiene_rls IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Falta RLS en psicobloom_interno.auditoria_administracion.';
    END IF;

    SELECT has_table_privilege('anon', 'psicobloom_interno.auditoria_administracion', 'SELECT'),
           has_table_privilege('authenticated', 'psicobloom_interno.auditoria_administracion', 'SELECT')
    INTO v_permiso_anon, v_permiso_auth;

    IF v_permiso_anon OR v_permiso_auth THEN
        RAISE EXCEPTION 'anon o authenticated no deben tener acceso directo a auditoria_administracion.';
    END IF;

    -- 2. Verificar que anon no pueda ejecutar ninguna RPC administrativa
    IF has_function_privilege('anon', 'public.resumen_administracion()', 'EXECUTE')
       OR has_function_privilege('anon', 'public.listar_citas_administracion(text, date, date, integer, integer)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.guardar_especialidad_administracion(uuid, text, text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'anon no debe poder ejecutar funciones administrativas.';
    END IF;

    -- 3. Rechazar rol NULL (sin sesion / sin claim sub)
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claim.role', 'anon', true);
    BEGIN
        PERFORM public.resumen_administracion();
        RAISE EXCEPTION 'Debio rechazar sesion con rol NULL.';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    -- 4. Rechazar paciente y profesional si existen en la base
    SELECT p.id INTO v_paciente_id
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.rol = 'paciente' AND p.cuenta_activa = TRUE
    LIMIT 1;

    IF v_paciente_id IS NOT NULL THEN
        PERFORM set_config('request.jwt.claim.sub', v_paciente_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        BEGIN
            PERFORM public.listar_usuarios_administracion(NULL, 'todos', 0, 5);
            RAISE EXCEPTION 'Un paciente no debe poder listar usuarios administrativos.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;
    END IF;

    SELECT p.id INTO v_prof_id
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.rol = 'profesional' AND p.cuenta_activa = TRUE
    LIMIT 1;

    IF v_prof_id IS NOT NULL THEN
        PERFORM set_config('request.jwt.claim.sub', v_prof_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
        BEGIN
            PERFORM public.listar_citas_administracion('todas', NULL, NULL, 0, 5);
            RAISE EXCEPTION 'Un profesional no debe poder supervisar todas las citas.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;
    END IF;

    -- 5. Simular sesion de administrador activo
    SELECT p.id
    INTO v_admin_id
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.rol = 'administrador' AND p.cuenta_activa = TRUE
    LIMIT 1;

    IF v_admin_id IS NOT NULL THEN
        PERFORM set_config('request.jwt.claim.sub', v_admin_id::TEXT, true);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

        -- Verificar resumen general y coherencia matematica de citas
        v_resumen := public.resumen_administracion();
        v_suma_citas :=
            (v_resumen->>'citas_pendientes')::BIGINT +
            (v_resumen->>'citas_confirmadas')::BIGINT +
            (v_resumen->>'citas_canceladas')::BIGINT +
            (v_resumen->>'citas_rechazadas')::BIGINT +
            (v_resumen->>'citas_finalizadas')::BIGINT;

        IF (v_resumen->>'total_citas')::BIGINT <> v_suma_citas THEN
            RAISE EXCEPTION 'Incoherencia en total_citas de resumen_administracion.';
        END IF;

        -- Verificar ejecucion de listados reales
        PERFORM count(*) FROM public.listar_usuarios_administracion(NULL, 'todos', 0, 5);
        PERFORM count(*) FROM public.listar_profesionales_administracion('todos');
        PERFORM count(*) FROM public.listar_especialidades_administracion();
        PERFORM count(*) FROM public.listar_citas_administracion('todas', NULL, NULL, 0, 5);

        -- Crear especialidad nueva, rechazar duplicado con espacios/mayusculas, editar y desactivar
        v_id_esp := public.guardar_especialidad_administracion(NULL, 'Prueba Admin Temporal', 'Descripcion temporal');
        BEGIN
            PERFORM public.guardar_especialidad_administracion(NULL, '  prueba   admin temporal ', NULL);
            RAISE EXCEPTION 'Debio rechazar especialidad duplicada.';
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;

        PERFORM public.guardar_especialidad_administracion(v_id_esp, 'Prueba Admin Editada', 'Actualizada');
        PERFORM public.cambiar_estado_especialidad_administracion(v_id_esp, FALSE);

        SELECT e.activa INTO v_activa_esp
        FROM public."Especialidades" e
        WHERE e.id_especialidad = v_id_esp;

        IF v_activa_esp IS DISTINCT FROM FALSE THEN
            RAISE EXCEPTION 'La especialidad debio quedar desactivada.';
        END IF;

        -- Verificar proteccion de auto-desactivacion
        BEGIN
            PERFORM public.cambiar_estado_cuenta(v_admin_id, FALSE, 'Motivo de prueba');
            RAISE EXCEPTION 'Debio rechazar desactivar la propia cuenta.';
        EXCEPTION
            WHEN insufficient_privilege THEN NULL;
        END;
    END IF;
END $$;

ROLLBACK;
