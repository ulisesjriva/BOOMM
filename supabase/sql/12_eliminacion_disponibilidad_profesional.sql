-- =============================================================================
-- SCRIPT 12 — MIGRACION ADITIVA: ELIMINACION SEGURA DE HORARIOS SIN CITAS (I3-04)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencias verificadas:
--   - esquema_real_psicobloom.json
--   - 06_disponibilidad_profesional.sql
--   - 08_solicitud_citas_paciente.sql
--   - 10_respuesta_citas_profesional.sql
-- Ejecutar en: Supabase > SQL Editor como postgres (despues de 06, 08 y 10)
--
-- Proposito:
--   1. Mantener privilegios minimos y RLS en public."Disponibilidad" y public."Citas"
--      sin conceder DELETE directo a anon ni a authenticated.
--   2. Actualizar listar_disponibilidad_profesional_propia(),
--      actualizar_disponibilidad_profesional_propia() y
--      cambiar_estado_disponibilidad_profesional_propia() para que el campo
--      tiene_cita_vinculada refleje la existencia de CUALQUIER cita vinculada
--      en public."Citas" (incluidas 'pendiente', 'confirmada', 'rechazada' y
--      'cancelada'), protegiendo las fechas y horas del historial.
--   3. Incorporar trigger BEFORE DELETE en public."Disponibilidad" que serializa
--      contra public."Profesionales" FOR UPDATE e impide eliminar horarios
--      reservados o vinculados a cualquier cita activa o historica.
--   4. Crear la RPC SECURITY DEFINER:
--      - public.eliminar_disponibilidad_profesional_propia(UUID)
--      que comprueba sesion, rol profesional y cuenta activa, reutiliza el orden
--      canonico de bloqueos (Profesionales FOR UPDATE -> Disponibilidad FOR UPDATE)
--      para evitar condiciones de carrera con solicitar_cita_paciente, y elimina
--      unicamente horarios propios sin ninguna cita vinculada.
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. PRIVILEGIOS MINIMOS Y BLOQUEO DE DELETE DIRECTO
-- ---------------------------------------------------------------------------
ALTER TABLE public."Disponibilidad" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Citas" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."Disponibilidad", public."Citas" FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public."Disponibilidad", public."Citas" TO authenticated;

-- Asegura que no exista ninguna politica RLS de DELETE directo para clientes
DROP POLICY IF EXISTS disponibilidad_eliminar_propio ON public."Disponibilidad";

-- ---------------------------------------------------------------------------
-- 2. TRIGGER BEFORE DELETE EN public."Disponibilidad" PARA PROTEGER HISTORIAL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validar_eliminacion_disponibilidad_profesional()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- 1er bloqueo del orden canonico: fila del profesional titular
    PERFORM 1
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = OLD.id_profesional
    FOR UPDATE;

    IF OLD.estado = 'reservada' THEN
        RAISE EXCEPTION 'No se puede eliminar un horario que se encuentra reservado.' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = OLD.id_disponibilidad
    ) THEN
        RAISE EXCEPTION 'No se puede eliminar un horario con citas vinculadas en el historial (incluidas rechazadas o canceladas).' USING ERRCODE = '22023';
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS validar_eliminacion_disponibilidad_profesional_trg ON public."Disponibilidad";
CREATE TRIGGER validar_eliminacion_disponibilidad_profesional_trg
BEFORE DELETE ON public."Disponibilidad"
FOR EACH ROW
EXECUTE FUNCTION public.validar_eliminacion_disponibilidad_profesional();

REVOKE ALL ON FUNCTION
    public.validar_eliminacion_disponibilidad_profesional()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. ACTUALIZACION DE RPC EXISTENTES PARA INCLUIR HISTORIAL EN tiene_cita_vinculada
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_disponibilidad_profesional_propia()
RETURNS TABLE(
    id_disponibilidad UUID,
    id_profesional UUID,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT,
    tiene_cita_vinculada BOOLEAN
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
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid();

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        d.id_disponibilidad,
        d.id_profesional,
        d.fecha,
        d.hora_inicio,
        d.hora_fin,
        d.estado,
        EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = d.id_disponibilidad
              AND c.id_profesional = d.id_profesional
        ) AS tiene_cita_vinculada
    FROM public."Disponibilidad" d
    WHERE d.id_profesional = v_id_profesional
    ORDER BY d.fecha ASC, d.hora_inicio ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.actualizar_disponibilidad_profesional_propia(
    p_id_disponibilidad UUID,
    p_fecha DATE,
    p_hora_inicio TIME WITHOUT TIME ZONE,
    p_hora_fin TIME WITHOUT TIME ZONE
)
RETURNS TABLE(
    id_disponibilidad UUID,
    id_profesional UUID,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT,
    tiene_cita_vinculada BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_fila public."Disponibilidad"%ROWTYPE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el horario que deseas editar.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El horario indicado no existe o no pertenece a tu perfil profesional.' USING ERRCODE = '42501';
    END IF;

    UPDATE public."Disponibilidad" d
    SET fecha = p_fecha,
        hora_inicio = p_hora_inicio,
        hora_fin = p_hora_fin
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    RETURNING * INTO v_fila;

    RETURN QUERY
    SELECT
        v_fila.id_disponibilidad,
        v_fila.id_profesional,
        v_fila.fecha,
        v_fila.hora_inicio,
        v_fila.hora_fin,
        v_fila.estado,
        EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = v_fila.id_disponibilidad
              AND c.id_profesional = v_fila.id_profesional
        ) AS tiene_cita_vinculada;
