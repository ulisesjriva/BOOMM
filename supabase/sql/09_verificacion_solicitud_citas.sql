-- =============================================================================
-- SCRIPT 9 — VERIFICACION TRANSACCIONAL DE SOLICITUD Y CONSULTA DE CITAS (I3-02)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar COMPLETO en Supabase > SQL Editor como postgres (despues de 06 y 08).
--
-- Crea cuentas, horarios y solicitudes ficticias SOLO dentro de esta transaccion
-- y finaliza con ROLLBACK para conservar intactos los datos reales del proyecto.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE resultados_citas_bloom(
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    prueba TEXT,
    resultado TEXT
);
GRANT INSERT, SELECT ON pg_temp.resultados_citas_bloom TO anon, authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_citas_bloom_numero_seq TO anon, authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %', prueba;
    END IF;
    INSERT INTO pg_temp.resultados_citas_bloom(prueba, resultado) VALUES(prueba, 'OK');
END;
$$;

CREATE FUNCTION pg_temp.comprobar_error(prueba TEXT, consulta TEXT, codigo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE codigo_obtenido TEXT;
BEGIN
    BEGIN
        EXECUTE consulta;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS codigo_obtenido = RETURNED_SQLSTATE;
    END;
    PERFORM pg_temp.comprobar(prueba, codigo_obtenido = codigo);
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.comprobar(TEXT, BOOLEAN),
    pg_temp.comprobar_error(TEXT, TEXT, TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. PRIVILEGIOS MINIMOS Y BLOQUEO DE ESCRITURA DIRECTA
-- ---------------------------------------------------------------------------
SELECT pg_temp.comprobar(
    'Authenticated sin INSERT UPDATE DELETE directos sobre Citas ni Pacientes',
    NOT has_table_privilege('authenticated', 'public."Citas"', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public."Citas"', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public."Citas"', 'DELETE')
    AND NOT has_table_privilege('authenticated', 'public."Pacientes"', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public."Pacientes"', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public."Pacientes"', 'DELETE')
);

SELECT pg_temp.comprobar(
    'Anon sin lectura de Citas ni ejecucion de RPC de solicitud de citas',
    NOT has_table_privilege('anon', 'public."Citas"', 'SELECT')
    AND NOT has_function_privilege('anon', 'public.listar_horarios_disponibles_profesional(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.solicitar_cita_paciente(uuid,uuid)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.listar_citas_paciente_propias()', 'EXECUTE')
);

-- ---------------------------------------------------------------------------
-- 2. CUENTAS TEMPORALES DE PRUEBA (CON id_profesional DISTINTO DE id_usuario)
-- ---------------------------------------------------------------------------
SELECT set_config('bloom.paciente_1', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.paciente_2', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.paciente_inactivo', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_aprobado_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_aprobado_id', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_pendiente_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.fecha_futura_1', ((now() AT TIME ZONE 'America/Guayaquil')::date + 4)::text, TRUE);
SELECT set_config('bloom.fecha_futura_2', ((now() AT TIME ZONE 'America/Guayaquil')::date + 6)::text, TRUE);

INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT current_setting('bloom.' || clave)::uuid,
       'cita-' || current_setting('bloom.' || clave) || '@example.invalid',
       jsonb_build_object('nombre', 'Prueba', 'apellido', 'Cita', 'rol', rol)
FROM (
    VALUES
        ('paciente_1', 'paciente'),
        ('paciente_2', 'paciente'),
        ('paciente_inactivo', 'paciente'),
        ('prof_aprobado_usr', 'profesional'),
        ('prof_pendiente_usr', 'profesional')
) AS cuentas(clave, rol);

UPDATE psicobloom_interno.perfiles_compat
SET aprobacion = 'aprobado'
WHERE id = current_setting('bloom.prof_aprobado_usr')::uuid;

UPDATE psicobloom_interno.perfiles_compat
SET cuenta_activa = FALSE
WHERE id = current_setting('bloom.paciente_inactivo')::uuid;

-- Asignamos a prof_aprobado_usr un id_profesional distinto de su id_usuario
DELETE FROM psicobloom_interno.detalle_profesional
WHERE id = (
    SELECT id_profesional
    FROM public."Profesionales"
    WHERE id_usuario = current_setting('bloom.prof_aprobado_usr')::uuid
);

UPDATE public."Profesionales"
SET id_profesional = current_setting('bloom.prof_aprobado_id')::uuid
WHERE id_usuario = current_setting('bloom.prof_aprobado_usr')::uuid;

INSERT INTO psicobloom_interno.detalle_profesional(id)
VALUES (current_setting('bloom.prof_aprobado_id')::uuid);

-- ---------------------------------------------------------------------------
-- 3. CONFIGURACION DE HORARIOS DEL PROFESIONAL APROBADO Y DEL PENDIENTE
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_aprobado_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_aprobado_usr'), 'role', 'authenticated')::text,
    TRUE
);

-- Horario disponible mas tardio (fecha_futura_2, 11:00 - 11:50)
SELECT set_config(
    'bloom.disp_libre_tarde',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_2')::date,
            '11:00'::time,
            '11:50'::time
        )
    ),
    TRUE
);

