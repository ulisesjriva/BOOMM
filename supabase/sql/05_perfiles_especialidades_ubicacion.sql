-- =============================================================================
-- SCRIPT 5 — MIGRACION ADITIVA DEFINITIVA ADAPTADA A public Y psicobloom_interno
-- Proyecto: PsicoBloom (esquemas: public, psicobloom_interno y storage)
-- Referencias verificadas:
--   - esquema_real_psicobloom.json (esquema public y storage)
--   - exportacion complementaria de psicobloom_interno (tablas, vistas y triggers)
-- Ejecutar en: Supabase > SQL Editor como postgres
--
-- Proposito:
--   1. Conservar intactas las tablas reales public."Usuarios", public."Pacientes",
--      public."Profesionales", public."Administradores", public."Roles",
--      public."Especialidades", public."ProfesionalEspecialidad", public."Servicios"
--      y las tablas/vistas internas de psicobloom_interno:
--      - psicobloom_interno.estado_usuario (PK id -> public."Usuarios".id_usuario)
--      - psicobloom_interno.detalle_profesional (PK id -> public."Profesionales".id_profesional)
--      - psicobloom_interno.revisiones_profesionales (PK id -> public."Usuarios".id_usuario)
--      - psicobloom_interno.cambios_estado_cuenta
--      - psicobloom_interno.perfiles_compat (vista con trigger escribir_perfil_compat)
--      - psicobloom_interno.profesionales_compat (vista con trigger escribir_profesional_compat)
--   2. Agregar de forma aditiva:
--      - public."Profesionales".modalidad ('Presencial', 'Virtual', 'Híbrida')
--      - public."Especialidades".activa (BOOLEAN DEFAULT TRUE)
--   3. Configurar permisos y politicas RLS en public."Profesionales",
--      public."Especialidades", public."ProfesionalEspecialidad", public."Servicios"
--      y public."Usuarios"(telefono).
--   4. Sembrar de forma idempotente el catalogo base en public."Especialidades".
--   5. Crear/actualizar las funciones RPC SECURITY DEFINER respetando la distincion
--      exacta entre id_usuario (public."Usuarios".id_usuario) e id_profesional
--      (public."Profesionales".id_profesional y psicobloom_interno.detalle_profesional.id):
--      - public.obtener_perfil_profesional_propio()
--      - public.guardar_especialidades_profesional(UUID[])
--      - public.actualizar_foto_profesional_propia(TEXT)
--      - public.actualizar_perfil_profesional_propio(...)
--      - public.directorio_profesionales() (conservando su firma de 7 columnas)
--      - public.directorio_profesionales_completo()
--   6. Crear el bucket 'fotos-profesionales' en Supabase Storage y sus politicas RLS.
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. COLUMNAS ADITIVAS Y PERMISOS EN TABLAS EXISTENTES (public."Profesionales",
--    public."Usuarios", public."Especialidades")
-- ---------------------------------------------------------------------------

ALTER TABLE public."Profesionales"
    ADD COLUMN IF NOT EXISTS modalidad TEXT NOT NULL DEFAULT 'Presencial'
        CHECK (modalidad IN ('Presencial', 'Virtual', 'Híbrida'));

ALTER TABLE public."Especialidades"
    ADD COLUMN IF NOT EXISTS activa BOOLEAN NOT NULL DEFAULT TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_especialidades_nombre_normalizado
    ON public."Especialidades" (lower(trim(nombre)));

GRANT UPDATE (nombres, apellidos, telefono) ON public."Usuarios" TO authenticated;

GRANT UPDATE (
    descripcion,
    direccion_consultorio,
    latitud,
    longitud,
    modalidad
) ON public."Profesionales" TO authenticated;

DROP POLICY IF EXISTS profesionales_editar_propio ON public."Profesionales";
CREATE POLICY profesionales_editar_propio ON public."Profesionales"
FOR UPDATE TO authenticated
USING (
    id_usuario = (SELECT auth.uid())
    AND (SELECT public._rol_activo()) = 'profesional'
)
WITH CHECK (
    id_usuario = (SELECT auth.uid())
    AND (SELECT public._rol_activo()) = 'profesional'
);

-- ---------------------------------------------------------------------------
-- 2. PERMISOS, POLITICAS RLS SIN RECURSION Y SEMILLA EN public."Especialidades",
--    public."ProfesionalEspecialidad" Y public."Servicios"
-- ---------------------------------------------------------------------------

