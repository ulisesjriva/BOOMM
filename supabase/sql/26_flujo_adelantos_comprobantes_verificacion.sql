-- =============================================================================
-- SCRIPT 26 — MIGRACION ADITIVA: SOLICITUD CON ADELANTO, QR PRIVADO,
--             COMPROBANTE, VERIFICACION, INCIDENCIAS Y VENCIMIENTO (ETAPA 4)
-- Proyecto: PsicoBloom (esquemas: public, psicobloom_interno y storage)
-- Ejecutar en: Supabase > SQL Editor como postgres (DESPUES de 22, 23, 24 y 25)
--
-- Garantias principales:
--   1. NO modifica los scripts 22 a 25 ya aplicados ni altera citas anteriores.
--   2. Citas sin adelanto conservan exactamente su flujo actual.
--   3. Autorizacion estricta: rechaza explicitamente v_rol IS NULL y cuentas
--      desactivadas (incluido un profesional titular inactivo).
--   4. Funciones de mantenimiento (vencer_adelantos_expirados,
--      encolar_avisos_revision_demorada, reclamar/finalizar eventos) revocadas
--      a PUBLIC, anon y authenticated; otorgadas solo a service_role (sin usar
--      current_user dentro de SECURITY DEFINER).
--   5. Compatibilidad total con dias no laborables (script 14): tras rechazo
--      o vencimiento en un dia no laborable, el horario pasa a 'bloqueada' y
--      NUNCA a 'disponible'.
--   6. Oferta versionada y aceptacion expresa de condiciones en servidor.
--   7. Idempotencia estricta verificando paciente, profesional y horario.
--   8. Cola de avisos Telegram con reintentos/bloqueos (sin HTTP en SQL y sin
--      comprobantes ni datos bancarios).
-- =============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS psicobloom_interno;

-- ---------------------------------------------------------------------------
-- 1. TABLAS INTERNAS DE ADELANTOS, COMPROBANTES, OBSERVACIONES, INCIDENCIAS Y AVISOS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS psicobloom_interno.adelantos_citas (
    id_cita UUID PRIMARY KEY
        REFERENCES public."Citas"(id_cita) ON DELETE RESTRICT,
    id_paciente UUID NOT NULL
        REFERENCES public."Pacientes"(id_paciente) ON DELETE RESTRICT,
    id_profesional UUID NOT NULL
        REFERENCES public."Profesionales"(id_profesional) ON DELETE RESTRICT,
    requiere_adelanto BOOLEAN NOT NULL DEFAULT TRUE CHECK (requiere_adelanto = TRUE),
    estado_adelanto TEXT NOT NULL DEFAULT 'pendiente_aceptacion'
        CHECK (
            estado_adelanto IN (
                'pendiente_aceptacion',
                'pendiente_adelanto',
                'comprobante_en_revision',
                'observado',
                'verificado',
                'vencido_sin_pago',
                'incidencia_pago',
                'rechazado_sin_pago'
            )
        ),
    moneda TEXT NOT NULL DEFAULT 'USD' CHECK (moneda = 'USD'),
    precio_consulta NUMERIC(10, 2) NOT NULL CHECK (precio_consulta > 0),
    monto_adelanto NUMERIC(10, 2) NOT NULL CHECK (monto_adelanto > 0 AND monto_adelanto <= precio_consulta),
    saldo_despues_adelanto NUMERIC(10, 2) NOT NULL CHECK (saldo_despues_adelanto = precio_consulta - monto_adelanto),
    ruta_qr_storage TEXT NOT NULL CHECK (
        nullif(trim(ruta_qr_storage), '') IS NOT NULL
        AND ruta_qr_storage NOT LIKE 'http://%'
        AND ruta_qr_storage NOT LIKE 'https://%'
        AND ruta_qr_storage NOT LIKE '%..%'
    ),
    banco_beneficiario TEXT NOT NULL CHECK (char_length(trim(banco_beneficiario)) >= 2),
    titular_beneficiario TEXT NOT NULL CHECK (char_length(trim(titular_beneficiario)) >= 3),
    tipo_cuenta_beneficiario TEXT NULL,
    numero_cuenta_referencia TEXT NULL,
    condiciones_aceptadas TEXT NOT NULL,
    version_oferta_aceptada TEXT NOT NULL,
    condiciones_aceptadas_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    clave_idempotencia_solicitud TEXT NULL,
    aceptado_para_pago_en TIMESTAMPTZ NULL,
    limite_pago_en TIMESTAMPTZ NULL,
    comprobante_enviado_en TIMESTAMPTZ NULL,
    limite_revision_en TIMESTAMPTZ NULL,
    verificado_por UUID NULL,
    verificado_en TIMESTAMPTZ NULL,
    vencido_en TIMESTAMPTZ NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_adelantos_citas_idempotencia UNIQUE (id_paciente, clave_idempotencia_solicitud)
);

CREATE INDEX IF NOT EXISTS idx_adelantos_citas_estado_limites
    ON psicobloom_interno.adelantos_citas (estado_adelanto, limite_pago_en, limite_revision_en);

CREATE INDEX IF NOT EXISTS idx_adelantos_citas_profesional
    ON psicobloom_interno.adelantos_citas (id_profesional, estado_adelanto);

CREATE TABLE IF NOT EXISTS psicobloom_interno.comprobantes_adelanto (
    id_comprobante UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cita UUID NOT NULL
        REFERENCES psicobloom_interno.adelantos_citas(id_cita) ON DELETE RESTRICT,
    ruta_storage TEXT NOT NULL CHECK (
        nullif(trim(ruta_storage), '') IS NOT NULL
        AND ruta_storage NOT LIKE 'http://%'
        AND ruta_storage NOT LIKE 'https://%'
        AND ruta_storage NOT LIKE '%..%'
    ),
    nota_paciente TEXT NULL,
    clave_idempotencia TEXT NULL,
    creado_por UUID NOT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_comprobantes_idempotencia UNIQUE (id_cita, clave_idempotencia)
);

CREATE INDEX IF NOT EXISTS idx_comprobantes_adelanto_cita
    ON psicobloom_interno.comprobantes_adelanto (id_cita, creado_en DESC);

CREATE TABLE IF NOT EXISTS psicobloom_interno.observaciones_adelanto (
    id_observacion UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cita UUID NOT NULL
        REFERENCES psicobloom_interno.adelantos_citas(id_cita) ON DELETE RESTRICT,
    tipo_actor TEXT NOT NULL CHECK (tipo_actor IN ('profesional', 'paciente')),
    mensaje TEXT NOT NULL CHECK (char_length(trim(mensaje)) >= 5 AND char_length(trim(mensaje)) <= 500),
    creado_por UUID NOT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_observaciones_adelanto_cita
    ON psicobloom_interno.observaciones_adelanto (id_cita, creado_en DESC);

CREATE TABLE IF NOT EXISTS psicobloom_interno.incidencias_adelanto (
    id_incidencia UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cita UUID NOT NULL
        REFERENCES psicobloom_interno.adelantos_citas(id_cita) ON DELETE RESTRICT,
    detalle TEXT NOT NULL CHECK (char_length(trim(detalle)) >= 5 AND char_length(trim(detalle)) <= 500),
    horario_ya_liberado BOOLEAN NOT NULL DEFAULT FALSE,
    estado_incidencia TEXT NOT NULL DEFAULT 'pendiente_revision'
        CHECK (estado_incidencia IN ('pendiente_revision', 'en_revision', 'resuelta')),
    clave_idempotencia TEXT NULL,
    creado_por UUID NOT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_incidencias_idempotencia UNIQUE (id_cita, clave_idempotencia)
);

CREATE INDEX IF NOT EXISTS idx_incidencias_adelanto_cita
    ON psicobloom_interno.incidencias_adelanto (id_cita, creado_en DESC);

-- Cola interna de avisos de adelanto compatible con el despachador Telegram
-- (vinculada a id_vinculacion, reintentos <= 5, bloqueo temporal, sin HTTP en SQL
-- y sin comprobantes ni datos bancarios)
CREATE TABLE IF NOT EXISTS psicobloom_interno.eventos_avisos_adelanto (
    id_evento UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cita UUID NOT NULL REFERENCES public."Citas"(id_cita) ON DELETE CASCADE,
    id_profesional UUID NOT NULL REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    id_vinculacion UUID NOT NULL,
    tipo_evento TEXT NOT NULL CHECK (
        tipo_evento IN ('comprobante_enviado', 'revision_demorada', 'incidencia_pago')
    ),
    referencia_evento TEXT NOT NULL,
    estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'procesando', 'enviado', 'fallido', 'omitido')),
    intentos INTEGER NOT NULL DEFAULT 0,
    proximo_intento_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    bloqueado_hasta TIMESTAMPTZ NULL,
    ultimo_error TEXT NULL,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    enviado_en TIMESTAMPTZ NULL,
    CONSTRAINT uq_eventos_avisos_adelanto_unico UNIQUE (id_cita, tipo_evento, referencia_evento)
);

CREATE INDEX IF NOT EXISTS idx_eventos_avisos_adelanto_despacho
    ON psicobloom_interno.eventos_avisos_adelanto (estado, proximo_intento_en)
    WHERE estado IN ('pendiente', 'procesando');

