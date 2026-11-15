-- =============================================================================
-- SCRIPT 11 — VERIFICACION TRANSACCIONAL DE CONSULTA Y RESPUESTA DE CITAS (I3-03)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar COMPLETO en Supabase > SQL Editor como postgres (despues de 06, 08 y 10).
--
-- Crea cuentas, horarios y solicitudes ficticias SOLO dentro de esta transaccion
-- y finaliza con ROLLBACK para conservar intactos los datos reales del proyecto.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE resultados_respuesta_citas_bloom(
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    prueba TEXT,
    resultado TEXT
);
GRANT INSERT, SELECT ON pg_temp.resultados_respuesta_citas_bloom TO anon, authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_respuesta_citas_bloom_numero_seq TO anon, authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %', prueba;
    END IF;
    INSERT INTO pg_temp.resultados_respuesta_citas_bloom(prueba, resultado) VALUES(prueba, 'OK');
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
    'Authenticated sin INSERT UPDATE DELETE directos sobre Citas ni Disponibilidad',
    NOT has_table_privilege('authenticated', 'public."Citas"', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public."Citas"', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public."Citas"', 'DELETE')
    AND NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public."Disponibilidad"', 'DELETE')
);

SELECT pg_temp.comprobar(
    'Anon sin ejecucion de RPC de citas del profesional',
    NOT has_function_privilege('anon', 'public.listar_citas_profesional_propias()', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.responder_solicitud_cita_profesional(uuid,text)', 'EXECUTE')
);

-- ---------------------------------------------------------------------------
-- 2. CUENTAS TEMPORALES DE PRUEBA (CON id_profesional DISTINTO DE id_usuario)
-- ---------------------------------------------------------------------------
SELECT set_config('bloom.paciente_1', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.paciente_2', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_1_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_1_id', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_2_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.prof_inactivo_usr', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.fecha_futura_1', ((now() AT TIME ZONE 'America/Guayaquil')::date + 3)::text, TRUE);
SELECT set_config('bloom.fecha_futura_2', ((now() AT TIME ZONE 'America/Guayaquil')::date + 5)::text, TRUE);

INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT current_setting('bloom.' || clave)::uuid,
       'i303-' || current_setting('bloom.' || clave) || '@example.invalid',
       jsonb_build_object('nombre', nombre, 'apellido', apellido, 'rol', rol)
FROM (
    VALUES
        ('paciente_1', 'Lucia', 'Andrade', 'paciente'),
        ('paciente_2', 'Mateo', 'Salazar', 'paciente'),
        ('prof_1_usr', 'Elena', 'Viteri', 'profesional'),
        ('prof_2_usr', 'Carlos', 'Mena', 'profesional'),
        ('prof_inactivo_usr', 'Dario', 'Paredes', 'profesional')
) AS cuentas(clave, nombre, apellido, rol);

UPDATE psicobloom_interno.perfiles_compat
SET aprobacion = 'aprobado'
WHERE id IN (
    current_setting('bloom.prof_1_usr')::uuid,
    current_setting('bloom.prof_2_usr')::uuid,
    current_setting('bloom.prof_inactivo_usr')::uuid
);

UPDATE psicobloom_interno.perfiles_compat
SET cuenta_activa = FALSE
WHERE id = current_setting('bloom.prof_inactivo_usr')::uuid;

-- Asignamos a prof_1_usr un id_profesional distinto de su id_usuario
DELETE FROM psicobloom_interno.detalle_profesional
WHERE id = (
    SELECT id_profesional
    FROM public."Profesionales"
    WHERE id_usuario = current_setting('bloom.prof_1_usr')::uuid
);

UPDATE public."Profesionales"
SET id_profesional = current_setting('bloom.prof_1_id')::uuid,
    modalidad = 'Híbrida'
WHERE id_usuario = current_setting('bloom.prof_1_usr')::uuid;

INSERT INTO psicobloom_interno.detalle_profesional(id)
VALUES (current_setting('bloom.prof_1_id')::uuid);

-- ---------------------------------------------------------------------------
-- 3. CREACION DE HORARIOS Y SOLICITUDES DE CITA
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT set_config(
    'bloom.disp_aceptar',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_1')::date,
            '09:00'::time,
            '09:50'::time
        )
    ),
    TRUE
);

SELECT set_config(
    'bloom.disp_rechazar',
    (
        SELECT id_disponibilidad::text
        FROM public.crear_disponibilidad_profesional_propia(
            current_setting('bloom.fecha_futura_2')::date,
            '15:00'::time,
            '16:00'::time
        )
    ),
    TRUE
);
RESET ROLE;

-- Paciente 1 envia solicitud sobre ambos horarios
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text,
    TRUE
);

