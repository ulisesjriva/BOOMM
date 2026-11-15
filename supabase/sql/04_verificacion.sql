-- =============================================================================
-- SCRIPT 4 — VERIFICACION TRANSACCIONAL CONTRA public Y psicobloom_interno
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencias:
--   - esquema_real_psicobloom.json (esquema public y storage)
--   - exportacion complementaria de psicobloom_interno
-- Ejecutar COMPLETO en Supabase > SQL Editor como postgres (despues de 05).
--
-- Crea cuentas ficticias SOLO dentro de esta transaccion. No envia correos.
-- El ROLLBACK final elimina las cuentas y revierte todas las modificaciones.
-- Si algo falla, NO ejecutar COMMIT: ejecutar ROLLBACK y compartir el error.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE resultados_bloom(
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    prueba TEXT,
    resultado TEXT
);
GRANT INSERT, SELECT ON pg_temp.resultados_bloom TO anon, authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_bloom_numero_seq TO anon, authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %', prueba;
    END IF;
    INSERT INTO pg_temp.resultados_bloom(prueba, resultado) VALUES(prueba, 'OK');
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
-- 1. CREACION DE CUENTAS TEMPORALES DE PRUEBA (UUID aleatorios)
-- ---------------------------------------------------------------------------
SELECT set_config('bloom.paciente', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.otro', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.pendiente', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.aprobado', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.admin', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.inactivo', gen_random_uuid()::text, TRUE);
SELECT set_config('bloom.falso_admin', gen_random_uuid()::text, TRUE);

INSERT INTO auth.users(id, email, raw_user_meta_data)
SELECT current_setting('bloom.' || nombre)::uuid,
       'prueba-' || current_setting('bloom.' || nombre) || '@example.invalid',
       jsonb_build_object('nombre', 'Prueba', 'apellido', 'Bloom', 'rol', rol)
FROM (
    VALUES
        ('paciente', 'paciente'),
        ('otro', 'paciente'),
        ('pendiente', 'profesional'),
        ('aprobado', 'profesional'),
        ('admin', 'paciente'),
        ('inactivo', 'paciente'),
        ('falso_admin', 'administrador')
) AS cuentas(nombre, rol);

-- Promocion SOLO de las cuentas temporales mediante psicobloom_interno.perfiles_compat
-- (dispara escribir_perfil_compat y preparar_usuario_pdf -> public."Administradores").
UPDATE psicobloom_interno.perfiles_compat
SET rol = 'administrador'
WHERE id IN (
    current_setting('bloom.admin')::uuid,
    current_setting('bloom.inactivo')::uuid
);

UPDATE psicobloom_interno.perfiles_compat
SET cuenta_activa = FALSE
WHERE id = current_setting('bloom.inactivo')::uuid;

UPDATE psicobloom_interno.perfiles_compat
SET aprobacion = 'aprobado'
WHERE id = current_setting('bloom.aprobado')::uuid;

-- Comprobaciones sobre public."Usuarios", public."Roles", public."Pacientes",
-- public."Profesionales", public."Administradores" y psicobloom_interno
SELECT pg_temp.comprobar(
    'Metadatos no asignan administrador en public."Usuarios"',
    (
        SELECT r.nombre_rol = 'paciente'
        FROM public."Usuarios" u
        JOIN public."Roles" r ON r.id_rol = u.id_rol
        WHERE u.id_usuario = current_setting('bloom.falso_admin')::uuid
    )
    AND EXISTS (
        SELECT 1 FROM public."Pacientes" pa
        WHERE pa.id_usuario = current_setting('bloom.falso_admin')::uuid
    )
    AND NOT EXISTS (
        SELECT 1 FROM public."Administradores" ad
        WHERE ad.id_usuario = current_setting('bloom.falso_admin')::uuid
    )
);

SELECT pg_temp.comprobar(
    'Triggers crean filas en public."Profesionales", detalle_profesional y revisiones_profesionales',
    EXISTS (
        SELECT 1 FROM public."Profesionales" pr
        JOIN psicobloom_interno.detalle_profesional dp ON dp.id = pr.id_profesional
        WHERE pr.id_usuario = current_setting('bloom.pendiente')::uuid
    )
    AND EXISTS (
        SELECT 1 FROM psicobloom_interno.revisiones_profesionales rv
        WHERE rv.id = current_setting('bloom.pendiente')::uuid
    )
);

UPDATE auth.users
SET email = 'cambio-' || id::text || '@example.invalid'
WHERE id = current_setting('bloom.otro')::uuid;

SELECT pg_temp.comprobar(
    'Correo sincronizado desde Auth hacia public."Usuarios"',
    (
        SELECT u.correo = au.email
        FROM public."Usuarios" u
        JOIN auth.users au ON au.id = u.id_usuario
        WHERE u.id_usuario = current_setting('bloom.otro')::uuid
    )
);

-- ---------------------------------------------------------------------------
-- 2. VERIFICACION DE RLS Y PRIVILEGIOS EFECTIVOS EN TABLAS Y FUNCIONES REALES
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    tabla_nombre TEXT;
    col_protegida TEXT;
    funcion_firma TEXT;
BEGIN
    FOREACH tabla_nombre IN ARRAY ARRAY[
        'public."Roles"',
        'public."Usuarios"',
        'public."Pacientes"',
        'public."Profesionales"',
        'public."Administradores"',
        'public."Especialidades"',
        'public."ProfesionalEspecialidad"',
        'public."Servicios"',
        'psicobloom_interno.estado_usuario',
        'psicobloom_interno.detalle_profesional',
        'psicobloom_interno.revisiones_profesionales',
        'psicobloom_interno.cambios_estado_cuenta'
    ] LOOP
        PERFORM pg_temp.comprobar(
            'RLS habilitado: ' || tabla_nombre,
            (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = tabla_nombre::regclass)
        );
        PERFORM pg_temp.comprobar(
            'Anon sin SELECT: ' || tabla_nombre,
            NOT has_table_privilege('anon', tabla_nombre, 'SELECT')
        );
    END LOOP;

    FOREACH tabla_nombre IN ARRAY ARRAY[
        'public."Roles"',
        'public."Usuarios"',
        'public."Pacientes"',
        'public."Profesionales"',
        'public."Administradores"',
        'public."Especialidades"'
    ] LOOP
        PERFORM pg_temp.comprobar(
            'Authenticated sin INSERT ni DELETE directos: ' || tabla_nombre,
            NOT has_table_privilege('authenticated', tabla_nombre, 'INSERT')
            AND NOT has_table_privilege('authenticated', tabla_nombre, 'DELETE')
        );
    END LOOP;

    FOREACH col_protegida IN ARRAY ARRAY[
        'id_usuario',
        'correo',
        'activo',
        'fecha_registro',
        'id_rol'
    ] LOOP
        PERFORM pg_temp.comprobar(
            'Columna protegida en public."Usuarios": ' || col_protegida,
            NOT has_column_privilege('authenticated', 'public."Usuarios"', col_protegida, 'UPDATE')
        );
    END LOOP;

    FOREACH funcion_firma IN ARRAY ARRAY[
        'public._rol_activo()',
        'public._es_profesional_propio(uuid)',
        'public._profesional_es_publicable(uuid)',
        'public._especialidad_esta_activa(uuid)',
        'public._profesional_tiene_especialidad_propia(uuid)',
        'public.perfil_del_usuario_actual()',
        'public.verificar_acceso_usuario()',
        'public.actualizar_nombre_apellido(text,text)',
        'public.directorio_profesionales()',
        'public.directorio_profesionales_completo()',
        'public.obtener_perfil_profesional_propio()',
        'public.guardar_especialidades_profesional(uuid[])',
        'public.actualizar_foto_profesional_propia(text)',
        'public.actualizar_perfil_profesional_propio(text,text,uuid[],text,text,integer,text,text,text,text,text,numeric,numeric)',
        'public.listar_profesionales_pendientes()',
        'public.aprobar_profesional(uuid,public.estado_aprobacion,text)',
        'public.consultar_motivo_rechazo_propio()',
        'public.cambiar_estado_cuenta(uuid,boolean,text)'
    ] LOOP
        PERFORM pg_temp.comprobar(
            'Anon sin EXECUTE: ' || funcion_firma,
            NOT has_function_privilege('anon', funcion_firma, 'EXECUTE')
        );
        PERFORM pg_temp.comprobar(
            'Authenticated con EXECUTE: ' || funcion_firma,
            has_function_privilege('authenticated', funcion_firma, 'EXECUTE')
        );
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. PRUEBAS CON ROL ANON
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', TRUE);
SELECT set_config('request.jwt.claims', '{}', TRUE);

SELECT pg_temp.comprobar_error(
    'Anon no lee public."Usuarios"',
    $consulta$SELECT * FROM public."Usuarios"$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Anon no llama directorio_profesionales',
    $consulta$SELECT * FROM public.directorio_profesionales()$consulta$,
    '42501'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. PRUEBAS CON ROL AUTHENTICATED (PACIENTE ACTIVO)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Paciente lee solo su propia fila en public."Usuarios"',
    (SELECT count(*) = 1 FROM public."Usuarios")
);
SELECT pg_temp.comprobar_error(
    'Paciente no tiene lectura directa sobre Pacientes',
    $consulta$SELECT * FROM public."Pacientes"$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no tiene lectura directa sobre Administradores',
    $consulta$SELECT * FROM public."Administradores"$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no tiene lectura directa sobre AuditoriaAdministrativa',
    $consulta$SELECT * FROM public."AuditoriaAdministrativa"$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no accede al esquema psicobloom_interno',
    $consulta$SELECT * FROM psicobloom_interno.revisiones_profesionales$consulta$,
    '42501'
);

SELECT public.actualizar_nombre_apellido('Nombre', 'Actualizado');
SELECT pg_temp.comprobar(
    'Paciente actualiza nombre propio mediante RPC',
    (SELECT nombres = 'Nombre' AND apellidos = 'Actualizado' FROM public."Usuarios" WHERE id_usuario = auth.uid())
);

WITH cambios AS (
    UPDATE public."Usuarios"
    SET nombres = 'Intruso'
    WHERE id_usuario = current_setting('bloom.otro')::uuid
    RETURNING id_usuario
)
SELECT pg_temp.comprobar('Paciente no modifica usuario ajeno', count(*) = 0)
FROM cambios;

SELECT pg_temp.comprobar_error(
    'Paciente no cambia id_rol en public."Usuarios"',
    $consulta$UPDATE public."Usuarios" SET id_rol = gen_random_uuid() WHERE id_usuario = auth.uid()$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no cambia estado activo en public."Usuarios"',
    $consulta$UPDATE public."Usuarios" SET activo = FALSE WHERE id_usuario = auth.uid()$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no lista profesionales pendientes',
    $consulta$SELECT * FROM public.listar_profesionales_pendientes()$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no aprueba profesional',
    $consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid, 'aprobado', NULL)$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no bloquea cuentas',
    $consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.otro')::uuid, FALSE, 'Prueba bloqueo')$consulta$,
    '42501'
);
SELECT pg_temp.comprobar(
    'Directorio incluye profesional aprobado',
    (SELECT EXISTS(SELECT 1 FROM public.directorio_profesionales() WHERE id = current_setting('bloom.aprobado')::uuid))
);
SELECT pg_temp.comprobar(
    'Directorio excluye profesional pendiente',
    (SELECT NOT EXISTS(SELECT 1 FROM public.directorio_profesionales() WHERE id = current_setting('bloom.pendiente')::uuid))
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5. PRUEBAS CON ROL AUTHENTICATED (PROFESIONAL PENDIENTE)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.pendiente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.pendiente'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Profesional solo lee su propio registro en public."Profesionales"',
    (SELECT count(*) = 1 FROM public."Profesionales")
);

