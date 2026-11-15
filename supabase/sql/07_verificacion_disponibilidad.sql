-- =============================================================================
-- SCRIPT 7 — VERIFICACION TRANSACCIONAL DE DISPONIBILIDAD DEL PROFESIONAL (I3-01)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar COMPLETO en Supabase > SQL Editor como postgres (despues de 06).
--
-- Crea cuentas y horarios ficticios SOLO dentro de esta transaccion y finaliza
-- con ROLLBACK para no alterar los datos reales del proyecto.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE resultados_disponibilidad_bloom(
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    prueba TEXT,
    resultado TEXT
);
GRANT INSERT, SELECT ON pg_temp.resultados_disponibilidad_bloom TO anon, authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_disponibilidad_bloom_numero_seq TO anon, authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %', prueba;
    END IF;
    INSERT INTO pg_temp.resultados_disponibilidad_bloom(prueba, resultado) VALUES(prueba, 'OK');
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


-- Privilegios: las escrituras de la app pasan por las RPC.
SELECT pg_temp.comprobar(
    'Authenticated sin INSERT UPDATE DELETE directos sobre Disponibilidad',
    NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'DELETE')
);
SELECT pg_temp.comprobar(
    'Anon sin lectura de Disponibilidad ni ejecucion de las RPC',
    NOT has_table_privilege('anon', 'public."Disponibilidad"', 'SELECT')
    AND NOT has_function_privilege('anon','public.listar_disponibilidad_profesional_propia()','EXECUTE')
    AND NOT has_function_privilege('anon','public.crear_disponibilidad_profesional_propia(date,time,time)','EXECUTE')
    AND NOT has_function_privilege('anon','public.actualizar_disponibilidad_profesional_propia(uuid,date,time,time)','EXECUTE')
    AND NOT has_function_privilege('anon','public.cambiar_estado_disponibilidad_profesional_propia(uuid,text)','EXECUTE')
);

-- ---------------------------------------------------------------------------
-- 1. CUENTAS TEMPORALES DE PRUEBA (CON id_profesional DISTINTO DE id_usuario)
-- ---------------------------------------------------------------------------
SELECT set_config('bloom.paciente', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_aprobado_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_aprobado_id', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_pendiente_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_inactivo_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.fecha_futura', ((now() AT TIME ZONE 'America/Guayaquil')::date + 5)::text, TRUE);
SELECT set_config('bloom.fecha_pasada', ((now() AT TIME ZONE 'America/Guayaquil')::date - 2)::text, TRUE);

INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT current_setting('bloom.' || clave)::uuid,
       'disp-' || current_setting('bloom.' || clave) || '@example.invalid',
       jsonb_build_object('nombre', 'Prueba', 'apellido', 'Horario', 'rol', rol)
FROM (
    VALUES
        ('paciente', 'paciente'),
        ('prof_aprobado_usr', 'profesional'),
        ('prof_pendiente_usr', 'profesional'),
        ('prof_inactivo_usr', 'profesional')
) AS cuentas(clave, rol);

UPDATE psicobloom_interno.perfiles_compat
SET aprobacion = 'aprobado'
WHERE id = current_setting('bloom.prof_aprobado_usr')::uuid;

UPDATE psicobloom_interno.perfiles_compat
SET cuenta_activa = FALSE
WHERE id = current_setting('bloom.prof_inactivo_usr')::uuid;

-- Asignamos a prof_aprobado_usr un id_profesional distinto de su id_usuario
-- para verificar que las RPC y politicas resuelven Profesionales.id_usuario = auth.uid().
DELETE FROM psicobloom_interno.detalle_profesional WHERE id = (SELECT id_profesional FROM public."Profesionales" WHERE id_usuario=current_setting('bloom.prof_aprobado_usr')::uuid);
UPDATE public."Profesionales"
SET id_profesional = current_setting('bloom.prof_aprobado_id')::uuid
WHERE id_usuario = current_setting('bloom.prof_aprobado_usr')::uuid;

INSERT INTO psicobloom_interno.detalle_profesional(id) VALUES(current_setting('bloom.prof_aprobado_id')::uuid);