SELECT set_config(
    'bloom.cita_para_aceptar',
    (
        SELECT id_cita::text
        FROM public.solicitar_cita_paciente(
            current_setting('bloom.prof_1_id')::uuid,
            current_setting('bloom.disp_aceptar')::uuid
        )
    ),
    TRUE
);

SELECT set_config(
    'bloom.cita_para_rechazar',
    (
        SELECT id_cita::text
        FROM public.solicitar_cita_paciente(
            current_setting('bloom.prof_1_id')::uuid,
            current_setting('bloom.disp_rechazar')::uuid
        )
    ),
    TRUE
);

-- Paciente no puede confirmar ni rechazar usando la RPC del profesional
SELECT pg_temp.comprobar_error(
    'Paciente no puede confirmar ni rechazar citas mediante RPC del profesional',
    format(
        $q$SELECT * FROM public.responder_solicitud_cita_profesional(%L::uuid, 'confirmada')$q$,
        current_setting('bloom.cita_para_aceptar')
    ),
    '42501'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. CONSULTA EXCLUSIVA DE CITAS PROPIAS Y RECHAZO DE ACCESO AJENO / INACTIVO
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_2_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_2_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Profesional 2 no ve las solicitudes de Profesional 1',
    (SELECT count(*) = 0 FROM public.listar_citas_profesional_propias())
);

SELECT pg_temp.comprobar_error(
    'Profesional 2 no puede responder una solicitud de Profesional 1',
    format(
        $q$SELECT * FROM public.responder_solicitud_cita_profesional(%L::uuid, 'confirmada')$q$,
        current_setting('bloom.cita_para_aceptar')
    ),
    '42501'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_inactivo_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_inactivo_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar_error(
    'Profesional con cuenta inactiva no puede consultar citas',
    $q$SELECT * FROM public.listar_citas_profesional_propias()$q$,
    '42501'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5. ACEPTACION DE SOLICITUD PENDIENTE Y PROTECCION FRENTE A DOBLE RESPUESTA
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Profesional 1 lista sus 2 solicitudes propias con nombre del paciente y modalidad',
    (
        SELECT count(*) = 2
           AND bool_and(nombre_paciente = 'Lucia Andrade')
           AND bool_and(modalidad_profesional = 'Híbrida')
           AND bool_and(estado = 'pendiente')
        FROM public.listar_citas_profesional_propias()
    )
);

-- Acepta la primera solicitud
SELECT pg_temp.comprobar(
    'Aceptar solicitud cambia cita a confirmada y mantiene horario en reservada',
    EXISTS (
        SELECT 1
        FROM public.responder_solicitud_cita_profesional(
            current_setting('bloom.cita_para_aceptar')::uuid,
            'confirmada'
        ) r
        WHERE r.id_cita = current_setting('bloom.cita_para_aceptar')::uuid
          AND r.estado = 'confirmada'
          AND r.estado_disponibilidad = 'reservada'
    )
);

-- Doble toque o intento de cambiar una cita ya confirmada es rechazado (23P01)
SELECT pg_temp.comprobar_error(
    'Rechaza segundo intento sobre una solicitud que ya fue confirmada',
    format(
        $q$SELECT * FROM public.responder_solicitud_cita_profesional(%L::uuid, 'rechazada')$q$,
        current_setting('bloom.cita_para_aceptar')
    ),
    '23P01'
);

-- ---------------------------------------------------------------------------
-- 6. RECHAZO DE SOLICITUD PENDIENTE, CONSERVACION HISTORICA Y LIBERACION DE HORARIO
-- ---------------------------------------------------------------------------

-- Provoca un fallo al liberar el horario para verificar atomicidad.
RESET ROLE;
CREATE FUNCTION pg_temp.fallar_liberacion_prueba()
RETURNS TRIGGER LANGUAGE plpgsql AS $trigger_test$
BEGIN
    IF OLD.id_disponibilidad = current_setting('bloom.disp_rechazar')::uuid
       AND NEW.estado = 'disponible' THEN
        RAISE EXCEPTION 'Fallo deliberado de verificacion' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$trigger_test$;
CREATE TRIGGER zz_fallar_liberacion_prueba
BEFORE UPDATE ON public."Disponibilidad"
FOR EACH ROW EXECUTE FUNCTION pg_temp.fallar_liberacion_prueba();
SET LOCAL ROLE authenticated;
SELECT pg_temp.comprobar_error(
    'Fallo deliberado al liberar el horario aborta la respuesta',
    format($q$SELECT * FROM public.responder_solicitud_cita_profesional(%L::uuid, 'rechazada')$q$,
           current_setting('bloom.cita_para_rechazar')), 'P0001');
SELECT pg_temp.comprobar(
    'Tras el fallo la cita sigue pendiente',
    EXISTS(SELECT 1 FROM public.listar_citas_profesional_propias()
           WHERE id_cita=current_setting('bloom.cita_para_rechazar')::uuid AND estado='pendiente'));
SELECT pg_temp.comprobar(
    'Tras el fallo el horario sigue reservado',
    EXISTS(SELECT 1 FROM public.listar_citas_profesional_propias()
           WHERE id_cita=current_setting('bloom.cita_para_rechazar')::uuid AND estado_disponibilidad='reservada'));
RESET ROLE;
DROP TRIGGER zz_fallar_liberacion_prueba ON public."Disponibilidad";
SET LOCAL ROLE authenticated;

SELECT pg_temp.comprobar(
    'Rechazar solicitud conserva la cita como rechazada y libera el horario a disponible',
    EXISTS (
        SELECT 1
        FROM public.responder_solicitud_cita_profesional(
            current_setting('bloom.cita_para_rechazar')::uuid,
            'rechazada'
        ) r
        WHERE r.id_cita = current_setting('bloom.cita_para_rechazar')::uuid
          AND r.estado = 'rechazada'
          AND r.estado_disponibilidad = 'disponible'
    )
);

SELECT pg_temp.comprobar_error(
    'Rechaza doble toque sobre una solicitud que ya fue rechazada',
    format(
        $q$SELECT * FROM public.responder_solicitud_cita_profesional(%L::uuid, 'confirmada')$q$,
        current_setting('bloom.cita_para_rechazar')
    ),
    '23P01'
);
RESET ROLE;


-- Protege la fecha y las horas del historial, permitiendo reutilizar el mismo intervalo.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text, TRUE);
SELECT pg_temp.comprobar_error(
    'No permite editar fecha ni horas de un horario con cita rechazada',
    format($q$SELECT * FROM public.actualizar_disponibilidad_profesional_propia(
        %L::uuid, %L::date, '16:00'::time, '17:00'::time)$q$,
        current_setting('bloom.disp_rechazar'), current_setting('bloom.fecha_futura_2')), '22023');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text, TRUE);
