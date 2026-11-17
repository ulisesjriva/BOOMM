-- =============================================================================
-- SCRIPT 20 — MIGRACION ADITIVA DEL MODULO ADMINISTRADOR COMPLETO
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar en: Supabase > SQL Editor como postgres
--
-- Proposito:
--   1. Incorporar tabla interna de auditoria administrativa con RLS.
--   2. Exponer RPC autorizadas (SECURITY DEFINER, _rol_activo() = 'administrador')
--      para Panel general, Usuarios, Profesionales, Especialidades, Citas,
--      Control de cuentas (incluyendo proteccion al ultimo administrador) y
--      Correcciones puntuales de informacion.
--   3. Conservar tablas, relaciones historicas y flujos existentes sin
--      debilitar permisos ni exponer datos clinicos o de orientacion.
-- =============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS psicobloom_interno;

-- ---------------------------------------------------------------------------
-- 1. AUDITORIA ADMINISTRATIVA INTERNA (SIN ACCESO DIRECTO A CLIENTES)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS psicobloom_interno.auditoria_administracion (
    id_auditoria UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_administrador UUID NOT NULL,
    accion TEXT NOT NULL,
    entidad TEXT NOT NULL,
    id_objetivo UUID NULL,
    detalle TEXT NOT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE psicobloom_interno.auditoria_administracion ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE psicobloom_interno.auditoria_administracion
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. PANEL GENERAL: INDICADORES REALES Y ACTIVIDAD RECIENTE REAL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resumen_administracion()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_usuarios BIGINT := 0;
    v_prof_activos_aprobados BIGINT := 0;
    v_prof_pendientes BIGINT := 0;
    v_citas_pendientes BIGINT := 0;
    v_citas_confirmadas BIGINT := 0;
    v_citas_canceladas BIGINT := 0;
    v_citas_rechazadas BIGINT := 0;
    v_citas_finalizadas BIGINT := 0;
    v_actividad JSONB := '[]'::jsonb;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    SELECT
        count(*) FILTER (WHERE p.rol IN ('paciente', 'profesional')),
        count(*) FILTER (WHERE p.rol = 'profesional' AND p.aprobacion = 'aprobado' AND p.cuenta_activa = TRUE),
        count(*) FILTER (WHERE p.rol = 'profesional' AND p.aprobacion = 'pendiente' AND p.cuenta_activa = TRUE)
    INTO v_usuarios, v_prof_activos_aprobados, v_prof_pendientes
    FROM psicobloom_interno.perfiles_compat p;

    SELECT
        count(*) FILTER (WHERE c.estado = 'pendiente'),
        count(*) FILTER (WHERE c.estado = 'confirmada'),
        count(*) FILTER (WHERE c.estado = 'cancelada'),
        count(*) FILTER (WHERE c.estado = 'rechazada'),
        count(*) FILTER (WHERE c.estado = 'finalizada')
    INTO v_citas_pendientes, v_citas_confirmadas, v_citas_canceladas, v_citas_rechazadas, v_citas_finalizadas
    FROM public."Citas" c;

    SELECT COALESCE(jsonb_agg(item ORDER BY item.fecha DESC), '[]'::jsonb)
    INTO v_actividad
    FROM (
        SELECT * FROM (
            SELECT
                'nuevo_profesional'::TEXT AS tipo,
                'Nuevo profesional registrado'::TEXT AS titulo,
                trim(p.nombre || ' ' || p.apellido) || ' se registró como profesional' AS detalle,
                p.creado_en AS fecha
            FROM psicobloom_interno.perfiles_compat p
            WHERE p.rol = 'profesional' AND p.creado_en IS NOT NULL
            ORDER BY p.creado_en DESC
            LIMIT 4
        ) q1
        UNION ALL
        SELECT * FROM (
            SELECT
                'solicitud_cita'::TEXT AS tipo,
                'Solicitud de cita'::TEXT AS titulo,
                trim(pp.nombre || ' ' || pp.apellido) || ' solicitó una cita con ' || trim(ppr.nombre || ' ' || ppr.apellido) AS detalle,
                c.fecha_solicitud AS fecha
            FROM public."Citas" c
            JOIN public."Pacientes" pa ON pa.id_paciente = c.id_paciente
            JOIN psicobloom_interno.perfiles_compat pp ON pp.id = pa.id_usuario
            JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
            JOIN psicobloom_interno.perfiles_compat ppr ON ppr.id = pr.id_usuario
            WHERE c.fecha_solicitud IS NOT NULL
            ORDER BY c.fecha_solicitud DESC
            LIMIT 4
        ) q2
        UNION ALL
        SELECT * FROM (
            SELECT
                'auditoria'::TEXT AS tipo,
                a.accion AS titulo,
                a.detalle AS detalle,
                a.creado_en AS fecha
            FROM psicobloom_interno.auditoria_administracion a
            ORDER BY a.creado_en DESC
            LIMIT 4
        ) q3
        ORDER BY fecha DESC
        LIMIT 8
    ) item;

    RETURN jsonb_build_object(
        'usuarios_registrados', v_usuarios,
        'profesionales_activos_aprobados', v_prof_activos_aprobados,
        'profesionales_pendientes', v_prof_pendientes,
        'citas_pendientes', v_citas_pendientes,
        'citas_confirmadas', v_citas_confirmadas,
        'citas_canceladas', v_citas_canceladas,
        'citas_rechazadas', v_citas_rechazadas,
        'citas_finalizadas', v_citas_finalizadas,
        'total_citas', v_citas_pendientes + v_citas_confirmadas + v_citas_canceladas + v_citas_rechazadas + v_citas_finalizadas,
        'actividad_reciente', v_actividad
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. GESTION DE USUARIOS (BUSQUEDA, FILTRO POR ROL, PAGINACION)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_usuarios_administracion(
    p_busqueda TEXT DEFAULT NULL,
    p_rol TEXT DEFAULT 'todos',
    p_pagina INTEGER DEFAULT 0,
    p_tamano INTEGER DEFAULT 20
)
RETURNS TABLE(
    id UUID,
    nombre TEXT,
    apellido TEXT,
    correo TEXT,
    rol TEXT,
    cuenta_activa BOOLEAN,
    aprobacion TEXT,
    foto_url TEXT,
    creado_en TIMESTAMPTZ,
    total_registros BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_busqueda TEXT := NULLIF(lower(trim(COALESCE(p_busqueda, ''))), '');
    v_rol TEXT := lower(trim(COALESCE(p_rol, 'todos')));
    v_pagina INTEGER := GREATEST(0, COALESCE(p_pagina, 0));
    v_tamano INTEGER := GREATEST(1, LEAST(COALESCE(p_tamano, 20), 50));
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        p.nombre,
        p.apellido,
        p.correo,
        p.rol::TEXT,
        p.cuenta_activa,
        p.aprobacion::TEXT,
        d.foto_url,
        p.creado_en,
        count(*) OVER() AS total_registros
    FROM psicobloom_interno.perfiles_compat p
    LEFT JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    WHERE (
        (v_rol = 'todos' AND p.rol IN ('paciente', 'profesional'))
        OR (v_rol IN ('paciente', 'profesional') AND p.rol::TEXT = v_rol)
    )
      AND (
        v_busqueda IS NULL
        OR lower(p.nombre || ' ' || p.apellido) LIKE '%' || v_busqueda || '%'
        OR lower(p.correo) LIKE '%' || v_busqueda || '%'
      )
    ORDER BY p.creado_en DESC NULLS LAST, p.nombre, p.apellido
    OFFSET v_pagina * v_tamano
    LIMIT v_tamano;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. GESTION DE PROFESIONALES (FILTRO POR ESTADO Y DETALLE COMPLETO)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_profesionales_administracion(
    p_estado TEXT DEFAULT 'todos'
)
RETURNS TABLE(
    id_usuario UUID,
    id_profesional UUID,
    nombre TEXT,
    apellido TEXT,
    correo TEXT,
    aprobacion TEXT,
    cuenta_activa BOOLEAN,
    especialidad TEXT,
    numero_registro TEXT,
    descripcion TEXT,
    anios_experiencia INTEGER,
    telefono_contacto TEXT,
    modalidad TEXT,
    direccion_consultorio TEXT,
    foto_url TEXT,
    motivo_rechazo TEXT,
    creado_en TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_estado TEXT := lower(trim(COALESCE(p_estado, 'todos')));
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id AS id_usuario,
        pr.id_profesional,
        p.nombre,
        p.apellido,
        p.correo,
        p.aprobacion::TEXT,
        p.cuenta_activa,
        COALESCE(
            (
                SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
            ),
            NULLIF(trim(d.especialidad), ''),
            'Psicología General'
        ) AS especialidad,
        d.numero_registro,
        pr.descripcion,
        d.anios_experiencia,
        d.telefono_contacto,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad,
        pr.direccion_consultorio,
        d.foto_url,
        CASE WHEN p.aprobacion = 'rechazado' THEN rev.motivo_rechazo END AS motivo_rechazo,
        p.creado_en
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    LEFT JOIN psicobloom_interno.revisiones_profesionales rev ON rev.id = p.id
    WHERE p.rol = 'profesional'
      AND (
        v_estado = 'todos'
        OR (v_estado = 'deshabilitado' AND p.cuenta_activa = FALSE)
        OR (v_estado IN ('pendiente', 'aprobado', 'rechazado')
            AND p.aprobacion::TEXT = v_estado
            AND p.cuenta_activa = TRUE)
      )
    ORDER BY
        CASE WHEN p.aprobacion = 'pendiente' AND p.cuenta_activa THEN 0 ELSE 1 END,
        p.creado_en DESC NULLS LAST;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. ESPECIALIDADES (LISTAR, CREAR/EDITAR SIN DUPLICADOS, ACTIVAR/DESACTIVAR)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_especialidades_administracion()
RETURNS TABLE(
    id UUID,
    nombre TEXT,
    descripcion TEXT,
    activa BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        e.id_especialidad AS id,
        e.nombre,
        e.descripcion,
        e.activa
    FROM public."Especialidades" e
    ORDER BY lower(e.nombre);
END;
$$;

CREATE OR REPLACE FUNCTION public.guardar_especialidad_administracion(
    p_id_especialidad UUID DEFAULT NULL,
    p_nombre TEXT DEFAULT '',
    p_descripcion TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_nombre TEXT := regexp_replace(trim(COALESCE(p_nombre, '')), '\s+', ' ', 'g');
    v_descripcion TEXT := NULLIF(trim(COALESCE(p_descripcion, '')), '');
    v_id UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    IF char_length(v_nombre) < 3 THEN
        RAISE EXCEPTION 'El nombre de la especialidad debe tener al menos 3 caracteres.'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Especialidades" e
        WHERE lower(regexp_replace(trim(e.nombre), '\s+', ' ', 'g')) = lower(v_nombre)
          AND (p_id_especialidad IS NULL OR e.id_especialidad <> p_id_especialidad)
    ) THEN
        RAISE EXCEPTION 'Ya existe una especialidad registrada con ese nombre.'
            USING ERRCODE = '23505';
    END IF;

    IF p_id_especialidad IS NULL THEN
        INSERT INTO public."Especialidades" (nombre, descripcion, activa)
        VALUES (v_nombre, v_descripcion, TRUE)
        RETURNING id_especialidad INTO v_id;

        INSERT INTO psicobloom_interno.auditoria_administracion (
            id_administrador, accion, entidad, id_objetivo, detalle
        )
        VALUES (
            auth.uid(), 'Especialidad creada', 'Especialidades', v_id,
            'Se creó la especialidad ' || v_nombre
        );
    ELSE
        UPDATE public."Especialidades"
        SET nombre = v_nombre,
            descripcion = v_descripcion
        WHERE id_especialidad = p_id_especialidad
        RETURNING id_especialidad INTO v_id;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'No se encontró la especialidad solicitada.' USING ERRCODE = '22023';
        END IF;

        INSERT INTO psicobloom_interno.auditoria_administracion (
            id_administrador, accion, entidad, id_objetivo, detalle
        )
        VALUES (
            auth.uid(), 'Especialidad editada', 'Especialidades', v_id,
            'Se actualizó la especialidad ' || v_nombre
        );
    END IF;

    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cambiar_estado_especialidad_administracion(
    p_id_especialidad UUID,
    p_activa BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_nombre TEXT;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    IF p_id_especialidad IS NULL OR p_activa IS NULL THEN
        RAISE EXCEPTION 'Indica una especialidad y un estado válido.' USING ERRCODE = '22023';
    END IF;

    -- Conserva intactas las relaciones historicas en ProfesionalEspecialidad.
    UPDATE public."Especialidades"
    SET activa = p_activa
    WHERE id_especialidad = p_id_especialidad
    RETURNING nombre INTO v_nombre;

    IF v_nombre IS NULL THEN
        RAISE EXCEPTION 'No se encontró la especialidad solicitada.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO psicobloom_interno.auditoria_administracion (
        id_administrador, accion, entidad, id_objetivo, detalle
    )
    VALUES (
        auth.uid(),
        CASE WHEN p_activa THEN 'Especialidad activada' ELSE 'Especialidad desactivada' END,
        'Especialidades',
        p_id_especialidad,
        v_nombre
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. SUPERVISION DE CITAS (SOLO LECTURA AUTORIZADA, SIN MODIFICAR ESTADOS)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_citas_administracion(
    p_estado TEXT DEFAULT 'todas',
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_pagina INTEGER DEFAULT 0,
    p_tamano INTEGER DEFAULT 25
)
RETURNS TABLE(
    id_cita UUID,
    paciente_nombre TEXT,
    profesional_nombre TEXT,
    fecha DATE,
    hora_inicio TEXT,
    hora_fin TEXT,
    estado TEXT,
    fecha_solicitud TIMESTAMPTZ,
    motivo_respuesta TEXT,
    total_registros BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_estado TEXT := lower(trim(COALESCE(p_estado, 'todas')));
    v_pagina INTEGER := GREATEST(0, COALESCE(p_pagina, 0));
    v_tamano INTEGER := GREATEST(1, LEAST(COALESCE(p_tamano, 25), 100));
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        c.id_cita,
        trim(pp.nombre || ' ' || pp.apellido) AS paciente_nombre,
        trim(ppr.nombre || ' ' || ppr.apellido) AS profesional_nombre,
        d.fecha,
        to_char(d.hora_inicio, 'HH24:MI') AS hora_inicio,
        to_char(d.hora_fin, 'HH24:MI') AS hora_fin,
        c.estado::TEXT,
        c.fecha_solicitud,
        NULL::TEXT AS motivo_respuesta,
        count(*) OVER() AS total_registros
    FROM public."Citas" c
    JOIN public."Disponibilidad" d ON d.id_disponibilidad = c.id_disponibilidad
    JOIN public."Pacientes" pa ON pa.id_paciente = c.id_paciente
    JOIN psicobloom_interno.perfiles_compat pp ON pp.id = pa.id_usuario
    JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
    JOIN psicobloom_interno.perfiles_compat ppr ON ppr.id = pr.id_usuario
    WHERE (
        v_estado = 'todas'
        OR c.estado::TEXT = v_estado
    )
      AND (p_fecha_desde IS NULL OR d.fecha >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR d.fecha <= p_fecha_hasta)
    ORDER BY d.fecha DESC, d.hora_inicio DESC, c.fecha_solicitud DESC
    OFFSET v_pagina * v_tamano
    LIMIT v_tamano;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. CONTROL DE CUENTAS (PROTECCION AL ULTIMO ADMIN, SIN MEZCLAR APROBACION)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cambiar_estado_cuenta(
    p_usuario_id UUID,
    p_activo BOOLEAN,
    p_motivo TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_estado_anterior BOOLEAN;
    v_rol_destino public.rol_usuario;
    v_nombre_completo TEXT;
    v_admins_activos INTEGER;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    IF p_usuario_id IS NULL OR p_activo IS NULL OR
       char_length(trim(COALESCE(p_motivo, ''))) < 5 THEN
        RAISE EXCEPTION 'Indica usuario, estado y motivo de al menos 5 caracteres.'
            USING ERRCODE = '22023';
    END IF;

    IF p_usuario_id = auth.uid() THEN
        RAISE EXCEPTION 'No puedes desactivar o cambiar tu propia cuenta.'
            USING ERRCODE = '42501';
    END IF;

    SELECT p.cuenta_activa, p.rol, trim(p.nombre || ' ' || p.apellido)
    INTO v_estado_anterior, v_rol_destino, v_nombre_completo
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.id = p_usuario_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró la cuenta seleccionada.' USING ERRCODE = '22023';
    END IF;

    IF v_rol_destino = 'administrador' AND p_activo = FALSE THEN
        PERFORM pg_advisory_xact_lock(hashtext('psicobloom_ultimo_admin'));

        SELECT count(*)
        INTO v_admins_activos
        FROM psicobloom_interno.perfiles_compat p
        WHERE p.rol = 'administrador'
          AND p.cuenta_activa = TRUE;

        IF v_admins_activos <= 1 THEN
            RAISE EXCEPTION 'No se puede desactivar al último administrador activo del sistema.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_estado_anterior = p_activo THEN
        RAISE EXCEPTION 'La cuenta ya tiene ese estado.' USING ERRCODE = '22023';
    END IF;

    -- Actualiza unicamente cuenta_activa; nunca modifica aprobacion automaticamente.
    UPDATE psicobloom_interno.perfiles_compat
    SET cuenta_activa = p_activo
    WHERE id = p_usuario_id;

    INSERT INTO psicobloom_interno.auditoria_administracion (
        id_administrador, accion, entidad, id_objetivo, detalle
    )
    VALUES (
        auth.uid(),
        CASE WHEN p_activo THEN 'Cuenta reactivada' ELSE 'Cuenta deshabilitada' END,
        'Usuarios',
        p_usuario_id,
        CASE WHEN p_activo
            THEN 'Se reactivó la cuenta de ' || v_nombre_completo
            ELSE 'Se deshabilitó la cuenta de ' || v_nombre_completo
        END
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. CORRECCION PUNTUAL AUTORIZADA DE DATOS DE USUARIO / PROFESIONAL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.corregir_datos_usuario_administracion(
    p_usuario_id UUID,
    p_nombre TEXT,
    p_apellido TEXT,
    p_numero_registro TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_nombre TEXT := trim(COALESCE(p_nombre, ''));
    v_apellido TEXT := trim(COALESCE(p_apellido, ''));
    v_registro TEXT := NULLIF(trim(COALESCE(p_numero_registro, '')), '');
    v_rol public.rol_usuario;
    v_id_profesional UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    IF p_usuario_id IS NULL OR char_length(v_nombre) < 2 OR char_length(v_apellido) < 2 THEN
        RAISE EXCEPTION 'El nombre y el apellido deben tener al menos 2 caracteres.'
            USING ERRCODE = '22023';
    END IF;

    SELECT p.rol
    INTO v_rol
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.id = p_usuario_id
    FOR UPDATE;

    IF NOT FOUND OR v_rol = 'administrador' THEN
        RAISE EXCEPTION 'Selecciona una cuenta de paciente o profesional válida.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE psicobloom_interno.perfiles_compat
    SET nombre = v_nombre,
        apellido = v_apellido
    WHERE id = p_usuario_id;

    IF v_rol = 'profesional' THEN
        SELECT pr.id_profesional
        INTO v_id_profesional
        FROM public."Profesionales" pr
        WHERE pr.id_usuario = p_usuario_id;

        IF v_id_profesional IS NOT NULL THEN
            UPDATE psicobloom_interno.detalle_profesional
            SET numero_registro = COALESCE(v_registro, numero_registro)
            WHERE id = v_id_profesional;
        END IF;
    END IF;

    INSERT INTO psicobloom_interno.auditoria_administracion (
        id_administrador, accion, entidad, id_objetivo, detalle
    )
    VALUES (
        auth.uid(),
        'Corrección de datos',
        'Usuarios',
        p_usuario_id,
        'Se corrigió nombre/registro de ' || v_nombre || ' ' || v_apellido
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. PRIVILEGIOS MINIMOS DE EJECUCION
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
    public.resumen_administracion(),
    public.listar_usuarios_administracion(TEXT, TEXT, INTEGER, INTEGER),
    public.listar_profesionales_administracion(TEXT),
    public.listar_especialidades_administracion(),
    public.guardar_especialidad_administracion(UUID, TEXT, TEXT),
    public.cambiar_estado_especialidad_administracion(UUID, BOOLEAN),
    public.listar_citas_administracion(TEXT, DATE, DATE, INTEGER, INTEGER),
    public.cambiar_estado_cuenta(UUID, BOOLEAN, TEXT),
    public.corregir_datos_usuario_administracion(UUID, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.resumen_administracion(),
    public.listar_usuarios_administracion(TEXT, TEXT, INTEGER, INTEGER),
    public.listar_profesionales_administracion(TEXT),
    public.listar_especialidades_administracion(),
    public.guardar_especialidad_administracion(UUID, TEXT, TEXT),
    public.cambiar_estado_especialidad_administracion(UUID, BOOLEAN),
    public.listar_citas_administracion(TEXT, DATE, DATE, INTEGER, INTEGER),
    public.cambiar_estado_cuenta(UUID, BOOLEAN, TEXT),
    public.corregir_datos_usuario_administracion(UUID, TEXT, TEXT, TEXT)
    TO authenticated;

COMMIT;
