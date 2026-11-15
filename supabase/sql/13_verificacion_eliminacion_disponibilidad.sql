-- PSICOBLOOM: verificacion corregida de eliminacion de horarios.
-- Ejecutar completa como postgres despues del archivo 12.
-- Solo datos ficticios aleatorios; todas las operaciones se revierten al final.
-- No prueba concurrencia entre conexiones independientes.
BEGIN;

CREATE TEMP TABLE resultados_eliminacion_bloom(
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    prueba TEXT,
    resultado TEXT
);
GRANT INSERT, SELECT ON pg_temp.resultados_eliminacion_bloom TO anon, authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_eliminacion_bloom_numero_seq TO anon, authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %', prueba;
    END IF;
    INSERT INTO pg_temp.resultados_eliminacion_bloom(prueba, resultado) VALUES(prueba, 'OK');
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


SELECT pg_temp.comprobar('Sin DELETE directo para anon ni authenticated', NOT has_table_privilege('anon','public."Disponibilidad"','DELETE') AND NOT has_table_privilege('authenticated','public."Disponibilidad"','DELETE'));

SELECT pg_temp.comprobar('RPC sin acceso anon y con permiso authenticated', NOT has_function_privilege('anon','public.eliminar_disponibilidad_profesional_propia(uuid)','EXECUTE') AND has_function_privilege('authenticated','public.eliminar_disponibilidad_profesional_propia(uuid)','EXECUTE'));

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
       'agenda-elim-' || current_setting('bloom.' || clave) || '@example.invalid',
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



RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text, TRUE);

SELECT set_config('bloom.disp_libre', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '08:00'::time, '09:00'::time)), TRUE);

SELECT set_config('bloom.disp_bloqueada', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '09:00'::time, '10:00'::time)), TRUE);

SELECT set_config('bloom.disp_pendiente', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '10:00'::time, '11:00'::time)), TRUE);

SELECT set_config('bloom.disp_confirmada', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '11:00'::time, '12:00'::time)), TRUE);

SELECT set_config('bloom.disp_rechazada', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '12:00'::time, '13:00'::time)), TRUE);

SELECT set_config('bloom.disp_cancelada', (SELECT id_disponibilidad::text FROM public.crear_disponibilidad_profesional_propia(current_setting('bloom.fecha_futura_1')::date, '13:00'::time, '14:00'::time)), TRUE);

SELECT * FROM public.cambiar_estado_disponibilidad_profesional_propia(current_setting('bloom.disp_bloqueada')::uuid, 'bloqueada');

SELECT pg_temp.comprobar_error('Rechaza identificador nulo', $q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(NULL)$q$, '22023');

