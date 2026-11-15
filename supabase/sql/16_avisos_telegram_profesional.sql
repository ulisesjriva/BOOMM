-- =============================================================================
-- SCRIPT 16 — MIGRACION ADITIVA DE AVISOS OPCIONALES POR TELEGRAM (PROFESIONAL)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar en: Supabase > SQL Editor como postgres
--
-- Proposito:
--   1. Almacenar vinculaciones privadas de Telegram, codigos temporales
--      hasheados (10 min, un solo uso) y cola persistente de avisos por cita.
--   2. Proteger todas las tablas en psicobloom_interno con RLS y privilegios
--      minimos (sin acceso directo para anon ni authenticated).
--   3. Encolar un evento unico al insertar una cita nueva en estado 'pendiente'
--      sin modificar las RPC de citas ni hacer llamadas HTTP dentro de SQL, y
--      sin generar avisos historicos para citas previas.
--   4. Exponer RPC autorizadas para el profesional autenticado (sin chat_id) y
--      funciones exclusivas de service_role para las Edge Functions.
-- =============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS psicobloom_interno;

-- ---------------------------------------------------------------------------
-- 1. TABLAS INTERNAS DE VINCULACION, CODIGOS Y COLA DE AVISOS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS psicobloom_interno.vinculaciones_telegram (
    id_profesional UUID PRIMARY KEY
        REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    id_vinculacion UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    chat_id BIGINT NOT NULL UNIQUE,
    conectado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS psicobloom_interno.codigos_vinculacion_telegram (
    id_codigo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_profesional UUID NOT NULL
        REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    hash_codigo TEXT NOT NULL UNIQUE,
    expira_en TIMESTAMPTZ NOT NULL,
    usado_en TIMESTAMPTZ NULL,
    anulado_en TIMESTAMPTZ NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_codigos_telegram_prof_pendientes
    ON psicobloom_interno.codigos_vinculacion_telegram (id_profesional, expira_en DESC)
    WHERE usado_en IS NULL AND anulado_en IS NULL;

CREATE TABLE IF NOT EXISTS psicobloom_interno.eventos_avisos_telegram (
    id_evento UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cita UUID NOT NULL UNIQUE
        REFERENCES public."Citas"(id_cita) ON DELETE CASCADE,
    id_profesional UUID NOT NULL
        REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    id_vinculacion UUID NOT NULL,
    estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'procesando', 'enviado', 'fallido', 'omitido')),
    intentos INTEGER NOT NULL DEFAULT 0,
    proximo_intento_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    bloqueado_hasta TIMESTAMPTZ NULL,
    ultimo_error TEXT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    enviado_en TIMESTAMPTZ NULL
);

CREATE INDEX IF NOT EXISTS idx_eventos_telegram_despacho
    ON psicobloom_interno.eventos_avisos_telegram (estado, proximo_intento_en)
    WHERE estado IN ('pendiente', 'procesando');

-- ---------------------------------------------------------------------------
-- 2. RLS Y PRIVILEGIOS MINIMOS
-- ---------------------------------------------------------------------------
ALTER TABLE psicobloom_interno.vinculaciones_telegram ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.codigos_vinculacion_telegram ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.eventos_avisos_telegram ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    psicobloom_interno.vinculaciones_telegram,
    psicobloom_interno.codigos_vinculacion_telegram,
    psicobloom_interno.eventos_avisos_telegram
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. TRIGGER ADITIVO AL INSERTAR NUEVA SOLICITUD REAL EN public."Citas"
--    - No genera avisos historicos sobre filas ya existentes.
--    - No realiza llamadas HTTP dentro de la transaccion SQL.
--    - Ante cualquier error inesperado de cola, no cancela la solicitud de cita.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION psicobloom_interno._encolar_aviso_telegram_nueva_cita()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
        RETURN NEW;
    END IF;

    INSERT INTO psicobloom_interno.eventos_avisos_telegram (
        id_cita,
        id_profesional,
        id_vinculacion
    )
    SELECT NEW.id_cita, NEW.id_profesional, v.id_vinculacion
    FROM psicobloom_interno.vinculaciones_telegram v
    JOIN public."Profesionales" p ON p.id_profesional = v.id_profesional
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = p.id_usuario
    WHERE v.id_profesional = NEW.id_profesional
      AND pe.cuenta_activa AND pe.rol = 'profesional'
    ON CONFLICT (id_cita) DO NOTHING;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'No se pudo encolar el aviso Telegram (SQLSTATE %).', SQLSTATE;
        RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_encolar_aviso_telegram_nueva_cita ON public."Citas";