-- Horario disponible mas temprano (fecha_futura_1, 09:00 - 09:45)
SELECT set_config(
    'bloom.disp_libre_temprano',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_1')::date,
            '09:00'::time,
            '09:45'::time
        )
    ),
    TRUE
);

-- Horario bloqueado (fecha_futura_1, 10:00 - 11:00)
SELECT set_config(
    'bloom.disp_bloqueado',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_1')::date,
            '10:00'::time,
            '11:00'::time
        )
    ),
    TRUE
);
SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(
    current_setting('bloom.disp_bloqueado')::uuid,
    'bloqueada'
);
RESET ROLE;

-- Horario de profesional pendiente de aprobacion
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_pendiente_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_pendiente_usr'), 'role', 'authenticated')::text,
    TRUE
);
SELECT set_config(
    'bloom.disp_prof_pendiente',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_1')::date,
            '15:00'::time,
            '16:00'::time
        )
    ),
    TRUE
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. CONSULTA DE HORARIOS DISPONIBLES Y EXCLUSION DE BLOQUEADOS/NO APROBADOS
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Lista horarios futuros disponibles ordenados por fecha y hora (excluye bloqueados)',
    (
        SELECT count(*) = 2
           AND (array_agg(id_disponibilidad ORDER BY fecha, hora_inicio))[1] = current_setting('bloom.disp_libre_temprano')::uuid
           AND (array_agg(id_disponibilidad ORDER BY fecha, hora_inicio))[2] = current_setting('bloom.disp_libre_tarde')::uuid
        FROM public.listar_horarios_disponibles_profesional(
            current_setting('bloom.prof_aprobado_usr')::uuid
        )
    )
);

SELECT pg_temp.comprobar(
    'Excluye horarios de profesionales no aprobados en consulta de horarios',
    (
        SELECT count(*) = 0
        FROM public.listar_horarios_disponibles_profesional(
            current_setting('bloom.prof_pendiente_usr')::uuid
        )
    )
);

-- ---------------------------------------------------------------------------
-- 5. ENVIO DE SOLICITUD VALIDA, TRANSACCION ATOMICA Y PREVENCION DE DUPLICADOS
-- ---------------------------------------------------------------------------
SELECT pg_temp.comprobar_error(
    'Paciente no puede insertar directamente en la tabla Citas evitando la RPC',
    format(
        $q$INSERT INTO public."Citas"(id_paciente, id_profesional, id_disponibilidad, estado)
           VALUES (%L::uuid, %L::uuid, %L::uuid, 'pendiente')$q$,
        current_setting('bloom.paciente_1'),
        current_setting('bloom.prof_aprobado_id'),
        current_setting('bloom.disp_libre_temprano')
    ),
    '42501'
);

SELECT set_config(
    'bloom.cita_creada',
    (
        SELECT id_cita::text
        FROM public.solicitar_cita_paciente(
            current_setting('bloom.prof_aprobado_usr')::uuid,
            current_setting('bloom.disp_libre_temprano')::uuid
        )
    ),
    TRUE
);

