-- =============================================================================
-- SCRIPT 22 — MIGRACION ADITIVA: CONFIGURACION DE COBRO Y QR PRIVADO (ETAPA 2)
-- Proyecto: PsicoBloom (esquemas: public, psicobloom_interno y storage)
-- Ejecutar en: Supabase > SQL Editor como postgres (DESPUES de revisar 22a)
--
-- Proposito:
--   1. Almacenar la configuracion de cobro propia del profesional como fuente
--      unica de verdad para el flujo de adelantos (requiere adelanto, precio
--      total en USD exacto, monto del adelanto en USD exacto, ruta del objeto
--      QR en Storage privado y datos minimos del beneficiario).
--   2. No altera ni elimina public."QRTransferencia" ni
--      public."Servicios".precio_referencial mientras se revisan dependencias.
--   3. Configura el bucket PRIVADO `qr-cobro-profesionales` (public = FALSE):
--      - Solo permite SELECT e INSERT en la carpeta propia `<auth.uid()>/...`
--        para profesionales con cuenta activa.
--      - NO otorga politicas UPDATE ni DELETE a authenticated ni anon: impide
--        sobrescribir o borrar un QR cargado/referenciado. Para reemplazar un
--        QR se sube un nuevo objeto con nombre unico y se cambia la referencia
--        mediante guardar_configuracion_cobro_propia.
--   4. Valida en servidor existencia real del objeto en storage.objects,
--      pertenencia al profesional autenticado, montos USD exactos sin redondeo
--      silencioso (rechaza NaN, infinitos, fuera de rango y < 1 centavo) y
--      devuelve la fila efectivamente persistida.
-- =============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS psicobloom_interno;

-- ---------------------------------------------------------------------------
-- 1. TABLA INTERNA DE CONFIGURACION DE COBRO DEL PROFESIONAL
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS psicobloom_interno.configuracion_cobro_profesional (
    id_profesional UUID PRIMARY KEY
        REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    requiere_adelanto BOOLEAN NOT NULL DEFAULT FALSE,
    moneda TEXT NOT NULL DEFAULT 'USD'
        CHECK (moneda = 'USD'),
    precio_consulta NUMERIC(10, 2) NULL
        CHECK (
            precio_consulta IS NULL
            OR (precio_consulta > 0 AND precio_consulta <= 99999999.99)
        ),
    monto_adelanto NUMERIC(10, 2) NULL
        CHECK (
            monto_adelanto IS NULL
            OR (monto_adelanto > 0 AND monto_adelanto <= 99999999.99)
        ),
    ruta_qr_storage TEXT NULL
        CHECK (
            ruta_qr_storage IS NULL
            OR (
                nullif(trim(ruta_qr_storage), '') IS NOT NULL
                AND ruta_qr_storage NOT LIKE 'http://%'
                AND ruta_qr_storage NOT LIKE 'https://%'
                AND ruta_qr_storage NOT LIKE '%..%'
            )
        ),
    banco_beneficiario TEXT NULL,
    titular_beneficiario TEXT NULL,
    tipo_cuenta_beneficiario TEXT NULL,
    numero_cuenta_referencia TEXT NULL,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_cobro_adelanto_valido CHECK (
        NOT requiere_adelanto
        OR (
            precio_consulta IS NOT NULL
            AND precio_consulta > 0
            AND monto_adelanto IS NOT NULL
            AND monto_adelanto > 0
            AND monto_adelanto <= precio_consulta
            AND nullif(trim(coalesce(ruta_qr_storage, '')), '') IS NOT NULL
            AND char_length(trim(coalesce(banco_beneficiario, ''))) >= 2
            AND char_length(trim(coalesce(titular_beneficiario, ''))) >= 3
        )
    ),
    CONSTRAINT chk_adelanto_no_supera_precio CHECK (
        monto_adelanto IS NULL
        OR precio_consulta IS NULL
        OR monto_adelanto <= precio_consulta
    )
);