CREATE TRIGGER trg_encolar_aviso_telegram_nueva_cita
    AFTER INSERT ON public."Citas"
    FOR EACH ROW
    EXECUTE FUNCTION psicobloom_interno._encolar_aviso_telegram_nueva_cita();

-- ---------------------------------------------------------------------------
-- 4. RPC AUTORIZADAS PARA EL PROFESIONAL AUTENTICADO (SIN EXPONER chat_id)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.estado_telegram_profesional_propio()
RETURNS TABLE(
    conectado BOOLEAN,
    conectado_en TIMESTAMPTZ,
    tiene_codigo_pendiente BOOLEAN,
    codigo_expira_en TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Solo un profesional con cuenta activa puede consultar su vinculación de Telegram.'
            USING ERRCODE = '42501';
    END IF;

    SELECT p.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" p
    WHERE p.id_usuario = auth.uid();

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontró un perfil profesional asociado a tu cuenta.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        EXISTS (
            SELECT 1
            FROM psicobloom_interno.vinculaciones_telegram v
            WHERE v.id_profesional = v_id_profesional
        ) AS conectado,
        (
            SELECT v.conectado_en
            FROM psicobloom_interno.vinculaciones_telegram v
            WHERE v.id_profesional = v_id_profesional
            LIMIT 1
        ) AS conectado_en,
        EXISTS (
            SELECT 1
            FROM psicobloom_interno.codigos_vinculacion_telegram c
            WHERE c.id_profesional = v_id_profesional
              AND c.usado_en IS NULL
              AND c.anulado_en IS NULL
              AND c.expira_en > now()
        ) AS tiene_codigo_pendiente,
        (
            SELECT c.expira_en
            FROM psicobloom_interno.codigos_vinculacion_telegram c
            WHERE c.id_profesional = v_id_profesional
              AND c.usado_en IS NULL
              AND c.anulado_en IS NULL
              AND c.expira_en > now()
            ORDER BY c.expira_en DESC
            LIMIT 1
        ) AS codigo_expira_en;
END;
$$;

CREATE OR REPLACE FUNCTION public.desconectar_telegram_profesional_propio()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Solo un profesional con cuenta activa puede desconectar su Telegram.'
            USING ERRCODE = '42501';
    END IF;

    SELECT p.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" p
    WHERE p.id_usuario = auth.uid();

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontró un perfil profesional asociado a tu cuenta.'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1 FROM public."Profesionales"
    WHERE id_profesional = v_id_profesional FOR UPDATE;

    UPDATE psicobloom_interno.eventos_avisos_telegram
    SET estado = 'omitido', bloqueado_hasta = NULL,
        ultimo_error = 'DESCONEXION', actualizado_en = now()
    WHERE id_profesional = v_id_profesional
      AND estado IN ('pendiente', 'procesando');

    DELETE FROM psicobloom_interno.vinculaciones_telegram
    WHERE id_profesional = v_id_profesional;

    UPDATE psicobloom_interno.codigos_vinculacion_telegram
    SET anulado_en = now()
    WHERE id_profesional = v_id_profesional
      AND usado_en IS NULL
      AND anulado_en IS NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. FUNCIONES EXCLUSIVAS DE service_role PARA EDGE FUNCTIONS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_codigo_vinculacion_telegram(
    p_id_profesional UUID,
    p_hash_codigo TEXT,
    p_expira_en TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF p_id_profesional IS NULL OR p_hash_codigo IS NULL
       OR p_hash_codigo !~ '^[0-9a-f]{64}$'
       OR p_expira_en IS NULL OR p_expira_en <= now()
       OR p_expira_en > now() + interval '10 minutes 30 seconds' THEN
        RAISE EXCEPTION 'Parámetros inválidos para generar código de vinculación.'
            USING ERRCODE = '22023';
    END IF;

    PERFORM 1 FROM public."Profesionales" p
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = p.id_usuario
    WHERE p.id_profesional = p_id_profesional
      AND pe.cuenta_activa AND pe.rol = 'profesional'
    FOR UPDATE OF p;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profesional no autorizado.' USING ERRCODE = '42501';
    END IF;

    UPDATE psicobloom_interno.codigos_vinculacion_telegram
    SET anulado_en = now()
    WHERE id_profesional = p_id_profesional
      AND usado_en IS NULL
      AND anulado_en IS NULL;

    INSERT INTO psicobloom_interno.codigos_vinculacion_telegram (
        id_profesional,
        hash_codigo,
        expira_en
    )
    VALUES (
        p_id_profesional,
        trim(p_hash_codigo),
        p_expira_en
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.consumir_codigo_vinculacion_telegram(
    p_hash_codigo TEXT,
    p_chat_id BIGINT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_codigo psicobloom_interno.codigos_vinculacion_telegram%ROWTYPE;
    v_prof_activo BOOLEAN;
    v_otro_profesional UUID;
BEGIN
    IF p_hash_codigo IS NULL OR length(trim(p_hash_codigo)) < 32 OR p_chat_id IS NULL OR p_chat_id <= 0 THEN
        RETURN 'codigo_invalido';
    END IF;

    SELECT * INTO v_codigo
    FROM psicobloom_interno.codigos_vinculacion_telegram
    WHERE hash_codigo = trim(p_hash_codigo);
    IF NOT FOUND THEN RETURN 'codigo_invalido'; END IF;

    PERFORM 1 FROM public."Profesionales"
    WHERE id_profesional = v_codigo.id_profesional FOR UPDATE;

    SELECT * INTO v_codigo
    FROM psicobloom_interno.codigos_vinculacion_telegram
    WHERE hash_codigo = trim(p_hash_codigo) FOR UPDATE;
    IF NOT FOUND THEN RETURN 'codigo_invalido'; END IF;

    IF v_codigo.usado_en IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM psicobloom_interno.vinculaciones_telegram v
            WHERE v.id_profesional = v_codigo.id_profesional AND v.chat_id = p_chat_id) THEN
            RETURN 'ya_vinculado';
        END IF;
        RETURN 'codigo_usado';
    END IF;

    IF v_codigo.anulado_en IS NOT NULL THEN
        RETURN 'codigo_anulado';
    END IF;

    IF v_codigo.expira_en <= now() THEN
        RETURN 'codigo_expirado';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public."Profesionales" pr
        JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
        WHERE pr.id_profesional = v_codigo.id_profesional
          AND pe.rol = 'profesional'
          AND pe.cuenta_activa = TRUE
    )
    INTO v_prof_activo;

    IF NOT v_prof_activo THEN
        RETURN 'profesional_inactivo';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('telegram-chat:' || p_chat_id::text, 0));

    SELECT v.id_profesional
    INTO v_otro_profesional
    FROM psicobloom_interno.vinculaciones_telegram v
    WHERE v.chat_id = p_chat_id
      AND v.id_profesional <> v_codigo.id_profesional
    LIMIT 1;

    IF v_otro_profesional IS NOT NULL THEN
        RETURN 'chat_en_uso_por_otro';
    END IF;

    UPDATE psicobloom_interno.codigos_vinculacion_telegram
    SET usado_en = now()
    WHERE id_codigo = v_codigo.id_codigo;

    UPDATE psicobloom_interno.codigos_vinculacion_telegram
    SET anulado_en = now()
    WHERE id_profesional = v_codigo.id_profesional
      AND id_codigo <> v_codigo.id_codigo
      AND usado_en IS NULL
      AND anulado_en IS NULL;

    INSERT INTO psicobloom_interno.vinculaciones_telegram (
        id_profesional,
        chat_id,
        conectado_en,
        actualizado_en
    )
    VALUES (
        v_codigo.id_profesional,
        p_chat_id,
        now(),
        now()
    )
    ON CONFLICT (id_profesional) DO UPDATE
    SET chat_id = EXCLUDED.chat_id,
        id_vinculacion = gen_random_uuid(),
        conectado_en = now(),
        actualizado_en = now();

    UPDATE psicobloom_interno.eventos_avisos_telegram e
    SET estado = 'omitido', bloqueado_hasta = NULL,
        ultimo_error = 'VINCULACION_CAMBIADA', actualizado_en = now()
    WHERE e.id_profesional = v_codigo.id_profesional
      AND e.estado IN ('pendiente', 'procesando')
      AND NOT EXISTS (SELECT 1 FROM psicobloom_interno.vinculaciones_telegram v
          WHERE v.id_vinculacion = e.id_vinculacion);

    RETURN 'vinculado';
END;
$$;

CREATE OR REPLACE FUNCTION public.reclamar_eventos_avisos_telegram(
    p_limite INTEGER DEFAULT 10,
    p_bloqueo_segundos INTEGER DEFAULT 60
)
RETURNS TABLE(
    id_evento UUID,
    id_cita UUID,
    id_profesional UUID,
    intentos INTEGER,
    chat_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_limite INTEGER := GREATEST(1, LEAST(COALESCE(p_limite, 10), 50));
    v_bloqueo INTERVAL := make_interval(secs => GREATEST(15, LEAST(COALESCE(p_bloqueo_segundos, 60), 300)));
BEGIN
    UPDATE psicobloom_interno.eventos_avisos_telegram e
    SET estado = 'fallido', bloqueado_hasta = NULL,
        ultimo_error = 'MAXIMO_INTENTOS', actualizado_en = now()
    WHERE e.intentos >= 5 AND (
        e.estado = 'pendiente' OR
        (e.estado = 'procesando' AND e.bloqueado_hasta <= now()));

    UPDATE psicobloom_interno.eventos_avisos_telegram e
    SET estado = 'omitido', bloqueado_hasta = NULL,
        ultimo_error = 'SIN_VINCULACION_O_SOLICITUD_ACTIVA', actualizado_en = now()
    WHERE e.estado IN ('pendiente', 'procesando') AND NOT EXISTS (
        SELECT 1 FROM psicobloom_interno.vinculaciones_telegram v
        JOIN public."Profesionales" p ON p.id_profesional = v.id_profesional
        JOIN psicobloom_interno.perfiles_compat pe ON pe.id = p.id_usuario
        JOIN public."Citas" c ON c.id_cita = e.id_cita
        WHERE v.id_vinculacion = e.id_vinculacion
          AND v.id_profesional = e.id_profesional
          AND pe.cuenta_activa AND pe.rol = 'profesional'
          AND c.estado = 'pendiente');

    RETURN QUERY
    WITH candidatos AS (
        SELECT e.id_evento
        FROM psicobloom_interno.eventos_avisos_telegram e
        WHERE e.intentos < 5 AND (
            (e.estado = 'pendiente' AND e.proximo_intento_en <= now())
            OR (e.estado = 'procesando' AND e.bloqueado_hasta IS NOT NULL AND e.bloqueado_hasta <= now()))
        ORDER BY e.creado_en ASC
        LIMIT v_limite
        FOR UPDATE OF e SKIP LOCKED
    ),
    actualizados AS (
        UPDATE psicobloom_interno.eventos_avisos_telegram e
        SET estado = 'procesando',
            bloqueado_hasta = now() + v_bloqueo,
            intentos = e.intentos + 1,
            actualizado_en = now()
        FROM candidatos c
        WHERE e.id_evento = c.id_evento
        RETURNING e.id_evento, e.id_cita, e.id_profesional, e.intentos, e.id_vinculacion
    )
    SELECT
        a.id_evento,
        a.id_cita,
        a.id_profesional,
        a.intentos,
        v.chat_id
    FROM actualizados a
    LEFT JOIN psicobloom_interno.vinculaciones_telegram v
        ON v.id_profesional = a.id_profesional AND v.id_vinculacion = a.id_vinculacion;
END;
$$;

-- El trabajador antiguo no puede finalizar una reserva recuperada por otro.
DROP FUNCTION IF EXISTS public.finalizar_evento_aviso_telegram(UUID, TEXT, TEXT, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION public.finalizar_evento_aviso_telegram(
    p_id_evento UUID,
    p_resultado TEXT,
    p_error TEXT DEFAULT NULL,
    p_reintentar_en TIMESTAMPTZ DEFAULT NULL,
    p_intento_esperado INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE v_filas INTEGER;
BEGIN
    IF p_resultado NOT IN ('enviado', 'omitido', 'reintentar', 'fallido')
       OR p_resultado IS NULL OR p_intento_esperado IS NULL THEN
        RAISE EXCEPTION 'Resultado o reserva inválidos.' USING ERRCODE = '22023';
    END IF;
    UPDATE psicobloom_interno.eventos_avisos_telegram e
    SET estado = CASE
            WHEN p_resultado = 'reintentar' AND e.intentos < 5 THEN 'pendiente'
            WHEN p_resultado = 'reintentar' THEN 'fallido'
            ELSE p_resultado END,
        enviado_en = CASE WHEN p_resultado = 'enviado' THEN now() ELSE e.enviado_en END,
        proximo_intento_en = CASE WHEN p_resultado = 'reintentar'
            THEN COALESCE(p_reintentar_en, now() + interval '1 minute') ELSE e.proximo_intento_en END,
        bloqueado_hasta = NULL,
        ultimo_error = CASE WHEN p_resultado = 'enviado' THEN NULL ELSE left(p_error, 120) END,
        actualizado_en = now()
    WHERE e.id_evento = p_id_evento AND e.estado = 'procesando'
      AND e.intentos = p_intento_esperado AND e.bloqueado_hasta > now();
    GET DIAGNOSTICS v_filas = ROW_COUNT;
    RETURN v_filas = 1;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. PERMISOS DE EJECUCION
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
    psicobloom_interno._encolar_aviso_telegram_nueva_cita(),
    public.estado_telegram_profesional_propio(),
    public.desconectar_telegram_profesional_propio(),
    public.crear_codigo_vinculacion_telegram(UUID, TEXT, TIMESTAMPTZ),
    public.consumir_codigo_vinculacion_telegram(TEXT, BIGINT),
    public.reclamar_eventos_avisos_telegram(INTEGER, INTEGER),
    public.finalizar_evento_aviso_telegram(UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.estado_telegram_profesional_propio(),
    public.desconectar_telegram_profesional_propio()
    TO authenticated;

GRANT EXECUTE ON FUNCTION
    public.crear_codigo_vinculacion_telegram(UUID, TEXT, TIMESTAMPTZ),
    public.consumir_codigo_vinculacion_telegram(TEXT, BIGINT),
    public.reclamar_eventos_avisos_telegram(INTEGER, INTEGER),
    public.finalizar_evento_aviso_telegram(UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER)
    TO service_role;

COMMIT;

-- =============================================================================
-- PROGRAMACION DEL DESPACHADOR (SIN CREDENCIALES EN SQL)
-- Ejecutar manualmente en Supabase SQL Editor si se usa pg_cron + pg_net,
-- guardando previamente la URL del proyecto y el token del despachador en
-- Supabase Vault (nunca literales en este archivo):
--
-- SELECT cron.schedule(
--   'despachar-avisos-telegram-cada-minuto',
--   '* * * * *',
--   $$
--   SELECT net.http_post(
--     url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'psicobloom_supabase_url')
--            || '/functions/v1/despachar-avisos-telegram',
--     headers := jsonb_build_object(
--       'Content-Type', 'application/json',
--       'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'psicobloom_service_role_key')
--     ),
--     body := '{}'::jsonb
--   );
--   $$
-- );
-- =============================================================================