SELECT pg_temp.comprobar(
    'Solicitud valida crea cita pendiente y cambia horario a reservada en una transaccion',
    EXISTS (
        SELECT 1
        FROM public.listar_citas_paciente_propias() c
        WHERE c.id_cita = current_setting('bloom.cita_creada')::uuid
          AND c.estado = 'pendiente'
          AND c.id_profesional = current_setting('bloom.prof_aprobado_id')::uuid
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public.listar_horarios_disponibles_profesional(
            current_setting('bloom.prof_aprobado_id')::uuid
        ) h
        WHERE h.id_disponibilidad = current_setting('bloom.disp_libre_temprano')::uuid
    )
);

-- Doble toque / reintento del mismo paciente sobre el mismo horario es rechazado (23505)
SELECT pg_temp.comprobar_error(
    'Impide solicitud duplicada del mismo paciente para el mismo horario',
    format(
        $q$SELECT * FROM public.solicitar_cita_paciente(%L::uuid, %L::uuid)$q$,
        current_setting('bloom.prof_aprobado_id'),
        current_setting('bloom.disp_libre_temprano')
    ),
    '23505'
);

-- Solicitud sobre horario bloqueado es rechazada (23P01)
SELECT pg_temp.comprobar_error(
    'Rechaza solicitud sobre horario bloqueado',
    format(
        $q$SELECT * FROM public.solicitar_cita_paciente(%L::uuid, %L::uuid)$q$,
        current_setting('bloom.prof_aprobado_id'),
        current_setting('bloom.disp_bloqueado')
    ),
    '23P01'
);

-- Solicitud sobre profesional pendiente de aprobacion es rechazada (42501)
SELECT pg_temp.comprobar_error(
    'Rechaza solicitud con profesional pendiente de aprobacion',
    format(
        $q$SELECT * FROM public.solicitar_cita_paciente(%L::uuid, %L::uuid)$q$,
        current_setting('bloom.prof_pendiente_usr'),
        current_setting('bloom.disp_prof_pendiente')
    ),
    '42501'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 6. SEGUNDO PACIENTE, CONFLICTO DE HORARIO OCUPADO Y AISLAMIENTO DE MIS CITAS
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_2'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_2'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar_error(
    'Segundo paciente recibe rechazo 23P01 al solicitar un horario ya ocupado',
    format(
        $q$SELECT * FROM public.solicitar_cita_paciente(%L::uuid, %L::uuid)$q$,
        current_setting('bloom.prof_aprobado_id'),
        current_setting('bloom.disp_libre_temprano')
    ),
    '23P01'
);

SELECT pg_temp.comprobar(
    'Paciente 2 no visualiza las citas de Paciente 1 en Mis citas ni en tabla Citas',
    (SELECT count(*) = 0 FROM public.listar_citas_paciente_propias())
    AND (SELECT count(*) = 0 FROM public."Citas")
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 7. RECHAZO DE CUENTA INACTIVA Y REVERSION ANTE FALLO
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_inactivo'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_inactivo'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar_error(
    'Paciente con cuenta inactiva no puede consultar horarios disponibles',
    format(
        $q$SELECT * FROM public.listar_horarios_disponibles_profesional(%L::uuid)$q$,
        current_setting('bloom.prof_aprobado_id')
    ),
    '42501'
);

SELECT pg_temp.comprobar_error(
    'Paciente con cuenta inactiva no puede solicitar citas',
    format(
        $q$SELECT * FROM public.solicitar_cita_paciente(%L::uuid, %L::uuid)$q$,
        current_setting('bloom.prof_aprobado_id'),
        current_setting('bloom.disp_libre_tarde')
    ),
    '42501'
);
RESET ROLE;

-- Verifica que tras todos los rechazos anteriores el horario libre de la tarde
-- sigue en estado 'disponible' y sin ninguna cita asociada (reversion completa).
SELECT pg_temp.comprobar(
    'Operaciones rechazadas revierten por completo sin alterar horario ni crear cita',
    (
        SELECT estado = 'disponible'
        FROM public."Disponibilidad"
        WHERE id_disponibilidad = current_setting('bloom.disp_libre_tarde')::uuid
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public."Citas"
        WHERE id_disponibilidad = current_setting('bloom.disp_libre_tarde')::uuid
    )
);

SELECT numero, prueba, resultado FROM pg_temp.resultados_citas_bloom ORDER BY numero;
ROLLBACK;
