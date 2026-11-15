-- =============================================================================
-- SCRIPT 10 — MIGRACION ADITIVA DE CONSULTA Y RESPUESTA DE CITAS DEL PROFESIONAL (I3-03)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencias verificadas:
--   - esquema_real_psicobloom.json
--   - 06_disponibilidad_profesional.sql
--   - 08_solicitud_citas_paciente.sql
-- Ejecutar en: Supabase > SQL Editor como postgres (despues de 06 y 08)
--
-- Proposito:
--   1. Conservar intactas las tablas, columnas y estados existentes:
--      - public."Citas" ya admite 'pendiente', 'confirmada', 'rechazada', 'cancelada'
--        (restriccion Citas_c_0f24f818). No se requiere alterar columnas ni estados.
--      - public."Disponibilidad" admite 'disponible', 'reservada', 'bloqueada'.
--   2. Reforzar los triggers de integridad en public."Disponibilidad" y public."Citas":
--      - Impedir eliminacion de filas en public."Citas" para preservar el historial.
--      - Permitir cambiar estado de 'pendiente' a 'confirmada' o 'rechazada'
--        exclusivamente al profesional propio, aprobado y con cuenta activa, y
--        solo sobre intervalos futuros en zona America/Guayaquil.
--      - Al rechazar una solicitud pendiente, liberar el horario a 'disponible'
--        unicamente dentro de la transaccion autorizada y solo si ninguna otra
--        cita activa ('pendiente' o 'confirmada') ocupa ese horario.
--      - Al liberar un horario tras un rechazo, conservar la cita 'rechazada'
--        como registro historico sin impedir nuevas solicitudes ni la gestion
--        posterior de su estado cuando esta libre de citas activas.
--        La fecha y las horas se conservan para no alterar el historial.
--   3. Crear las funciones RPC SECURITY DEFINER que resuelven id_profesional
--      mediante public."Profesionales".id_usuario = auth.uid() y mantienen el
--      orden canonico de bloqueos (Profesionales -> Disponibilidad -> Citas):
--      - public.listar_citas_profesional_propias()
--      - public.responder_solicitud_cita_profesional(UUID, TEXT)
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. INDICE DE APOYO Y PRIVILEGIOS MINIMOS EN public."Citas" Y public."Disponibilidad"
-- ---------------------------------------------------------------------------
ALTER TABLE public."Citas" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Disponibilidad" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."Citas", public."Disponibilidad" FROM PUBLIC, anon, authenticated;
-- Solo lectura mediante RLS; toda escritura ocurre mediante RPC autorizadas.
GRANT SELECT ON public."Citas", public."Disponibilidad" TO authenticated;

CREATE INDEX IF NOT EXISTS idx_citas_profesional_estado_fecha
    ON public."Citas" (id_profesional, estado, fecha_solicitud DESC);

-- ---------------------------------------------------------------------------
-- 2. TRIGGERS DE INTEGRIDAD PARA TRANSICIONES DE CITAS Y DISPONIBILIDAD
-- ---------------------------------------------------------------------------

