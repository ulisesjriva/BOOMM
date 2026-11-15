-- =============================================================================
-- SCRIPT 6 — MIGRACION ADITIVA DE DISPONIBILIDAD DEL PROFESIONAL (I3-01)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencia verificada: esquema_real_psicobloom.json
-- Ejecutar en: Supabase > SQL Editor como postgres
--
-- Proposito:
--   1. Conservar intactas las tablas y restricciones existentes de
--      public."Disponibilidad" y public."Citas" sin duplicar tablas ni
--      inventar columnas:
--      - public."Disponibilidad" (id_disponibilidad, id_profesional, fecha,
--        hora_inicio, hora_fin, estado)
--      - public."Citas" (id_cita, id_paciente, id_profesional, id_disponibilidad,
--        fecha_solicitud, estado)
--   2. Configurar privilegios minimos y politicas RLS sin recursion sobre
--      public."Disponibilidad":
--      - Profesional activo: consulta y gestiona unicamente sus horarios propios.
--      - Administrador activo: lectura autorizada para supervision.
--      - Paciente activo: lectura unicamente de horarios futuros con estado
--        'disponible' pertenecientes a profesionales aprobados y con cuenta activa.
--   3. Incorporar triggers de integridad en base de datos para:
--      - Evitar intervalos superpuestos del mismo profesional en la misma fecha,
--        incluso en solicitudes simultaneas (bloqueando la fila del profesional
--        en public."Profesionales" con FOR UPDATE y permitiendo intervalos contiguos).
--      - Validar fecha y hora contra la zona horaria de Ecuador continental
--        (America/Guayaquil).
--      - Impedir que un profesional asigne manualmente el estado 'reservada'.
--      - Proteger los horarios reservados o vinculados a public."Citas" frente
--        a ediciones o bloqueos incompatibles.
--      - Impedir reservas en public."Citas" con profesionales no aprobados o inactivos.
--   4. Crear las funciones RPC SECURITY DEFINER que resuelven id_profesional
--      mediante public."Profesionales".id_usuario = auth.uid():
--      - public.listar_disponibilidad_profesional_propia()
--      - public.crear_disponibilidad_profesional_propia(DATE, TIME, TIME)
--      - public.actualizar_disponibilidad_profesional_propia(UUID, DATE, TIME, TIME)
--      - public.cambiar_estado_disponibilidad_profesional_propia(UUID, TEXT)
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. FUNCIONES AUXILIARES DE AUTORIZACION SIN RECURSION (IDEMPOTENTES)
-- ---------------------------------------------------------------------------
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

REVOKE ALL ON FUNCTION
    public._es_profesional_propio(UUID),
    public._profesional_es_publicable(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public._es_profesional_propio(UUID),
    public._profesional_es_publicable(UUID)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. PRIVILEGIOS MINIMOS Y POLITICAS RLS EN public."Disponibilidad"
-- ---------------------------------------------------------------------------
ALTER TABLE public."Disponibilidad" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."Disponibilidad" FROM PUBLIC, anon, authenticated;
-- La app consulta con RLS y escribe exclusivamente mediante RPC autorizadas.
GRANT SELECT ON public."Disponibilidad" TO authenticated;

CREATE INDEX IF NOT EXISTS idx_disponibilidad_profesional_fecha_inicio
    ON public."Disponibilidad" (id_profesional, fecha, hora_inicio);

DROP POLICY IF EXISTS disponibilidad_leer_autorizados ON public."Disponibilidad";
CREATE POLICY disponibilidad_leer_autorizados ON public."Disponibilidad"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'profesional'
        AND public._es_profesional_propio(id_profesional)
    )
    OR (SELECT public._rol_activo()) = 'administrador'
    OR (
        (SELECT public._rol_activo()) = 'paciente'
        AND estado = 'disponible'
        AND public._profesional_es_publicable(id_profesional)
        AND (fecha + hora_inicio) > (now() AT TIME ZONE 'America/Guayaquil')
    )
);

DROP POLICY IF EXISTS disponibilidad_insertar_propio ON public."Disponibilidad";
CREATE POLICY disponibilidad_insertar_propio ON public."Disponibilidad"
FOR INSERT TO authenticated
WITH CHECK (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
    AND estado IN ('disponible', 'bloqueada')
);

DROP POLICY IF EXISTS disponibilidad_actualizar_propio ON public."Disponibilidad";
CREATE POLICY disponibilidad_actualizar_propio ON public."Disponibilidad"
FOR UPDATE TO authenticated
USING (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
    AND estado IN ('disponible', 'bloqueada')
)
WITH CHECK (
    (SELECT public._rol_activo()) = 'profesional'
    AND public._es_profesional_propio(id_profesional)
    AND estado IN ('disponible', 'bloqueada')
);