UPDATE public."Profesionales"
SET descripcion = 'Atención clínica inicial'
WHERE id_usuario = auth.uid();

SELECT pg_temp.comprobar(
    'Profesional pendiente edita su descripcion en public."Profesionales"',
    (SELECT descripcion = 'Atención clínica inicial' FROM public."Profesionales" WHERE id_usuario = auth.uid())
);

SELECT pg_temp.comprobar_error(
    'Profesional no se autoaprueba',
    $consulta$SELECT public.aprobar_profesional(auth.uid(), 'aprobado', NULL)$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Profesional no lee notas internas en psicobloom_interno',
    $consulta$SELECT * FROM psicobloom_interno.revisiones_profesionales$consulta$,
    '42501'
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 6. PRUEBAS CON ROL AUTHENTICATED (ADMINISTRADOR ACTIVO Y REVISIONES)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.admin'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.admin'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Admin lista profesionales pendientes',
    (SELECT EXISTS(SELECT 1 FROM public.listar_profesionales_pendientes() WHERE id = current_setting('bloom.pendiente')::uuid))
);
SELECT pg_temp.comprobar_error(
    'Decision nula rechazada',
    $consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid, NULL, NULL)$consulta$,
    '22023'
);
SELECT pg_temp.comprobar_error(
    'Rechazo exige motivo de al menos 5 caracteres',
    $consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid, 'rechazado', NULL)$consulta$,
    '22023'
);
SELECT pg_temp.comprobar_error(
    'Estado nulo rechazado',
    $consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid, NULL, 'Motivo prueba')$consulta$,
    '22023'
);
SELECT pg_temp.comprobar_error(
    'Bloqueo exige motivo',
    $consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid, FALSE, NULL)$consulta$,
    '22023'
);
SELECT pg_temp.comprobar_error(
    'Admin no revisa su propia cuenta',
    $consulta$SELECT public.aprobar_profesional(auth.uid(), 'aprobado', NULL)$consulta$,
    '42501'
);