END;
$$;

CREATE OR REPLACE FUNCTION public.cambiar_estado_disponibilidad_profesional_propia(
    p_id_disponibilidad UUID,
    p_nuevo_estado TEXT
)
RETURNS TABLE(
    id_disponibilidad UUID,
    id_profesional UUID,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT,
    tiene_cita_vinculada BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_estado_limpio TEXT := lower(trim(COALESCE(p_nuevo_estado, '')));
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_actual public."Disponibilidad"%ROWTYPE;
    v_fila public."Disponibilidad"%ROWTYPE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el horario a modificar.' USING ERRCODE = '22023';
    END IF;

    IF v_estado_limpio = 'reservada' THEN
        RAISE EXCEPTION 'No puedes asignar manualmente el estado reservada a un horario.' USING ERRCODE = '22023';
    END IF;

    IF v_estado_limpio NOT IN ('disponible', 'bloqueada') THEN
        RAISE EXCEPTION 'Solo puedes cambiar el estado del horario a disponible o bloqueada.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '22023';
    END IF;

    SELECT *
    INTO v_actual
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El horario indicado no existe o no pertenece a tu perfil profesional.' USING ERRCODE = '42501';
    END IF;

    IF v_actual.estado = 'reservada' OR EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_actual.id_disponibilidad
          AND c.id_profesional = v_actual.id_profesional
          AND c.estado IN ('pendiente', 'confirmada')
    ) THEN
        RAISE EXCEPTION 'No puedes bloquear ni desbloquear un horario que se encuentra reservado o vinculado a una cita activa.' USING ERRCODE = '22023';
    END IF;

    IF (v_actual.fecha + v_actual.hora_inicio) <= v_ahora_ecuador THEN
        RAISE EXCEPTION 'No puedes cambiar el estado de un horario que ya inicio o pertenece al pasado.' USING ERRCODE = '22023';
    END IF;

    UPDATE public."Disponibilidad" d
    SET estado = v_estado_limpio
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    RETURNING * INTO v_fila;

    RETURN QUERY
    SELECT
        v_fila.id_disponibilidad,
        v_fila.id_profesional,
        v_fila.fecha,
        v_fila.hora_inicio,
        v_fila.hora_fin,
        v_fila.estado,
        EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = v_fila.id_disponibilidad
              AND c.id_profesional = v_fila.id_profesional
        ) AS tiene_cita_vinculada;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. RPC AUTORIZADA: ELIMINAR HORARIO PROPIO SIN CITAS VINCULADAS
-- ---------------------------------------------------------------------------
-- Orden canonico de bloqueos:
--   1) public."Profesionales" FOR UPDATE
--   2) public."Disponibilidad" FOR UPDATE
-- Esto serializa la eliminacion frente a solicitar_cita_paciente y evita
-- que una eliminacion simultanea con una reserva deje datos inconsistentes.
CREATE OR REPLACE FUNCTION public.eliminar_disponibilidad_profesional_propia(
    p_id_disponibilidad UUID
)
RETURNS TABLE(
    id_disponibilidad UUID,
    id_profesional UUID,
    fecha DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    estado TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_actual public."Disponibilidad"%ROWTYPE;
    v_eliminado public."Disponibilidad"%ROWTYPE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el horario que deseas eliminar.' USING ERRCODE = '22023';
    END IF;

    -- 1er bloqueo del orden canonico: fila del profesional titular
    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '22023';
    END IF;

    -- 2do bloqueo del orden canonico: fila del horario en public."Disponibilidad"
    SELECT *
    INTO v_actual
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El horario indicado no existe o no pertenece a tu perfil profesional.' USING ERRCODE = '42501';
    END IF;

    IF v_actual.estado = 'reservada' THEN
        RAISE EXCEPTION 'No se puede eliminar un horario que se encuentra reservado.' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_actual.id_disponibilidad
    ) THEN
        RAISE EXCEPTION 'No se puede eliminar un horario con citas vinculadas en el historial (incluidas rechazadas o canceladas).' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = v_actual.id_disponibilidad
      AND d.id_profesional = v_id_profesional
    RETURNING * INTO v_eliminado;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No fue posible eliminar el horario seleccionado.' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        v_eliminado.id_disponibilidad,
        v_eliminado.id_profesional,
        v_eliminado.fecha,
        v_eliminado.hora_inicio,
        v_eliminado.hora_fin,
        v_eliminado.estado;
END;
$$;

REVOKE ALL ON FUNCTION
    public.listar_disponibilidad_profesional_propia(),
    public.actualizar_disponibilidad_profesional_propia(UUID, DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.cambiar_estado_disponibilidad_profesional_propia(UUID, TEXT),
    public.eliminar_disponibilidad_profesional_propia(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.listar_disponibilidad_profesional_propia(),
    public.actualizar_disponibilidad_profesional_propia(UUID, DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.cambiar_estado_disponibilidad_profesional_propia(UUID, TEXT),
    public.eliminar_disponibilidad_profesional_propia(UUID)
    TO authenticated;

COMMIT;
