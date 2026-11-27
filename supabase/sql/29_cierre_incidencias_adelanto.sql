-- =============================================================================
-- PsicoBloom - Migración 29 (aditiva): cierre manual de incidencias de carga
-- de comprobantes de adelanto.
--
-- Reglas clave:
-- - Envuelta en BEGIN / COMMIT para evitar aplicaciones parciales.
-- - No modifica migraciones anteriores (22 a 28) ni funciones/colas de Telegram.
-- - Solo el profesional titular, activo y aprobado puede cerrar una incidencia
--   de carga de comprobante.
-- - Exige motivo de resolución (5 a 500 caracteres), guarda responsable y fecha
--   del servidor, conserva el detalle original y todo el historial.
-- - Cierre estrictamente idempotente: repetir no duplica ni sobrescribe una
--   resolución anterior.
-- - Alcance acotado: exige comprobante registrado y adelanto en
--   comprobante_en_revision, observado o verificado; rechaza incidencias con
--   horario_ya_liberado = TRUE (requieren tratamiento posterior).
-- - NO verifica el ingreso, NO confirma ni cancela la cita, NO modifica
--   disponibilidad ni importes y NO registra reembolsos.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. COLUMNAS Y RESTRICCIONES ADITIVAS EN incidencias_adelanto
-- ---------------------------------------------------------------------------
ALTER TABLE psicobloom_interno.incidencias_adelanto
    ADD COLUMN IF NOT EXISTS motivo_resolucion TEXT NULL,
    ADD COLUMN IF NOT EXISTS resuelto_por UUID NULL,
    ADD COLUMN IF NOT EXISTS resuelto_en TIMESTAMPTZ NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'chk_incidencias_adelanto_resolucion_consistente'
          AND conrelid = 'psicobloom_interno.incidencias_adelanto'::regclass
    ) THEN
        ALTER TABLE psicobloom_interno.incidencias_adelanto
            ADD CONSTRAINT chk_incidencias_adelanto_resolucion_consistente
            CHECK (
                (
                    estado_incidencia = 'resuelta'
                    AND motivo_resolucion IS NOT NULL
                    AND char_length(trim(motivo_resolucion)) BETWEEN 5 AND 500
                    AND resuelto_por IS NOT NULL
                    AND resuelto_en IS NOT NULL
                )
                OR (
                    estado_incidencia <> 'resuelta'
                    AND motivo_resolucion IS NULL
                    AND resuelto_por IS NULL
                    AND resuelto_en IS NULL
                )
            );
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. ACTUALIZAR obtener_detalle_adelanto_cita PARA EXPONER DATOS DE RESOLUCIÓN
--    Conserva exactamente el control de acceso y el contrato existente,
--    añadiendo motivo_resolucion, resuelto_por y resuelto_en por incidencia.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.obtener_detalle_adelanto_cita(
    p_id_cita UUID
)
RETURNS JSONB
LANGUAGE plpgsql
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
            'creado_en', i.creado_en,
            'motivo_resolucion', i.motivo_resolucion,
            'resuelto_por', i.resuelto_por,
            'resuelto_en', i.resuelto_en
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

-- ---------------------------------------------------------------------------
-- 3. RPC DE CIERRE MANUAL E IDEMPOTENTE DE INCIDENCIA DE CARGA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolver_incidencia_adelanto(
    p_id_cita UUID,
    p_id_incidencia UUID,
    p_motivo_resolucion TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_rol TEXT := public._rol_activo();
    v_id_profesional UUID;
    v_motivo TEXT := trim(coalesce(p_motivo_resolucion, ''));
    v_ahora TIMESTAMPTZ := now();
    v_a psicobloom_interno.adelantos_citas%ROWTYPE;
    v_inc psicobloom_interno.incidencias_adelanto%ROWTYPE;
    v_tiene_comprobante BOOLEAN := FALSE;
BEGIN
    IF v_uid IS NULL OR v_rol IS NULL OR v_rol <> 'profesional' THEN
        RAISE EXCEPTION 'Solo el profesional titular con cuenta activa y aprobada puede resolver una incidencia de carga.'
            USING ERRCODE = '42501';
    END IF;

    IF p_id_cita IS NULL OR p_id_incidencia IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la cita y la incidencia a resolver.'
            USING ERRCODE = '22023';
    END IF;

    IF char_length(v_motivo) < 5 OR char_length(v_motivo) > 500 THEN
        RAISE EXCEPTION 'El motivo de resolución debe tener entre 5 y 500 caracteres.'
            USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = v_uid
    FOR UPDATE;

    IF v_id_profesional IS NULL OR NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'Tu perfil profesional debe estar activo y aprobado para resolver incidencias.'
            USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_a
    FROM psicobloom_interno.adelantos_citas a
    WHERE a.id_cita = p_id_cita
      AND a.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La cita no existe o no pertenece a tu perfil profesional.'
            USING ERRCODE = '42501';
    END IF;

    SELECT *
    INTO v_inc
    FROM psicobloom_interno.incidencias_adelanto i
    WHERE i.id_incidencia = p_id_incidencia
      AND i.id_cita = p_id_cita
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La incidencia indicada no existe o no pertenece a esta cita.'
            USING ERRCODE = '22023';
    END IF;

    -- Idempotencia estricta: si ya estaba resuelta, no duplica ni sobrescribe
    -- motivo_resolucion, resuelto_por ni resuelto_en.
    IF v_inc.estado_incidencia = 'resuelta' THEN
        RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
    END IF;

    IF v_inc.horario_ya_liberado IS TRUE THEN
        RAISE EXCEPTION 'Esta incidencia ocurrió con el horario ya liberado y requiere tratamiento posterior; no puede cerrarse con el cierre simple de carga.'
            USING ERRCODE = '23P01';
    END IF;

    IF v_a.estado_adelanto NOT IN ('comprobante_en_revision', 'observado', 'verificado') THEN
        RAISE EXCEPTION 'Solo se puede resolver la incidencia de carga cuando el adelanto esté en revisión, observado o verificado (estado actual: %).', v_a.estado_adelanto
            USING ERRCODE = '23P01';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM psicobloom_interno.comprobantes_adelanto c
        WHERE c.id_cita = p_id_cita
    ) INTO v_tiene_comprobante;

    IF NOT v_tiene_comprobante THEN
        RAISE EXCEPTION 'Debe existir al menos un comprobante registrado en la cita antes de resolver la incidencia de carga.'
            USING ERRCODE = '23P01';
    END IF;

    -- Actualiza únicamente el estado y auditoría de resolución de la incidencia.
    -- NO toca Citas, adelantos_citas ni Disponibilidad.
    UPDATE psicobloom_interno.incidencias_adelanto i
    SET estado_incidencia = 'resuelta',
        motivo_resolucion = v_motivo,
        resuelto_por = v_uid,
        resuelto_en = v_ahora
    WHERE i.id_incidencia = p_id_incidencia
      AND i.id_cita = p_id_cita
      AND i.estado_incidencia <> 'resuelta';

    RETURN public.obtener_detalle_adelanto_cita(p_id_cita);
END;
$$;

REVOKE ALL ON FUNCTION public.resolver_incidencia_adelanto(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.resolver_incidencia_adelanto(UUID, UUID, TEXT) TO authenticated;

COMMIT;