SELECT public.aprobar_profesional(
    current_setting('bloom.pendiente')::uuid,
    'rechazado',
    'Documento incompleto'
);
RESET ROLE;

-- Comprobacion de rechazo por el propio profesional mediante RPC
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.pendiente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.pendiente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar(
    'Profesional consulta su motivo de rechazo mediante RPC',
    (SELECT aprobacion = 'rechazado' AND motivo_rechazo = 'Documento incompleto' FROM public.consultar_motivo_rechazo_propio())
);
RESET ROLE;

-- Aprobacion y bloqueo de cuenta por administrador activo
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.admin'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.admin'), 'role', 'authenticated')::text,
    TRUE
);
SELECT public.aprobar_profesional(
    current_setting('bloom.pendiente')::uuid,
    'aprobado',
    'Nota interna de prueba'
);
SELECT public.cambiar_estado_cuenta(
    current_setting('bloom.paciente')::uuid,
    FALSE,
    'Bloqueo de prueba'
);
RESET ROLE;

SELECT pg_temp.comprobar(
    'Aprobacion registrada en estado_usuario y reflejar_validador_pdf actualiza public."Profesionales"',
    (
        SELECT aprobacion = 'aprobado'
        FROM psicobloom_interno.estado_usuario
        WHERE id = current_setting('bloom.pendiente')::uuid
    )
    AND (
        SELECT id_administrador_validador = current_setting('bloom.admin')::uuid
        FROM public."Profesionales"
        WHERE id_usuario = current_setting('bloom.pendiente')::uuid
    )
);
SELECT pg_temp.comprobar(
    'Historial registra bloqueo de paciente en psicobloom_interno.cambios_estado_cuenta',
    (
        SELECT count(*) = 1
        FROM psicobloom_interno.cambios_estado_cuenta
        WHERE usuario_id = current_setting('bloom.paciente')::uuid
          AND responsable_id = current_setting('bloom.admin')::uuid
          AND estado_nuevo = FALSE
    )
);

