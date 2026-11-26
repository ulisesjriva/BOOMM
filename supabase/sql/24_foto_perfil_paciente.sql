-- =============================================================================
-- SCRIPT 24 — MIGRACION ADITIVA DE FOTOGRAFIA DE PERFIL DEL PACIENTE
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar en: Supabase > SQL Editor como postgres (NO ejecutado automaticamente)
-- Numeracion: 24 (evita colisiones con 00..23 usados en otras ramas).
--
-- Proposito:
--   1. Agregar de forma aditiva e idempotente en public."Pacientes":
--      - foto_url            TEXT         (URL HTTPS de Cloudinary)
--      - foto_public_id      TEXT         (public_id en Cloudinary propio del paciente)
--      - foto_actualizada_en TIMESTAMPTZ  (marca temporal de auditoria)
--   2. Incorporar restricciones de integridad y pertenencia a nivel de tabla:
--      - foto_url y foto_public_id deben coexistir o ser ambos NULL.
--      - foto_url solo acepta direcciones HTTPS de res.cloudinary.com.
--      - foto_public_id solo acepta el prefijo estricto
--        'psicobloom/pacientes/<id_usuario>_<uuid>' del propio paciente
--        (sin comodines LIKE, usando position(...) = 1).
--   3. Mantener bloqueada cualquier escritura directa desde authenticated/anon
--      sobre public."Pacientes" sin alterar SELECT ni las politicas RLS existentes
--      de 08_solicitud_citas_paciente.sql, el registro de pacientes ni
--      actualizar_nombre_apellido().
--   4. Crear tabla interna psicobloom_interno.limpieza_fotos_paciente_pendientes
--      (RLS activo, sin acceso para anon/authenticated) para registrar de forma
--      atomica los recursos de Cloudinary sustituidos o eliminados y permitir
--      su limpieza segura y reintentable con FOR UPDATE SKIP LOCKED sin dejar
--      nunca referencias invalidas en public."Pacientes".
--   5. Exponer funciones RPC seguras:
--      - public.obtener_perfil_paciente_propio() [authenticated]
--      - public.obtener_estado_foto_paciente_servidor(UUID) [solo service_role]
--      - public.establecer_foto_paciente_servidor(UUID, TEXT, TEXT) [solo service_role]
--      - public.eliminar_foto_paciente_servidor(UUID) [solo service_role]
--      - public.encolar_limpieza_foto_paciente_servidor(UUID, TEXT) [solo service_role]
--      - public.reclamar_limpiezas_foto_paciente_pendientes_servidor(UUID, INTEGER) [solo service_role]
--      - public.registrar_resultado_limpieza_foto_paciente_servidor(UUID, TEXT, BOOLEAN, TEXT) [solo service_role]
--   6. No modifica tablas de profesionales, administradores, citas, mapas ni pagos QR.
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. COLUMNAS ADITIVAS EN public."Pacientes"
--    Todas inician en NULL; no sobrescribe ni altera registros existentes.
-- ---------------------------------------------------------------------------
ALTER TABLE public."Pacientes"
    ADD COLUMN IF NOT EXISTS foto_url TEXT,
    ADD COLUMN IF NOT EXISTS foto_public_id TEXT,
    ADD COLUMN IF NOT EXISTS foto_actualizada_en TIMESTAMPTZ;

-- ---------------------------------------------------------------------------
-- 2. RESTRICCIONES DE COHERENCIA Y PROPIEDAD A NIVEL DE BASE DE DATOS
-- ---------------------------------------------------------------------------
ALTER TABLE public."Pacientes"
    DROP CONSTRAINT IF EXISTS chk_pacientes_foto_par_coherente;
ALTER TABLE public."Pacientes"
    ADD CONSTRAINT chk_pacientes_foto_par_coherente CHECK (
        (foto_url IS NULL AND foto_public_id IS NULL)
        OR
        (foto_url IS NOT NULL AND foto_public_id IS NOT NULL)
    );

ALTER TABLE public."Pacientes"
    DROP CONSTRAINT IF EXISTS chk_pacientes_foto_url_https_cloudinary;
ALTER TABLE public."Pacientes"
    ADD CONSTRAINT chk_pacientes_foto_url_https_cloudinary CHECK (
        foto_url IS NULL
        OR foto_url ~* '^https://res\.cloudinary\.com/[^[:space:]]+$'
    );

ALTER TABLE public."Pacientes"
    DROP CONSTRAINT IF EXISTS chk_pacientes_foto_public_id_propietario;
