-- =============================================================================
-- PsicoBloom - Script 30: verificación independiente de cierre manual de
-- incidencias de carga de comprobantes (migración 29).
--
-- Ejecutable en Supabase > SQL Editor o psql DESPUÉS de aplicar la migración 29.
-- Todo ocurre dentro de BEGIN / ROLLBACK sin dejar residuos permanentes.
--
-- NOTA IMPORTANTE DE ALCANCE:
-- - Crea horarios en estado 'disponible' y usa el flujo válido de solicitud y
--   aceptación (solicitar_cita_paciente + responder_solicitud_cita_profesional)
--   para respetar triggers y campos NOT NULL de adelantos_citas.
-- - No inserta objetos ficticios en storage.objects. Para probar el cierre con
--   comprobante registrado a nivel SQL, prefiere un comprobante real existente
--   si hubiera uno o registra una fila interna en comprobantes_adelanto bajo
--   ROLLBACK (declarado expresamente: esto verifica la lógica SQL/RPC y NO
--   equivale a probar permisos HTTP de Storage API).
-- =============================================================================

BEGIN;

DO $$
DECLARE
    v_prof_uid UUID;
    v_prof_id UUID;
    v_prof_otro_uid UUID;
    v_pac_uid UUID;
    v_pac_id UUID;
    v_admin_uid UUID;

    v_pendientes TEXT[] := ARRAY[]::TEXT[];
    v_version_oferta TEXT;

    v_disp_id UUID;
    v_disp_otra_id UUID;
    v_cita_id UUID;
    v_cita_otra_id UUID;

    v_inc_abierta_id UUID;
    v_inc_liberada_id UUID;
    v_inc_otra_cita_id UUID;

    v_detalle JSONB;
    v_inc_json JSONB;
    v_motivo_guardado TEXT;
    v_resuelto_por_1 UUID;
    v_resuelto_en_1 TIMESTAMPTZ;
    v_resuelto_en_2 TIMESTAMPTZ;
    v_conteo_inc INTEGER;

    v_estado_cita TEXT;
    v_estado_adelanto TEXT;
    v_estado_disp TEXT;
    v_precio_antes NUMERIC(10, 2);
    v_adelanto_antes NUMERIC(10, 2);
    v_saldo_antes NUMERIC(10, 2);
    v_precio_despues NUMERIC(10, 2);
    v_adelanto_despues NUMERIC(10, 2);
    v_saldo_despues NUMERIC(10, 2);
    v_fallo_esperado BOOLEAN;