SELECT pg_temp.comprobar(
    'Historial del paciente conserva fecha y horas originales tras rechazo',
    EXISTS(SELECT 1 FROM public.listar_citas_paciente_propias()
           WHERE id_cita=current_setting('bloom.cita_para_rechazar')::uuid
             AND fecha=current_setting('bloom.fecha_futura_2')::date
             AND hora_inicio='15:00'::time AND hora_fin='16:00'::time AND estado='rechazada'));
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 7. ESTADO ACTUALIZADO PARA EL PACIENTE Y NUEVA SOLICITUD EN HORARIO LIBERADO
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Paciente 1 visualiza sus citas actualizadas como confirmada y rechazada en Mis citas',
    EXISTS (
        SELECT 1
        FROM public.listar_citas_paciente_propias() c
        WHERE c.id_cita = current_setting('bloom.cita_para_aceptar')::uuid
          AND c.estado = 'confirmada'
    )
    AND EXISTS (
        SELECT 1
        FROM public.listar_citas_paciente_propias() c
        WHERE c.id_cita = current_setting('bloom.cita_para_rechazar')::uuid
          AND c.estado = 'rechazada'
    )
);
RESET ROLE;

-- Paciente 2 solicita el horario que quedo liberado tras el rechazo
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_2'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente_2'), 'role', 'authenticated')::text,
    TRUE
);

SELECT set_config(
    'bloom.nueva_cita_horario_liberado',
    (
        SELECT id_cita::text
        FROM public.solicitar_cita_paciente(
            current_setting('bloom.prof_1_id')::uuid,
            current_setting('bloom.disp_rechazar')::uuid
        )
    ),
    TRUE
);
RESET ROLE;

SELECT pg_temp.comprobar(
    'Nueva solicitud sobre horario liberado se crea en pendiente sin alterar ni borrar la cita rechazada anterior',
    EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_cita = current_setting('bloom.cita_para_rechazar')::uuid
          AND c.estado = 'rechazada'
    )
    AND EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_cita = current_setting('bloom.nueva_cita_horario_liberado')::uuid
          AND c.estado = 'pendiente'
    )
    AND (
        SELECT estado = 'reservada'
        FROM public."Disponibilidad"
        WHERE id_disponibilidad = current_setting('bloom.disp_rechazar')::uuid
    )
);

-- ---------------------------------------------------------------------------
-- 8. IMPEDIMENTO DE ELIMINAR CITAS HISTORICAS
-- ---------------------------------------------------------------------------
SELECT pg_temp.comprobar_error(
    'Trigger impide eliminar registros historicos de la tabla Citas',
    format(
        $q$DELETE FROM public."Citas" WHERE id_cita = %L::uuid$q$,
        current_setting('bloom.cita_para_rechazar')
    ),
    '42501'
);

SELECT numero, prueba, resultado FROM pg_temp.resultados_respuesta_citas_bloom ORDER BY numero;
ROLLBACK;