SELECT pg_temp.comprobar_error('Rechaza identificador inexistente', $q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(gen_random_uuid())$q$, '42501');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_2_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_2_usr'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar_error('Otro profesional no puede eliminar horario ajeno', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_libre')::uuid), '42501');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar_error('Paciente no puede eliminar horarios', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_libre')::uuid), '42501');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_inactivo_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_inactivo_usr'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar_error('Cuenta inactiva no puede eliminar horarios', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_libre')::uuid), '42501');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar('Elimina horario propio disponible y devuelve su identificador', EXISTS(SELECT 1 FROM public.eliminar_disponibilidad_profesional_propia(current_setting('bloom.disp_libre')::uuid) r WHERE r.id_disponibilidad=current_setting('bloom.disp_libre')::uuid));

SELECT pg_temp.comprobar('Horario eliminado ya no aparece en listado propio', NOT EXISTS(SELECT 1 FROM public.listar_disponibilidad_profesional_propia() WHERE id_disponibilidad=current_setting('bloom.disp_libre')::uuid));

SELECT pg_temp.comprobar_error('Reintento de eliminacion no simula exito', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_libre')::uuid), '42501');

SELECT pg_temp.comprobar('Elimina horario propio bloqueado sin citas', EXISTS(SELECT 1 FROM public.eliminar_disponibilidad_profesional_propia(current_setting('bloom.disp_bloqueada')::uuid) r WHERE r.estado='bloqueada'));

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text, TRUE);

SELECT set_config('bloom.cita_pendiente', (SELECT id_cita::text FROM public.solicitar_cita_paciente(current_setting('bloom.prof_1_id')::uuid, current_setting('bloom.disp_pendiente')::uuid)), TRUE);

SELECT set_config('bloom.cita_confirmada', (SELECT id_cita::text FROM public.solicitar_cita_paciente(current_setting('bloom.prof_1_id')::uuid, current_setting('bloom.disp_confirmada')::uuid)), TRUE);

SELECT set_config('bloom.cita_rechazada', (SELECT id_cita::text FROM public.solicitar_cita_paciente(current_setting('bloom.prof_1_id')::uuid, current_setting('bloom.disp_rechazada')::uuid)), TRUE);

SELECT set_config('bloom.cita_cancelada', (SELECT id_cita::text FROM public.solicitar_cita_paciente(current_setting('bloom.prof_1_id')::uuid, current_setting('bloom.disp_cancelada')::uuid)), TRUE);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text, TRUE);

SELECT * FROM public.responder_solicitud_cita_profesional(current_setting('bloom.cita_confirmada')::uuid, 'confirmada');

SELECT * FROM public.responder_solicitud_cita_profesional(current_setting('bloom.cita_rechazada')::uuid, 'rechazada');

RESET ROLE;
-- Preparar una cita historica cancelada como fixture, solo dentro de esta transaccion.
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text, TRUE);
UPDATE public."Citas" SET estado='cancelada' WHERE id_cita=current_setting('bloom.cita_cancelada')::uuid;
UPDATE public."Disponibilidad" SET estado='disponible' WHERE id_disponibilidad=current_setting('bloom.disp_cancelada')::uuid;

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.prof_1_usr'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.prof_1_usr'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar_error('Protege horario con cita pendiente', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_pendiente')::uuid), '22023');

SELECT pg_temp.comprobar_error('Protege horario con cita confirmada', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_confirmada')::uuid), '22023');

SELECT pg_temp.comprobar_error('Protege horario con cita rechazada', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_rechazada')::uuid), '22023');

SELECT pg_temp.comprobar_error('Protege horario con cita cancelada', format($q$SELECT * FROM public.eliminar_disponibilidad_profesional_propia(%L::uuid)$q$, current_setting('bloom.disp_cancelada')::uuid), '22023');

SELECT pg_temp.comprobar('Listado informa historial rechazado y cancelado', (SELECT count(*)=2 AND bool_and(tiene_cita_vinculada) FROM public.listar_disponibilidad_profesional_propia() WHERE id_disponibilidad IN (current_setting('bloom.disp_rechazada')::uuid,current_setting('bloom.disp_cancelada')::uuid)));

SELECT pg_temp.comprobar_error('No modifica fecha ni horas del historial rechazado', format($q$SELECT * FROM public.actualizar_disponibilidad_profesional_propia(%L::uuid,%L::date,'15:00'::time,'16:00'::time)$q$, current_setting('bloom.disp_rechazada')::uuid,current_setting('bloom.fecha_futura_1')), '22023');

SELECT pg_temp.comprobar('Puede bloquear intervalo rechazado conservando historial', EXISTS(SELECT 1 FROM public.cambiar_estado_disponibilidad_profesional_propia(current_setting('bloom.disp_rechazada')::uuid,'bloqueada') WHERE estado='bloqueada' AND tiene_cita_vinculada));

SELECT pg_temp.comprobar('Puede desbloquear intervalo rechazado conservando historial', EXISTS(SELECT 1 FROM public.cambiar_estado_disponibilidad_profesional_propia(current_setting('bloom.disp_rechazada')::uuid,'disponible') WHERE estado='disponible' AND tiene_cita_vinculada));

SELECT pg_temp.comprobar_error('Cliente no puede borrar directamente saltando RPC', format($q$DELETE FROM public."Disponibilidad" WHERE id_disponibilidad=%L::uuid$q$, current_setting('bloom.disp_rechazada')::uuid), '42501');

RESET ROLE;

SELECT pg_temp.comprobar_error('Trigger protege historial incluso ante DELETE como postgres', format($q$DELETE FROM public."Disponibilidad" WHERE id_disponibilidad=%L::uuid$q$, current_setting('bloom.disp_rechazada')::uuid), '22023');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente_1'), TRUE);
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('bloom.paciente_1'), 'role', 'authenticated')::text, TRUE);

SELECT pg_temp.comprobar('Paciente conserva fecha y horas de cita rechazada', EXISTS(SELECT 1 FROM public.listar_citas_paciente_propias() WHERE id_cita=current_setting('bloom.cita_rechazada')::uuid AND estado='rechazada' AND fecha=current_setting('bloom.fecha_futura_1')::date AND hora_inicio='12:00'::time AND hora_fin='13:00'::time));

RESET ROLE;

SELECT pg_temp.comprobar('Solo desaparecieron los dos intervalos eliminados sin citas', (SELECT count(*)=4 FROM public."Disponibilidad" WHERE id_profesional=current_setting('bloom.prof_1_id')::uuid));

SELECT numero, prueba, resultado FROM pg_temp.resultados_eliminacion_bloom ORDER BY numero;
ROLLBACK;