BEGIN
    -- 0. Localizar perfiles reales existentes (profesional con adelanto activo,
    --    paciente activo, otro profesional activo y administrador activo).
    SELECT c.id_profesional, pr.id_usuario
    INTO v_prof_id, v_prof_uid
    FROM psicobloom_interno.configuracion_cobro_profesional c
    JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
    WHERE c.requiere_adelanto IS TRUE
      AND pe.rol = 'profesional'
      AND pe.cuenta_activa IS TRUE
      AND public._profesional_es_publicable(c.id_profesional)
    LIMIT 1;

    IF v_prof_uid IS NULL OR v_prof_id IS NULL THEN
        RAISE EXCEPTION 'Se requiere al menos un profesional publicable y activo con requiere_adelanto = TRUE para ejecutar la verificación 30.';
    END IF;

    SELECT pr.id_usuario
    INTO v_prof_otro_uid
    FROM public."Profesionales" pr
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
    WHERE pe.rol = 'profesional'
      AND pe.cuenta_activa IS TRUE
      AND pr.id_usuario IS DISTINCT FROM v_prof_uid
      AND public._profesional_es_publicable(pr.id_profesional)
    LIMIT 1;

    SELECT pa.id_usuario, pa.id_paciente
    INTO v_pac_uid, v_pac_id
    FROM public."Pacientes" pa
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pa.id_usuario
    WHERE pe.rol = 'paciente'
      AND pe.cuenta_activa IS TRUE
    ORDER BY pa.id_paciente
    LIMIT 1;

    IF v_pac_uid IS NULL OR v_pac_id IS NULL THEN
        RAISE EXCEPTION 'Se requiere al menos un paciente activo para ejecutar la verificación 30.';
    END IF;

    SELECT pe.id
    INTO v_admin_uid
    FROM psicobloom_interno.perfiles_compat pe
    WHERE pe.rol = 'administrador'
      AND pe.cuenta_activa IS TRUE
    LIMIT 1;

    -- 1. Preparar disponibilidades en estado 'disponible' (respetando trigger)
    --    y crear dos solicitudes válidas usando el flujo real del backend.
    INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
    VALUES (
        v_prof_id,
        ((now() + INTERVAL '45 days') AT TIME ZONE 'America/Guayaquil')::DATE,
        '10:00:00'::TIME, '11:00:00'::TIME, 'disponible'
    )
    RETURNING id_disponibilidad INTO v_disp_id;

    INSERT INTO public."Disponibilidad" (id_profesional, fecha, hora_inicio, hora_fin, estado)
    VALUES (
        v_prof_id,
        ((now() + INTERVAL '46 days') AT TIME ZONE 'America/Guayaquil')::DATE,
        '10:00:00'::TIME, '11:00:00'::TIME, 'disponible'
    )
    RETURNING id_disponibilidad INTO v_disp_otra_id;

    -- Solicitar ambas citas como paciente titular (puebla todos los NOT NULL de adelantos_citas)
    PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    SELECT o.version_oferta
    INTO v_version_oferta
    FROM public.obtener_oferta_adelanto_profesional(v_prof_id) o;

    SELECT s.id_cita
    INTO v_cita_id
    FROM public.solicitar_cita_paciente(v_prof_id, v_disp_id, 'idem-30-cita-1', TRUE, v_version_oferta) s;

    SELECT s.id_cita
    INTO v_cita_otra_id
    FROM public.solicitar_cita_paciente(v_prof_id, v_disp_otra_id, 'idem-30-cita-2', TRUE, v_version_oferta) s;

    RESET ROLE;

    -- Aceptar ambas solicitudes como profesional titular -> estado_adelanto = 'pendiente_adelanto'
    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    PERFORM * FROM public.responder_solicitud_cita_profesional(v_cita_id, 'confirmada');
    PERFORM * FROM public.responder_solicitud_cita_profesional(v_cita_otra_id, 'confirmada');

    RESET ROLE;

    -- Registrar incidencias usando la RPC real como paciente titular
    PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    PERFORM public.registrar_incidencia_adelanto(
        v_cita_id,
        'Error de red al adjuntar la primera foto del comprobante.',
        'inc-30-abierta'
    );
    PERFORM public.registrar_incidencia_adelanto(
        v_cita_otra_id,
        'Incidencia registrada en una segunda cita.',
        'inc-30-otra'
    );

    RESET ROLE;

    -- Recuperar IDs de incidencias y valores económicos congelados
    SELECT i.id_incidencia INTO v_inc_abierta_id
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_cita = v_cita_id AND i.clave_idempotencia = 'inc-30-abierta';

    SELECT i.id_incidencia INTO v_inc_otra_cita_id
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_cita = v_cita_otra_id AND i.clave_idempotencia = 'inc-30-otra';

    SELECT a.precio_consulta, a.monto_adelanto, a.saldo_despues_adelanto
    INTO v_precio_antes, v_adelanto_antes, v_saldo_antes
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = v_cita_id;

    -- Fixture interno explícito para caso de horario ya liberado (dentro de ROLLBACK)
    INSERT INTO psicobloom_interno.incidencias_adelanto (
        id_cita, detalle, horario_ya_liberado, estado_incidencia, creado_por
    )
    VALUES (
        v_cita_id,
        'Transferí antes del límite pero el horario ya se liberó.',
        TRUE,
        'pendiente_revision',
        v_pac_uid
    )
    RETURNING id_incidencia INTO v_inc_liberada_id;

    -- 2. Sesión anónima (SET LOCAL ROLE anon, sub vacío) -> 42501
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claim.role', 'anon', TRUE);
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', TRUE);
    SET LOCAL ROLE anon;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Anónimo intenta cerrar.');
    EXCEPTION WHEN insufficient_privilege THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: rol anon no fue rechazado con 42501.';
    END IF;

    -- 3. Autenticado con rol NULL (sin perfil activo en perfiles_compat) -> 42501
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid()::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Usuario con rol NULL intenta cerrar.');
    EXCEPTION WHEN insufficient_privilege THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: usuario autenticado con rol NULL no fue rechazado con 42501.';
    END IF;

    -- 4. Paciente titular -> 42501
    PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Paciente intenta cerrar.');
    EXCEPTION WHEN insufficient_privilege THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: paciente titular no fue rechazado con 42501.';
    END IF;

    -- 5. Administrador -> 42501 (nunca omitir silenciosamente)
    IF v_admin_uid IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un administrador activo para comprobar rechazo 42501 en resolver_incidencia_adelanto.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_admin_uid::TEXT, TRUE);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
        SET LOCAL ROLE authenticated;

        v_fallo_esperado := FALSE;
        BEGIN
            PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Admin intenta cerrar.');
        EXCEPTION WHEN insufficient_privilege THEN
            v_fallo_esperado := TRUE;
        END;
        RESET ROLE;
        IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'Fallo: administrador no fue rechazado con 42501.';
        END IF;
    END IF;

    -- 6. Otro profesional activo -> 42501 (nunca omitir silenciosamente)
    IF v_prof_otro_uid IS NULL THEN
        v_pendientes := array_append(v_pendientes, 'Falta un segundo profesional activo y aprobado para comprobar rechazo 42501 entre profesionales.');
    ELSE
        PERFORM set_config('request.jwt.claim.sub', v_prof_otro_uid::TEXT, TRUE);
        PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_otro_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
        SET LOCAL ROLE authenticated;

        v_fallo_esperado := FALSE;
        BEGIN
            PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Otro profesional intenta cerrar.');
        EXCEPTION WHEN insufficient_privilege THEN
            v_fallo_esperado := TRUE;
        END;
        RESET ROLE;
        IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'Fallo: otro profesional no fue rechazado con 42501.';
        END IF;
    END IF;

    -- 7. Profesional titular con cuenta desactivada (usando fuente real perfiles_compat) -> 42501
    UPDATE psicobloom_interno.perfiles_compat
    SET cuenta_activa = FALSE
    WHERE id = v_prof_uid;

    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Profesional inactivo intenta cerrar.');
    EXCEPTION WHEN insufficient_privilege THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;

    UPDATE psicobloom_interno.perfiles_compat
    SET cuenta_activa = TRUE
    WHERE id = v_prof_uid;

    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: profesional titular desactivado no fue rechazado con 42501.';
    END IF;

    -- 8. Validaciones de motivo (< 5 y > 500) y pertenencia de incidencia a la cita -> 22023
    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'abc');
    EXCEPTION WHEN invalid_parameter_value THEN
        v_fallo_esperado := TRUE;
    END;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RESET ROLE;
        RAISE EXCEPTION 'Fallo: motivo menor a 5 caracteres no fue rechazado con 22023.';
    END IF;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, repeat('x', 501));
    EXCEPTION WHEN invalid_parameter_value THEN
        v_fallo_esperado := TRUE;
    END;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RESET ROLE;
        RAISE EXCEPTION 'Fallo: motivo mayor a 500 caracteres no fue rechazado con 22023.';
    END IF;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_otra_cita_id, 'Intento con incidencia de otra cita.');
    EXCEPTION WHEN invalid_parameter_value THEN
        v_fallo_esperado := TRUE;
    END;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RESET ROLE;
        RAISE EXCEPTION 'Fallo: incidencia perteneciente a otra cita no fue rechazada con 22023.';
    END IF;

    -- 9A. Prueba separada de ESTADO INVÁLIDO (estado_adelanto = 'incidencia_pago') -> 23P01
    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Intento en estado incidencia_pago.');
    EXCEPTION WHEN exclusion_violation THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: cierre en estado no permitido (incidencia_pago) no fue rechazado con 23P01.';
    END IF;

    -- 9B. Prueba separada de COMPROBANTE AUSENTE en estado permitido ('comprobante_en_revision') -> 23P01
    UPDATE psicobloom_interno.adelantos_citas
    SET estado_adelanto = 'comprobante_en_revision',
        comprobante_enviado_en = now(),
        limite_revision_en = now() + INTERVAL '12 hours'
    WHERE id_cita = v_cita_id;

    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_abierta_id, 'Intento en estado permitido sin comprobante.');
    EXCEPTION WHEN exclusion_violation THEN
        v_fallo_esperado := TRUE;
    END;
    RESET ROLE;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'Fallo: cierre sin comprobante registrado en estado permitido no fue rechazado con 23P01.';
    END IF;

    -- Fixture interno explícito de comprobante en tabla interna (bajo ROLLBACK,
    -- sin insertar objetos ficticios en storage.objects; NO prueba Storage API).
    INSERT INTO psicobloom_interno.comprobantes_adelanto (
        id_cita, ruta_storage, nota_paciente, creado_por
    )
    VALUES (
        v_cita_id,
        v_cita_id::TEXT || '/' || v_pac_uid::TEXT || '/fixture_sql_comprobante.png',
        'Fixture SQL interno de comprobante (no prueba Storage API)',
        v_pac_uid
    );

    -- 10. Rechazo de incidencia con horario_ya_liberado = TRUE aun con comprobante y estado permitido -> 23P01
    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_fallo_esperado := FALSE;
    BEGIN
        PERFORM public.resolver_incidencia_adelanto(v_cita_id, v_inc_liberada_id, 'Intento sobre horario ya liberado.');
    EXCEPTION WHEN exclusion_violation THEN
        v_fallo_esperado := TRUE;
    END;
    IF v_fallo_esperado IS DISTINCT FROM TRUE THEN
        RESET ROLE;
        RAISE EXCEPTION 'Fallo: incidencia con horario_ya_liberado = TRUE no fue rechazada con 23P01.';
    END IF;

    -- 11. Cierre válido por el profesional titular activo y aprobado
    v_detalle := public.resolver_incidencia_adelanto(
        v_cita_id,
        v_inc_abierta_id,
        'El paciente logró subir el comprobante legible; se cierra la incidencia de carga.'
    );
    RESET ROLE;

    SELECT i.motivo_resolucion, i.resuelto_por, i.resuelto_en
    INTO v_motivo_guardado, v_resuelto_por_1, v_resuelto_en_1
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_incidencia = v_inc_abierta_id;

    IF v_motivo_guardado IS DISTINCT FROM 'El paciente logró subir el comprobante legible; se cierra la incidencia de carga.'
       OR v_resuelto_por_1 IS DISTINCT FROM v_prof_uid
       OR v_resuelto_en_1 IS NULL THEN
        RAISE EXCEPTION 'Fallo: auditoría de resolución incompleta o incorrecta.';
    END IF;

    -- Verificar que NO cambió estado de cita, adelanto, disponibilidad ni importes
    SELECT c.estado INTO v_estado_cita FROM public."Citas" c WHERE c.id_cita = v_cita_id;
    SELECT a.estado_adelanto, a.precio_consulta, a.monto_adelanto, a.saldo_despues_adelanto
    INTO v_estado_adelanto, v_precio_despues, v_adelanto_despues, v_saldo_despues
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = v_cita_id;
    SELECT d.estado INTO v_estado_disp FROM public."Disponibilidad" d WHERE d.id_disponibilidad = v_disp_id;

    IF v_estado_cita IS DISTINCT FROM 'pendiente'
       OR v_estado_adelanto IS DISTINCT FROM 'comprobante_en_revision'
       OR v_estado_disp IS DISTINCT FROM 'reservada'
       OR v_precio_despues IS DISTINCT FROM v_precio_antes
       OR v_adelanto_despues IS DISTINCT FROM v_adelanto_antes
       OR v_saldo_despues IS DISTINCT FROM v_saldo_antes THEN
        RAISE EXCEPTION 'Fallo: resolver la incidencia alteró cita, adelanto, disponibilidad o importes.';
    END IF;

    -- 12. Repetición idempotente con otro motivo: no duplica ni sobrescribe resolución previa
    PERFORM set_config('request.jwt.claim.sub', v_prof_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_prof_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_detalle := public.resolver_incidencia_adelanto(
        v_cita_id,
        v_inc_abierta_id,
        'Motivo distinto que NO debe sobrescribir la resolución previa.'
    );
    RESET ROLE;

    SELECT COUNT(*) INTO v_conteo_inc
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_cita = v_cita_id;

    SELECT i.motivo_resolucion, i.resuelto_en
    INTO v_motivo_guardado, v_resuelto_en_2
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_incidencia = v_inc_abierta_id;

    IF v_conteo_inc IS DISTINCT FROM 2
       OR v_motivo_guardado IS DISTINCT FROM 'El paciente logró subir el comprobante legible; se cierra la incidencia de carga.'
       OR v_resuelto_en_2 IS DISTINCT FROM v_resuelto_en_1 THEN
        RAISE EXCEPTION 'Fallo: repetición idempotente duplicó filas o sobrescribió motivo/fecha previos.';
    END IF;

    -- 13. Paciente titular consulta detalle y ve resolución + detalle original intacto
    PERFORM set_config('request.jwt.claim.sub', v_pac_uid::TEXT, TRUE);
    PERFORM set_config('request.jwt.claim.role', 'authenticated', TRUE);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pac_uid::TEXT, 'role', 'authenticated')::TEXT, TRUE);
    SET LOCAL ROLE authenticated;

    v_detalle := public.obtener_detalle_adelanto_cita(v_cita_id);
    RESET ROLE;

    SELECT elem
    INTO v_inc_json
    FROM jsonb_array_elements(v_detalle->'incidencias') elem
    WHERE (elem->>'id_incidencia')::UUID = v_inc_abierta_id;

    IF v_inc_json IS NULL
       OR (v_inc_json->>'estado_incidencia') IS DISTINCT FROM 'resuelta'
       OR (v_inc_json->>'detalle') IS DISTINCT FROM 'Error de red al adjuntar la primera foto del comprobante.'
       OR (v_inc_json->>'motivo_resolucion') IS DISTINCT FROM 'El paciente logró subir el comprobante legible; se cierra la incidencia de carga.'
       OR (v_inc_json->>'resuelto_en') IS NULL THEN
        RAISE EXCEPTION 'Fallo: el detalle del paciente no expone correctamente la resolución y el historial.';
    END IF;

    -- Limpiar claims antes de cerrar
    PERFORM set_config('request.jwt.claim.sub', '', TRUE);
    PERFORM set_config('request.jwt.claim.role', '', TRUE);
    PERFORM set_config('request.jwt.claims', '{}', TRUE);

    IF cardinality(v_pendientes) > 0 THEN
        RAISE NOTICE 'VERIFICACION PARCIAL (migración 29) — casos pendientes: %. Nota: el comprobante de prueba usó fixture SQL interno (no equivale a probar Storage API).', array_to_string(v_pendientes, ' | ');
    ELSE
        RAISE NOTICE 'OK: verificación SQL completa de cierre manual de incidencias (migración 29). Nota: el comprobante de prueba usó fixture SQL interno (no equivale a probar Storage API).';
    END IF;
END;
$$;

ROLLBACK;