-- ---------------------------------------------------------------------------
-- 7. PRUEBAS CON CUENTAS INACTIVAS (PACIENTE Y ADMINISTRADOR)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar(
    'Paciente inactivo puede leer su estado propio',
    (SELECT activo = FALSE FROM public."Usuarios" WHERE id_usuario = auth.uid())
    AND (SELECT cuenta_activa = FALSE FROM public.perfil_del_usuario_actual())
);
SELECT pg_temp.comprobar_error(
    'Paciente inactivo no edita mediante RPC',
    $consulta$SELECT public.actualizar_nombre_apellido('Nombre', 'Prohibido')$consulta$,
    '42501'
);
WITH cambios AS (
    UPDATE public."Usuarios"
    SET nombres = 'Prohibido'
    WHERE id_usuario = auth.uid()
    RETURNING id_usuario
)
SELECT pg_temp.comprobar('Paciente inactivo no edita directamente', count(*) = 0)
FROM cambios;
SELECT pg_temp.comprobar_error(
    'Paciente inactivo no consulta directorio',
    $consulta$SELECT * FROM public.directorio_profesionales()$consulta$,
    '42501'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.inactivo'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.inactivo'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar_error(
    'Admin inactivo no lista pendientes',
    $consulta$SELECT * FROM public.listar_profesionales_pendientes()$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Admin inactivo no aprueba',
    $consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid, 'aprobado', NULL)$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Admin inactivo no reactiva cuentas',
    $consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid, TRUE, 'Reactivacion prohibida')$consulta$,
    '42501'
);
SELECT pg_temp.comprobar(
    'Admin inactivo solo lee su propia fila en public."Usuarios"',
    (SELECT count(*) = 1 FROM public."Usuarios")
);
RESET ROLE;