-- ---------------------------------------------------------------------------
-- 3. TRIGGERS DE VALIDACION, NO SOLAPAMIENTO Y PROTECCION DE CITAS
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

    -- Serializa las escrituras simultaneas sobre la agenda del mismo profesional
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

        IF public._rol_activo() = 'profesional' AND NEW.estado = 'reservada' THEN
            RAISE EXCEPTION 'El estado reservada solo se asigna mediante el flujo de citas.' USING ERRCODE = '22023';
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
              AND c.id_profesional = OLD.id_profesional
        ) INTO v_tiene_cita_historica;

        -- Si cambia fecha, hora_inicio o hora_fin:
        IF NEW.fecha IS DISTINCT FROM OLD.fecha
           OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
           OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin THEN

            IF OLD.estado <> 'disponible' OR v_tiene_cita_activa OR v_tiene_cita_historica THEN
                RAISE EXCEPTION 'Solo se pueden editar horarios disponibles que no tengan citas vinculadas.' USING ERRCODE = '22023';
            END IF;

            IF (OLD.fecha + OLD.hora_inicio) <= v_ahora_ecuador THEN
                RAISE EXCEPTION 'No se pueden editar horarios que ya iniciaron o pertenecen al pasado.' USING ERRCODE = '22023';
            END IF;

            IF (NEW.fecha + NEW.hora_inicio) <= v_ahora_ecuador THEN
                RAISE EXCEPTION 'La nueva fecha y hora de inicio deben ser futuras (hora de Ecuador).' USING ERRCODE = '22023';
            END IF;
        END IF;

        -- Si cambia el estado:
        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF public._rol_activo() = 'profesional' AND NEW.estado = 'reservada' THEN
                RAISE EXCEPTION 'No puedes cambiar manualmente un horario al estado reservada.' USING ERRCODE = '22023';
            END IF;

            IF (OLD.estado = 'reservada' OR v_tiene_cita_activa)
               AND NEW.estado IN ('disponible', 'bloqueada')
               AND public._rol_activo() = 'profesional' THEN
                RAISE EXCEPTION 'No se puede bloquear ni liberar manualmente un horario reservado o con cita activa.' USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;

    -- Verifica que no exista solapamiento en la misma fecha para el mismo profesional.
    -- La condicion (d.hora_inicio < NEW.hora_fin AND d.hora_fin > NEW.hora_inicio)
    -- rechaza cualquier interseccion y permite intervalos contiguos (ej. 09:00-10:00 y 10:00-11:00).
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

DROP TRIGGER IF EXISTS validar_disponibilidad_profesional_trg ON public."Disponibilidad";
CREATE TRIGGER validar_disponibilidad_profesional_trg
BEFORE INSERT OR UPDATE ON public."Disponibilidad"
FOR EACH ROW
EXECUTE FUNCTION public.validar_disponibilidad_profesional();

-- Impide que en public."Citas" se registren reservas con profesionales sin aprobar o inactivos
CREATE OR REPLACE FUNCTION public.validar_profesional_aprobado_en_citas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NOT public._profesional_es_publicable(NEW.id_profesional) THEN
        RAISE EXCEPTION 'No se permiten reservas con profesionales pendientes de aprobacion o inactivos.' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validar_profesional_aprobado_en_citas_trg ON public."Citas";
CREATE TRIGGER validar_profesional_aprobado_en_citas_trg
BEFORE INSERT OR UPDATE OF id_profesional, id_disponibilidad ON public."Citas"
FOR EACH ROW
EXECUTE FUNCTION public.validar_profesional_aprobado_en_citas();

REVOKE ALL ON FUNCTION
    public.validar_disponibilidad_profesional(),
    public.validar_profesional_aprobado_en_citas()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. FUNCIONES RPC PARA GESTION DE DISPONIBILIDAD PROPIA DEL PROFESIONAL
-- ---------------------------------------------------------------------------

-- 4.1 Consultar los horarios propios ordenados por fecha y hora de inicio
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
              AND c.estado IN ('pendiente', 'confirmada')
        ) AS tiene_cita_vinculada
    FROM public."Disponibilidad" d
    WHERE d.id_profesional = v_id_profesional
    ORDER BY d.fecha ASC, d.hora_inicio ASC;
END;
$$;

-- 4.2 Crear un intervalo individual de disponibilidad propia
CREATE OR REPLACE FUNCTION public.crear_disponibilidad_profesional_propia(
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

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid()
    FOR UPDATE;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public."Disponibilidad" (
        id_profesional,
        fecha,
        hora_inicio,
        hora_fin,
        estado
    )
    VALUES (
        v_id_profesional,
        p_fecha,
        p_hora_inicio,
        p_hora_fin,
        'disponible'
    )
    RETURNING * INTO v_fila;

    RETURN QUERY
    SELECT
        v_fila.id_disponibilidad,
        v_fila.id_profesional,
        v_fila.fecha,
        v_fila.hora_inicio,
        v_fila.hora_fin,
        v_fila.estado,
        FALSE AS tiene_cita_vinculada;
END;
$$;

-- 4.3 Editar fecha, hora inicial y hora final de un horario futuro disponible propio
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
              AND c.estado IN ('pendiente', 'confirmada')
        ) AS tiene_cita_vinculada;
END;
$$;

-- 4.4 Bloquear o desbloquear un horario propio no reservado
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
        FALSE AS tiene_cita_vinculada;
END;
$$;

REVOKE ALL ON FUNCTION
    public.listar_disponibilidad_profesional_propia(),
    public.crear_disponibilidad_profesional_propia(DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.actualizar_disponibilidad_profesional_propia(UUID, DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.cambiar_estado_disponibilidad_profesional_propia(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.listar_disponibilidad_profesional_propia(),
    public.crear_disponibilidad_profesional_propia(DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.actualizar_disponibilidad_profesional_propia(UUID, DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE),
    public.cambiar_estado_disponibilidad_profesional_propia(UUID, TEXT)
    TO authenticated;

COMMIT;