ALTER TABLE public."Pacientes"
    ADD CONSTRAINT chk_pacientes_foto_public_id_propietario CHECK (
        foto_public_id IS NULL
        OR (
            foto_public_id ~ '^psicobloom/pacientes/[0-9a-f-]{36}_[0-9a-f-]{36}$'
            AND position(('psicobloom/pacientes/' || id_usuario::text || '_') IN foto_public_id) = 1
        )
    );

-- ---------------------------------------------------------------------------
-- 3. REFUERZO DE PRIVILEGIOS MINIMOS EN public."Pacientes"
--    Mantiene intacto GRANT SELECT y las politicas RLS de 08_solicitud_citas_paciente.sql.
--    Los triggers de registro (SECURITY DEFINER / postgres) y actualizar_nombre_apellido
--    (que escribe en public."Usuarios") no se ven afectados.
-- ---------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public."Pacientes" FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. COLA INTERNA DE LIMPIEZA REINTENTABLE EN CLOUDINARY
--    Permite actualizar primero public."Pacientes" de forma atomica (evitando
--    referencias rotas 404) y reintentar la eliminacion en Cloudinary si falla
--    temporalmente la red o el proveedor externo.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS psicobloom_interno.limpieza_fotos_paciente_pendientes (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario          UUID        NOT NULL REFERENCES public."Usuarios"(id_usuario) ON DELETE CASCADE,
    foto_public_id      TEXT        NOT NULL,
    estado              TEXT        NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'eliminado')),
    intentos            INTEGER     NOT NULL DEFAULT 0 CHECK (intentos >= 0),
    bloqueado_hasta     TIMESTAMPTZ,
    ultimo_error        TEXT,
    creado_en           TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
    eliminado_en        TIMESTAMPTZ,
    CONSTRAINT uq_limpieza_fotos_paciente_public_id UNIQUE (foto_public_id),
    CONSTRAINT chk_limpieza_foto_paciente_public_id_propietario CHECK (
        foto_public_id ~ '^psicobloom/pacientes/[0-9a-f-]{36}_[0-9a-f-]{36}$'
        AND position(('psicobloom/pacientes/' || id_usuario::text || '_') IN foto_public_id) = 1
    )
);

ALTER TABLE psicobloom_interno.limpieza_fotos_paciente_pendientes
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON psicobloom_interno.limpieza_fotos_paciente_pendientes
    FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_limpieza_fotos_paciente_usuario_pendiente
    ON psicobloom_interno.limpieza_fotos_paciente_pendientes (id_usuario, creado_en)
    WHERE estado = 'pendiente';

-- ---------------------------------------------------------------------------
-- 5. FUNCION AUXILIAR INTERNA DE VERIFICACION DE CONTEXTO DE SERVIDOR
--    Defensa en profundidad adicional a REVOKE/GRANT: si existe claim JWT de
--    PostgREST, exige estrictamente rol 'service_role'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION psicobloom_interno._exigir_contexto_servidor()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol_jwt TEXT := NULLIF(trim(COALESCE(current_setting('request.jwt.claim.role', TRUE), '')), '');
BEGIN
    IF v_rol_jwt IS NOT NULL AND v_rol_jwt <> 'service_role' THEN
        RAISE EXCEPTION 'Operacion restringida al servidor autorizado.'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION psicobloom_interno._exigir_contexto_servidor()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. RPC DE LECTURA PARA PACIENTE AUTENTICADO