-- ---------------------------------------------------------------------------
-- 2. CREACION, INTERVALOS CONTIGUOS, ORDENAMIENTO Y RECHAZO DE SOLAPAMIENTOS
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_aprobado_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_aprobado_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar_error(
    'Profesional no altera la tabla directamente para evitar las RPC',
    $q$UPDATE public."Disponibilidad" SET estado='bloqueada'$q$,
    '42501'
);

-- Crear primer horario futuro (10:00 a 10:45)
SELECT set_config(
    'bloom.disp_1',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura')::date,
            '10:00'::time,
            '10:45'::time
        )
    ),
    TRUE
);

-- Crear intervalo contiguo anterior (09:15 a 10:00) -> debe permitirse y ordenarse antes
SELECT set_config(
    'bloom.disp_2',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura')::date,
            '09:15'::time,
            '10:00'::time
        )
    ),
    TRUE
);

SELECT pg_temp.comprobar(
    'Resuelve id_profesional distinto de id_usuario y ordena horarios por fecha y hora',
    (
        SELECT count(*) = 2
           AND (array_agg(hora_inicio ORDER BY fecha, hora_inicio))[1] = '09:15'::time
           AND (array_agg(id_profesional))[1] = current_setting('bloom.prof_aprobado_id')::uuid
        FROM public.listar_disponibilidad_profesional_propia()
    )
);

-- Rechazar fecha pasada
SELECT pg_temp.comprobar_error(
    'Rechaza creacion de intervalo en fecha pasada',
    format(
        $q$SELECT * FROM public.crear_disponibilidad_profesional_propia(%L::date, '09:00'::time, '10:00'::time)$q$,
        current_setting('bloom.fecha_pasada')
    ),
    '22023'
);

-- Rechazar hora_fin <= hora_inicio
SELECT pg_temp.comprobar_error(
    'Rechaza intervalo con hora final menor o igual a la inicial',
    format(
        $q$SELECT * FROM public.crear_disponibilidad_profesional_propia(%L::date, '11:00'::time, '11:00'::time)$q$,
        current_setting('bloom.fecha_futura')
    ),
    '23514'
);

-- Rechazar solapamiento parcial (09:30 a 10:15 se superpone con 09:15-10:00 y 10:00-10:45)
SELECT pg_temp.comprobar_error(
    'Rechaza intervalo superpuesto en la misma fecha',
    format(
        $q$SELECT * FROM public.crear_disponibilidad_profesional_propia(%L::date, '09:30'::time, '10:15'::time)$q$,
        current_setting('bloom.fecha_futura')
    ),
    '23P01'
);

-- Editar horario disponible futuro (10:00-10:45 -> 10:00-11:15)
SELECT * FROM public.actualizar_disponibilidad_profesional_propia(
    current_setting('bloom.disp_1')::uuid,
    current_setting('bloom.fecha_futura')::date,
    '10:00'::time,
    '11:15'::time
);

SELECT pg_temp.comprobar(
    'Edita horario futuro disponible correctamente',
    (
        SELECT hora_fin = '11:15'::time
        FROM public.listar_disponibilidad_profesional_propia()
        WHERE id_disponibilidad = current_setting('bloom.disp_1')::uuid
    )
);

-- Bloquear y desbloquear horario no reservado
SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(
    current_setting('bloom.disp_1')::uuid,
    'bloqueada'
);
SELECT pg_temp.comprobar(
    'Bloquea horario propio no reservado',
    (
        SELECT estado = 'bloqueada'
        FROM public.listar_disponibilidad_profesional_propia()
        WHERE id_disponibilidad = current_setting('bloom.disp_1')::uuid
    )
);

SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(
    current_setting('bloom.disp_1')::uuid,
    'disponible'
);
SELECT pg_temp.comprobar(
    'Desbloquea horario propio bloqueado',
    (
        SELECT estado = 'disponible'
        FROM public.listar_disponibilidad_profesional_propia()
        WHERE id_disponibilidad = current_setting('bloom.disp_1')::uuid
    )
);

