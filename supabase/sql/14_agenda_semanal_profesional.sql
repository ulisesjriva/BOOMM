-- =============================================================================
-- SCRIPT 14 — MIGRACION ADITIVA: AGENDA SEMANAL SIMPLIFICADA DEL PROFESIONAL
-- (CREACION DE VARIOS INTERVALOS POR JORNADA, REPETICION SEMANAL CON VISTA
-- PREVIA Y DIAS NO LABORABLES)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencias verificadas:
--   - esquema_real_psicobloom.json
--   - 06_disponibilidad_profesional.sql
--   - 08_solicitud_citas_paciente.sql
--   - 10_respuesta_citas_profesional.sql
--   - 12_eliminacion_disponibilidad_profesional.sql
-- Ejecutar en: Supabase > SQL Editor como postgres (despues de 06, 08, 10 y 12)
--
-- Proposito:
--   1. Conservar intactas las migraciones 06 a 13 y las tablas public."Disponibilidad"
--      y public."Citas" sin agregar plantillas persistentes redundantes.
--   2. Crear la estructura minima public."DiasNoLaborables" para registrar
--      excepciones de dias no laborables por profesional y fecha, con RLS y
--      privilegios minimos (sin escritura directa desde el cliente).
--   3. Aplicar la restriccion de dias no laborables en los triggers y RPC
--      existentes de creacion, edicion, desbloqueo y solicitud de citas, sin
--      cancelar ni rechazar automaticamente citas pendientes o confirmadas.
--   4. Incorporar la RPC transaccional para crear varios intervalos en una
--      jornada con duracion y descanso configurables:
--      - public.crear_intervalos_jornada_profesional_propia(DATE, TIME, TIME, INTEGER, INTEGER)
--   5. Incorporar las RPC para gestionar dias no laborables desde la agenda:
--      - public.listar_dias_no_laborables_profesional_propios()
--      - public.registrar_dia_no_laborable_profesional_propio(DATE, TEXT)
--      - public.retirar_dia_no_laborable_profesional_propio(DATE)
--   6. Incorporar las RPC para previsualizar y confirmar la copia explicita de
--      la semana visible hacia 1 a 4 semanas posteriores:
--      - public.previsualizar_repeticion_semana_profesional_propia(DATE, INTEGER)
--      - public.confirmar_repeticion_semana_profesional_propia(DATE, INTEGER, TEXT)
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. TABLA MINIMA DE EXCEPCIONES: public."DiasNoLaborables" Y POLITICAS RLS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public."DiasNoLaborables" (
    id_dia_no_laborable UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_profesional UUID NOT NULL REFERENCES public."Profesionales"(id_profesional) ON DELETE CASCADE,
    fecha DATE NOT NULL,
    motivo TEXT,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT dias_no_laborables_profesional_fecha_unica UNIQUE (id_profesional, fecha),
    CONSTRAINT dias_no_laborables_motivo_longitud CHECK (
        motivo IS NULL OR char_length(trim(motivo)) <= 200
    )
);

ALTER TABLE public."DiasNoLaborables" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."DiasNoLaborables" FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public."DiasNoLaborables" TO authenticated;

CREATE INDEX IF NOT EXISTS idx_dias_no_laborables_profesional_fecha
    ON public."DiasNoLaborables" (id_profesional, fecha);

CREATE OR REPLACE FUNCTION public._es_dia_no_laborable_profesional(
    p_id_profesional UUID,
    p_fecha DATE
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."DiasNoLaborables" dnl
        WHERE dnl.id_profesional = p_id_profesional
          AND dnl.fecha = p_fecha
    );
$$;

REVOKE ALL ON FUNCTION
    public._es_dia_no_laborable_profesional(UUID, DATE)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public._es_dia_no_laborable_profesional(UUID, DATE)
    TO authenticated;

DROP POLICY IF EXISTS dias_no_laborables_leer_autorizados ON public."DiasNoLaborables";
CREATE POLICY dias_no_laborables_leer_autorizados ON public."DiasNoLaborables"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'profesional'
        AND public._es_profesional_propio(id_profesional)
    )
    OR (SELECT public._rol_activo()) = 'administrador'
);

-- Actualiza la politica de lectura de public."Disponibilidad" para que el
-- paciente tampoco vea como disponibles los intervalos de dias no laborables.
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
        AND NOT public._es_dia_no_laborable_profesional(id_profesional, fecha)
        AND (fecha + hora_inicio) > (now() AT TIME ZONE 'America/Guayaquil')
    )
);