ALTER TABLE psicobloom_interno.configuracion_cobro_profesional
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE psicobloom_interno.configuracion_cobro_profesional
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. BUCKET PRIVADO DE SUPABASE STORAGE PARA QR BANCARIO
--    (public = FALSE, sin lectura general, SIN UPDATE ni DELETE desde cliente)
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'qr-cobro-profesionales',
    'qr-cobro-profesionales',
    FALSE,
    5242880,
    ARRAY['image/png', 'image/jpeg']
)
ON CONFLICT (id) DO UPDATE
SET public = FALSE,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS qr_cobro_profesional_leer_propio ON storage.objects;
CREATE POLICY qr_cobro_profesional_leer_propio
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'qr-cobro-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::TEXT)
);

DROP POLICY IF EXISTS qr_cobro_profesional_insertar_propio ON storage.objects;
CREATE POLICY qr_cobro_profesional_insertar_propio
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'qr-cobro-profesionales'
    AND (SELECT public._rol_activo()) = 'profesional'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::TEXT)
);

-- Se eliminan explicitamente politicas UPDATE y DELETE para impedir sobrescribir
-- o borrar un QR ya cargado o referenciado por una configuracion vigente.
DROP POLICY IF EXISTS qr_cobro_profesional_actualizar_propio ON storage.objects;
DROP POLICY IF EXISTS qr_cobro_profesional_eliminar_propio ON storage.objects;