-- Impedir asignar manualmente 'reservada'
SELECT pg_temp.comprobar_error(
    'Impide cambiar manualmente el estado a reservada',
    format(
        $q$SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(%L::uuid, 'reservada')$q$,
        current_setting('bloom.disp_1')
    ),
    '22023'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. ACCESO AJENO, CUENTA INACTIVA Y PROFESIONAL PENDIENTE VS PACIENTE
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_pendiente_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_pendiente_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Profesional no ve horarios de otro profesional',
    (SELECT count(*) = 0 FROM public.listar_disponibilidad_profesional_propia())
);

SELECT pg_temp.comprobar_error(
    'Profesional no puede modificar ni bloquear horario ajeno',
    format(
        $q$SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(%L::uuid, 'bloqueada')$q$,
        current_setting('bloom.disp_1')
    ),
    '42501'
);

-- Profesional pendiente puede configurar su horario propio, pero no sera visible ni reservable por pacientes
SELECT set_config(
    'bloom.disp_pendiente',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura')::date,
            '14:00'::time,
            '14:50'::time
        )
    ),
    TRUE
);
RESET ROLE;

-- Profesional con cuenta inactiva no puede consultar ni crear horarios
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_inactivo_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_inactivo_usr'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar_error(
    'Profesional con cuenta inactiva no consulta disponibilidad',
    $q$SELECT * FROM public.listar_disponibilidad_profesional_propia()$q$,
    '42501'
);
RESET ROLE;

-- Paciente activo solo ve horarios disponibles de profesionales aprobados (no ve los del profesional pendiente)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar(
    'Paciente ve horarios disponibles del aprobado y ninguno del profesional pendiente',
    EXISTS (
        SELECT 1 FROM public."Disponibilidad"
        WHERE id_disponibilidad = current_setting('bloom.disp_1')::uuid
    )
    AND NOT EXISTS (
        SELECT 1 FROM public."Disponibilidad"
        WHERE id_disponibilidad = current_setting('bloom.disp_pendiente')::uuid
    )
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. PROTECCION DE HORARIOS RESERVADOS Y VINCULADOS A CITAS
-- ---------------------------------------------------------------------------
-- Vinculamos una cita en public."Citas" al horario disp_2 del profesional aprobado
INSERT INTO public."Citas" (
    id_paciente,
    id_profesional,
    id_disponibilidad,
    estado
)
VALUES (
    current_setting('bloom.paciente')::uuid,
    current_setting('bloom.prof_aprobado_id')::uuid,
    current_setting('bloom.disp_2')::uuid,
    'confirmada'
);

UPDATE public."Disponibilidad"
SET estado = 'reservada'
WHERE id_disponibilidad = current_setting('bloom.disp_2')::uuid;

-- Comprobar que public."Citas" rechaza reservas con profesionales pendientes de aprobacion
SELECT pg_temp.comprobar_error(
    'Trigger en Citas impide reservar horario de profesional no aprobado',
    format(
        $q$INSERT INTO public."Citas"(id_paciente, id_profesional, id_disponibilidad, estado)
           VALUES (%L::uuid, %L::uuid, %L::uuid, 'pendiente')$q$,
        current_setting('bloom.paciente'),
        current_setting('bloom.prof_pendiente_usr'),
        current_setting('bloom.disp_pendiente')
    ),
    '42501'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_aprobado_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_aprobado_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar_error(
    'Impide editar fecha u hora de horario reservado o con cita vinculada',
    format(
        $q$SELECT * FROM public.actualizar_disponibilidad_profesional_propia(%L::uuid, %L::date, '08:00'::time, '09:00'::time)$q$,
        current_setting('bloom.disp_2'),
        current_setting('bloom.fecha_futura')
    ),
    '22023'
);

SELECT pg_temp.comprobar_error(
    'Impide bloquear o desbloquear horario reservado o con cita activa',
    format(
        $q$SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(%L::uuid, 'bloqueada')$q$,
        current_setting('bloom.disp_2')
    ),
    '22023'
);
RESET ROLE;

SELECT numero, prueba, resultado FROM pg_temp.resultados_disponibilidad_bloom ORDER BY numero;
ROLLBACK;