-- 2.1 Trigger en public."Disponibilidad": conserva todas las reglas de 06 y 08,
-- y habilita la transicion controlada 'reservada' -> 'disponible' unicamente
-- cuando se rechaza una solicitud en la misma transaccion y no queda ninguna
-- otra cita activa ('pendiente' o 'confirmada') vinculada al horario.
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

    -- 1er bloqueo del orden canonico (Profesionales -> Disponibilidad -> Citas)
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

        -- La fecha y las horas tambien describen las citas historicas.
        SELECT EXISTS (
            SELECT 1 FROM public."Citas" c
            WHERE c.id_disponibilidad = OLD.id_disponibilidad
        ) INTO v_tiene_cita_historica;

        -- Si cambia fecha, hora_inicio o hora_fin:
        IF NEW.fecha IS DISTINCT FROM OLD.fecha
           OR NEW.hora_inicio IS DISTINCT FROM OLD.hora_inicio
           OR NEW.hora_fin IS DISTINCT FROM OLD.hora_fin THEN

            IF OLD.estado <> 'disponible' OR v_tiene_cita_activa OR v_tiene_cita_historica THEN
                RAISE EXCEPTION 'No se pueden cambiar fecha ni horas de un horario con citas vinculadas, incluidas las rechazadas. Registra otro horario para usar un intervalo diferente.' USING ERRCODE = '22023';
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
            IF NEW.estado = 'reservada' THEN
                IF public._rol_activo() = 'profesional' THEN
                    RAISE EXCEPTION 'No puedes cambiar manualmente un horario al estado reservada.' USING ERRCODE = '22023';
                END IF;
                IF NOT v_tiene_cita_activa THEN
                    RAISE EXCEPTION 'El estado reservada requiere una cita activa vinculada al horario.' USING ERRCODE = '22023';
                END IF;
            END IF;

            -- Si existe una cita activa ('pendiente' o 'confirmada'), jamas se
            -- permite pasar el horario a 'disponible' ni a 'bloqueada'.
            IF v_tiene_cita_activa AND NEW.estado IN ('disponible', 'bloqueada') THEN
                RAISE EXCEPTION 'No se puede bloquear ni liberar un horario que tiene una cita activa.' USING ERRCODE = '22023';
            END IF;

            -- Si estaba 'reservada' y ya no tiene cita activa, solo puede pasar
            -- a 'disponible' dentro de la transaccion autorizada de rechazo.
            IF OLD.estado = 'reservada' AND NEW.estado = 'bloqueada' THEN
                RAISE EXCEPTION 'No se puede bloquear directamente un horario reservado.' USING ERRCODE = '22023';
            END IF;

            IF OLD.estado = 'reservada'
               AND NEW.estado = 'disponible'
               AND public._rol_activo() = 'profesional'
               AND v_contexto_respuesta IS DISTINCT FROM 'rechazo_profesional' THEN
                RAISE EXCEPTION 'No se puede liberar manualmente un horario reservado fuera del flujo de respuesta de solicitudes.' USING ERRCODE = '22023';
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

-- 2.2 Trigger en public."Citas" para validar inserciones y transiciones de estado
CREATE OR REPLACE FUNCTION public.validar_profesional_aprobado_en_citas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_horario public."Disponibilidad"%ROWTYPE;
BEGIN
    IF NOT public._profesional_es_publicable(NEW.id_profesional) THEN
        RAISE EXCEPTION 'No se permiten operaciones de citas con profesionales pendientes de aprobacion o inactivos.' USING ERRCODE = '42501';
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

-- 2.3 Trigger que impide eliminar citas para preservar el historial
CREATE OR REPLACE FUNCTION public.impedir_eliminacion_citas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RAISE EXCEPTION 'No se permite eliminar citas ni sobrescribir su historial.' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS validar_profesional_aprobado_en_citas_trg ON public."Citas";
CREATE TRIGGER validar_profesional_aprobado_en_citas_trg
BEFORE INSERT OR UPDATE ON public."Citas"
FOR EACH ROW
EXECUTE FUNCTION public.validar_profesional_aprobado_en_citas();

DROP TRIGGER IF EXISTS impedir_eliminacion_citas_trg ON public."Citas";
CREATE TRIGGER impedir_eliminacion_citas_trg
BEFORE DELETE ON public."Citas"
FOR EACH ROW
EXECUTE FUNCTION public.impedir_eliminacion_citas();

REVOKE ALL ON FUNCTION
    public.validar_disponibilidad_profesional(),
    public.validar_profesional_aprobado_en_citas(),
    public.impedir_eliminacion_citas()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. FUNCIONES RPC PARA EL PROFESIONAL: CONSULTA Y RESPUESTA DE SOLICITUDES
-- ---------------------------------------------------------------------------

-- 3.1 Listar unicamente las solicitudes y citas propias del profesional autenticado
CREATE OR REPLACE FUNCTION public.listar_citas_profesional_propias()
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
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa para consultar solicitudes de citas.' USING ERRCODE = '42501';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_usuario = auth.uid();

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro profesional asociado a tu cuenta.' USING ERRCODE = '42501';
    END IF;

    IF NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'Tu perfil profesional debe estar aprobado y activo para gestionar solicitudes de citas.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        c.id_cita,
        c.id_paciente,
        c.id_profesional,
        c.id_disponibilidad,
        trim(p.nombre || ' ' || p.apellido) AS nombre_paciente,
        COALESCE(pr.modalidad, 'Presencial') AS modalidad_profesional,
        d.fecha,
        d.hora_inicio,
        d.hora_fin,
        c.estado,
        d.estado AS estado_disponibilidad,
        c.fecha_solicitud
    FROM public."Citas" c
    JOIN public."Disponibilidad" d
      ON d.id_disponibilidad = c.id_disponibilidad
     AND d.id_profesional = c.id_profesional
    JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
    JOIN public."Pacientes" pa ON pa.id_paciente = c.id_paciente
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pa.id_usuario
    WHERE c.id_profesional = v_id_profesional
    ORDER BY d.fecha ASC, d.hora_inicio ASC, c.fecha_solicitud DESC;