-- RLS y privilegios minimos: ningun acceso directo a tablas internas desde clientes
ALTER TABLE psicobloom_interno.adelantos_citas ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.comprobantes_adelanto ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.observaciones_adelanto ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.incidencias_adelanto ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.eventos_avisos_adelanto ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    psicobloom_interno.adelantos_citas,
    psicobloom_interno.comprobantes_adelanto,
    psicobloom_interno.observaciones_adelanto,
    psicobloom_interno.incidencias_adelanto,
    psicobloom_interno.eventos_avisos_adelanto
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. BUCKET PRIVADO SEPARADO PARA COMPROBANTES Y ACCESO PRIVADO AL QR POR CITA
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'comprobantes-adelantos',
    'comprobantes-adelantos',
    FALSE,
    5242880,
    ARRAY['image/png', 'image/jpeg']
)
ON CONFLICT (id) DO UPDATE
SET public = FALSE,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Helper interno de huella de oferta (deterministico sobre configuracion vigente)
CREATE OR REPLACE FUNCTION psicobloom_interno._calcular_version_oferta(
    p_cobro psicobloom_interno.configuracion_cobro_profesional
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT md5(
        coalesce(p_cobro.requiere_adelanto::TEXT, '') || '|' ||
        coalesce(p_cobro.moneda, '') || '|' ||
        coalesce(p_cobro.precio_consulta::TEXT, '') || '|' ||
        coalesce(p_cobro.monto_adelanto::TEXT, '') || '|' ||
        coalesce(p_cobro.ruta_qr_storage, '') || '|' ||
        coalesce(p_cobro.banco_beneficiario, '') || '|' ||
        coalesce(p_cobro.titular_beneficiario, '') || '|' ||
        coalesce(p_cobro.actualizado_en::TEXT, '')
    );
$$;

REVOKE ALL ON FUNCTION
    psicobloom_interno._calcular_version_oferta(psicobloom_interno.configuracion_cobro_profesional)
    FROM PUBLIC, anon, authenticated;

-- Helper SECURITY DEFINER: autoriza al paciente titular activo a leer UNICAMENTE
-- el QR exacto de su solicitud aceptada pendiente de adelanto / en revision / observada.
CREATE OR REPLACE FUNCTION public._paciente_puede_ver_qr_cobro(p_ruta_qr TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        public._rol_activo() = 'paciente'
        AND EXISTS (
            SELECT 1
            FROM psicobloom_interno.adelantos_citas a
            JOIN public."Pacientes" pa ON pa.id_paciente = a.id_paciente
            WHERE pa.id_usuario = auth.uid()
              AND a.ruta_qr_storage = p_ruta_qr
              AND a.estado_adelanto IN (
                  'pendiente_adelanto',
                  'comprobante_en_revision',
                  'observado',
                  'incidencia_pago'
              )
        );
$$;

-- Helper SECURITY DEFINER: autoriza al paciente titular activo a subir comprobante
-- con ruta `<id_cita>/<auth.uid()>/comp_...` solo si su cita acepta comprobante.
CREATE OR REPLACE FUNCTION public._paciente_puede_subir_comprobante(p_nombre_objeto TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol TEXT := public._rol_activo();
    v_carpetas TEXT[];
    v_id_cita UUID;
BEGIN
    IF v_rol IS NULL OR v_rol IS DISTINCT FROM 'paciente' THEN
        RETURN FALSE;
    END IF;

    v_carpetas := storage.foldername(p_nombre_objeto);
    IF array_length(v_carpetas, 1) < 2 THEN
        RETURN FALSE;
    END IF;

    IF v_carpetas[2] IS DISTINCT FROM auth.uid()::TEXT THEN
        RETURN FALSE;
    END IF;

    BEGIN
        v_id_cita := v_carpetas[1]::UUID;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN FALSE;
    END;

    RETURN EXISTS (
        SELECT 1
        FROM psicobloom_interno.adelantos_citas a
        JOIN public."Pacientes" pa ON pa.id_paciente = a.id_paciente
        WHERE a.id_cita = v_id_cita
          AND pa.id_usuario = auth.uid()
          AND (
              (a.estado_adelanto = 'pendiente_adelanto' AND (a.limite_pago_en IS NULL OR now() <= a.limite_pago_en))
              OR a.estado_adelanto IN ('observado', 'incidencia_pago')
          )
    );
END;
$$;

-- Helper SECURITY DEFINER: autoriza lectura de comprobantes UNICAMENTE al
-- paciente titular ACTIVO o al profesional titular ACTIVO (rechaza NULL e inactivos).
CREATE OR REPLACE FUNCTION public._usuario_puede_ver_comprobante(p_nombre_objeto TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol TEXT := public._rol_activo();
    v_carpetas TEXT[];
    v_id_cita UUID;
BEGIN
    IF v_rol IS NULL OR v_rol NOT IN ('paciente', 'profesional') THEN
        RETURN FALSE;
    END IF;

    v_carpetas := storage.foldername(p_nombre_objeto);
    IF array_length(v_carpetas, 1) < 2 THEN
        RETURN FALSE;
    END IF;

    BEGIN
        v_id_cita := v_carpetas[1]::UUID;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN FALSE;
    END;

    IF v_rol = 'paciente' THEN
        RETURN EXISTS (
            SELECT 1
            FROM psicobloom_interno.adelantos_citas a
            JOIN public."Pacientes" pa ON pa.id_paciente = a.id_paciente
            WHERE a.id_cita = v_id_cita
              AND pa.id_usuario = auth.uid()
        );
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM psicobloom_interno.adelantos_citas a
        JOIN public."Profesionales" pr ON pr.id_profesional = a.id_profesional
        WHERE a.id_cita = v_id_cita
          AND pr.id_usuario = auth.uid()
    );
END;
$$;

REVOKE ALL ON FUNCTION
    public._paciente_puede_ver_qr_cobro(TEXT),
    public._paciente_puede_subir_comprobante(TEXT),
    public._usuario_puede_ver_comprobante(TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public._paciente_puede_ver_qr_cobro(TEXT),
    public._paciente_puede_subir_comprobante(TEXT),
    public._usuario_puede_ver_comprobante(TEXT)
    TO authenticated;

-- Politica acotada en qr-cobro-profesionales para el paciente titular de cita aceptada
DROP POLICY IF EXISTS qr_cobro_paciente_cita_aceptada ON storage.objects;
CREATE POLICY qr_cobro_paciente_cita_aceptada
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'qr-cobro-profesionales'
    AND public._paciente_puede_ver_qr_cobro(name)
);

-- Politicas estrictas en comprobantes-adelantos (SOLO SELECT e INSERT; sin UPDATE ni DELETE)
DROP POLICY IF EXISTS comprobantes_adelanto_insertar_paciente ON storage.objects;
CREATE POLICY comprobantes_adelanto_insertar_paciente
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'comprobantes-adelantos'
    AND public._paciente_puede_subir_comprobante(name)
);

DROP POLICY IF EXISTS comprobantes_adelanto_leer_partes_cita ON storage.objects;
CREATE POLICY comprobantes_adelanto_leer_partes_cita
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'comprobantes-adelantos'
    AND public._usuario_puede_ver_comprobante(name)
);

DROP POLICY IF EXISTS comprobantes_adelanto_actualizar ON storage.objects;
DROP POLICY IF EXISTS comprobantes_adelanto_eliminar ON storage.objects;

-- ---------------------------------------------------------------------------
-- 3. ACTUALIZAR TRIGGERS DE DISPONIBILIDAD Y CITAS (COMPATIBLE CON 10 Y 14)
--    - Conserva todas las reglas de dias no laborables del script 14.
--    - Tras rechazo o vencimiento en dia no laborable: permite 'reservada' -> 'bloqueada'
--      unicamente desde contextos autorizados ('rechazo_profesional', 'vencimiento_adelanto').
--    - Protege citas con adelanto reportado/verificado contra cancelacion directa.
--    - Permite vencimiento automatico incluso si la cuenta profesional fue desactivada.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validar_disponibilidad_profesional()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_tiene_cita_activa BOOLEAN;
    v_tiene_cita_historica BOOLEAN;
    v_contexto_respuesta TEXT := COALESCE(current_setting('psicobloom.contexto_respuesta_cita', TRUE), '');
BEGIN
    IF NEW.id_profesional IS NULL OR NEW.fecha IS NULL OR NEW.hora_inicio IS NULL OR NEW.hora_fin IS NULL THEN
        RAISE EXCEPTION 'Debes indicar profesional, fecha, hora de inicio y hora de fin.' USING ERRCODE = '22023';
    END IF;

    IF NEW.hora_fin <= NEW.hora_inicio THEN
        RAISE EXCEPTION 'La hora de finalizacion debe ser posterior a la hora de inicio.' USING ERRCODE = '23514';
    END IF;

    IF NEW.estado NOT IN ('disponible', 'reservada', 'bloqueada') THEN
        RAISE EXCEPTION 'El estado del horario no es valido.' USING ERRCODE = '23514';
    END IF;

    PERFORM 1
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = NEW.id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el profesional asociado al horario.' USING ERRCODE = '23503';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF (NEW.fecha + NEW.hora_inicio) <= v_ahora_ecuador THEN
            RAISE EXCEPTION 'No se permiten crear intervalos en fechas u horas pasadas (hora de Ecuador).' USING ERRCODE = '22023';
        END IF;

        IF NEW.estado = 'reservada' THEN
            RAISE EXCEPTION 'El estado reservada solo se asigna mediante el flujo de citas.' USING ERRCODE = '22023';
        END IF;

        IF public._es_dia_no_laborable_profesional(NEW.id_profesional, NEW.fecha) THEN
            RAISE EXCEPTION 'No se pueden crear horarios en una fecha marcada como dia no laborable (%). Retira primero la excepcion si deseas agregar horarios.', NEW.fecha
                USING ERRCODE = '22023';
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.id_profesional IS DISTINCT FROM OLD.id_profesional THEN
            RAISE EXCEPTION 'No se permite reasignar un horario a otro profesional.' USING ERRCODE = '42501';
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = OLD.id_disponibilidad
              AND c.id_profesional = OLD.id_profesional
              AND c.estado IN ('pendiente', 'confirmada')
        ) INTO v_tiene_cita_activa;

        SELECT EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = OLD.id_disponibilidad
        ) INTO v_tiene_cita_historica;

        IF NEW.fecha IS DISTINCT FROM OLD.fecha
           OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
           OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin THEN

            IF OLD.estado <> 'disponible' OR v_tiene_cita_activa OR v_tiene_cita_historica THEN
                RAISE EXCEPTION 'No se pueden cambiar fecha ni horas de un horario con citas vinculadas, incluidas las rechazadas. Registra otro horario para usar un intervalo diferente.' USING ERRCODE = '22023';
            END IF;

            IF public._es_dia_no_laborable_profesional(OLD.id_profesional, OLD.fecha)
               OR public._es_dia_no_laborable_profesional(NEW.id_profesional, NEW.fecha) THEN
                RAISE EXCEPTION 'No se pueden editar horarios en una fecha marcada como dia no laborable.' USING ERRCODE = '22023';
            END IF;

            IF (OLD.fecha + OLD.hora_inicio) <= v_ahora_ecuador THEN
                RAISE EXCEPTION 'No se pueden editar horarios que ya iniciaron o pertenecen al pasado.' USING ERRCODE = '22023';
            END IF;

            IF (NEW.fecha + NEW.hora_inicio) <= v_ahora_ecuador THEN
                RAISE EXCEPTION 'La nueva fecha y hora de inicio deben ser futuras (hora de Ecuador).' USING ERRCODE = '22023';
            END IF;
        END IF;

        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF NEW.estado = 'reservada' THEN
                IF public._rol_activo() = 'profesional' THEN
                    RAISE EXCEPTION 'No puedes cambiar manualmente un horario al estado reservada.' USING ERRCODE = '22023';
                END IF;
                IF NOT v_tiene_cita_activa THEN
                    RAISE EXCEPTION 'El estado reservada requiere una cita activa vinculada al horario.' USING ERRCODE = '22023';
                END IF;
            END IF;

            IF v_tiene_cita_activa AND NEW.estado IN ('disponible', 'bloqueada') THEN
                RAISE EXCEPTION 'No se puede bloquear ni liberar un horario que tiene una cita activa.' USING ERRCODE = '22023';
            END IF;

            -- Regla del script 14: jamas habilitar como 'disponible' en dia no laborable
            IF NEW.estado = 'disponible'
               AND public._es_dia_no_laborable_profesional(NEW.id_profesional, NEW.fecha) THEN
                RAISE EXCEPTION 'No se puede desbloquear ni habilitar un horario en una fecha marcada como dia no laborable. Retira primero la excepcion del dia.' USING ERRCODE = '22023';
            END IF;

            -- Solo permitir 'reservada' -> 'bloqueada' desde flujos autorizados (rechazo o vencimiento)
            IF OLD.estado = 'reservada'
               AND NEW.estado = 'bloqueada'
               AND v_contexto_respuesta NOT IN ('rechazo_profesional', 'vencimiento_adelanto') THEN
                RAISE EXCEPTION 'No se puede bloquear directamente un horario reservado.' USING ERRCODE = '22023';
            END IF;

            -- Solo permitir 'reservada' -> 'disponible' desde flujos autorizados
            IF OLD.estado = 'reservada'
               AND NEW.estado = 'disponible'
               AND v_contexto_respuesta NOT IN ('rechazo_profesional', 'vencimiento_adelanto') THEN
                RAISE EXCEPTION 'No se puede liberar manualmente un horario reservado fuera de los flujos autorizados.' USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Disponibilidad" d
        WHERE d.id_profesional = NEW.id_profesional
          AND d.fecha = NEW.fecha
          AND d.id_disponibilidad IS DISTINCT FROM NEW.id_disponibilidad
          AND d.hora_inicio < NEW.hora_fin
          AND d.hora_fin > NEW.hora_inicio
    ) THEN
        RAISE EXCEPTION 'El intervalo se superpone con otro horario registrado en esa fecha.' USING ERRCODE = '23P01';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validar_profesional_aprobado_en_citas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_horario public."Disponibilidad"%ROWTYPE;
    v_contexto TEXT := COALESCE(current_setting('psicobloom.contexto_respuesta_cita', TRUE), '');
    v_estado_adelanto TEXT;