-- Funciones auxiliares STABLE SECURITY DEFINER (siguiendo el patron de public._rol_activo())
-- para evaluar propiedad, publicabilidad y estado activo sin introducir recursion entre
-- las politicas RLS de Especialidades, ProfesionalEspecialidad, Servicios y Profesionales.
CREATE OR REPLACE FUNCTION public._es_profesional_propio(p_id_profesional UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profesionales" pr
        WHERE pr.id_profesional = p_id_profesional
          AND pr.id_usuario = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public._profesional_es_publicable(p_id_profesional UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Profesionales" pr
        JOIN psicobloom_interno.perfiles_compat p ON p.id = pr.id_usuario
        WHERE pr.id_profesional = p_id_profesional
          AND p.rol = 'profesional'
          AND p.aprobacion = 'aprobado'
          AND p.cuenta_activa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public._especialidad_esta_activa(p_id_especialidad UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Especialidades" e
        WHERE e.id_especialidad = p_id_especialidad
          AND e.activa = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public._profesional_tiene_especialidad_propia(p_id_especialidad UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."ProfesionalEspecialidad" pe
        JOIN public."Profesionales" pr ON pr.id_profesional = pe.id_profesional
        WHERE pe.id_especialidad = p_id_especialidad
          AND pr.id_usuario = auth.uid()
    );
$$;

REVOKE ALL ON FUNCTION
    public._es_profesional_propio(UUID),
    public._profesional_es_publicable(UUID),
    public._especialidad_esta_activa(UUID),
    public._profesional_tiene_especialidad_propia(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public._es_profesional_propio(UUID),
    public._profesional_es_publicable(UUID),
    public._especialidad_esta_activa(UUID),
    public._profesional_tiene_especialidad_propia(UUID)
    TO authenticated;

ALTER TABLE public."Especialidades" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."ProfesionalEspecialidad" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Servicios" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."Especialidades", public."ProfesionalEspecialidad", public."Servicios"
    FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public."Especialidades", public."ProfesionalEspecialidad", public."Servicios"
    TO authenticated;
GRANT INSERT, DELETE ON public."ProfesionalEspecialidad" TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public."Servicios" TO authenticated;

DROP POLICY IF EXISTS especialidades_leer_activas ON public."Especialidades";
CREATE POLICY especialidades_leer_activas ON public."Especialidades"
FOR SELECT TO authenticated
USING (
    (SELECT public._rol_activo()) IS NOT NULL
    AND (
        activa = TRUE
        OR (SELECT public._rol_activo()) = 'administrador'
        OR (
            (SELECT public._rol_activo()) = 'profesional'
            AND public._profesional_tiene_especialidad_propia(id_especialidad)
        )
    )
);

-- Lectura restringida en public."ProfesionalEspecialidad":
-- 1. Profesional: unicamente sus datos propios.
-- 2. Administrador: registros autorizados para revision y gestion.
-- 3. Paciente: unicamente datos publicables (especialidades activas de profesionales aprobados y activos).
DROP POLICY IF EXISTS prof_esp_leer_autenticados ON public."ProfesionalEspecialidad";
DROP POLICY IF EXISTS prof_esp_leer_autorizados ON public."ProfesionalEspecialidad";
CREATE POLICY prof_esp_leer_autorizados ON public."ProfesionalEspecialidad"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'profesional'
        AND public._es_profesional_propio(id_profesional)
    )
    OR (SELECT public._rol_activo()) = 'administrador'
    OR (
        (SELECT public._rol_activo()) = 'paciente'
        AND public._profesional_es_publicable(id_profesional)
        AND public._especialidad_esta_activa(id_especialidad)
    )
);

DROP POLICY IF EXISTS prof_esp_insertar_propio ON public."ProfesionalEspecialidad";
CREATE POLICY prof_esp_insertar_propio ON public."ProfesionalEspecialidad"
FOR INSERT TO authenticated
WITH CHECK (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
    AND public._especialidad_esta_activa(id_especialidad)
);

DROP POLICY IF EXISTS prof_esp_eliminar_propio ON public."ProfesionalEspecialidad";
CREATE POLICY prof_esp_eliminar_propio ON public."ProfesionalEspecialidad"
FOR DELETE TO authenticated
USING (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
);

-- Lectura restringida en public."Servicios":
-- 1. Profesional: unicamente sus propios servicios (activos o inactivos).
-- 2. Administrador: registros autorizados.
-- 3. Paciente: unicamente servicios activos de profesionales aprobados y activos.
DROP POLICY IF EXISTS servicios_leer_autenticados ON public."Servicios";
DROP POLICY IF EXISTS servicios_leer_autorizados ON public."Servicios";
CREATE POLICY servicios_leer_autorizados ON public."Servicios"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'profesional'
        AND public._es_profesional_propio(id_profesional)
    )
    OR (SELECT public._rol_activo()) = 'administrador'
    OR (
        (SELECT public._rol_activo()) = 'paciente'
        AND activo = TRUE
        AND public._profesional_es_publicable(id_profesional)
    )
);