-- Reactivacion de paciente por admin activo
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.admin'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.admin'), 'role', 'authenticated')::text,
    TRUE
);
SELECT public.cambiar_estado_cuenta(
    current_setting('bloom.paciente')::uuid,
    TRUE,
    'Reactivacion de prueba'
);
RESET ROLE;

SELECT pg_temp.comprobar(
    'Historial conserva bloqueo y reactivacion',
    (
        SELECT count(*) = 2
        FROM psicobloom_interno.cambios_estado_cuenta
        WHERE usuario_id = current_setting('bloom.paciente')::uuid
    )
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT public.actualizar_nombre_apellido('Cuenta', 'Reactivada');
SELECT pg_temp.comprobar(
    'Cuenta reactivada vuelve a operar',
    (SELECT nombres = 'Cuenta' FROM public."Usuarios" WHERE id_usuario = auth.uid())
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 8. VERIFICACIONES DE 05_perfiles_especialidades_ubicacion.sql
--    (public."Especialidades", public."ProfesionalEspecialidad",
--     public."Servicios", public."Profesionales", psicobloom_interno.detalle_profesional
--     y RPCs nuevas)
-- ---------------------------------------------------------------------------
SELECT pg_temp.comprobar(
    'Catalogo public."Especialidades" con datos iniciales activos',
    (SELECT count(*) >= 5 FROM public."Especialidades" WHERE activa = TRUE)
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar_error(
    'Paciente no modifica catalogo public."Especialidades"',
    $consulta$INSERT INTO public."Especialidades"(nombre, descripcion) VALUES('Intrusa', 'No permitida')$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no guarda especialidades profesionales',
    $consulta$SELECT public.guardar_especialidades_profesional(ARRAY[]::uuid[])$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no actualiza fotografia profesional',
    $consulta$SELECT public.actualizar_foto_profesional_propia('https://ejemplo.com/foto.jpg')$consulta$,
    '42501'
);
SELECT pg_temp.comprobar_error(
    'Paciente no consulta perfil profesional propio',
    $consulta$SELECT * FROM public.obtener_perfil_profesional_propio()$consulta$,
    '42501'
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.aprobado'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.aprobado'), 'role', 'authenticated')::text,
    TRUE
);

SELECT public.actualizar_perfil_profesional_propio(
    'Doctora',
    'Aprobada',
    ARRAY(SELECT id_especialidad FROM public."Especialidades" WHERE activa = TRUE ORDER BY nombre LIMIT 2),
    'MSP-102938',
    'Especialista en evaluación y acompañamiento psicológico.',
    6,
    '0991234567',
    'https://hteasqflwhfvlckubvio.supabase.co/storage/v1/object/public/fotos-profesionales/prueba.jpg',
    'Híbrida',
    'Evaluación psicológica, Psicoterapia individual',
    'Av. Daniel León Borja, Riobamba',
    -1.6709800,
    -78.6471200
);

SELECT public.actualizar_foto_profesional_propia(
    'https://hteasqflwhfvlckubvio.supabase.co/storage/v1/object/public/fotos-profesionales/nueva.jpg'
);

SELECT pg_temp.comprobar(
    'Profesional actualiza perfil, modalidad, foto, servicios, especialidades y coordenadas',
    (
        SELECT modalidad = 'Híbrida'
           AND array_length(especialidades_ids, 1) = 2
           AND numero_registro = 'MSP-102938'
           AND telefono_contacto = '0991234567'
           AND foto_url LIKE '%/nueva.jpg'
           AND abs(latitud - (-1.67098)) < 0.0001
           AND abs(longitud - (-78.64712)) < 0.0001
           AND position('Evaluación psicológica' IN COALESCE(servicios, '')) > 0
        FROM public.obtener_perfil_profesional_propio()
    )
);

SELECT pg_temp.comprobar_error(
    'Restriccion en public."Profesionales" rechaza latitud fuera de rango',
    $consulta$UPDATE public."Profesionales" SET latitud = 120, longitud = -78.64 WHERE id_usuario = auth.uid()$consulta$,
    '23514'
);

SELECT pg_temp.comprobar(
    'Relacion public."ProfesionalEspecialidad" almacena las 2 especialidades del profesional',
    (
        SELECT count(*) = 2
        FROM public."ProfesionalEspecialidad" pe
        JOIN public."Profesionales" pr ON pr.id_profesional = pe.id_profesional
        WHERE pr.id_usuario = auth.uid()
    )
);

SELECT pg_temp.comprobar(
    'Tabla public."Servicios" almacena los servicios activos del profesional',
    (
        SELECT count(*) = 2
        FROM public."Servicios" s
        JOIN public."Profesionales" pr ON pr.id_profesional = s.id_profesional
        WHERE pr.id_usuario = auth.uid()
          AND s.activo = TRUE
    )
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);
SELECT pg_temp.comprobar(
    'Directorio completo expone modalidad, coordenadas, servicios y especialidades del aprobado',
    (
        SELECT modalidad = 'Híbrida'
           AND array_length(especialidades, 1) = 2
           AND abs(latitud - (-1.67098)) < 0.0001
           AND position('Psicoterapia individual' IN COALESCE(servicios, '')) > 0
        FROM public.directorio_profesionales_completo()
        WHERE id = current_setting('bloom.aprobado')::uuid
    )
);
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 9. VERIFICACION DE LECTURA DIRECTA Y NO RECURSION EN ProfesionalEspecialidad
--    Y Servicios (PROPIO, ADMINISTRADOR Y PACIENTE SOLO PUBLICABLES)
-- ---------------------------------------------------------------------------
-- Resolver las claves profesionales reales; no asumir que coinciden con auth.users.id.
SELECT set_config(
    'bloom.id_profesional_aprobado',
    (SELECT id_profesional::text FROM public."Profesionales"
     WHERE id_usuario = current_setting('bloom.aprobado')::uuid),
    TRUE
);
SELECT set_config(
    'bloom.id_profesional_pendiente',
    (SELECT id_profesional::text FROM public."Profesionales"
     WHERE id_usuario = current_setting('bloom.pendiente')::uuid),
    TRUE
);

-- Volvemos a dejar a bloom.pendiente en estado 'pendiente' y le asignamos
-- especialidades y servicios (uno activo y uno inactivo) para comprobar que:
-- - El profesional pendiente solo ve sus propios registros (y no los de bloom.aprobado).
-- - El paciente solo ve registros publicables de bloom.aprobado (y ninguno de bloom.pendiente ni servicios inactivos).
-- - El administrador ve los registros tanto de bloom.aprobado como de bloom.pendiente.
UPDATE psicobloom_interno.perfiles_compat
SET aprobacion = 'pendiente'
WHERE id = current_setting('bloom.pendiente')::uuid;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.pendiente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.pendiente'), 'role', 'authenticated')::text,
    TRUE
);