-- ---------------------------------------------------------------------------
-- 3. RPC AUTORIZADAS PARA CONSULTAR Y GUARDAR CONFIGURACION PROPIA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_configuracion_cobro_propia()
RETURNS TABLE(
    requiere_adelanto BOOLEAN,
    moneda TEXT,
    precio_consulta NUMERIC(10, 2),
    monto_adelanto NUMERIC(10, 2),
    ruta_qr_storage TEXT,
    banco_beneficiario TEXT,
    titular_beneficiario TEXT,
    tipo_cuenta_beneficiario TEXT,
    numero_cuenta_referencia TEXT,
    actualizado_en TIMESTAMPTZ
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
        RAISE EXCEPTION 'Solo un profesional con cuenta activa puede consultar su configuración de cobro.'
            USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid();

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontró un perfil profesional asociado a tu cuenta.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        c.requiere_adelanto,
        c.moneda,
        c.precio_consulta,
        c.monto_adelanto,
        c.ruta_qr_storage,
        c.banco_beneficiario,
        c.titular_beneficiario,
        c.tipo_cuenta_beneficiario,
        c.numero_cuenta_referencia,
        c.actualizado_en
    FROM psicobloom_interno.configuracion_cobro_profesional c
    WHERE c.id_profesional = v_id_profesional;
END;
$$;

-- Se elimina la firma previa (VOID) antes de definir la version que devuelve
-- la fila efectivamente persistida.
DROP FUNCTION IF EXISTS public.guardar_configuracion_cobro_propia(
    BOOLEAN, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION public.guardar_configuracion_cobro_propia(
    p_requiere_adelanto BOOLEAN,
    p_precio_consulta NUMERIC,
    p_monto_adelanto NUMERIC,
    p_ruta_qr_storage TEXT,
    p_banco_beneficiario TEXT,
    p_titular_beneficiario TEXT,
    p_tipo_cuenta_beneficiario TEXT DEFAULT NULL,
    p_numero_cuenta_referencia TEXT DEFAULT NULL
)
RETURNS TABLE(
    requiere_adelanto BOOLEAN,
    moneda TEXT,
    precio_consulta NUMERIC(10, 2),
    monto_adelanto NUMERIC(10, 2),
    ruta_qr_storage TEXT,
    banco_beneficiario TEXT,
    titular_beneficiario TEXT,
    tipo_cuenta_beneficiario TEXT,
    numero_cuenta_referencia TEXT,
    actualizado_en TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_uid_texto TEXT := auth.uid()::TEXT;
    v_ruta TEXT;
    v_banco TEXT := nullif(trim(coalesce(p_banco_beneficiario, '')), '');
    v_titular TEXT := nullif(trim(coalesce(p_titular_beneficiario, '')), '');
    v_tipo_cuenta TEXT := nullif(trim(coalesce(p_tipo_cuenta_beneficiario, '')), '');
    v_numero_cuenta TEXT := nullif(trim(coalesce(p_numero_cuenta_referencia, '')), '');
    v_precio NUMERIC(10, 2);
    v_adelanto NUMERIC(10, 2);
    v_objeto_existe BOOLEAN := FALSE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Solo un profesional con cuenta activa puede configurar sus datos de cobro.'
            USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontró un perfil profesional asociado a tu cuenta.'
            USING ERRCODE = '42501';
    END IF;

    IF p_requiere_adelanto IS NULL THEN
        RAISE EXCEPTION 'Debes indicar si requieres adelanto.'
            USING ERRCODE = '22023';
    END IF;

    -- Validaciones monetarias estrictas sin redondeo silencioso:
    -- rechaza NaN, infinitos, valores <= 0, > 99999999.99 y fracciones < 0.01.
    IF p_precio_consulta IS NOT NULL THEN
        IF p_precio_consulta = 'NaN'::NUMERIC
           OR p_precio_consulta = 'Infinity'::NUMERIC
           OR p_precio_consulta = '-Infinity'::NUMERIC THEN
            RAISE EXCEPTION 'El precio total de la consulta no es un número válido.'
                USING ERRCODE = '22023';
        END IF;
        IF p_precio_consulta <= 0 OR p_precio_consulta > 99999999.99 THEN
            RAISE EXCEPTION 'El precio total debe estar entre 0.01 y 99999999.99 USD.'
                USING ERRCODE = '22023';
        END IF;
        IF p_precio_consulta <> trunc(p_precio_consulta, 2) THEN
            RAISE EXCEPTION 'El precio total en USD admite como máximo dos decimales (centavos exactos).'
                USING ERRCODE = '22023';
        END IF;
        v_precio := p_precio_consulta;
    END IF;

    IF p_monto_adelanto IS NOT NULL THEN
        IF p_monto_adelanto = 'NaN'::NUMERIC
           OR p_monto_adelanto = 'Infinity'::NUMERIC
           OR p_monto_adelanto = '-Infinity'::NUMERIC THEN
            RAISE EXCEPTION 'El monto del adelanto no es un número válido.'
                USING ERRCODE = '22023';
        END IF;
        IF p_monto_adelanto <= 0 OR p_monto_adelanto > 99999999.99 THEN
            RAISE EXCEPTION 'El monto del adelanto debe estar entre 0.01 y 99999999.99 USD.'
                USING ERRCODE = '22023';
        END IF;
        IF p_monto_adelanto <> trunc(p_monto_adelanto, 2) THEN
            RAISE EXCEPTION 'El monto del adelanto en USD admite como máximo dos decimales (centavos exactos).'
                USING ERRCODE = '22023';
        END IF;
        v_adelanto := p_monto_adelanto;
    END IF;

    IF v_precio IS NOT NULL AND v_adelanto IS NOT NULL AND v_adelanto > v_precio THEN
        RAISE EXCEPTION 'El monto del adelanto no puede superar el precio total de la consulta.'
            USING ERRCODE = '22023';
    END IF;

    -- Validacion de ruta privada del QR: rechaza cadenas vacias, URLs firmadas,
    -- rutas ajenas y objetos inexistentes en storage.objects.
    IF p_ruta_qr_storage IS NOT NULL THEN
        v_ruta := trim(p_ruta_qr_storage);
        IF v_ruta = '' THEN
            RAISE EXCEPTION 'La ruta del código QR no puede estar vacía.'
                USING ERRCODE = '22023';
        END IF;
        IF v_ruta LIKE 'http://%'
           OR v_ruta LIKE 'https://%'
           OR v_ruta LIKE '%..%'
           OR left(v_ruta, 1) = '/' THEN
            RAISE EXCEPTION 'Debes guardar la ruta privada del archivo QR, no una URL firmada.'
                USING ERRCODE = '22023';
        END IF;
        IF left(v_ruta, char_length(v_uid_texto) + 1) <> (v_uid_texto || '/')
           OR coalesce((storage.foldername(v_ruta))[1], '') <> v_uid_texto THEN
            RAISE EXCEPTION 'La ruta del QR no pertenece a tu cuenta profesional.'
                USING ERRCODE = '42501';
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM storage.objects o
            WHERE o.bucket_id = 'qr-cobro-profesionales'
              AND o.name = v_ruta
              AND (storage.foldername(o.name))[1] = v_uid_texto
              AND (o.owner IS NULL OR o.owner = auth.uid())
        )
        INTO v_objeto_existe;

        IF NOT v_objeto_existe THEN
            RAISE EXCEPTION 'El código QR indicado no existe en el almacenamiento privado.'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF p_requiere_adelanto THEN
        IF v_precio IS NULL OR v_precio <= 0 THEN
            RAISE EXCEPTION 'Ingresa un precio total positivo en USD para activar el cobro con adelanto.'
                USING ERRCODE = '22023';
        END IF;
        IF v_adelanto IS NULL OR v_adelanto <= 0 OR v_adelanto > v_precio THEN
            RAISE EXCEPTION 'Ingresa un adelanto mayor a 0 USD y menor o igual al precio total.'
                USING ERRCODE = '22023';
        END IF;
        IF v_ruta IS NULL THEN
            RAISE EXCEPTION 'Debes subir tu código QR bancario antes de activar el cobro con adelanto.'
                USING ERRCODE = '22023';
        END IF;
        IF v_banco IS NULL OR char_length(v_banco) < 2 THEN
            RAISE EXCEPTION 'Indica el banco o entidad financiera del beneficiario.'
                USING ERRCODE = '22023';
        END IF;
        IF v_titular IS NULL OR char_length(v_titular) < 3 THEN
            RAISE EXCEPTION 'Indica el nombre completo del titular de la cuenta.'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    RETURN QUERY
    INSERT INTO psicobloom_interno.configuracion_cobro_profesional AS c (
        id_profesional,
        requiere_adelanto,
        moneda,
        precio_consulta,
        monto_adelanto,
        ruta_qr_storage,
        banco_beneficiario,
        titular_beneficiario,
        tipo_cuenta_beneficiario,
        numero_cuenta_referencia,
        actualizado_en
    )
    VALUES (
        v_id_profesional,
        p_requiere_adelanto,
        'USD',
        v_precio,
        v_adelanto,
        v_ruta,
        v_banco,
        v_titular,
        v_tipo_cuenta,
        v_numero_cuenta,
        now()
    )
    ON CONFLICT (id_profesional) DO UPDATE
    SET requiere_adelanto = EXCLUDED.requiere_adelanto,
        moneda = 'USD',
        precio_consulta = EXCLUDED.precio_consulta,
        monto_adelanto = EXCLUDED.monto_adelanto,
        ruta_qr_storage = EXCLUDED.ruta_qr_storage,
        banco_beneficiario = EXCLUDED.banco_beneficiario,
        titular_beneficiario = EXCLUDED.titular_beneficiario,
        tipo_cuenta_beneficiario = EXCLUDED.tipo_cuenta_beneficiario,
        numero_cuenta_referencia = EXCLUDED.numero_cuenta_referencia,
        actualizado_en = now()
    RETURNING
        c.requiere_adelanto,
        c.moneda,
        c.precio_consulta,
        c.monto_adelanto,
        c.ruta_qr_storage,
        c.banco_beneficiario,
        c.titular_beneficiario,
        c.tipo_cuenta_beneficiario,
        c.numero_cuenta_referencia,
        c.actualizado_en;
END;
$$;

REVOKE ALL ON FUNCTION
    public.obtener_configuracion_cobro_propia(),
    public.guardar_configuracion_cobro_propia(BOOLEAN, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.obtener_configuracion_cobro_propia(),
    public.guardar_configuracion_cobro_propia(BOOLEAN, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT)
    TO authenticated;

COMMIT;