DROP POLICY IF EXISTS servicios_gestionar_propio ON public."Servicios";
CREATE POLICY servicios_gestionar_propio ON public."Servicios"
FOR ALL TO authenticated
USING (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
)
WITH CHECK (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
);

INSERT INTO public."Especialidades" (nombre, descripcion, activa)
SELECT v.nombre, v.descripcion, TRUE
FROM (
    VALUES
        ('Psicología Clínica', 'Evaluación y acompañamiento psicológico en malestar emocional, ansiedad y estado de ánimo.'),
        ('Psicología Familiar', 'Orientación e intervención en dinámica familiar, comunicación y resolución de conflictos.'),
        ('Psicología de Pareja', 'Acompañamiento psicológico enfocado en vínculos afectivos y acuerdos de convivencia.'),
        ('Psicoterapia Cognitiva', 'Abordaje centrado en pensamientos, emociones y conductas adaptativas.'),
        ('Psicología Infantil', 'Atención psicológica para niñas, niños y acompañamiento a sus cuidadores.'),
        ('Psicología Educativa', 'Apoyo en adaptación académica, hábitos de estudio y orientación vocacional.')
) AS v(nombre, descripcion)
WHERE NOT EXISTS (
    SELECT 1
    FROM public."Especialidades" e
    WHERE lower(trim(e.nombre)) = lower(trim(v.nombre))
);

-- ---------------------------------------------------------------------------
-- 3. FUNCIONES RPC ADAPTADAS A public Y psicobloom_interno
-- ---------------------------------------------------------------------------