-- ---------------------------------------------------------------------------
-- 2. REFUERZO DE TRIGGERS Y RPC EXISTENTES CON REGLA DE DIA NO LABORABLE
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

        -- Si cambia fecha, hora_inicio o hora_fin:
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

            IF v_tiene_cita_activa AND NEW.estado IN ('disponible', 'bloqueada') THEN
                RAISE EXCEPTION 'No se puede bloquear ni liberar un horario que tiene una cita activa.' USING ERRCODE = '22023';
            END IF;

            IF NEW.estado = 'disponible'
               AND public._es_dia_no_laborable_profesional(NEW.id_profesional, NEW.fecha) THEN
                RAISE EXCEPTION 'No se puede desbloquear ni habilitar un horario en una fecha marcada como dia no laborable. Retira primero la excepcion del dia.' USING ERRCODE = '22023';
            END IF;

            IF OLD.estado = 'reservada'
               AND NEW.estado = 'bloqueada'
               AND v_contexto_respuesta IS DISTINCT FROM 'rechazo_profesional' THEN
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

REVOKE ALL ON FUNCTION
    public.validar_disponibilidad_profesional(),
    public.validar_profesional_aprobado_en_citas()
    FROM PUBLIC, anon, authenticated;

-- Actualiza listar_horarios_disponibles_profesional y solicitar_cita_paciente
-- para excluir dias no laborables en las consultas y reservas de pacientes.
CREATE OR REPLACE FUNCTION public.listar_horarios_disponibles_profesional(
    p_id_profesional UUID
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
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa para consultar horarios disponibles.' USING ERRCODE = '42501';
    END IF;

    IF p_id_profesional IS NULL THEN
        RAISE EXCEPTION 'Debes indicar el profesional cuyos horarios deseas consultar.' USING ERRCODE = '22023';
    END IF;

    SELECT pr.id_profesional
    INTO v_id_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = p_id_profesional
       OR pr.id_usuario = p_id_profesional;

    IF v_id_profesional IS NULL OR NOT public._profesional_es_publicable(v_id_profesional) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        d.id_disponibilidad,
        d.id_profesional,
        d.fecha,
        d.hora_inicio,
        d.hora_fin,
        d.estado
    FROM public."Disponibilidad" d
    WHERE d.id_profesional = v_id_profesional
      AND d.estado = 'disponible'
      AND NOT public._es_dia_no_laborable_profesional(d.id_profesional, d.fecha)
      AND (d.fecha + d.hora_inicio) > v_ahora_ecuador
      AND NOT EXISTS (
          SELECT 1
          FROM public."Citas" c
          WHERE c.id_disponibilidad = d.id_disponibilidad
            AND c.estado IN ('pendiente', 'confirmada')
      )
    ORDER BY d.fecha ASC, d.hora_inicio ASC;
END;
$$;

-- En responder_solicitud_cita_profesional: si se rechaza una solicitud en un
-- dia marcado como no laborable, el intervalo queda en 'bloqueada' en lugar de
-- volver a 'disponible' mientras la excepcion siga activa.
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
    v_estado_disp_destino TEXT;
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
        UPDATE public."Citas" c
        SET estado = 'rechazada'
        WHERE c.id_cita = v_cita.id_cita
          AND c.id_profesional = v_id_profesional
          AND c.estado = 'pendiente'
        RETURNING * INTO v_cita;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No fue posible rechazar la solicitud; la operacion se revirtio.' USING ERRCODE = '23P01';
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
            v_estado_disp_destino := CASE
                WHEN public._es_dia_no_laborable_profesional(v_id_profesional, v_horario.fecha)
                THEN 'bloqueada'
                ELSE 'disponible'
            END;

            PERFORM set_config('psicobloom.contexto_respuesta_cita', 'rechazo_profesional', TRUE);

            UPDATE public."Disponibilidad" d
            SET estado = v_estado_disp_destino
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
-- 3. RPC TRANSACCIONAL: CREAR VARIOS INTERVALOS EN UNA JORNADA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_intervalos_jornada_profesional_propia(
    p_fecha DATE,
    p_hora_inicio TIME WITHOUT TIME ZONE,
    p_hora_fin TIME WITHOUT TIME ZONE,
    p_duracion_minutos INTEGER,
    p_descanso_minutos INTEGER DEFAULT 0
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
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_min_inicio INTEGER;
    v_min_fin INTEGER;
    v_cursor_min INTEGER;
    v_inicios TIME WITHOUT TIME ZONE[] := ARRAY[]::TIME WITHOUT TIME ZONE[];
    v_fines TIME WITHOUT TIME ZONE[] := ARRAY[]::TIME WITHOUT TIME ZONE[];
    v_total_generados INTEGER := 0;
    v_conflictos TEXT[] := ARRAY[]::TEXT[];
    v_idx INTEGER;
    v_hora_ini TIME WITHOUT TIME ZONE;
    v_hora_fin_item TIME WITHOUT TIME ZONE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL
       OR p_duracion_minutos IS NULL OR p_descanso_minutos IS NULL THEN
        RAISE EXCEPTION 'Debes indicar fecha, hora inicial, hora final, duracion y descanso.' USING ERRCODE = '22023';
    END IF;

    IF p_hora_fin <= p_hora_inicio THEN
        RAISE EXCEPTION 'La hora final debe ser posterior a la hora inicial.' USING ERRCODE = '23514';
    END IF;

    IF p_duracion_minutos <= 0 OR p_duracion_minutos > 720 THEN
        RAISE EXCEPTION 'La duracion de cada cita debe ser mayor a 0 y de maximo 720 minutos.' USING ERRCODE = '22023';
    END IF;

    IF p_descanso_minutos < 0 OR p_descanso_minutos > 360 THEN
        RAISE EXCEPTION 'El descanso entre citas no puede ser negativo (0 a 360 minutos).' USING ERRCODE = '22023';
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

    IF public._es_dia_no_laborable_profesional(v_id_profesional, p_fecha) THEN
        RAISE EXCEPTION 'No se pueden agregar horarios en % porque esta marcado como dia no laborable.', p_fecha
            USING ERRCODE = '22023';
    END IF;

    IF (p_fecha + p_hora_inicio) <= v_ahora_ecuador THEN
        RAISE EXCEPTION 'No se permiten crear intervalos en fechas u horas pasadas (hora de Ecuador).' USING ERRCODE = '22023';
    END IF;

    v_min_inicio := (EXTRACT(HOUR FROM p_hora_inicio)::INTEGER * 60) + EXTRACT(MINUTE FROM p_hora_inicio)::INTEGER;
    v_min_fin := (EXTRACT(HOUR FROM p_hora_fin)::INTEGER * 60) + EXTRACT(MINUTE FROM p_hora_fin)::INTEGER;
    v_cursor_min := v_min_inicio;

    WHILE (v_cursor_min + p_duracion_minutos) <= v_min_fin LOOP
        v_total_generados := v_total_generados + 1;
        IF v_total_generados > 24 THEN
            RAISE EXCEPTION 'Se permite generar un maximo de 24 intervalos por operacion. Reduce el rango horario o aumenta la duracion.'
                USING ERRCODE = '22023';
        END IF;

        v_hora_ini := make_time(v_cursor_min / 60, v_cursor_min % 60, 0);
        v_hora_fin_item := make_time((v_cursor_min + p_duracion_minutos) / 60, (v_cursor_min + p_duracion_minutos) % 60, 0);

        v_inicios := array_append(v_inicios, v_hora_ini);
        v_fines := array_append(v_fines, v_hora_fin_item);

        v_cursor_min := v_cursor_min + p_duracion_minutos + p_descanso_minutos;
    END LOOP;

    IF v_total_generados = 0 THEN
        RAISE EXCEPTION 'No cabe ningun intervalo completo de % minutos entre % y %.',
            p_duracion_minutos,
            to_char(p_hora_inicio, 'HH24:MI'),
            to_char(p_hora_fin, 'HH24:MI')
            USING ERRCODE = '22023';
    END IF;

    -- Comprueba todos los intervalos candidatos frente a los ya existentes en esa fecha
    -- para informar exactamente cuales entran en conflicto sin guardar parcialmente el grupo.
    FOR v_idx IN 1..v_total_generados LOOP
        v_hora_ini := v_inicios[v_idx];
        v_hora_fin_item := v_fines[v_idx];

        IF EXISTS (
            SELECT 1
            FROM public."Disponibilidad" d
            WHERE d.id_profesional = v_id_profesional
              AND d.fecha = p_fecha
              AND d.hora_inicio < v_hora_fin_item
              AND d.hora_fin > v_hora_ini
        ) THEN
            v_conflictos := array_append(
                v_conflictos,
                to_char(v_hora_ini, 'HH24:MI') || '–' || to_char(v_hora_fin_item, 'HH24:MI')
            );
        END IF;
    END LOOP;

    IF COALESCE(array_length(v_conflictos, 1), 0) > 0 THEN
        RAISE EXCEPTION 'No se guardo ningun horario porque los siguientes intervalos entran en conflicto con horarios existentes: %.',
            array_to_string(v_conflictos, ', ')
            USING ERRCODE = '23P01';
    END IF;

    RETURN QUERY
    WITH insertados AS (
        INSERT INTO public."Disponibilidad" (
            id_profesional,
            fecha,
            hora_inicio,
            hora_fin,
            estado
        )
        SELECT
            v_id_profesional,
            p_fecha,
            u.ini,
            u.fin,
            'disponible'
        FROM unnest(v_inicios, v_fines) WITH ORDINALITY AS u(ini, fin, ord)
        ORDER BY u.ord
        RETURNING *
    )
    SELECT
        ins.id_disponibilidad,
        ins.id_profesional,
        ins.fecha,
        ins.hora_inicio,
        ins.hora_fin,
        ins.estado,
        FALSE AS tiene_cita_vinculada
    FROM insertados ins
    ORDER BY ins.hora_inicio ASC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. RPC DE DIAS NO LABORABLES DESDE LA MISMA AGENDA
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_dias_no_laborables_profesional_propios()
RETURNS TABLE(
    id_dia_no_laborable UUID,
    id_profesional UUID,
    fecha DATE,
    motivo TEXT,
    intervalos_bloqueados INTEGER,
    citas_pendientes INTEGER,
    citas_confirmadas INTEGER,
    citas_activas_por_gestionar INTEGER
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
        dnl.id_dia_no_laborable,
        dnl.id_profesional,
        dnl.fecha,
        dnl.motivo,
        (
            SELECT count(*)::INTEGER
            FROM public."Disponibilidad" d
            WHERE d.id_profesional = dnl.id_profesional
              AND d.fecha = dnl.fecha
              AND d.estado = 'bloqueada'
        ) AS intervalos_bloqueados,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = dnl.id_profesional
              AND d.fecha = dnl.fecha
              AND c.estado = 'pendiente'
        ) AS citas_pendientes,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = dnl.id_profesional
              AND d.fecha = dnl.fecha
              AND c.estado = 'confirmada'
        ) AS citas_confirmadas,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = dnl.id_profesional
              AND d.fecha = dnl.fecha
              AND c.estado IN ('pendiente', 'confirmada')
        ) AS citas_activas_por_gestionar
    FROM public."DiasNoLaborables" dnl
    WHERE dnl.id_profesional = v_id_profesional
    ORDER BY dnl.fecha ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_dia_no_laborable_profesional_propio(
    p_fecha DATE,
    p_motivo TEXT DEFAULT NULL
)
RETURNS TABLE(
    id_dia_no_laborable UUID,
    id_profesional UUID,
    fecha DATE,
    motivo TEXT,
    intervalos_bloqueados INTEGER,
    citas_pendientes INTEGER,
    citas_confirmadas INTEGER,
    citas_activas_por_gestionar INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_hoy_ecuador DATE := (now() AT TIME ZONE 'America/Guayaquil')::DATE;
    v_motivo_limpio TEXT := NULLIF(trim(COALESCE(p_motivo, '')), '');
    v_excepcion public."DiasNoLaborables"%ROWTYPE;
    v_bloqueados INTEGER := 0;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_fecha IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la fecha que deseas marcar como dia no laborable.' USING ERRCODE = '22023';
    END IF;

    IF p_fecha < v_hoy_ecuador THEN
        RAISE EXCEPTION 'No se puede marcar como no laborable una fecha pasada (hora de Ecuador).' USING ERRCODE = '22023';
    END IF;

    IF v_motivo_limpio IS NOT NULL AND char_length(v_motivo_limpio) > 200 THEN
        RAISE EXCEPTION 'El motivo opcional no puede superar los 200 caracteres.' USING ERRCODE = '22023';
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

    IF public._es_dia_no_laborable_profesional(v_id_profesional, p_fecha) THEN
        RAISE EXCEPTION 'La fecha seleccionada ya se encuentra registrada como dia no laborable.' USING ERRCODE = '23505';
    END IF;

    -- 2do bloqueo del orden canonico: filas de disponibilidad del dia
    PERFORM 1
    FROM public."Disponibilidad" d
    WHERE d.id_profesional = v_id_profesional
      AND d.fecha = p_fecha
    FOR UPDATE;

    INSERT INTO public."DiasNoLaborables" (
        id_profesional,
        fecha,
        motivo
    )
    VALUES (
        v_id_profesional,
        p_fecha,
        v_motivo_limpio
    )
    RETURNING * INTO v_excepcion;

    -- Bloquea unicamente los intervalos disponibles que no tengan cita activa.
    -- Conserva intactos los intervalos reservados y el historial de citas.
    UPDATE public."Disponibilidad" d
    SET estado = 'bloqueada'
    WHERE d.id_profesional = v_id_profesional
      AND d.fecha = p_fecha
      AND d.estado = 'disponible'
      AND NOT EXISTS (
          SELECT 1
          FROM public."Citas" c
          WHERE c.id_disponibilidad = d.id_disponibilidad
            AND c.id_profesional = d.id_profesional
            AND c.estado IN ('pendiente', 'confirmada')
      );

    GET DIAGNOSTICS v_bloqueados = ROW_COUNT;

    RETURN QUERY
    SELECT
        v_excepcion.id_dia_no_laborable,
        v_excepcion.id_profesional,
        v_excepcion.fecha,
        v_excepcion.motivo,
        v_bloqueados AS intervalos_bloqueados,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = v_id_profesional
              AND d.fecha = p_fecha
              AND c.estado = 'pendiente'
        ) AS citas_pendientes,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = v_id_profesional
              AND d.fecha = p_fecha
              AND c.estado = 'confirmada'
        ) AS citas_confirmadas,
        (
            SELECT count(*)::INTEGER
            FROM public."Citas" c
            JOIN public."Disponibilidad" d
              ON d.id_disponibilidad = c.id_disponibilidad
             AND d.id_profesional = c.id_profesional
            WHERE c.id_profesional = v_id_profesional
              AND d.fecha = p_fecha
              AND c.estado IN ('pendiente', 'confirmada')
        ) AS citas_activas_por_gestionar;