SELECT public.actualizar_perfil_profesional_propio(
    'Profesional',
    'Pendiente',
    ARRAY(SELECT id_especialidad FROM public."Especialidades" WHERE activa = TRUE ORDER BY nombre LIMIT 1),
    'MSP-555555',
    'En revisión.',
    2,
    '0987654321',
    NULL,
    'Virtual',
    'Orientación inicial, Taller grupal',
    NULL,
    NULL,
    NULL
);

-- Desactivamos uno de los servicios propios de bloom.pendiente
UPDATE public."Servicios"
SET activo = FALSE
WHERE nombre_servicio = 'Taller grupal';

SELECT pg_temp.comprobar(
    'Profesional lee en ProfesionalEspecialidad solo sus propios registros (sin ver los de otro profesional)',
    (
        SELECT count(*) = 1
        FROM public."ProfesionalEspecialidad" pe
        JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public."ProfesionalEspecialidad" pe
        WHERE pe.id_profesional = current_setting('bloom.id_profesional_aprobado')::uuid
    )
);

SELECT pg_temp.comprobar(
    'Profesional lee en Servicios solo sus propios servicios (activos e inactivos) sin ver los ajenos',
    (SELECT count(*) = 2 FROM public."Servicios")
    AND NOT EXISTS (
        SELECT 1
        FROM public."Servicios" s
        WHERE s.id_profesional = current_setting('bloom.id_profesional_aprobado')::uuid
    )
);
RESET ROLE;

