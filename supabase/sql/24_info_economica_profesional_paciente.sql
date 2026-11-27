-- =============================================================================
-- SCRIPT 24 — MIGRACION ADITIVA: INFORMACION ECONOMICA PARA EL PACIENTE (ETAPA 3)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Ejecutar en: Supabase > SQL Editor como postgres (DESPUES de 22 y 23)
--
-- Proposito:
--   1. Exponer al paciente (y usuarios activos autorizados que consultan el
--      directorio) UNICAMENTE la informacion economica publica de un profesional
--      visible, activo y aprobado:
--      - tiene_configuracion
--      - moneda ('USD')
--      - precio_consulta
--      - requiere_adelanto
--      - monto_adelanto_exigible (0.00 si requiere_adelanto = FALSE)
--      - saldo_despues_adelanto (calculado con NUMERIC(10, 2) exacto)
--   2. Reutiliza public._rol_activo() y public._profesional_es_publicable(UUID)
--      del directorio existente.
--   3. NO expone QR, ruta_qr_storage, banco, titular, numero de cuenta ni URLs
--      firmadas, y NO concede acceso directo sobre psicobloom_interno.
--   4. Si el profesional visible no tiene configuracion o precio cargado,
--      devuelve un resultado explicito (tiene_configuracion = FALSE, precios
--      NULL) sin inventar valores ni asumir gratuidad.
--   5. No modifica los scripts 22/23 ya aplicados ni la logica actual de citas.
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.obtener_info_economica_profesional(
    p_id_profesional UUID
)
RETURNS TABLE(
    tiene_configuracion BOOLEAN,
    moneda TEXT,
    precio_consulta NUMERIC(10, 2),
    requiere_adelanto BOOLEAN,
    monto_adelanto_exigible NUMERIC(10, 2),
    saldo_despues_adelanto NUMERIC(10, 2)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_rol_actual TEXT;
    v_id_profesional UUID;
    v_config RECORD;
    v_adelanto_exigible NUMERIC(10, 2);
    v_saldo NUMERIC(10, 2);
BEGIN
    v_rol_actual := public._rol_activo();
    IF v_rol_actual IS NULL
       OR v_rol_actual NOT IN ('paciente', 'profesional', 'administrador') THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa autorizada para consultar la información económica.'
            USING ERRCODE = '42501';
    END IF;

    IF p_id_profesional IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el profesional que deseas consultar.'
            USING ERRCODE = '22023';
    END IF;

    -- Resuelve id_profesional tanto si se recibe Profesionales.id_profesional
    -- como si se recibe Profesionales.id_usuario (consistente con script 08).
    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = p_id_profesional
       OR pr.id_usuario = p_id_profesional;

    -- Reutiliza la regla vigente del directorio: solo profesionales visibles,
    -- activos y aprobados. Si no es publicable, devuelve 0 filas sin filtrar datos.
    IF v_id_profesional IS NULL OR NOT public._profesional_es_publicable(v_id_profesional) THEN
        RETURN;
    END IF;

    SELECT
        c.moneda,
        c.precio_consulta,
        c.requiere_adelanto,
        c.monto_adelanto
    INTO v_config
    FROM psicobloom_interno.configuracion_cobro_profesional c
    WHERE c.id_profesional = v_id_profesional;

    -- Sin configuracion o sin precio registrado: respuesta explicita sin asumir gratuidad.
    IF NOT FOUND OR v_config.precio_consulta IS NULL THEN
        RETURN QUERY
        SELECT
            FALSE::BOOLEAN,
            'USD'::TEXT,
            NULL::NUMERIC(10, 2),
            FALSE::BOOLEAN,
            NULL::NUMERIC(10, 2),
            NULL::NUMERIC(10, 2);
        RETURN;
    END IF;

    -- Si requiere_adelanto esta desactivado, el adelanto exigible es 0.00
    -- aunque la tabla conserve un monto_adelanto historico.
    IF v_config.requiere_adelanto IS TRUE AND v_config.monto_adelanto IS NOT NULL THEN
        v_adelanto_exigible := v_config.monto_adelanto;
    ELSE
        v_adelanto_exigible := 0.00::NUMERIC(10, 2);
    END IF;

    v_saldo := (v_config.precio_consulta - v_adelanto_exigible)::NUMERIC(10, 2);

    RETURN QUERY
    SELECT
        TRUE::BOOLEAN,
        coalesce(nullif(trim(v_config.moneda), ''), 'USD')::TEXT,
        v_config.precio_consulta::NUMERIC(10, 2),
        (v_config.requiere_adelanto IS TRUE)::BOOLEAN,
        v_adelanto_exigible::NUMERIC(10, 2),
        v_saldo::NUMERIC(10, 2);
END;
$$;

REVOKE ALL ON FUNCTION
    public.obtener_info_economica_profesional(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.obtener_info_economica_profesional(UUID)
    TO authenticated;

COMMIT;