END;
$$;

CREATE OR REPLACE FUNCTION public.retirar_dia_no_laborable_profesional_propio(
    p_fecha DATE
)
RETURNS TABLE(
    id_dia_no_laborable UUID,
    id_profesional UUID,
    fecha DATE,
    motivo TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_profesional UUID;
    v_eliminada public."DiasNoLaborables"%ROWTYPE;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF p_fecha IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la fecha cuya excepcion deseas retirar.' USING ERRCODE = '22023';
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

    -- Retira unicamente la excepcion del dia, sin desbloquear automaticamente
    -- los intervalos bloqueados para conservar los bloqueos manuales.
    DELETE FROM public."DiasNoLaborables" dnl
    WHERE dnl.id_profesional = v_id_profesional
      AND dnl.fecha = p_fecha
    RETURNING * INTO v_eliminada;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La fecha seleccionada no tiene una excepcion de dia no laborable activa.' USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
    SELECT
        v_eliminada.id_dia_no_laborable,
        v_eliminada.id_profesional,
        v_eliminada.fecha,
        v_eliminada.motivo;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. RPC DE PREVISUALIZACION Y CONFIRMACION DE REPETICION SEMANAL (1..4 SEMANAS)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._calcular_repeticion_semana_profesional(
    p_id_profesional UUID,
    p_lunes_origen DATE,
    p_semanas_posteriores INTEGER
)
RETURNS TABLE(
    semana_offset INTEGER,
    fecha_origen DATE,
    fecha_destino DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    accion TEXT,
    motivo TEXT,
    huella_vista_previa TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_lunes_origen DATE;
    v_fin_origen DATE;
    v_fin_destino DATE;
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_resumen_origen TEXT;
    v_resumen_excepciones TEXT;
    v_resumen_candidatos TEXT;
    v_huella TEXT;
BEGIN
    IF p_lunes_origen IS NULL THEN
        RAISE EXCEPTION 'Debes indicar la semana de origen.' USING ERRCODE = '22023';
    END IF;

    IF p_semanas_posteriores IS NULL OR p_semanas_posteriores < 1 OR p_semanas_posteriores > 4 THEN
        RAISE EXCEPTION 'Debes elegir entre 1 y 4 semanas posteriores.' USING ERRCODE = '22023';
    END IF;

    v_lunes_origen := p_lunes_origen - ((EXTRACT(ISODOW FROM p_lunes_origen)::INTEGER) - 1);
    v_fin_origen := v_lunes_origen + 6;
    v_fin_destino := v_lunes_origen + (p_semanas_posteriores * 7) + 6;

    SELECT COALESCE(
        string_agg(
            d.fecha::TEXT || ':' || to_char(d.hora_inicio, 'HH24:MI') || '-' || to_char(d.hora_fin, 'HH24:MI') || ':' || d.estado || ':' ||
            CASE WHEN (d.fecha + d.hora_inicio) > v_ahora_ecuador THEN 'F' ELSE 'P' END,
            '|' ORDER BY d.fecha ASC, d.hora_inicio ASC
        ),
        'SIN_ORIGEN'
    )
    INTO v_resumen_origen
    FROM public."Disponibilidad" d
    WHERE d.id_profesional = p_id_profesional
      AND d.fecha BETWEEN v_lunes_origen AND v_fin_origen;

    SELECT COALESCE(
        string_agg(
            dnl.fecha::TEXT,
            '|' ORDER BY dnl.fecha ASC
        ),
        'SIN_EXCEPCIONES'
    )
    INTO v_resumen_excepciones
    FROM public."DiasNoLaborables" dnl
    WHERE dnl.id_profesional = p_id_profesional
      AND dnl.fecha BETWEEN v_lunes_origen AND v_fin_destino;

    WITH origen_valido AS (
        SELECT
            d.fecha AS f_origen,
            d.hora_inicio AS h_inicio,
            d.hora_fin AS h_fin
        FROM public."Disponibilidad" d
        WHERE d.id_profesional = p_id_profesional
          AND d.fecha BETWEEN v_lunes_origen AND v_fin_origen
          AND d.estado IN ('disponible', 'reservada')
          AND NOT public._es_dia_no_laborable_profesional(p_id_profesional, d.fecha)
          AND (d.fecha + d.hora_inicio) > v_ahora_ecuador
    ),
    semanas AS (
        SELECT generate_series(1, p_semanas_posteriores) AS sem
    ),
    evaluados AS (
        SELECT
            s.sem::INTEGER AS sem_offset,
            o.f_origen,
            (o.f_origen + (s.sem * 7))::DATE AS f_destino,
            o.h_inicio,
            o.h_fin,
            CASE
                WHEN public._es_dia_no_laborable_profesional(
                    p_id_profesional,
                    (o.f_origen + (s.sem * 7))::DATE
                ) THEN 'omitido_dia_no_laborable'
                WHEN EXISTS (
                    SELECT 1
                    FROM public."Disponibilidad" dest
                    WHERE dest.id_profesional = p_id_profesional
                      AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                      AND dest.hora_inicio = o.h_inicio
                      AND dest.hora_fin = o.h_fin
                ) THEN 'omitido_identico'
                WHEN EXISTS (
                    SELECT 1
                    FROM public."Disponibilidad" dest
                    WHERE dest.id_profesional = p_id_profesional
                      AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                      AND dest.hora_inicio < o.h_fin
                      AND dest.hora_fin > o.h_inicio
                ) THEN 'omitido_solapamiento'
                ELSE 'crear'
            END AS accion_item
        FROM semanas s
        CROSS JOIN origen_valido o
    )
    SELECT COALESCE(
        string_agg(
            ev.sem_offset::TEXT || ':' || ev.f_destino::TEXT || ':' ||
            to_char(ev.h_inicio, 'HH24:MI') || '-' || to_char(ev.h_fin, 'HH24:MI') || ':' || ev.accion_item,
            '|' ORDER BY ev.sem_offset ASC, ev.f_destino ASC, ev.h_inicio ASC
        ),
        'SIN_CANDIDATOS'
    )
    INTO v_resumen_candidatos
    FROM evaluados ev;

    v_huella := md5(
        v_lunes_origen::TEXT || '||' ||
        p_semanas_posteriores::TEXT || '||' ||
        v_resumen_origen || '||' ||
        v_resumen_excepciones || '||' ||
        v_resumen_candidatos
    );

    RETURN QUERY
    WITH origen_valido AS (
        SELECT
            d.fecha AS f_origen,
            d.hora_inicio AS h_inicio,
            d.hora_fin AS h_fin
        FROM public."Disponibilidad" d
        WHERE d.id_profesional = p_id_profesional
          AND d.fecha BETWEEN v_lunes_origen AND v_fin_origen
          AND d.estado IN ('disponible', 'reservada')
          AND NOT public._es_dia_no_laborable_profesional(p_id_profesional, d.fecha)
          AND (d.fecha + d.hora_inicio) > v_ahora_ecuador
    ),
    semanas AS (
        SELECT generate_series(1, p_semanas_posteriores) AS sem
    )
    SELECT
        s.sem::INTEGER AS semana_offset,
        o.f_origen AS fecha_origen,
        (o.f_origen + (s.sem * 7))::DATE AS fecha_destino,
        o.h_inicio AS hora_inicio,
        o.h_fin AS hora_fin,
        CASE
            WHEN public._es_dia_no_laborable_profesional(
                p_id_profesional,
                (o.f_origen + (s.sem * 7))::DATE
            ) THEN 'omitido_dia_no_laborable'
            WHEN EXISTS (
                SELECT 1
                FROM public."Disponibilidad" dest
                WHERE dest.id_profesional = p_id_profesional
                  AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                  AND dest.hora_inicio = o.h_inicio
                  AND dest.hora_fin = o.h_fin
            ) THEN 'omitido_identico'
            WHEN EXISTS (
                SELECT 1
                FROM public."Disponibilidad" dest
                WHERE dest.id_profesional = p_id_profesional
                  AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                  AND dest.hora_inicio < o.h_fin
                  AND dest.hora_fin > o.h_inicio
            ) THEN 'omitido_solapamiento'
            ELSE 'crear'
        END AS accion,
        CASE
            WHEN public._es_dia_no_laborable_profesional(
                p_id_profesional,
                (o.f_origen + (s.sem * 7))::DATE
            ) THEN 'Omitido: día no laborable registrado en la fecha de destino'
            WHEN EXISTS (
                SELECT 1
                FROM public."Disponibilidad" dest
                WHERE dest.id_profesional = p_id_profesional
                  AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                  AND dest.hora_inicio = o.h_inicio
                  AND dest.hora_fin = o.h_fin
            ) THEN 'Omitido: ya existe un intervalo idéntico en esa fecha'
            WHEN EXISTS (
                SELECT 1
                FROM public."Disponibilidad" dest
                WHERE dest.id_profesional = p_id_profesional
                  AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                  AND dest.hora_inicio < o.h_fin
                  AND dest.hora_fin > o.h_inicio
            ) THEN (
                SELECT 'Omitido: se superpone con ' ||
                       to_char(dest.hora_inicio, 'HH24:MI') || '–' || to_char(dest.hora_fin, 'HH24:MI')
                FROM public."Disponibilidad" dest
                WHERE dest.id_profesional = p_id_profesional
                  AND dest.fecha = (o.f_origen + (s.sem * 7))::DATE
                  AND dest.hora_inicio < o.h_fin
                  AND dest.hora_fin > o.h_inicio
                ORDER BY dest.hora_inicio ASC
                LIMIT 1
            )
            ELSE 'Se creará como disponible'
        END AS motivo,
        v_huella AS huella_vista_previa
    FROM semanas s
    CROSS JOIN origen_valido o
    ORDER BY fecha_destino ASC, hora_inicio ASC;
END;
$$;

REVOKE ALL ON FUNCTION
    public._calcular_repeticion_semana_profesional(UUID, DATE, INTEGER)
    FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.previsualizar_repeticion_semana_profesional_propia(
    p_lunes_origen DATE,
    p_semanas_posteriores INTEGER
)
RETURNS TABLE(
    semana_offset INTEGER,
    fecha_origen DATE,
    fecha_destino DATE,
    hora_inicio TIME WITHOUT TIME ZONE,
    hora_fin TIME WITHOUT TIME ZONE,
    accion TEXT,
    motivo TEXT,
    huella_vista_previa TEXT
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
    SELECT *
    FROM public._calcular_repeticion_semana_profesional(
        v_id_profesional,
        p_lunes_origen,
        p_semanas_posteriores
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.confirmar_repeticion_semana_profesional_propia(
    p_lunes_origen DATE,
    p_semanas_posteriores INTEGER,
    p_huella_vista_previa TEXT
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
    v_huella_limpia TEXT := trim(COALESCE(p_huella_vista_previa, ''));
    v_huella_actual TEXT;
    v_total_crear INTEGER := 0;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'profesional' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de profesional activa.' USING ERRCODE = '42501';
    END IF;

    IF v_huella_limpia = '' THEN
        RAISE EXCEPTION 'Debes generar primero la vista previa antes de confirmar la repeticion semanal.' USING ERRCODE = '22023';
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

    SELECT
        max(calc.huella_vista_previa),
        count(*) FILTER (WHERE calc.accion = 'crear')::INTEGER
    INTO v_huella_actual, v_total_crear
    FROM public._calcular_repeticion_semana_profesional(
        v_id_profesional,
        p_lunes_origen,
        p_semanas_posteriores
    ) calc;

    IF v_huella_actual IS NULL THEN
        RAISE EXCEPTION 'La semana de origen no tiene horarios futuros disponibles o reservados para repetir.' USING ERRCODE = '22023';
    END IF;

    IF v_huella_actual IS DISTINCT FROM v_huella_limpia THEN
        RAISE EXCEPTION 'La agenda cambio desde que se genero la vista previa (se modifico la semana de origen, una excepcion de dia no laborable o aparecio un conflicto nuevo). Actualiza la vista previa antes de confirmar.'
            USING ERRCODE = '23P01';
    END IF;

    IF v_total_crear <= 0 THEN
        RAISE EXCEPTION 'No hay intervalos validos pendientes por crear en las semanas seleccionadas.' USING ERRCODE = '22023';
    END IF;

    IF v_total_crear > 168 THEN
        RAISE EXCEPTION 'La operacion supera el limite maximo permitido de 168 intervalos por confirmacion.' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH insertados AS (
        INSERT INTO public."Disponibilidad" (
            id_profesional,
            fecha,
            hora_inicio,
            hora_fin,
            estado
        )
        SELECT
            v_id_profesional,
            calc.fecha_destino,
            calc.hora_inicio,
            calc.hora_fin,
            'disponible'
        FROM public._calcular_repeticion_semana_profesional(
            v_id_profesional,
            p_lunes_origen,
            p_semanas_posteriores
        ) calc
        WHERE calc.accion = 'crear'
        ORDER BY calc.fecha_destino ASC, calc.hora_inicio ASC
        RETURNING *
    )
    SELECT
        ins.id_disponibilidad,
        ins.id_profesional,
        ins.fecha,
        ins.hora_inicio,
        ins.hora_fin,
        ins.estado,
        FALSE AS tiene_cita_vinculada
    FROM insertados ins
    ORDER BY ins.fecha ASC, ins.hora_inicio ASC;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. PERMISOS EXPLICITOS DE FUNCIONES RPC
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
    public.listar_horarios_disponibles_profesional(UUID),
    public.responder_solicitud_cita_profesional(UUID, TEXT),
    public.crear_intervalos_jornada_profesional_propia(DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE, INTEGER, INTEGER),
    public.listar_dias_no_laborables_profesional_propios(),
    public.registrar_dia_no_laborable_profesional_propio(DATE, TEXT),
    public.retirar_dia_no_laborable_profesional_propio(DATE),
    public.previsualizar_repeticion_semana_profesional_propia(DATE, INTEGER),
    public.confirmar_repeticion_semana_profesional_propia(DATE, INTEGER, TEXT)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.listar_horarios_disponibles_profesional(UUID),
    public.responder_solicitud_cita_profesional(UUID, TEXT),
    public.crear_intervalos_jornada_profesional_propia(DATE, TIME WITHOUT TIME ZONE, TIME WITHOUT TIME ZONE, INTEGER, INTEGER),
    public.listar_dias_no_laborables_profesional_propios(),
    public.registrar_dia_no_laborable_profesional_propio(DATE, TEXT),
    public.retirar_dia_no_laborable_profesional_propio(DATE),
    public.previsualizar_repeticion_semana_profesional_propia(DATE, INTEGER),
    public.confirmar_repeticion_semana_profesional_propia(DATE, INTEGER, TEXT)
    TO authenticated;

COMMIT;