-- En el profesional aprobado, marcamos uno de sus servicios como inactivo para verificar que el paciente no lo vea
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.aprobado'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.aprobado'), 'role', 'authenticated')::text,
    TRUE
);
INSERT INTO public."Servicios" (id_profesional, nombre_servicio, duracion_minutos, activo)
VALUES (current_setting('bloom.id_profesional_aprobado')::uuid, 'Servicio interno inactivo', 60, FALSE);
RESET ROLE;

-- Paciente activo consulta directamente ProfesionalEspecialidad y Servicios (incluyendo JOIN con Especialidades)
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.paciente'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.paciente'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Paciente lee en ProfesionalEspecialidad datos publicables del aprobado y 0 del pendiente (sin recursion)',
    (
        SELECT count(*) = 2
        FROM public."ProfesionalEspecialidad" pe
        JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
        WHERE pe.id_profesional = current_setting('bloom.id_profesional_aprobado')::uuid
    )
    AND (
        SELECT count(*) = 0
        FROM public."ProfesionalEspecialidad" pe
        WHERE pe.id_profesional = current_setting('bloom.id_profesional_pendiente')::uuid
    )
);

SELECT pg_temp.comprobar(
    'Paciente lee en Servicios solo activos de profesionales aprobados y activos (sin ver inactivos ni pendientes)',
    (
        SELECT count(*) = 2
        FROM public."Servicios" s
        WHERE s.id_profesional = current_setting('bloom.id_profesional_aprobado')::uuid
    )
    AND NOT EXISTS (
        SELECT 1
        FROM public."Servicios" s
        WHERE s.nombre_servicio = 'Servicio interno inactivo'
    )
    AND (
        SELECT count(*) = 0
        FROM public."Servicios" s
        WHERE s.id_profesional = current_setting('bloom.id_profesional_pendiente')::uuid
    )
);
RESET ROLE;

-- Administrador activo consulta directamente ProfesionalEspecialidad y Servicios de ambos
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', current_setting('bloom.admin'), TRUE);
SELECT set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', current_setting('bloom.admin'), 'role', 'authenticated')::text,
    TRUE
);

SELECT pg_temp.comprobar(
    'Administrador lee en ProfesionalEspecialidad y Servicios tanto aprobados como pendientes',
    EXISTS (
        SELECT 1 FROM public."ProfesionalEspecialidad"
        WHERE id_profesional = current_setting('bloom.id_profesional_aprobado')::uuid
    )
    AND EXISTS (
        SELECT 1 FROM public."ProfesionalEspecialidad"
        WHERE id_profesional = current_setting('bloom.id_profesional_pendiente')::uuid
    )
    AND EXISTS (
        SELECT 1 FROM public."Servicios"
        WHERE id_profesional = current_setting('bloom.id_profesional_pendiente')::uuid
    )
);
RESET ROLE;

SELECT numero, prueba, resultado FROM pg_temp.resultados_bloom ORDER BY numero;
ROLLBACK;