-- 3.1 Obtener el perfil profesional propio respetando:
--   - p.id = u.id_usuario (en psicobloom_interno.perfiles_compat)
--   - pr.id_profesional (en public."Profesionales")
--   - d.id = pr.id_profesional (en psicobloom_interno.detalle_profesional)
CREATE OR REPLACE FUNCTION public.obtener_perfil_profesional_propio()
RETURNS TABLE(
    id UUID,
    id_profesional UUID,
    nombre TEXT,
    apellido TEXT,
    correo TEXT,
    aprobacion public.estado_aprobacion,
    cuenta_activa BOOLEAN,
    especialidad TEXT,
    especialidades_ids UUID[],
    especialidades_nombres TEXT[],
    numero_registro TEXT,
    descripcion TEXT,
    anios_experiencia INTEGER,
    telefono_contacto TEXT,
    foto_url TEXT,
    modalidad TEXT,
    servicios TEXT,
    direccion_consultorio TEXT,
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        pr.id_profesional,
        p.nombre,
        p.apellido,
        p.correo,
        p.aprobacion,
        p.cuenta_activa,
        COALESCE(
            (
                SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
            ),
            NULLIF(trim(d.especialidad), '')
        ) AS especialidad,
        COALESCE(
            ARRAY(
                SELECT e.id_especialidad
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
                ORDER BY e.nombre
            ),
            ARRAY[]::UUID[]
        ) AS especialidades_ids,
        COALESCE(
            ARRAY(
                SELECT e.nombre
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
                ORDER BY e.nombre
            ),
            ARRAY[]::TEXT[]
        ) AS especialidades_nombres,
        d.numero_registro,
        pr.descripcion,
        d.anios_experiencia,
        COALESCE(NULLIF(trim(d.telefono_contacto), ''), p.telefono) AS telefono_contacto,
        d.foto_url,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad,
        (
            SELECT string_agg(s.nombre_servicio, ', ' ORDER BY s.nombre_servicio)
            FROM public."Servicios" s
            WHERE s.id_profesional = pr.id_profesional
              AND s.activo = TRUE
        ) AS servicios,
        pr.direccion_consultorio,
        pr.latitud::DOUBLE PRECISION,
        pr.longitud::DOUBLE PRECISION
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    WHERE p.id = auth.uid();
END;
$$;

-- 3.2 Guardar especialidades del profesional en public."ProfesionalEspecialidad"
-- (usando id_profesional) y sincronizar el resumen en psicobloom_interno.detalle_profesional
-- (cuya PK id referencia a public."Profesionales".id_profesional).
CREATE OR REPLACE FUNCTION public.guardar_especialidades_profesional(
    p_especialidades_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id_profesional UUID;
    v_resumen TEXT;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = v_uid;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado al usuario.' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM unnest(COALESCE(p_especialidades_ids, ARRAY[]::UUID[])) AS id_solicitado
        LEFT JOIN public."Especialidades" e ON e.id_especialidad = id_solicitado
        WHERE e.id_especialidad IS NULL
           OR (
               e.activa = FALSE
               AND NOT EXISTS (
                   SELECT 1 FROM public."ProfesionalEspecialidad" pe
                   WHERE pe.id_profesional = v_id_profesional
                     AND pe.id_especialidad = id_solicitado
               )
           )
    ) THEN
        RAISE EXCEPTION 'Una o mas especialidades seleccionadas no estan disponibles.' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public."ProfesionalEspecialidad"
    WHERE id_profesional = v_id_profesional
      AND NOT (id_especialidad = ANY(COALESCE(p_especialidades_ids, ARRAY[]::UUID[])));

    INSERT INTO public."ProfesionalEspecialidad" (id_profesional, id_especialidad)
    SELECT v_id_profesional, id_unico
    FROM (
        SELECT DISTINCT unnest(COALESCE(p_especialidades_ids, ARRAY[]::UUID[])) AS id_unico
    ) sub
    ON CONFLICT (id_profesional, id_especialidad) DO NOTHING;

    SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
    INTO v_resumen
    FROM public."ProfesionalEspecialidad" pe
    JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
    WHERE pe.id_profesional = v_id_profesional;

    INSERT INTO psicobloom_interno.detalle_profesional (id)
    VALUES (v_id_profesional)
    ON CONFLICT (id) DO NOTHING;

    UPDATE psicobloom_interno.detalle_profesional
    SET especialidad = v_resumen,
        actualizado_en = now()
    WHERE id = v_id_profesional;
END;
$$;

-- 3.3 Actualizar la URL de la fotografia en psicobloom_interno.detalle_profesional
-- usando v_id_profesional (FK hacia public."Profesionales".id_profesional).
CREATE OR REPLACE FUNCTION public.actualizar_foto_profesional_propia(
    p_foto_url TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id_profesional UUID;
    v_url_limpia TEXT := NULLIF(trim(COALESCE(p_foto_url, '')), '');
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF v_url_limpia IS NULL THEN
        RAISE EXCEPTION 'Indica una URL de fotografia valida.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = v_uid;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el perfil profesional asociado.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO psicobloom_interno.detalle_profesional (id)
    VALUES (v_id_profesional)
    ON CONFLICT (id) DO NOTHING;

    UPDATE psicobloom_interno.detalle_profesional
    SET foto_url = v_url_limpia,
        actualizado_en = now()
    WHERE id = v_id_profesional;
END;
$$;

-- 3.4 Actualizar de forma transaccional el perfil profesional propio en:
--   - public."Usuarios" (nombres, apellidos, telefono; clave id_usuario)
--   - public."Profesionales" (descripcion, direccion_consultorio, latitud, longitud, modalidad; clave id_profesional)
--   - psicobloom_interno.detalle_profesional (numero_registro, anios_experiencia, telefono_contacto, foto_url, actualizado_en; clave id = id_profesional)
--   - public."ProfesionalEspecialidad" (clave id_profesional)
--   - public."Servicios" (clave id_profesional)
CREATE OR REPLACE FUNCTION public.actualizar_perfil_profesional_propio(
    p_nombre TEXT,
    p_apellido TEXT,
    p_especialidades_ids UUID[] DEFAULT NULL,
    p_numero_registro TEXT DEFAULT NULL,
    p_descripcion TEXT DEFAULT NULL,
    p_anios_experiencia INTEGER DEFAULT NULL,
    p_telefono_contacto TEXT DEFAULT NULL,
    p_foto_url TEXT DEFAULT NULL,
    p_modalidad TEXT DEFAULT 'Presencial',
    p_servicios TEXT DEFAULT NULL,
    p_direccion_consultorio TEXT DEFAULT NULL,
    p_latitud NUMERIC(10,7) DEFAULT NULL,
    p_longitud NUMERIC(10,7) DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_id_profesional UUID;
    v_modalidad TEXT := COALESCE(NULLIF(trim(p_modalidad), ''), 'Presencial');
    v_telefono_limpio TEXT := NULLIF(trim(COALESCE(p_telefono_contacto, '')), '');
    v_servicio_nombre TEXT;
    v_servicios_lista TEXT[];
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF v_modalidad NOT IN ('Presencial', 'Virtual', 'Híbrida') THEN
        RAISE EXCEPTION 'La modalidad indicada no es valida.' USING ERRCODE = '22023';
    END IF;

    IF p_anios_experiencia IS NOT NULL AND p_anios_experiencia < 0 THEN
        RAISE EXCEPTION 'Los anos de experiencia no pueden ser negativos.' USING ERRCODE = '22023';
    END IF;

    IF (p_latitud IS NULL) <> (p_longitud IS NULL) THEN
        RAISE EXCEPTION 'Debes proporcionar latitud y longitud juntas.' USING ERRCODE = '23514';
    END IF;

    IF p_latitud IS NOT NULL AND (p_latitud < -90 OR p_latitud > 90 OR p_longitud < -180 OR p_longitud > 180) THEN
        RAISE EXCEPTION 'Las coordenadas estan fuera del rango permitido.' USING ERRCODE = '23514';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = v_uid
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el perfil profesional asociado.' USING ERRCODE = '22023';
    END IF;

    -- 1. Actualiza nombres y apellidos mediante la RPC existente
    PERFORM public.actualizar_nombre_apellido(p_nombre, p_apellido);

    -- 2. Actualiza telefono en public."Usuarios"
    UPDATE public."Usuarios"
    SET telefono = v_telefono_limpio
    WHERE id_usuario = v_uid
      AND activo = TRUE;

    -- 3. Actualiza campos propios en public."Profesionales"
    UPDATE public."Profesionales"
    SET descripcion = NULLIF(trim(COALESCE(p_descripcion, '')), ''),
        direccion_consultorio = NULLIF(trim(COALESCE(p_direccion_consultorio, '')), ''),
        latitud = p_latitud,
        longitud = p_longitud,
        modalidad = v_modalidad
    WHERE id_profesional = v_id_profesional;

    -- 4. Actualiza campos en psicobloom_interno.detalle_profesional (PK id = id_profesional)
    INSERT INTO psicobloom_interno.detalle_profesional (id)
    VALUES (v_id_profesional)
    ON CONFLICT (id) DO NOTHING;

    UPDATE psicobloom_interno.detalle_profesional
    SET numero_registro = NULLIF(trim(COALESCE(p_numero_registro, '')), ''),
        anios_experiencia = p_anios_experiencia,
        telefono_contacto = v_telefono_limpio,
        foto_url = COALESCE(NULLIF(trim(p_foto_url), ''), foto_url),
        actualizado_en = now()
    WHERE id = v_id_profesional;

    -- 5. Si se enviaron especialidades, sincroniza public."ProfesionalEspecialidad" y el resumen
    IF p_especialidades_ids IS NOT NULL THEN
        PERFORM public.guardar_especialidades_profesional(p_especialidades_ids);
    END IF;

    -- 6. Sincroniza public."Servicios" a partir de la lista separada por comas o saltos de linea
    IF p_servicios IS NOT NULL THEN
        SELECT COALESCE(
            ARRAY(
                SELECT DISTINCT trim(item)
                FROM regexp_split_to_table(p_servicios, '[,;\n\r]+') AS item
                WHERE length(trim(item)) > 0
            ),
            ARRAY[]::TEXT[]
        )
        INTO v_servicios_lista;

        UPDATE public."Servicios" s
        SET activo = FALSE
        WHERE s.id_profesional = v_id_profesional
          AND NOT (lower(trim(s.nombre_servicio)) = ANY(
              SELECT lower(trim(x)) FROM unnest(v_servicios_lista) AS x
          ));

        FOREACH v_servicio_nombre IN ARRAY v_servicios_lista LOOP
            UPDATE public."Servicios" s
            SET activo = TRUE
            WHERE s.id_profesional = v_id_profesional
              AND lower(trim(s.nombre_servicio)) = lower(trim(v_servicio_nombre));

            IF NOT FOUND THEN
                INSERT INTO public."Servicios" (
                    id_profesional,
                    nombre_servicio,
                    descripcion,
                    duracion_minutos,
                    precio_referencial,
                    activo
                )
                VALUES (
                    v_id_profesional,
                    trim(v_servicio_nombre),
                    NULL,
                    60,
                    NULL,
                    TRUE
                );
            END IF;
        END LOOP;
    END IF;
END;
$$;

-- 3.5 Conserva intacta la firma de retorno de public.directorio_profesionales()
CREATE OR REPLACE FUNCTION public.directorio_profesionales()
RETURNS TABLE(
    id UUID,
    nombre TEXT,
    apellido TEXT,
    especialidad TEXT,
    descripcion TEXT,
    anios_experiencia INTEGER,
    foto_url TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF public._rol_activo() IS NULL THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        p.nombre,
        p.apellido,
        COALESCE(
            NULLIF(trim(d.especialidad), ''),
            (
                SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
            )
        ) AS especialidad,
        pr.descripcion,
        d.anios_experiencia,
        d.foto_url
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    WHERE p.rol = 'profesional'
      AND p.aprobacion = 'aprobado'
      AND p.cuenta_activa = TRUE;
END;
$$;

-- 3.6 Directorio enriquecido para busqueda, filtros, perfil publico y mapa
CREATE OR REPLACE FUNCTION public.directorio_profesionales_completo()
RETURNS TABLE(
    id UUID,
    id_profesional UUID,
    nombre TEXT,
    apellido TEXT,
    especialidad TEXT,
    especialidades TEXT[],
    descripcion TEXT,
    anios_experiencia INTEGER,
    foto_url TEXT,
    modalidad TEXT,
    servicios TEXT,
    direccion_consultorio TEXT,
    latitud DOUBLE PRECISION,
    longitud DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF public._rol_activo() IS NULL THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        pr.id_profesional,
        p.nombre,
        p.apellido,
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
        COALESCE(
            ARRAY(
                SELECT e.nombre
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
                ORDER BY e.nombre
            ),
            CASE
                WHEN d.especialidad IS NOT NULL AND trim(d.especialidad) <> ''
                THEN ARRAY[trim(d.especialidad)]
                ELSE ARRAY[]::TEXT[]
            END
        ) AS especialidades,
        pr.descripcion,
        d.anios_experiencia,
        d.foto_url,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad,
        (
            SELECT string_agg(s.nombre_servicio, ', ' ORDER BY s.nombre_servicio)
            FROM public."Servicios" s
            WHERE s.id_profesional = pr.id_profesional
              AND s.activo = TRUE
        ) AS servicios,
        pr.direccion_consultorio,
        pr.latitud::DOUBLE PRECISION,
        pr.longitud::DOUBLE PRECISION
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    WHERE p.rol = 'profesional'
      AND p.aprobacion = 'aprobado'
      AND p.cuenta_activa = TRUE
    ORDER BY p.nombre, p.apellido;
END;
$$;

-- 3.7 Solicitudes profesionales pendientes y aprobacion tolerante a id_usuario / id_profesional
CREATE OR REPLACE FUNCTION public.listar_profesionales_pendientes()
RETURNS TABLE(
    id UUID,
    nombre TEXT,
    apellido TEXT,
    correo TEXT,
    especialidad TEXT,
    numero_registro TEXT,
    creado_en TIMESTAMPTZ
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
        p.id,
        p.nombre,
        p.apellido,
        p.correo,
        COALESCE(
            (
                SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
            ),
            NULLIF(trim(d.especialidad), '')
        ) AS especialidad,
        d.numero_registro,
        p.creado_en
    FROM psicobloom_interno.perfiles_compat p
    JOIN public."Profesionales" pr ON pr.id_usuario = p.id
    LEFT JOIN psicobloom_interno.detalle_profesional d ON d.id = pr.id_profesional
    WHERE p.rol = 'profesional'
      AND p.aprobacion = 'pendiente'
      AND p.cuenta_activa = TRUE
    ORDER BY p.creado_en;
END;
$$;

CREATE OR REPLACE FUNCTION public.aprobar_profesional(
    p_profesional_id UUID,
    p_decision public.estado_aprobacion,
    p_motivo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_usuario_id UUID;
    filas INTEGER;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE = '42501';
    END IF;

    IF p_profesional_id IS NULL OR p_decision IS NULL OR
       p_decision NOT IN ('aprobado', 'rechazado') THEN
        RAISE EXCEPTION 'Indica un profesional y una decision valida.' USING ERRCODE = '22023';
    END IF;

    -- Admite tanto id_usuario (perfiles_compat.id) como id_profesional (public."Profesionales".id_profesional)
    SELECT COALESCE(
        (SELECT pr.id_usuario FROM public."Profesionales" pr WHERE pr.id_profesional = p_profesional_id),
        p_profesional_id
    ) INTO v_usuario_id;

    IF v_usuario_id = auth.uid() THEN
        RAISE EXCEPTION 'No puedes revisar tu propia cuenta.' USING ERRCODE = '42501';
    END IF;

    IF p_decision = 'rechazado' AND char_length(trim(COALESCE(p_motivo, ''))) < 5 THEN
        RAISE EXCEPTION 'Indica un motivo de rechazo de al menos 5 caracteres.' USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM psicobloom_interno.perfiles_compat p
    WHERE p.id = v_usuario_id
      AND p.rol = 'profesional'
      AND p.cuenta_activa
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe un profesional activo con ese identificador.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO psicobloom_interno.revisiones_profesionales (id)
    VALUES (v_usuario_id)
    ON CONFLICT (id) DO NOTHING;

    UPDATE psicobloom_interno.perfiles_compat
    SET aprobacion = p_decision
    WHERE id = v_usuario_id;

    UPDATE psicobloom_interno.revisiones_profesionales
    SET revisado_en = NOW(),
        revisado_por = auth.uid(),
        motivo_rechazo = CASE WHEN p_decision = 'rechazado' THEN trim(p_motivo) END,
        nota_interna = CASE WHEN p_decision = 'aprobado' THEN NULLIF(trim(p_motivo), '') END
    WHERE id = v_usuario_id;

    GET DIAGNOSTICS filas = ROW_COUNT;
    IF filas <> 1 THEN
        RAISE EXCEPTION 'Falta la fila de revision. La operacion se revierte.';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION
    public.obtener_perfil_profesional_propio(),
    public.guardar_especialidades_profesional(UUID[]),
    public.actualizar_foto_profesional_propia(TEXT),
    public.actualizar_perfil_profesional_propio(TEXT, TEXT, UUID[], TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC),
    public.directorio_profesionales(),
    public.directorio_profesionales_completo(),
    public.listar_profesionales_pendientes(),
    public.aprobar_profesional(UUID, public.estado_aprobacion, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.obtener_perfil_profesional_propio(),
    public.guardar_especialidades_profesional(UUID[]),
    public.actualizar_foto_profesional_propia(TEXT),
    public.actualizar_perfil_profesional_propio(TEXT, TEXT, UUID[], TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC),
    public.directorio_profesionales(),
    public.directorio_profesionales_completo(),
    public.listar_profesionales_pendientes(),
    public.aprobar_profesional(UUID, public.estado_aprobacion, TEXT)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. BUCKET Y POLITICAS DE SUPABASE STORAGE PARA FOTOGRAFIAS DE PROFESIONALES
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'fotos-profesionales',
    'fotos-profesionales',
    TRUE,
    5242880, -- Limite de 5 MB por fotografia
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS fotos_prof_lectura_publica ON storage.objects;
CREATE POLICY fotos_prof_lectura_publica ON storage.objects
FOR SELECT TO public
USING (bucket_id = 'fotos-profesionales');

DROP POLICY IF EXISTS fotos_prof_subir_propia ON storage.objects;
CREATE POLICY fotos_prof_subir_propia ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'fotos-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

DROP POLICY IF EXISTS fotos_prof_actualizar_propia ON storage.objects;
CREATE POLICY fotos_prof_actualizar_propia ON storage.objects
FOR UPDATE TO authenticated
USING (
    bucket_id = 'fotos-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
)
WITH CHECK (
    bucket_id = 'fotos-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

DROP POLICY IF EXISTS fotos_prof_eliminar_propia ON storage.objects;
CREATE POLICY fotos_prof_eliminar_propia ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'fotos-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
);

COMMIT;