--    Conserva intacto public.perfil_del_usuario_actual() y agrega esta RPC
--    dedicada para devolver foto_url y tiene_foto_personalizada del paciente.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_perfil_paciente_propio()
RETURNS TABLE(
    id UUID,
    id_paciente UUID,
    nombre TEXT,
    apellido TEXT,
    correo TEXT,
    rol public.rol_usuario,
    aprobacion public.estado_aprobacion,
    cuenta_activa BOOLEAN,
    foto_url TEXT,
    tiene_foto_personalizada BOOLEAN,
    foto_actualizada_en TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        pa.id_paciente,
        p.nombre,
        p.apellido,
        p.correo,
        p.rol,
        p.aprobacion,
        p.cuenta_activa,
        pa.foto_url,
        (pa.foto_url IS NOT NULL AND pa.foto_public_id IS NOT NULL) AS tiene_foto_personalizada,
        pa.foto_actualizada_en
    FROM psicobloom_interno.perfiles_compat p
    LEFT JOIN public."Pacientes" pa ON pa.id_usuario = p.id
    WHERE p.id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.obtener_perfil_paciente_propio()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.obtener_perfil_paciente_propio()
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. FUNCIONES DE SERVIDOR EXCLUSIVAS PARA service_role (Edge Function)
--    Ningun cliente (anon/authenticated) puede invocarlas directamente.
-- ---------------------------------------------------------------------------

-- 7.1 Consulta interna del estado actual de la fotografia del paciente.
CREATE OR REPLACE FUNCTION public.obtener_estado_foto_paciente_servidor(
    p_id_usuario UUID
)
RETURNS TABLE(
    id_paciente UUID,
    foto_url TEXT,
    foto_public_id TEXT,
    tiene_foto_personalizada BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes indicar un identificador de usuario valido.'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM psicobloom_interno.perfiles_compat p
        WHERE p.id = p_id_usuario
          AND p.rol = 'paciente'
          AND p.cuenta_activa = TRUE
    ) THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        pa.id_paciente,
        pa.foto_url,
        pa.foto_public_id,
        (pa.foto_url IS NOT NULL AND pa.foto_public_id IS NOT NULL) AS tiene_foto_personalizada
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = p_id_usuario;
END;
$$;

-- 7.2 Persistencia segura de nueva fotografia (con bloqueo FOR UPDATE para
--     serializar operaciones concurrentes y encolar atomicamente el public_id
--     anterior sustituido para su limpieza reintentable en Cloudinary).
CREATE OR REPLACE FUNCTION public.establecer_foto_paciente_servidor(
    p_id_usuario UUID,
    p_foto_url TEXT,
    p_foto_public_id TEXT
)
RETURNS TABLE(
    id_paciente UUID,
    foto_url TEXT,
    foto_public_id TEXT,
    foto_public_id_anterior TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
    v_public_id_anterior TEXT;
    v_url_limpia TEXT := NULLIF(trim(COALESCE(p_foto_url, '')), '');
    v_public_id_limpio TEXT := NULLIF(trim(COALESCE(p_foto_public_id, '')), '');
    v_prefijo_esperado TEXT;
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes indicar un identificador de usuario valido.'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM psicobloom_interno.perfiles_compat p
        WHERE p.id = p_id_usuario
          AND p.rol = 'paciente'
          AND p.cuenta_activa = TRUE
    ) THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa.'
            USING ERRCODE = '42501';
    END IF;

    IF v_url_limpia IS NULL
       OR v_url_limpia !~* '^https://res\.cloudinary\.com/[^[:space:]]+$' THEN
        RAISE EXCEPTION 'La URL de la fotografia no es valida.'
            USING ERRCODE = '22023';
    END IF;

    v_prefijo_esperado := 'psicobloom/pacientes/' || p_id_usuario::text || '_';
    IF v_public_id_limpio IS NULL
       OR v_public_id_limpio !~ '^psicobloom/pacientes/[0-9a-f-]{36}_[0-9a-f-]{36}$'
       OR position(v_prefijo_esperado IN v_public_id_limpio) <> 1 THEN
        RAISE EXCEPTION 'El identificador de recurso no pertenece al paciente autenticado.'
            USING ERRCODE = '42501';
    END IF;

    -- Bloqueo exclusivo de fila para serializar subidas y eliminaciones simultaneas.
    SELECT pa.id_paciente, pa.foto_public_id
    INTO v_id_paciente, v_public_id_anterior
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = p_id_usuario
    FOR UPDATE;

    IF v_id_paciente IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro de paciente asociado a la cuenta.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public."Pacientes"
    SET foto_url = v_url_limpia,
        foto_public_id = v_public_id_limpio,
        foto_actualizada_en = now()
    WHERE public."Pacientes".id_paciente = v_id_paciente;

    -- Encola atomicamente la foto anterior para limpieza segura en Cloudinary.
    IF v_public_id_anterior IS NOT NULL
       AND v_public_id_anterior <> v_public_id_limpio
       AND position(v_prefijo_esperado IN v_public_id_anterior) = 1 THEN
        INSERT INTO psicobloom_interno.limpieza_fotos_paciente_pendientes (
            id_usuario,
            foto_public_id,
            estado
        )
        VALUES (
            p_id_usuario,
            v_public_id_anterior,
            'pendiente'
        )
        ON CONFLICT ON CONSTRAINT uq_limpieza_fotos_paciente_public_id DO NOTHING;
    END IF;

    RETURN QUERY
    SELECT
        v_id_paciente,
        v_url_limpia,
        v_public_id_limpio,
        v_public_id_anterior;
END;
$$;

-- 7.3 Eliminacion segura en BD primero (bajo FOR UPDATE) + registro atomico
--     del recurso a limpiar en Cloudinary. Asi nunca quedan referencias rotas
--     en public."Pacientes" y las eliminaciones fallidas en Cloudinary pueden
--     reintentarse de forma confiable.
--     Se reemplaza cualquier firma anterior con 2 parametros de versiones previas.
DROP FUNCTION IF EXISTS public.eliminar_foto_paciente_servidor(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.eliminar_foto_paciente_servidor(
    p_id_usuario UUID
)
RETURNS TABLE(
    eliminada BOOLEAN,
    foto_public_id_eliminado TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
    v_public_id_actual TEXT;
    v_prefijo_esperado TEXT;
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes indicar un identificador de usuario valido.'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM psicobloom_interno.perfiles_compat p
        WHERE p.id = p_id_usuario
          AND p.rol = 'paciente'
          AND p.cuenta_activa = TRUE
    ) THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa.'
            USING ERRCODE = '42501';
    END IF;

    SELECT pa.id_paciente, pa.foto_public_id
    INTO v_id_paciente, v_public_id_actual
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = p_id_usuario
    FOR UPDATE;

    IF v_id_paciente IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro de paciente asociado a la cuenta.'
            USING ERRCODE = '22023';
    END IF;

    IF v_public_id_actual IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT;
        RETURN;
    END IF;

    v_prefijo_esperado := 'psicobloom/pacientes/' || p_id_usuario::text || '_';
    IF position(v_prefijo_esperado IN v_public_id_actual) <> 1 THEN
        RAISE EXCEPTION 'El identificador de recurso no pertenece al paciente autenticado.'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public."Pacientes"
    SET foto_url = NULL,
        foto_public_id = NULL,
        foto_actualizada_en = now()
    WHERE public."Pacientes".id_paciente = v_id_paciente;

    INSERT INTO psicobloom_interno.limpieza_fotos_paciente_pendientes (
        id_usuario,
        foto_public_id,
        estado
    )
    VALUES (
        p_id_usuario,
        v_public_id_actual,
        'pendiente'
    )
    ON CONFLICT ON CONSTRAINT uq_limpieza_fotos_paciente_public_id DO NOTHING;

    RETURN QUERY SELECT TRUE, v_public_id_actual;
END;
$$;

-- 7.4 Encola un recurso propio recien subido que no pudo persistirse en BD ni
--     borrarse inmediatamente en Cloudinary, evitando archivos huerfanos.
CREATE OR REPLACE FUNCTION public.encolar_limpieza_foto_paciente_servidor(
    p_id_usuario UUID,
    p_foto_public_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_public_id_limpio TEXT := NULLIF(trim(COALESCE(p_foto_public_id, '')), '');
    v_prefijo_esperado TEXT;
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes indicar un identificador de usuario valido.'
            USING ERRCODE = '22023';
    END IF;

    v_prefijo_esperado := 'psicobloom/pacientes/' || p_id_usuario::text || '_';
    IF v_public_id_limpio IS NULL
       OR v_public_id_limpio !~ '^psicobloom/pacientes/[0-9a-f-]{36}_[0-9a-f-]{36}$'
       OR position(v_prefijo_esperado IN v_public_id_limpio) <> 1 THEN
        RAISE EXCEPTION 'El identificador de recurso no pertenece al paciente autenticado.'
            USING ERRCODE = '42501';
    END IF;

    -- Nunca encola la foto actualmente activa del paciente.
    IF EXISTS (
        SELECT 1
        FROM public."Pacientes" pa
        WHERE pa.id_usuario = p_id_usuario
          AND pa.foto_public_id = v_public_id_limpio
    ) THEN
        RETURN;
    END IF;

    INSERT INTO psicobloom_interno.limpieza_fotos_paciente_pendientes (
        id_usuario,
        foto_public_id,
        estado
    )
    VALUES (
        p_id_usuario,
        v_public_id_limpio,
        'pendiente'
    )
    ON CONFLICT ON CONSTRAINT uq_limpieza_fotos_paciente_public_id DO NOTHING;
END;
$$;

-- 7.5 Reclama limpiezas pendientes del paciente con FOR UPDATE SKIP LOCKED y
--     arrendamiento temporal (60 s) para evitar borrados duplicados concurrentes
--     y permitir reintentos automaticos si una ejecucion previa fallo.
CREATE OR REPLACE FUNCTION public.reclamar_limpiezas_foto_paciente_pendientes_servidor(
    p_id_usuario UUID,
    p_limite INTEGER DEFAULT 5
)
RETURNS TABLE(
    foto_public_id TEXT,
    intentos INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_limite INTEGER := GREATEST(1, LEAST(COALESCE(p_limite, 5), 20));
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL THEN
        RAISE EXCEPTION 'Debes indicar un identificador de usuario valido.'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH candidatos AS (
        SELECT l.id
        FROM psicobloom_interno.limpieza_fotos_paciente_pendientes l
        WHERE l.id_usuario = p_id_usuario
          AND l.estado = 'pendiente'
          AND (l.bloqueado_hasta IS NULL OR l.bloqueado_hasta < now())
          AND NOT EXISTS (
              SELECT 1
              FROM public."Pacientes" pa
              WHERE pa.id_usuario = p_id_usuario
                AND pa.foto_public_id = l.foto_public_id
          )
        ORDER BY l.creado_en ASC
        LIMIT v_limite
        FOR UPDATE SKIP LOCKED
    ),
    reclamados AS (
        UPDATE psicobloom_interno.limpieza_fotos_paciente_pendientes l
        SET bloqueado_hasta = now() + interval '60 seconds',
            actualizado_en = now()
        FROM candidatos c
        WHERE l.id = c.id
        RETURNING l.foto_public_id, l.intentos
    )
    SELECT r.foto_public_id, r.intentos
    FROM reclamados r;
END;
$$;

-- 7.6 Registra el resultado de cada intento de eliminacion en Cloudinary.
CREATE OR REPLACE FUNCTION public.registrar_resultado_limpieza_foto_paciente_servidor(
    p_id_usuario UUID,
    p_foto_public_id TEXT,
    p_eliminado BOOLEAN,
    p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_public_id_limpio TEXT := NULLIF(trim(COALESCE(p_foto_public_id, '')), '');
    v_error_limpio TEXT := left(NULLIF(trim(COALESCE(p_error, '')), ''), 250);
BEGIN
    PERFORM psicobloom_interno._exigir_contexto_servidor();

    IF p_id_usuario IS NULL OR v_public_id_limpio IS NULL THEN
        RETURN;
    END IF;

    IF p_eliminado IS TRUE THEN
        UPDATE psicobloom_interno.limpieza_fotos_paciente_pendientes
        SET estado = 'eliminado',
            intentos = intentos + 1,
            bloqueado_hasta = NULL,
            ultimo_error = NULL,
            eliminado_en = now(),
            actualizado_en = now()
        WHERE id_usuario = p_id_usuario
          AND foto_public_id = v_public_id_limpio;
    ELSE
        UPDATE psicobloom_interno.limpieza_fotos_paciente_pendientes
        SET estado = 'pendiente',
            intentos = intentos + 1,
            bloqueado_hasta = now() + interval '30 seconds',
            ultimo_error = COALESCE(v_error_limpio, 'ERROR_CLOUDINARY'),
            actualizado_en = now()
        WHERE id_usuario = p_id_usuario
          AND foto_public_id = v_public_id_limpio;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION
    public.obtener_estado_foto_paciente_servidor(UUID),
    public.establecer_foto_paciente_servidor(UUID, TEXT, TEXT),
    public.eliminar_foto_paciente_servidor(UUID),
    public.encolar_limpieza_foto_paciente_servidor(UUID, TEXT),
    public.reclamar_limpiezas_foto_paciente_pendientes_servidor(UUID, INTEGER),
    public.registrar_resultado_limpieza_foto_paciente_servidor(UUID, TEXT, BOOLEAN, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.obtener_estado_foto_paciente_servidor(UUID),
    public.establecer_foto_paciente_servidor(UUID, TEXT, TEXT),
    public.eliminar_foto_paciente_servidor(UUID),
    public.encolar_limpieza_foto_paciente_servidor(UUID, TEXT),
    public.reclamar_limpiezas_foto_paciente_pendientes_servidor(UUID, INTEGER),
    public.registrar_resultado_limpieza_foto_paciente_servidor(UUID, TEXT, BOOLEAN, TEXT)
    TO service_role;

COMMIT;