END;
$$;

-- 3.2 Responder una solicitud pendiente propia ('confirmada' o 'rechazada')
-- manteniendo el orden canonico de bloqueos:
--   1) public."Profesionales" FOR UPDATE
--   2) public."Disponibilidad" FOR UPDATE
--   3) public."Citas" FOR UPDATE
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
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_horario public."Disponibilidad"%ROWTYPE;
    v_cita public."Citas"%ROWTYPE;
    v_existe_otra_cita_activa BOOLEAN := FALSE;
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

    -- 1er bloqueo del orden canonico: fila del profesional titular
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

    -- Localiza el horario de la cita verificando pertenencia al profesional autenticado
    SELECT c.id_disponibilidad
    INTO v_id_disponibilidad
    FROM public."Citas" c
    WHERE c.id_cita = p_id_cita
      AND c.id_profesional = v_id_profesional;

    IF v_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'La solicitud indicada no existe o no pertenece a tu perfil profesional.' USING ERRCODE = '42501';
    END IF;

    -- 2do bloqueo del orden canonico: fila del horario en public."Disponibilidad"
    SELECT *
    INTO v_horario
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = v_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontro el horario asociado a la solicitud.' USING ERRCODE = '22023';
    END IF;

    -- 3er bloqueo del orden canonico: fila de la cita en public."Citas"
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

    IF v_nuevo_estado = 'confirmada' THEN
        IF v_horario.estado IS DISTINCT FROM 'reservada' THEN
            RAISE EXCEPTION 'El horario asociado no se encuentra reservado; no se pudo confirmar la solicitud.' USING ERRCODE = '23P01';
        END IF;

        UPDATE public."Citas" c
        SET estado = 'confirmada'
        WHERE c.id_cita = v_cita.id_cita
          AND c.id_profesional = v_id_profesional
          AND c.estado = 'pendiente'
        RETURNING * INTO v_cita;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No fue posible confirmar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
        END IF;
    ELSE
        -- Rechazo: conserva la cita como registro historico con estado 'rechazada'
        UPDATE public."Citas" c
        SET estado = 'rechazada'
        WHERE c.id_cita = v_cita.id_cita
          AND c.id_profesional = v_id_profesional
          AND c.estado = 'pendiente'
        RETURNING * INTO v_cita;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No fue posible rechazar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
        END IF;

        -- Comprueba si otra cita activa ('pendiente' o 'confirmada') ocupa el mismo horario
        SELECT EXISTS (
            SELECT 1
            FROM public."Citas" c
            WHERE c.id_disponibilidad = v_horario.id_disponibilidad
              AND c.id_profesional = v_id_profesional
              AND c.id_cita <> v_cita.id_cita
              AND c.estado IN ('pendiente', 'confirmada')
        ) INTO v_existe_otra_cita_activa;

        IF NOT v_existe_otra_cita_activa THEN
            PERFORM set_config('psicobloom.contexto_respuesta_cita', 'rechazo_profesional', TRUE);

            UPDATE public."Disponibilidad" d
            SET estado = 'disponible'
            WHERE d.id_disponibilidad = v_horario.id_disponibilidad
              AND d.id_profesional = v_id_profesional
              AND d.estado = 'reservada'
            RETURNING * INTO v_horario;

            GET DIAGNOSTICS v_filas_disp = ROW_COUNT;
            PERFORM set_config('psicobloom.contexto_respuesta_cita', '', TRUE);

            IF v_filas_disp <> 1 THEN
                RAISE EXCEPTION 'No fue posible liberar el horario tras rechazar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
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

REVOKE ALL ON FUNCTION
    public.listar_citas_profesional_propias(),
    public.responder_solicitud_cita_profesional(UUID, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.listar_citas_profesional_propias(),
    public.responder_solicitud_cita_profesional(UUID, TEXT)
    TO authenticated;

COMMIT;