BEGIN
    -- Permitir vencimiento automatico de reservas sin pago incluso si el
    -- profesional fue desactivado despues de aceptar la cita.
    IF NOT (
        TG_OP = 'UPDATE'
        AND NEW.estado = 'cancelada'
        AND v_contexto = 'vencimiento_adelanto'
    ) THEN
        IF NOT public._profesional_es_publicable(NEW.id_profesional) THEN
            RAISE EXCEPTION 'No se permiten operaciones de citas con profesionales pendientes de aprobacion o inactivos.' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NOT public._paciente_esta_activo(NEW.id_paciente) THEN
            RAISE EXCEPTION 'La cuenta del paciente debe estar activa para registrar una cita.' USING ERRCODE = '42501';
        END IF;

        IF public._rol_activo() = 'paciente' THEN
            IF NOT public._es_paciente_propio(NEW.id_paciente) THEN
                RAISE EXCEPTION 'No puedes registrar solicitudes de cita en nombre de otro paciente.' USING ERRCODE = '42501';
            END IF;
            IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
                RAISE EXCEPTION 'Las solicitudes creadas por el paciente deben iniciar en estado pendiente.' USING ERRCODE = '22023';
            END IF;
        END IF;

        SELECT *
        INTO v_horario
        FROM public."Disponibilidad" d
        WHERE d.id_disponibilidad = NEW.id_disponibilidad
          AND d.id_profesional = NEW.id_profesional;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'El horario seleccionado no pertenece al profesional indicado.' USING ERRCODE = '22023';
        END IF;

        -- Regla del script 14: impedir nuevas solicitudes en dia no laborable
        IF public._es_dia_no_laborable_profesional(NEW.id_profesional, v_horario.fecha) THEN
            RAISE EXCEPTION 'El profesional marco esta fecha como dia no laborable y no admite nuevas solicitudes.' USING ERRCODE = '23P01';
        END IF;

        IF v_horario.estado <> 'disponible' THEN
            RAISE EXCEPTION 'El horario seleccionado ya no se encuentra disponible.' USING ERRCODE = '23P01';
        END IF;

        IF (v_horario.fecha + v_horario.hora_inicio) <= v_ahora_ecuador THEN
            RAISE EXCEPTION 'No se pueden solicitar citas en horarios que ya iniciaron o pertenecen al pasado.' USING ERRCODE = '22023';
        END IF;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.id_cita IS DISTINCT FROM OLD.id_cita
           OR NEW.id_paciente IS DISTINCT FROM OLD.id_paciente
           OR NEW.id_profesional IS DISTINCT FROM OLD.id_profesional
           OR NEW.id_disponibilidad IS DISTINCT FROM OLD.id_disponibilidad
           OR NEW.fecha_solicitud IS DISTINCT FROM OLD.fecha_solicitud THEN
            RAISE EXCEPTION 'No se permite modificar los identificadores ni la fecha de solicitud de una cita existente.' USING ERRCODE = '42501';
        END IF;

        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF NEW.estado = 'pendiente' THEN
                RAISE EXCEPTION 'No se puede revertir una cita respondida al estado pendiente.' USING ERRCODE = '22023';
            END IF;

            -- Proteccion contra cancelaciones que omitan el tratamiento de adelanto
            IF NEW.estado = 'cancelada' AND v_contexto IS DISTINCT FROM 'vencimiento_adelanto' THEN
                SELECT a.estado_adelanto
                INTO v_estado_adelanto
                FROM psicobloom_interno.adelantos_citas a
                WHERE a.id_cita = OLD.id_cita;

                IF v_estado_adelanto IN ('comprobante_en_revision', 'observado', 'incidencia_pago', 'verificado') THEN
                    RAISE EXCEPTION 'Esta cita tiene un adelanto reportado o verificado y requiere revisión; la cancelación con tratamiento de adelanto aún no está habilitada.'
                        USING ERRCODE = '23P01';
                END IF;
            END IF;

            IF NEW.estado IN ('confirmada', 'rechazada') THEN
                IF public._rol_activo() IS DISTINCT FROM 'profesional'
                   OR NOT public._es_profesional_propio(OLD.id_profesional) THEN
                    RAISE EXCEPTION 'Solo el profesional titular con cuenta activa y aprobada puede confirmar o rechazar la solicitud.' USING ERRCODE = '42501';
                END IF;

                IF OLD.estado IS DISTINCT FROM 'pendiente' THEN
                    RAISE EXCEPTION 'Solo se pueden responder solicitudes que se encuentren en estado pendiente.' USING ERRCODE = '23P01';
                END IF;

                SELECT *
                INTO v_horario
                FROM public."Disponibilidad" d
                WHERE d.id_disponibilidad = OLD.id_disponibilidad
                  AND d.id_profesional = OLD.id_profesional;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'No se encontro el horario asociado a la solicitud.' USING ERRCODE = '22023';
                END IF;

                IF (v_horario.fecha + v_horario.hora_inicio) <= v_ahora_ecuador THEN
                    RAISE EXCEPTION 'No se puede responder una solicitud cuyo intervalo ya ha comenzado (hora de Ecuador).' USING ERRCODE = '22023';
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. RPC DE OFERTA VERSIONADA Y ACTUALIZACION DE SOLICITUD / RESPUESTA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_oferta_adelanto_profesional(
    p_id_profesional UUID
)
RETURNS TABLE(
    tiene_configuracion BOOLEAN,
    moneda TEXT,
    precio_consulta NUMERIC(10, 2),
    requiere_adelanto BOOLEAN,
    monto_adelanto_exigible NUMERIC(10, 2),
    saldo_despues_adelanto NUMERIC(10, 2),
    version_oferta TEXT,
    condiciones_texto TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol TEXT := public._rol_activo();
    v_id_profesional UUID;
    v_cobro psicobloom_interno.configuracion_cobro_profesional%ROWTYPE;
    v_adelanto NUMERIC(10, 2);
BEGIN
    IF v_rol IS NULL OR v_rol NOT IN ('paciente', 'profesional', 'administrador') THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa autorizada para consultar la oferta económica.'
            USING ERRCODE = '42501';
    END IF;

    IF p_id_profesional IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el profesional a consultar.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = p_id_profesional OR pr.id_usuario = p_id_profesional;

    IF v_id_profesional IS NULL OR NOT public._profesional_es_publicable(v_id_profesional) THEN
        RETURN;
    END IF;

    SELECT * INTO v_cobro
    FROM psicobloom_interno.configuracion_cobro_profesional c
    WHERE c.id_profesional = v_id_profesional;

    IF NOT FOUND OR v_cobro.precio_consulta IS NULL THEN
        RETURN QUERY
        SELECT
            FALSE::BOOLEAN,
            'USD'::TEXT,
            NULL::NUMERIC(10, 2),
            FALSE::BOOLEAN,
            NULL::NUMERIC(10, 2),
            NULL::NUMERIC(10, 2),
            NULL::TEXT,
            NULL::TEXT;
        RETURN;
    END IF;

    IF v_cobro.requiere_adelanto IS TRUE AND v_cobro.monto_adelanto IS NOT NULL THEN
        v_adelanto := v_cobro.monto_adelanto;
    ELSE
        v_adelanto := 0.00::NUMERIC(10, 2);
    END IF;

    RETURN QUERY
    SELECT
        TRUE::BOOLEAN,
        v_cobro.moneda,
        v_cobro.precio_consulta,
        (v_cobro.requiere_adelanto IS TRUE)::BOOLEAN,
        v_adelanto,
        (v_cobro.precio_consulta - v_adelanto)::NUMERIC(10, 2),
        psicobloom_interno._calcular_version_oferta(v_cobro),
        CASE
            WHEN v_cobro.requiere_adelanto IS TRUE THEN
                'Solicitud con adelanto: debes solicitar con más de 24 horas de anticipación. Si el profesional acepta, dispondrás hasta exactamente 24 horas antes del inicio de la cita para transferir y adjuntar tu comprobante privado. El profesional dispone de 12 horas para verificar el ingreso.'
            ELSE NULL
        END;
END;
$$;

DROP FUNCTION IF EXISTS public.solicitar_cita_paciente(UUID, UUID);
DROP FUNCTION IF EXISTS public.solicitar_cita_paciente(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS public.solicitar_cita_paciente(UUID, UUID, TEXT, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.solicitar_cita_paciente(
    p_id_profesional UUID,
    p_id_disponibilidad UUID,
    p_clave_idempotencia TEXT DEFAULT NULL,
    p_acepta_condiciones_adelanto BOOLEAN DEFAULT FALSE,
    p_version_oferta_adelanto TEXT DEFAULT NULL
)
RETURNS TABLE(
    id_cita UUID,
    id_paciente UUID,
    id_profesional UUID,
    id_disponibilidad UUID,
    nombre_profesional TEXT,
    especialidad_profesional TEXT,
    modalidad_profesional TEXT,
    direccion_consultorio TEXT,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT,
    fecha_solicitud TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
    v_id_profesional UUID;
    v_id_usuario_profesional UUID;
    v_ahora_tz TIMESTAMPTZ := now();
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (v_ahora_tz AT TIME ZONE 'America/Guayaquil');
    v_inicio_cita_tz TIMESTAMPTZ;
    v_horario public."Disponibilidad"%ROWTYPE;
    v_cita public."Citas"%ROWTYPE;
    v_cobro psicobloom_interno.configuracion_cobro_profesional%ROWTYPE;
    v_requiere_adelanto BOOLEAN := FALSE;
    v_version_actual TEXT;
    v_clave_limpia TEXT := nullif(trim(coalesce(p_clave_idempotencia, '')), '');
    v_cita_existente public."Citas"%ROWTYPE;
    v_filas_actualizadas INTEGER := 0;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa para solicitar una cita.' USING ERRCODE = '42501';
    END IF;

    IF p_id_profesional IS NULL OR p_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'Debes seleccionar un profesional y un horario disponible.' USING ERRCODE = '22023';
    END IF;

    SELECT pa.id_paciente
    INTO v_id_paciente
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = auth.uid();

    IF v_id_paciente IS NULL OR NOT public._paciente_esta_activo(v_id_paciente) THEN
        RAISE EXCEPTION 'No se encontro un perfil de paciente activo asociado a tu sesion.' USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional, pr.id_usuario
    INTO v_id_profesional, v_id_usuario_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = p_id_profesional
       OR pr.id_usuario = p_id_profesional;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'El profesional indicado no existe.' USING ERRCODE = '22023';
    END IF;

    -- Idempotencia estricta: verifica que la clave corresponda al MISMO paciente,
    -- MISMO profesional y MISMO horario; rechaza reutilizacion con otros parametros.
    IF v_clave_limpia IS NOT NULL THEN
        SELECT c.*
        INTO v_cita_existente
        FROM psicobloom_interno.adelantos_citas a
        JOIN public."Citas" c ON c.id_cita = a.id_cita
        WHERE a.id_paciente = v_id_paciente
          AND a.clave_idempotencia_solicitud = v_clave_limpia;

        IF FOUND THEN
            IF v_cita_existente.id_profesional IS DISTINCT FROM v_id_profesional
               OR v_cita_existente.id_disponibilidad IS DISTINCT FROM p_id_disponibilidad THEN
                RAISE EXCEPTION 'La clave de idempotencia ya fue utilizada para otra solicitud distinta.'
                    USING ERRCODE = '23505';
            END IF;

            RETURN QUERY
            SELECT
                c.id_cita,
                c.id_paciente,
                c.id_profesional,
                c.id_disponibilidad,
                trim(p.nombre || ' ' || p.apellido) AS nombre_profesional,
                COALESCE(
                    (
                        SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                        FROM public."ProfesionalEspecialidad" pe
                        JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                        WHERE pe.id_profesional = pr.id_profesional
                    ),
                    NULLIF(trim(dp.especialidad), ''),
                    'Psicología General'
                ) AS especialidad_profesional,
                COALESCE(pr.modalidad, 'Presencial') AS modalidad_profesional,
                COALESCE(pr.direccion_consultorio, '') AS direccion_consultorio,
                d.fecha,
                d.hora_inicio,
                d.hora_fin,
                c.estado,
                c.fecha_solicitud
            FROM public."Citas" c
            JOIN public."Disponibilidad" d ON d.id_disponibilidad = c.id_disponibilidad
            JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
            JOIN psicobloom_interno.perfiles_compat p ON p.id = pr.id_usuario
            LEFT JOIN psicobloom_interno.detalle_profesional dp ON dp.id = pr.id_profesional
            WHERE c.id_cita = v_cita_existente.id_cita;
            RETURN;
        END IF;
    END IF;

    IF v_id_paciente = v_id_profesional OR v_id_usuario_profesional = auth.uid() THEN
        RAISE EXCEPTION 'No puedes solicitar una cita contigo mismo.' USING ERRCODE = '22023';
    END IF;

    -- 1er bloqueo canonico: Profesionales
    PERFORM 1
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'El profesional seleccionado no se encuentra aprobado o activo para recibir solicitudes.' USING ERRCODE = '42501';
    END IF;

    -- 2do bloqueo canonico: Disponibilidad
    SELECT *
    INTO v_horario
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El horario seleccionado no existe o no pertenece al profesional indicado.' USING ERRCODE = '22023';
    END IF;

    IF public._es_dia_no_laborable_profesional(v_id_profesional, v_horario.fecha) THEN
        RAISE EXCEPTION 'El profesional marco esa fecha como dia no laborable. Elige otro horario disponible.' USING ERRCODE = '22023';
    END IF;

    IF (v_horario.fecha + v_horario.hora_inicio) <= v_ahora_ecuador THEN
        RAISE EXCEPTION 'El horario seleccionado ya inicio o pertenece a una fecha u hora pasada (hora de Ecuador).' USING ERRCODE = '22023';
    END IF;

    -- Consultar configuracion vigente de cobro del profesional
    SELECT *
    INTO v_cobro
    FROM psicobloom_interno.configuracion_cobro_profesional c
    WHERE c.id_profesional = v_id_profesional;

    v_requiere_adelanto := FOUND AND v_cobro.requiere_adelanto IS TRUE;

    IF v_requiere_adelanto THEN
        -- Exigir aceptacion expresa de condiciones y coincidencia con la oferta vigente
        IF p_acepta_condiciones_adelanto IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'Debes aceptar expresamente las condiciones del adelanto antes de enviar la solicitud.'
                USING ERRCODE = '22023';
        END IF;

        v_version_actual := psicobloom_interno._calcular_version_oferta(v_cobro);
        IF nullif(trim(coalesce(p_version_oferta_adelanto, '')), '') IS DISTINCT FROM v_version_actual THEN
            RAISE EXCEPTION 'Las condiciones o tarifa de adelanto cambiaron recientemente. Actualiza el resumen y vuelve a aceptar.'
                USING ERRCODE = '40001';
        END IF;

        v_inicio_cita_tz := ((v_horario.fecha + v_horario.hora_inicio) AT TIME ZONE 'America/Guayaquil');
        IF v_inicio_cita_tz <= (v_ahora_tz + INTERVAL '24 hours') THEN
            RAISE EXCEPTION 'Para citas con adelanto debes solicitar con más de 24 horas de anticipación (hora de Ecuador).'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_horario.id_disponibilidad
          AND c.id_paciente = v_id_paciente
          AND c.estado IN ('pendiente', 'confirmada')
    ) THEN
        RAISE EXCEPTION 'Ya registraste una solicitud activa para este horario. Puedes consultarla en Mis citas.' USING ERRCODE = '23505';
    END IF;

    IF v_horario.estado <> 'disponible' OR EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_horario.id_disponibilidad
          AND c.estado IN ('pendiente', 'confirmada')
    ) THEN
        RAISE EXCEPTION 'Este horario acaba de ser ocupado por otro paciente o ya no esta disponible. Elige otro intervalo.' USING ERRCODE = '23P01';
    END IF;

    INSERT INTO public."Citas" (
        id_paciente,
        id_profesional,
        id_disponibilidad,
        estado
    )
    VALUES (
        v_id_paciente,
        v_id_profesional,
        v_horario.id_disponibilidad,
        'pendiente'
    )
    RETURNING * INTO v_cita;

    UPDATE public."Disponibilidad" d
    SET estado = 'reservada'
    WHERE d.id_disponibilidad = v_horario.id_disponibilidad
      AND d.id_profesional = v_id_profesional
      AND d.estado = 'disponible';

    GET DIAGNOSTICS v_filas_actualizadas = ROW_COUNT;
    IF v_filas_actualizadas <> 1 THEN
        RAISE EXCEPTION 'No fue posible reservar el horario seleccionado; la operacion se revirtio.' USING ERRCODE = '23P01';
    END IF;

    -- Instantanea inmutable del adelanto y QR/beneficiario leida exclusivamente del servidor
    IF v_requiere_adelanto THEN
        INSERT INTO psicobloom_interno.adelantos_citas (
            id_cita,
            id_paciente,
            id_profesional,
            requiere_adelanto,
            estado_adelanto,
            moneda,
            precio_consulta,
            monto_adelanto,
            saldo_despues_adelanto,
            ruta_qr_storage,
            banco_beneficiario,
            titular_beneficiario,
            tipo_cuenta_beneficiario,
            numero_cuenta_referencia,
            condiciones_aceptadas,
            version_oferta_aceptada,
            condiciones_aceptadas_en,
            clave_idempotencia_solicitud
        )
        VALUES (
            v_cita.id_cita,
            v_id_paciente,
            v_id_profesional,
            TRUE,
            'pendiente_aceptacion',
            v_cobro.moneda,
            v_cobro.precio_consulta,
            v_cobro.monto_adelanto,
            (v_cobro.precio_consulta - v_cobro.monto_adelanto)::NUMERIC(10, 2),
            v_cobro.ruta_qr_storage,
            v_cobro.banco_beneficiario,
            v_cobro.titular_beneficiario,
            v_cobro.tipo_cuenta_beneficiario,
            v_cobro.numero_cuenta_referencia,
            'Solicitud con adelanto: debes solicitar con más de 24 horas de anticipación. Si el profesional acepta, dispondrás hasta exactamente 24 horas antes del inicio de la cita para transferir y adjuntar tu comprobante privado. El profesional dispone de 12 horas para verificar el ingreso.',
            v_version_actual,
            v_ahora_tz,
            v_clave_limpia
        );
    END IF;

    RETURN QUERY
    SELECT
        v_cita.id_cita,
        v_cita.id_paciente,
        v_cita.id_profesional,
        v_cita.id_disponibilidad,
        trim(p.nombre || ' ' || p.apellido) AS nombre_profesional,
        COALESCE(
            (
                SELECT string_agg(e.nombre, ', ' ORDER BY e.nombre)
                FROM public."ProfesionalEspecialidad" pe
                JOIN public."Especialidades" e ON e.id_especialidad = pe.id_especialidad
                WHERE pe.id_profesional = pr.id_profesional
            ),
            NULLIF(trim(dp.especialidad), ''),
            'Psicología General'
        ) AS especialidad_profesional,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad_profesional,
        COALESCE(pr.direccion_consultorio, '') AS direccion_consultorio,
        v_horario.fecha,
        v_horario.hora_inicio,
        v_horario.hora_fin,
        v_cita.estado,
        v_cita.fecha_solicitud
    FROM public."Profesionales" pr
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pr.id_usuario
    LEFT JOIN psicobloom_interno.detalle_profesional dp ON dp.id = pr.id_profesional
    WHERE pr.id_profesional = v_id_profesional;
END;
$$;

-- Actualizar responder_solicitud_cita_profesional respetando dias no laborables (script 14)
CREATE OR REPLACE FUNCTION public.responder_solicitud_cita_profesional(
    p_id_cita UUID,
    p_decision TEXT
)
RETURNS TABLE(
    id_cita UUID,
    id_paciente UUID,
    id_profesional UUID,
    id_disponibilidad UUID,
    nombre_paciente TEXT,
    modalidad_profesional TEXT,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT,
    estado_disponibilidad TEXT,
    fecha_solicitud TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_id_disponibilidad UUID;
    v_decision_limpia TEXT := lower(trim(COALESCE(p_decision, '')));
    v_nuevo_estado TEXT;
    v_ahora_tz TIMESTAMPTZ := now();
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (v_ahora_tz AT TIME ZONE 'America/Guayaquil');
    v_inicio_cita_tz TIMESTAMPTZ;
    v_horario public."Disponibilidad"%ROWTYPE;
    v_cita public."Citas"%ROWTYPE;
    v_adelanto psicobloom_interno.adelantos_citas%ROWTYPE;
    v_tiene_adelanto BOOLEAN := FALSE;
    v_existe_otra_cita_activa BOOLEAN := FALSE;
    v_estado_destino_horario TEXT;
    v_filas_disp INTEGER := 0;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa para responder solicitudes de citas.' USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la solicitud de cita a responder.' USING ERRCODE = '22023';
    END IF;

    IF v_decision_limpia IN ('confirmada', 'aceptar', 'aceptada') THEN
        v_nuevo_estado := 'confirmada';
    ELSIF v_decision_limpia IN ('rechazada', 'rechazar') THEN
        v_nuevo_estado := 'rechazada';
    ELSE
        RAISE EXCEPTION 'La decision indicada no es valida. Usa confirmada o rechazada.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '42501';
    END IF;

    IF NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'Tu perfil profesional debe estar aprobado y activo para responder solicitudes de citas.' USING ERRCODE = '42501';
    END IF;

    SELECT c.id_disponibilidad
    INTO v_id_disponibilidad
    FROM public."Citas" c
    WHERE c.id_cita = p_id_cita
      AND c.id_profesional = v_id_profesional;

    IF v_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'La solicitud indicada no existe o no pertenece a tu perfil profesional.' USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_horario
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = v_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontro el horario asociado a la solicitud.' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_cita
    FROM public."Citas" c
    WHERE c.id_cita = p_id_cita
      AND c.id_profesional = v_id_profesional
    FOR UPDATE;

    IF v_cita.estado IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION 'Esta solicitud ya fue respondida anteriormente (estado actual: %) y no puede modificarse.', v_cita.estado
            USING ERRCODE = '23P01';
    END IF;

    IF (v_horario.fecha + v_horario.hora_inicio) <= v_ahora_ecuador THEN
        RAISE EXCEPTION 'No se puede responder una solicitud cuyo intervalo ya ha comenzado (hora de Ecuador).' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_adelanto
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = v_cita.id_cita
    FOR UPDATE;
    v_tiene_adelanto := FOUND;

    IF v_tiene_adelanto AND v_adelanto.estado_adelanto IS DISTINCT FROM 'pendiente_aceptacion' THEN
        RAISE EXCEPTION 'Esta solicitud con adelanto ya fue aceptada previamente (estado de adelanto: %). Usa la revisión de comprobante para confirmarla.', v_adelanto.estado_adelanto
            USING ERRCODE = '23P01';
    END IF;

    IF v_nuevo_estado = 'confirmada' THEN
        IF v_horario.estado IS DISTINCT FROM 'reservada' THEN
            RAISE EXCEPTION 'El horario asociado no se encuentra reservado; no se pudo continuar.' USING ERRCODE = '23P01';
        END IF;

        IF v_tiene_adelanto THEN
            v_inicio_cita_tz := ((v_horario.fecha + v_horario.hora_inicio) AT TIME ZONE 'America/Guayaquil');
            IF v_inicio_cita_tz <= (v_ahora_tz + INTERVAL '24 hours') THEN
                RAISE EXCEPTION 'Solo se puede aceptar una solicitud con adelanto cuando faltan más de 24 horas para la cita (hora de Ecuador).'
                    USING ERRCODE = '22023';
            END IF;

            UPDATE psicobloom_interno.adelantos_citas a
            SET estado_adelanto = 'pendiente_adelanto',
                aceptado_para_pago_en = v_ahora_tz,
                limite_pago_en = (v_inicio_cita_tz - INTERVAL '24 hours'),
                actualizado_en = v_ahora_tz
            WHERE a.id_cita = v_cita.id_cita
              AND a.estado_adelanto = 'pendiente_aceptacion';
        ELSE
            UPDATE public."Citas" c
            SET estado = 'confirmada'
            WHERE c.id_cita = v_cita.id_cita
              AND c.id_profesional = v_id_profesional
              AND c.estado = 'pendiente'
            RETURNING * INTO v_cita;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'No fue posible confirmar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
            END IF;
        END IF;
    ELSE
        UPDATE public."Citas" c
        SET estado = 'rechazada'
        WHERE c.id_cita = v_cita.id_cita
          AND c.id_profesional = v_id_profesional
          AND c.estado = 'pendiente'
        RETURNING * INTO v_cita;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No fue posible rechazar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
        END IF;

        IF v_tiene_adelanto THEN
            UPDATE psicobloom_interno.adelantos_citas a
            SET estado_adelanto = 'rechazado_sin_pago',
                actualizado_en = v_ahora_tz
            WHERE a.id_cita = v_cita.id_cita;
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = v_horario.id_disponibilidad
              AND c.id_profesional = v_id_profesional
              AND c.id_cita <> v_cita.id_cita
              AND c.estado IN ('pendiente', 'confirmada')
        ) INTO v_existe_otra_cita_activa;

        IF NOT v_existe_otra_cita_activa THEN
            -- Compatibilidad con script 14: si es dia no laborable, pasa a 'bloqueada'
            v_estado_destino_horario := CASE
                WHEN public._es_dia_no_laborable_profesional(v_id_profesional, v_horario.fecha)
                THEN 'bloqueada'
                ELSE 'disponible'
            END;

            PERFORM set_config('psicobloom.contexto_respuesta_cita', 'rechazo_profesional', TRUE);

            UPDATE public."Disponibilidad" d
            SET estado = v_estado_destino_horario
            WHERE d.id_disponibilidad = v_horario.id_disponibilidad
              AND d.id_profesional = v_id_profesional
              AND d.estado = 'reservada'
            RETURNING * INTO v_horario;

            GET DIAGNOSTICS v_filas_disp = ROW_COUNT;
            PERFORM set_config('psicobloom.contexto_respuesta_cita', '', TRUE);

            IF v_filas_disp <> 1 THEN
                RAISE EXCEPTION 'No fue posible actualizar el horario tras rechazar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
            END IF;
        END IF;
    END IF;

    RETURN QUERY
    SELECT
        v_cita.id_cita,
        v_cita.id_paciente,
        v_cita.id_profesional,
        v_cita.id_disponibilidad,
        trim(p.nombre || ' ' || p.apellido) AS nombre_paciente,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad_profesional,
        v_horario.fecha,
        v_horario.hora_inicio,
        v_horario.hora_fin,
        v_cita.estado,
        v_horario.estado AS estado_disponibilidad,
        v_cita.fecha_solicitud
    FROM public."Profesionales" pr
    JOIN public."Pacientes" pa ON pa.id_paciente = v_cita.id_paciente
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pa.id_usuario
    WHERE pr.id_profesional = v_id_profesional;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. RPC DE ADELANTOS PARA CLIENTES AUTENTICADOS
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_adelantos_citas_visibles()
RETURNS TABLE(
    id_cita UUID,
    estado_adelanto TEXT,
    moneda TEXT,
    precio_consulta NUMERIC(10, 2),
    monto_adelanto NUMERIC(10, 2),
    saldo_despues_adelanto NUMERIC(10, 2),
    limite_pago_en TIMESTAMPTZ,
    comprobante_enviado_en TIMESTAMPTZ,
    limite_revision_en TIMESTAMPTZ,
    revision_demorada BOOLEAN,
    verificado_en TIMESTAMPTZ,
    tiene_incidencia BOOLEAN,
    total_comprobantes INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol TEXT := public._rol_activo();
BEGIN
    IF v_rol IS NULL OR v_rol NOT IN ('paciente', 'profesional', 'administrador') THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa autorizada.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        a.id_cita,
        a.estado_adelanto,
        a.moneda,
        a.precio_consulta,
        a.monto_adelanto,
        a.saldo_despues_adelanto,
        a.limite_pago_en,
        a.comprobante_enviado_en,
        a.limite_revision_en,
        (a.estado_adelanto = 'comprobante_en_revision' AND a.limite_revision_en IS NOT NULL AND now() > a.limite_revision_en) AS revision_demorada,
        a.verificado_en,
        EXISTS (
            SELECT 1 FROM psicobloom_interno.incidencias_adelanto inc
            WHERE inc.id_cita = a.id_cita
        ) AS tiene_incidencia,
        (
            SELECT count(*)::INTEGER FROM psicobloom_interno.comprobantes_adelanto comp
            WHERE comp.id_cita = a.id_cita
        ) AS total_comprobantes
    FROM psicobloom_interno.adelantos_citas a
    LEFT JOIN public."Pacientes" pa ON pa.id_paciente = a.id_paciente
    LEFT JOIN public."Profesionales" pr ON pr.id_profesional = a.id_profesional
    WHERE v_rol = 'administrador'
       OR (v_rol = 'paciente' AND pa.id_usuario = auth.uid())
       OR (v_rol = 'profesional' AND pr.id_usuario = auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION public.obtener_detalle_adelanto_cita(p_id_cita UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol TEXT := public._rol_activo();
    v_a psicobloom_interno.adelantos_citas%ROWTYPE;
    v_es_titular BOOLEAN := FALSE;
    v_mostrar_datos_pago BOOLEAN := FALSE;
    v_comprobantes JSONB := '[]'::jsonb;
    v_observaciones JSONB := '[]'::jsonb;
    v_incidencias JSONB := '[]'::jsonb;
BEGIN
    IF v_rol IS NULL OR v_rol NOT IN ('paciente', 'profesional') THEN
        RAISE EXCEPTION 'Solo el paciente o el profesional titular activos pueden consultar el detalle privado del adelanto.'
            USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la cita a consultar.' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_a
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = p_id_cita;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF v_rol = 'paciente' THEN
        SELECT EXISTS (
            SELECT 1 FROM public."Pacientes" pa
            WHERE pa.id_paciente = v_a.id_paciente AND pa.id_usuario = auth.uid()
        ) INTO v_es_titular;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM public."Profesionales" pr
            WHERE pr.id_profesional = v_a.id_profesional AND pr.id_usuario = auth.uid()
        ) INTO v_es_titular;
    END IF;

    IF NOT v_es_titular THEN
        RAISE EXCEPTION 'No tienes permiso para consultar el detalle de adelanto de esta cita.'
            USING ERRCODE = '42501';
    END IF;

    v_mostrar_datos_pago := (
        v_rol = 'profesional'
        OR v_a.estado_adelanto IN ('pendiente_adelanto', 'comprobante_en_revision', 'observado', 'incidencia_pago')
    );

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_comprobante', c.id_comprobante,
            'ruta_storage', c.ruta_storage,
            'nota_paciente', c.nota_paciente,
            'creado_en', c.creado_en
        ) ORDER BY c.creado_en DESC
    ), '[]'::jsonb)
    INTO v_comprobantes
    FROM psicobloom_interno.comprobantes_adelanto c
    WHERE c.id_cita = v_a.id_cita;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_observacion', o.id_observacion,
            'tipo_actor', o.tipo_actor,
            'mensaje', o.mensaje,
            'creado_en', o.creado_en
        ) ORDER BY o.creado_en DESC
    ), '[]'::jsonb)
    INTO v_observaciones
    FROM psicobloom_interno.observaciones_adelanto o
    WHERE o.id_cita = v_a.id_cita;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id_incidencia', i.id_incidencia,
            'detalle', i.detalle,
            'horario_ya_liberado', i.horario_ya_liberado,
            'estado_incidencia', i.estado_incidencia,
            'creado_en', i.creado_en
        ) ORDER BY i.creado_en DESC
    ), '[]'::jsonb)
    INTO v_incidencias
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_cita = v_a.id_cita;

    RETURN jsonb_build_object(
        'id_cita', v_a.id_cita,
        'estado_adelanto', v_a.estado_adelanto,
        'moneda', v_a.moneda,
        'precio_consulta', v_a.precio_consulta,
        'monto_adelanto', v_a.monto_adelanto,
        'saldo_despues_adelanto', v_a.saldo_despues_adelanto,
        'condiciones_aceptadas', v_a.condiciones_aceptadas,
        'ruta_qr_storage', CASE WHEN v_mostrar_datos_pago THEN v_a.ruta_qr_storage ELSE NULL END,
        'banco_beneficiario', CASE WHEN v_mostrar_datos_pago THEN v_a.banco_beneficiario ELSE NULL END,
        'titular_beneficiario', CASE WHEN v_mostrar_datos_pago THEN v_a.titular_beneficiario ELSE NULL END,
        'tipo_cuenta_beneficiario', CASE WHEN v_mostrar_datos_pago THEN v_a.tipo_cuenta_beneficiario ELSE NULL END,
        'numero_cuenta_referencia', CASE WHEN v_mostrar_datos_pago THEN v_a.numero_cuenta_referencia ELSE NULL END,
        'aceptado_para_pago_en', v_a.aceptado_para_pago_en,
        'limite_pago_en', v_a.limite_pago_en,
        'comprobante_enviado_en', v_a.comprobante_enviado_en,
        'limite_revision_en', v_a.limite_revision_en,
        'revision_demorada', (v_a.estado_adelanto = 'comprobante_en_revision' AND v_a.limite_revision_en IS NOT NULL AND now() > v_a.limite_revision_en),
        'verificado_por', v_a.verificado_por,
        'verificado_en', v_a.verificado_en,
        'vencido_en', v_a.vencido_en,
        'hora_servidor', now(),
        'comprobantes', v_comprobantes,
        'observaciones', v_observaciones,
        'incidencias', v_incidencias
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_comprobante_adelanto(
    p_id_cita UUID,
    p_ruta_storage TEXT,
    p_nota_paciente TEXT DEFAULT NULL,
    p_clave_idempotencia TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
    v_ahora TIMESTAMPTZ := now();
    v_ruta TEXT := trim(coalesce(p_ruta_storage, ''));
    v_nota TEXT := nullif(trim(coalesce(p_nota_paciente, '')), '');
    v_clave TEXT := nullif(trim(coalesce(p_clave_idempotencia, '')), '');
    v_a psicobloom_interno.adelantos_citas%ROWTYPE;
    v_comp_existente psicobloom_interno.comprobantes_adelanto%ROWTYPE;
    v_comp_id UUID;
    v_objeto_existe BOOLEAN := FALSE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Solo un paciente con cuenta activa puede enviar un comprobante.' USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL OR v_ruta = '' THEN
        RAISE EXCEPTION 'Debes indicar la cita y la ruta privada del comprobante.' USING ERRCODE = '22023';
    END IF;

    IF v_ruta LIKE 'http://%' OR v_ruta LIKE 'https://%' OR v_ruta LIKE '%..%' THEN
        RAISE EXCEPTION 'Debes registrar únicamente la ruta privada del comprobante.' USING ERRCODE = '22023';
    END IF;

    SELECT pa.id_paciente INTO v_id_paciente
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = auth.uid();

    IF v_id_paciente IS NULL THEN
        RAISE EXCEPTION 'No se encontró un perfil de paciente activo.' USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_a
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = p_id_cita
      AND a.id_paciente = v_id_paciente
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe una solicitud con adelanto asociada a tu cuenta.' USING ERRCODE = '42501';
    END IF;

    IF v_clave IS NOT NULL THEN
        SELECT * INTO v_comp_existente
        FROM psicobloom_interno.comprobantes_adelanto c
        WHERE c.id_cita = p_id_cita AND c.clave_idempotencia = v_clave;

        IF FOUND THEN
            IF v_comp_existente.ruta_storage IS DISTINCT FROM v_ruta THEN
                RAISE EXCEPTION 'La clave de idempotencia del comprobante ya fue usada con otro archivo.'
                    USING ERRCODE = '23505';
            END IF;
            RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
        END IF;
    END IF;

    IF v_a.estado_adelanto = 'vencido_sin_pago' THEN
        RAISE EXCEPTION 'El plazo para enviar el comprobante venció. Si ya transferiste, usa la opción de reportar incidencia.'
            USING ERRCODE = '23P01';
    END IF;

    IF v_a.estado_adelanto NOT IN ('pendiente_adelanto', 'observado', 'incidencia_pago') THEN
        RAISE EXCEPTION 'Esta solicitud no admite nuevos comprobantes en su estado actual (%).', v_a.estado_adelanto
            USING ERRCODE = '23P01';
    END IF;

    IF v_a.estado_adelanto = 'pendiente_adelanto'
       AND v_a.limite_pago_en IS NOT NULL
       AND v_ahora > v_a.limite_pago_en THEN
        RAISE EXCEPTION 'El límite de pago (24 horas antes de la cita) ya venció. Si ya transferiste, reporta una incidencia.'
            USING ERRCODE = '23P01';
    END IF;

    IF left(v_ruta, char_length(p_id_cita::TEXT || '/' || auth.uid()::TEXT || '/'))
       <> (p_id_cita::TEXT || '/' || auth.uid()::TEXT || '/') THEN
        RAISE EXCEPTION 'La ruta del comprobante no corresponde a esta cita o a tu cuenta.' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM storage.objects o
        WHERE o.bucket_id = 'comprobantes-adelantos'
          AND o.name = v_ruta
          AND (o.owner IS NULL OR o.owner = auth.uid())
    ) INTO v_objeto_existe;

    IF NOT v_objeto_existe THEN
        RAISE EXCEPTION 'El archivo del comprobante no existe en el almacenamiento privado.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO psicobloom_interno.comprobantes_adelanto (
        id_cita, ruta_storage, nota_paciente, clave_idempotencia, creado_por
    )
    VALUES (
        p_id_cita, v_ruta, v_nota, v_clave, auth.uid()
    )
    RETURNING id_comprobante INTO v_comp_id;

    IF v_nota IS NOT NULL AND char_length(v_nota) >= 5 THEN
        INSERT INTO psicobloom_interno.observaciones_adelanto (
            id_cita, tipo_actor, mensaje, creado_por
        )
        VALUES (p_id_cita, 'paciente', v_nota, auth.uid());
    END IF;

    UPDATE psicobloom_interno.adelantos_citas a
    SET estado_adelanto = 'comprobante_en_revision',
        comprobante_enviado_en = v_ahora,
        limite_revision_en = (v_ahora + INTERVAL '12 hours'),
        actualizado_en = v_ahora
    WHERE a.id_cita = p_id_cita;

    INSERT INTO psicobloom_interno.eventos_avisos_adelanto (
        id_cita, id_profesional, id_vinculacion, tipo_evento, referencia_evento
    )
    SELECT p_id_cita, v_a.id_profesional, v.id_vinculacion, 'comprobante_enviado', v_comp_id::TEXT
    FROM psicobloom_interno.vinculaciones_telegram v
    JOIN public."Profesionales" pr ON pr.id_profesional = v.id_profesional
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
    WHERE v.id_profesional = v_a.id_profesional
      AND pe.cuenta_activa IS TRUE
      AND pe.rol = 'profesional'
    ON CONFLICT (id_cita, tipo_evento, referencia_evento) DO NOTHING;

    RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_incidencia_adelanto(
    p_id_cita UUID,
    p_detalle TEXT,
    p_clave_idempotencia TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
    v_ahora TIMESTAMPTZ := now();
    v_detalle TEXT := trim(coalesce(p_detalle, ''));
    v_clave TEXT := nullif(trim(coalesce(p_clave_idempotencia, '')), '');
    v_a psicobloom_interno.adelantos_citas%ROWTYPE;
    v_inc_existente UUID;
    v_inc_id UUID;
    v_horario_liberado BOOLEAN := FALSE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Solo un paciente con cuenta activa puede reportar una incidencia.' USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL OR char_length(v_detalle) < 5 THEN
        RAISE EXCEPTION 'Describe brevemente el problema al adjuntar (mínimo 5 caracteres).' USING ERRCODE = '22023';
    END IF;

    SELECT pa.id_paciente INTO v_id_paciente
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = auth.uid();

    SELECT *
    INTO v_a
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = p_id_cita
      AND a.id_paciente = v_id_paciente
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe una solicitud con adelanto asociada a tu cuenta.' USING ERRCODE = '42501';
    END IF;

    IF v_clave IS NOT NULL THEN
        SELECT i.id_incidencia INTO v_inc_existente
        FROM psicobloom_interno.incidencias_adelanto i
        WHERE i.id_cita = p_id_cita AND i.clave_idempotencia = v_clave;

        IF v_inc_existente IS NOT NULL THEN
            RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
        END IF;
    END IF;

    IF v_a.estado_adelanto NOT IN ('pendiente_adelanto', 'observado', 'vencido_sin_pago', 'incidencia_pago') THEN
        RAISE EXCEPTION 'No se puede registrar una incidencia de carga en el estado actual (%).', v_a.estado_adelanto
            USING ERRCODE = '23P01';
    END IF;

    v_horario_liberado := (v_a.estado_adelanto = 'vencido_sin_pago');

    INSERT INTO psicobloom_interno.incidencias_adelanto (
        id_cita, detalle, horario_ya_liberado, clave_idempotencia, creado_por
    )
    VALUES (
        p_id_cita, v_detalle, v_horario_liberado, v_clave, auth.uid()
    )
    RETURNING id_incidencia INTO v_inc_id;

    IF NOT v_horario_liberado THEN
        UPDATE psicobloom_interno.adelantos_citas a
        SET estado_adelanto = 'incidencia_pago',
            actualizado_en = v_ahora
        WHERE a.id_cita = p_id_cita;
    END IF;

    INSERT INTO psicobloom_interno.eventos_avisos_adelanto (
        id_cita, id_profesional, id_vinculacion, tipo_evento, referencia_evento
    )
    SELECT p_id_cita, v_a.id_profesional, v.id_vinculacion, 'incidencia_pago', v_inc_id::TEXT
    FROM psicobloom_interno.vinculaciones_telegram v
    JOIN public."Profesionales" pr ON pr.id_profesional = v.id_profesional
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
    WHERE v.id_profesional = v_a.id_profesional
      AND pe.cuenta_activa IS TRUE
      AND pe.rol = 'profesional'
    ON CONFLICT (id_cita, tipo_evento, referencia_evento) DO NOTHING;

    RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
END;
$$;

CREATE OR REPLACE FUNCTION public.revisar_adelanto_profesional(
    p_id_cita UUID,
    p_accion TEXT,
    p_motivo TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_accion TEXT := lower(trim(coalesce(p_accion, '')));
    v_motivo TEXT := trim(coalesce(p_motivo, ''));
    v_ahora TIMESTAMPTZ := now();
    v_cita public."Citas"%ROWTYPE;
    v_a psicobloom_interno.adelantos_citas%ROWTYPE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Solo un profesional activo puede revisar adelantos.' USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL OR v_accion NOT IN ('verificar', 'observar') THEN
        RAISE EXCEPTION 'Indica la cita y una acción válida (verificar u observar).' USING ERRCODE = '22023';
    END IF;

    IF v_accion = 'observar' AND char_length(v_motivo) < 5 THEN
        RAISE EXCEPTION 'Debes ingresar un motivo claro de al menos 5 caracteres para observar el comprobante.'
            USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL OR NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'Tu perfil profesional debe estar aprobado y activo.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_cita
    FROM public."Citas" c
    WHERE c.id_cita = p_id_cita AND c.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cita no existe o no pertenece a tu perfil.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_a
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = p_id_cita
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Esta cita no corresponde al flujo de adelantos.' USING ERRCODE = '22023';
    END IF;

    IF v_cita.estado IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION 'La cita ya no se encuentra pendiente de confirmación (estado: %).', v_cita.estado
            USING ERRCODE = '23P01';
    END IF;

    IF v_a.estado_adelanto NOT IN ('comprobante_en_revision', 'incidencia_pago', 'observado') THEN
        RAISE EXCEPTION 'El adelanto no está listo para revisión en su estado actual (%).', v_a.estado_adelanto
            USING ERRCODE = '23P01';
    END IF;

    IF v_accion = 'verificar' THEN
        UPDATE psicobloom_interno.adelantos_citas a
        SET estado_adelanto = 'verificado',
            verificado_por = auth.uid(),
            verificado_en = v_ahora,
            actualizado_en = v_ahora
        WHERE a.id_cita = p_id_cita;

        UPDATE public."Citas" c
        SET estado = 'confirmada'
        WHERE c.id_cita = p_id_cita
          AND c.estado = 'pendiente';
    ELSE
        INSERT INTO psicobloom_interno.observaciones_adelanto (
            id_cita, tipo_actor, mensaje, creado_por
        )
        VALUES (p_id_cita, 'profesional', v_motivo, auth.uid());

        UPDATE psicobloom_interno.adelantos_citas a
        SET estado_adelanto = 'observado',
            actualizado_en = v_ahora
        WHERE a.id_cita = p_id_cita;
    END IF;

    RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. FUNCIONES DE MANTENIMIENTO Y DESPACHO (SOLO service_role / postgres)
--    Sin depender de current_user dentro de SECURITY DEFINER; revocadas a
--    PUBLIC, anon y authenticated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vencer_adelantos_expirados()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_ahora TIMESTAMPTZ := now();
    v_reg RECORD;
    v_total_vencidas INTEGER := 0;
    v_existe_otra_activa BOOLEAN;
    v_estado_destino_horario TEXT;
BEGIN
    FOR v_reg IN
        SELECT a.id_cita, a.id_profesional, c.id_disponibilidad, d.fecha
        FROM psicobloom_interno.adelantos_citas a
        JOIN public."Citas" c ON c.id_cita = a.id_cita
        JOIN public."Disponibilidad" d ON d.id_disponibilidad = c.id_disponibilidad
        WHERE a.estado_adelanto = 'pendiente_adelanto'
          AND a.limite_pago_en IS NOT NULL
          AND v_ahora > a.limite_pago_en
          AND c.estado = 'pendiente'
          AND NOT EXISTS (
              SELECT 1 FROM psicobloom_interno.comprobantes_adelanto comp
              WHERE comp.id_cita = a.id_cita
          )
          AND NOT EXISTS (
              SELECT 1 FROM psicobloom_interno.incidencias_adelanto inc
              WHERE inc.id_cita = a.id_cita
          )
        ORDER BY a.id_profesional, c.id_disponibilidad, a.id_cita
    LOOP
        -- Aislamiento por fila: un fallo puntual no revierte el resto del lote
        BEGIN
            PERFORM 1 FROM public."Profesionales" pr
            WHERE pr.id_profesional = v_reg.id_profesional FOR UPDATE;

            PERFORM 1 FROM public."Disponibilidad" d
            WHERE d.id_disponibilidad = v_reg.id_disponibilidad FOR UPDATE;

            PERFORM 1 FROM public."Citas" c
            WHERE c.id_cita = v_reg.id_cita AND c.estado = 'pendiente' FOR UPDATE;
            IF NOT FOUND THEN
                CONTINUE;
            END IF;

            PERFORM 1
            FROM psicobloom_interno.adelantos_citas a
            WHERE a.id_cita = v_reg.id_cita
              AND a.estado_adelanto = 'pendiente_adelanto'
              AND a.limite_pago_en IS NOT NULL
              AND v_ahora > a.limite_pago_en
              AND NOT EXISTS (
                  SELECT 1 FROM psicobloom_interno.comprobantes_adelanto comp
                  WHERE comp.id_cita = a.id_cita
              )
              AND NOT EXISTS (
                  SELECT 1 FROM psicobloom_interno.incidencias_adelanto inc
                  WHERE inc.id_cita = a.id_cita
              )
            FOR UPDATE;

            IF NOT FOUND THEN
                CONTINUE;
            END IF;

            PERFORM set_config('psicobloom.contexto_respuesta_cita', 'vencimiento_adelanto', TRUE);

            UPDATE public."Citas" c
            SET estado = 'cancelada'
            WHERE c.id_cita = v_reg.id_cita AND c.estado = 'pendiente';

            UPDATE psicobloom_interno.adelantos_citas a
            SET estado_adelanto = 'vencido_sin_pago',
                vencido_en = v_ahora,
                actualizado_en = v_ahora
            WHERE a.id_cita = v_reg.id_cita;

            SELECT EXISTS (
                SELECT 1
                FROM public."Citas" c
                WHERE c.id_disponibilidad = v_reg.id_disponibilidad
                  AND c.id_cita <> v_reg.id_cita
                  AND c.estado IN ('pendiente', 'confirmada')
            ) INTO v_existe_otra_activa;

            IF NOT v_existe_otra_activa THEN
                v_estado_destino_horario := CASE
                    WHEN public._es_dia_no_laborable_profesional(v_reg.id_profesional, v_reg.fecha)
                    THEN 'bloqueada'
                    ELSE 'disponible'
                END;

                UPDATE public."Disponibilidad" d
                SET estado = v_estado_destino_horario
                WHERE d.id_disponibilidad = v_reg.id_disponibilidad
                  AND d.estado = 'reservada';
            END IF;

            PERFORM set_config('psicobloom.contexto_respuesta_cita', '', TRUE);
            v_total_vencidas := v_total_vencidas + 1;
        EXCEPTION
            WHEN OTHERS THEN
                PERFORM set_config('psicobloom.contexto_respuesta_cita', '', TRUE);
                RAISE WARNING 'No se pudo vencer la cita % (SQLSTATE %): %', v_reg.id_cita, SQLSTATE, SQLERRM;
        END;
    END LOOP;

    RETURN v_total_vencidas;
END;
$$;

CREATE OR REPLACE FUNCTION public.encolar_avisos_revision_demorada()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_encolados INTEGER := 0;
BEGIN
    INSERT INTO psicobloom_interno.eventos_avisos_adelanto (
        id_cita, id_profesional, id_vinculacion, tipo_evento, referencia_evento
    )
    SELECT
        a.id_cita,
        a.id_profesional,
        v.id_vinculacion,
        'revision_demorada',
        to_char(a.limite_revision_en AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    FROM psicobloom_interno.adelantos_citas a
    JOIN public."Citas" c ON c.id_cita = a.id_cita
    JOIN psicobloom_interno.vinculaciones_telegram v ON v.id_profesional = a.id_profesional
    JOIN public."Profesionales" pr ON pr.id_profesional = a.id_profesional
    JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
    WHERE a.estado_adelanto = 'comprobante_en_revision'
      AND c.estado = 'pendiente'
      AND a.limite_revision_en IS NOT NULL
      AND now() > a.limite_revision_en
      AND pe.cuenta_activa IS TRUE
      AND pe.rol = 'profesional'
    ON CONFLICT (id_cita, tipo_evento, referencia_evento) DO NOTHING;

    GET DIAGNOSTICS v_encolados = ROW_COUNT;
    RETURN v_encolados;
END;
$$;

-- Reclamo y finalizacion de eventos_avisos_adelanto preservando TODAS las
-- garantias de reclamar_eventos_avisos_telegram / finalizar_evento_aviso_telegram:
--   1) marca 'fallido' si intentos >= 5 (incluyendo bloqueos vencidos);
--   2) omite eventos cuya id_vinculacion ya no este vigente (no redirige tras
--      desvincular y revincular) o cuyo estado de cita/adelanto ya no corresponda;
--   3) reclama solo intentos < 5 con SKIP LOCKED y une chat_id por id_vinculacion;
--   4) finaliza unicamente con intento esperado Y bloqueo vigente (bloqueado_hasta > now()).
CREATE OR REPLACE FUNCTION public.reclamar_eventos_avisos_adelanto(
    p_limite INTEGER DEFAULT 10,
    p_bloqueo_segundos INTEGER DEFAULT 60
)
RETURNS TABLE(
    id_evento UUID,
    id_cita UUID,
    id_profesional UUID,
    tipo_evento TEXT,
    intentos INTEGER,
    chat_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_limite INTEGER := GREATEST(1, LEAST(coalesce(p_limite, 10), 25));
    v_bloqueo INTERVAL := make_interval(secs => GREATEST(15, LEAST(coalesce(p_bloqueo_segundos, 60), 300)));
BEGIN
    -- 1. Agotar eventos con >= 5 intentos (incluidos bloqueos vencidos por caidas)
    UPDATE psicobloom_interno.eventos_avisos_adelanto e
    SET estado = 'fallido',
        bloqueado_hasta = NULL,
        ultimo_error = 'MAXIMO_INTENTOS',
        actualizado_en = now()
    WHERE e.intentos >= 5
      AND (
          e.estado = 'pendiente'
          OR (e.estado = 'procesando' AND e.bloqueado_hasta <= now())
      );

    -- 2. Omitir eventos cuya vinculacion cambio/se desvinculo o cuyo estado ya no aplica
    UPDATE psicobloom_interno.eventos_avisos_adelanto e
    SET estado = 'omitido',
        bloqueado_hasta = NULL,
        ultimo_error = 'SIN_VINCULACION_O_ESTADO_NO_VIGENTE',
        actualizado_en = now()
    WHERE e.estado IN ('pendiente', 'procesando')
      AND NOT EXISTS (
          SELECT 1
          FROM psicobloom_interno.vinculaciones_telegram v
          JOIN public."Profesionales" pr ON pr.id_profesional = v.id_profesional
          JOIN psicobloom_interno.perfiles_compat pe ON pe.id = pr.id_usuario
          JOIN public."Citas" c ON c.id_cita = e.id_cita
          JOIN psicobloom_interno.adelantos_citas a ON a.id_cita = e.id_cita
          WHERE v.id_vinculacion = e.id_vinculacion
            AND v.id_profesional = e.id_profesional
            AND pe.cuenta_activa IS TRUE
            AND pe.rol = 'profesional'
            AND (
                (e.tipo_evento = 'comprobante_enviado'
                    AND c.estado = 'pendiente'
                    AND a.estado_adelanto = 'comprobante_en_revision')
                OR (e.tipo_evento = 'revision_demorada'
                    AND c.estado = 'pendiente'
                    AND a.estado_adelanto = 'comprobante_en_revision'
                    AND a.limite_revision_en IS NOT NULL
                    AND now() > a.limite_revision_en)
                OR (e.tipo_evento = 'incidencia_pago'
                    AND (
                        a.estado_adelanto = 'incidencia_pago'
                        OR EXISTS (
                            SELECT 1 FROM psicobloom_interno.incidencias_adelanto inc
                            WHERE inc.id_cita = e.id_cita
                              AND inc.estado_incidencia = 'pendiente_revision'
                        )
                    ))
            )
      );

    -- 3. Reclamar solo eventos vigentes con intentos < 5
    RETURN QUERY
    WITH candidatos AS (
        SELECT e.id_evento
        FROM psicobloom_interno.eventos_avisos_adelanto e
        WHERE e.intentos < 5
          AND (
              (e.estado = 'pendiente' AND e.proximo_intento_en <= now())
              OR (e.estado = 'procesando' AND e.bloqueado_hasta IS NOT NULL AND e.bloqueado_hasta <= now())
          )
        ORDER BY e.proximo_intento_en ASC, e.creado_en ASC
        LIMIT v_limite
        FOR UPDATE OF e SKIP LOCKED
    ),
    actualizados AS (
        UPDATE psicobloom_interno.eventos_avisos_adelanto e
        SET estado = 'procesando',
            intentos = e.intentos + 1,
            bloqueado_hasta = now() + v_bloqueo,
            actualizado_en = now()
        FROM candidatos c
        WHERE e.id_evento = c.id_evento
        RETURNING e.id_evento, e.id_cita, e.id_profesional, e.id_vinculacion, e.tipo_evento, e.intentos
    )
    SELECT
        a.id_evento,
        a.id_cita,
        a.id_profesional,
        a.tipo_evento,
        a.intentos,
        v.chat_id
    FROM actualizados a
    LEFT JOIN psicobloom_interno.vinculaciones_telegram v
      ON v.id_profesional = a.id_profesional
     AND v.id_vinculacion = a.id_vinculacion;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalizar_evento_aviso_adelanto(
    p_id_evento UUID,
    p_intento_esperado INTEGER,
    p_resultado TEXT,
    p_error TEXT DEFAULT NULL,
    p_reintentar_en TIMESTAMPTZ DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_actualizadas INTEGER := 0;
BEGIN
    IF p_resultado IS NULL
       OR p_resultado NOT IN ('enviado', 'omitido', 'reintentar', 'fallido')
       OR p_intento_esperado IS NULL THEN
        RAISE EXCEPTION 'Resultado o reserva inválidos.' USING ERRCODE = '22023';
    END IF;

    UPDATE psicobloom_interno.eventos_avisos_adelanto e
    SET estado = CASE
            WHEN p_resultado = 'reintentar' AND e.intentos < 5 THEN 'pendiente'
            WHEN p_resultado = 'reintentar' THEN 'fallido'
            ELSE p_resultado
        END,
        enviado_en = CASE WHEN p_resultado = 'enviado' THEN now() ELSE e.enviado_en END,
        proximo_intento_en = CASE
            WHEN p_resultado = 'reintentar' THEN coalesce(p_reintentar_en, now() + INTERVAL '1 minute')
            ELSE e.proximo_intento_en
        END,
        bloqueado_hasta = NULL,
        ultimo_error = CASE WHEN p_resultado = 'enviado' THEN NULL ELSE left(coalesce(p_error, 'SIN_DETALLE'), 200) END,
        actualizado_en = now()
    WHERE e.id_evento = p_id_evento
      AND e.estado = 'procesando'
      AND e.intentos = p_intento_esperado
      AND e.bloqueado_hasta > now();

    GET DIAGNOSTICS v_actualizadas = ROW_COUNT;
    RETURN v_actualizadas = 1;
END;
$$;

-- Permisos de RPC de cliente (authenticated)
REVOKE ALL ON FUNCTION
    public.obtener_oferta_adelanto_profesional(UUID),
    public.solicitar_cita_paciente(UUID, UUID, TEXT, BOOLEAN, TEXT),
    public.responder_solicitud_cita_profesional(UUID, TEXT),
    public.listar_adelantos_citas_visibles(),
    public.obtener_detalle_adelanto_cita(UUID),
    public.registrar_comprobante_adelanto(UUID, TEXT, TEXT, TEXT),
    public.registrar_incidencia_adelanto(UUID, TEXT, TEXT),
    public.revisar_adelanto_profesional(UUID, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.obtener_oferta_adelanto_profesional(UUID),
    public.solicitar_cita_paciente(UUID, UUID, TEXT, BOOLEAN, TEXT),
    public.responder_solicitud_cita_profesional(UUID, TEXT),
    public.listar_adelantos_citas_visibles(),
    public.obtener_detalle_adelanto_cita(UUID),
    public.registrar_comprobante_adelanto(UUID, TEXT, TEXT, TEXT),
    public.registrar_incidencia_adelanto(UUID, TEXT, TEXT),
    public.revisar_adelanto_profesional(UUID, TEXT, TEXT)
    TO authenticated;

-- Permisos estrictos de mantenimiento y despacho: REVOCADOS a PUBLIC, anon y authenticated;
-- otorgados UNICAMENTE a service_role (y propietario postgres).
REVOKE ALL ON FUNCTION
    public.vencer_adelantos_expirados(),
    public.encolar_avisos_revision_demorada(),
    public.reclamar_eventos_avisos_adelanto(INTEGER, INTEGER),
    public.finalizar_evento_aviso_adelanto(UUID, INTEGER, TEXT, TEXT, TIMESTAMPTZ)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.vencer_adelantos_expirados(),
    public.encolar_avisos_revision_demorada(),
    public.reclamar_eventos_avisos_adelanto(INTEGER, INTEGER),
    public.finalizar_evento_aviso_adelanto(UUID, INTEGER, TEXT, TEXT, TIMESTAMPTZ)
    TO service_role;

COMMIT;
