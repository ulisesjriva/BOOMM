-- =============================================================================
-- SCRIPT 8 — MIGRACION ADITIVA DE SOLICITUD Y CONSULTA DE CITAS DEL PACIENTE (I3-02)
-- Proyecto: PsicoBloom (esquemas: public y psicobloom_interno)
-- Referencias verificadas:
--   - esquema_real_psicobloom.json
--   - 05_perfiles_especialidades_ubicacion.sql
--   - 06_disponibilidad_profesional.sql
-- Ejecutar en: Supabase > SQL Editor como postgres (despues de 06)
--
-- Proposito:
--   1. Conservar intactas las tablas y columnas existentes:
--      - public."Citas" (id_cita, id_paciente, id_profesional, id_disponibilidad,
--        fecha_solicitud, estado)
--      - public."Disponibilidad" (id_disponibilidad, id_profesional, fecha,
--        hora_inicio, hora_fin, estado)
--      - public."Pacientes" (id_paciente, id_usuario)
--      - public."Profesionales" (id_profesional, id_usuario, ...)
--   2. Configurar privilegios minimos y politicas RLS sin recursion en
--      public."Pacientes" y public."Citas" (sin otorgar escritura directa).
--   3. Incorporar indice unico parcial en public."Citas"(id_disponibilidad)
--      para estados activos ('pendiente', 'confirmada') y triggers de integridad
--      compatibles con 06_disponibilidad_profesional.sql.
--   4. Crear las funciones RPC SECURITY DEFINER que resuelven id_paciente e
--      id_profesional mediante id_usuario y reutilizan el orden de bloqueos de
--      I3-01 (Profesionales FOR UPDATE -> Disponibilidad FOR UPDATE):
--      - public.listar_horarios_disponibles_profesional(UUID)
--      - public.solicitar_cita_paciente(UUID, UUID)
--      - public.listar_citas_paciente_propias()
-- =============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. FUNCION AUXILIAR DE AUTORIZACION PARA PACIENTES (SIN RECURSION)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._es_paciente_propio(p_id_paciente UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Pacientes" pa
        WHERE pa.id_paciente = p_id_paciente
          AND pa.id_usuario = auth.uid()
    );
$$;

CREATE OR REPLACE FUNCTION public._paciente_esta_activo(p_id_paciente UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public."Pacientes" pa
        JOIN psicobloom_interno.perfiles_compat p ON p.id = pa.id_usuario
        WHERE pa.id_paciente = p_id_paciente
          AND p.rol = 'paciente'
          AND p.cuenta_activa = TRUE
    );
$$;

REVOKE ALL ON FUNCTION
    public._es_paciente_propio(UUID),
    public._paciente_esta_activo(UUID)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public._es_paciente_propio(UUID),
    public._paciente_esta_activo(UUID)
    TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. PRIVILEGIOS MINIMOS, INDICES Y POLITICAS RLS EN public."Pacientes" Y public."Citas"
-- ---------------------------------------------------------------------------
ALTER TABLE public."Pacientes" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."Citas" ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public."Pacientes", public."Citas" FROM PUBLIC, anon, authenticated;
-- Lectura protegida por RLS; todas las escrituras se ejecutan mediante RPC autorizadas.
GRANT SELECT ON public."Pacientes", public."Citas" TO authenticated;

-- Indice unico parcial: impide a nivel fisico dos citas activas ('pendiente' o
-- 'confirmada') para el mismo horario, incluso ante transacciones simultaneas.
CREATE UNIQUE INDEX IF NOT EXISTS idx_citas_disponibilidad_activa_unica
    ON public."Citas" (id_disponibilidad)
    WHERE estado IN ('pendiente', 'confirmada');

CREATE INDEX IF NOT EXISTS idx_citas_paciente_fecha_solicitud
    ON public."Citas" (id_paciente, fecha_solicitud DESC);

DROP POLICY IF EXISTS pacientes_leer_autorizados ON public."Pacientes";
CREATE POLICY pacientes_leer_autorizados ON public."Pacientes"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'paciente'
        AND id_usuario = (SELECT auth.uid())
    )
    OR (SELECT public._rol_activo()) = 'administrador'
);

DROP POLICY IF EXISTS citas_leer_autorizados ON public."Citas";
CREATE POLICY citas_leer_autorizados ON public."Citas"
FOR SELECT TO authenticated
USING (
    (
        (SELECT public._rol_activo()) = 'paciente'
        AND public._es_paciente_propio(id_paciente)
    )
    OR (
        (SELECT public._rol_activo()) = 'profesional'
        AND public._es_profesional_propio(id_profesional)
    )
    OR (SELECT public._rol_activo()) = 'administrador'
);

-- ---------------------------------------------------------------------------
-- 3. COMPATIBILIDAD Y REFUERZO DE TRIGGERS EN public."Disponibilidad" Y public."Citas"
-- ---------------------------------------------------------------------------
-- Actualiza validar_disponibilidad_profesional() de 06 para asegurar que el
-- paso a 'reservada' requiera siempre una cita activa vinculada y nunca pueda
-- ser invocado manualmente por el profesional.
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

    -- 1er bloqueo del orden canonico (Profesionales -> Disponibilidad)
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
            IF NEW.estado = 'reservada' THEN
                IF public._rol_activo() = 'profesional' THEN
                    RAISE EXCEPTION 'No puedes cambiar manualmente un horario al estado reservada.' USING ERRCODE = '22023';
                END IF;
                IF NOT v_tiene_cita_activa THEN
                    RAISE EXCEPTION 'El estado reservada requiere una cita activa vinculada al horario.' USING ERRCODE = '22023';
                END IF;
            END IF;

            IF (OLD.estado = 'reservada' OR v_tiene_cita_activa)
               AND NEW.estado IN ('disponible', 'bloqueada')
               AND public._rol_activo() = 'profesional' THEN
                RAISE EXCEPTION 'No se puede bloquear ni liberar manualmente un horario reservado o con cita activa.' USING ERRCODE = '22023';
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

-- Trigger de integridad en public."Citas" para validar paciente activo,
-- profesional aprobado y activo, y horario disponible y futuro al insertar.
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
        RAISE EXCEPTION 'No se permiten reservas con profesionales pendientes de aprobacion o inactivos.' USING ERRCODE = '42501';
    END IF;

    IF NOT public._paciente_esta_activo(NEW.id_paciente) THEN
        RAISE EXCEPTION 'La cuenta del paciente debe estar activa para registrar una cita.' USING ERRCODE = '42501';
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- Si quien ejecuta la insercion es un paciente autenticado, solo puede
        -- crear citas para su propio id_paciente y en estado 'pendiente'.
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
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validar_profesional_aprobado_en_citas_trg ON public."Citas";
CREATE TRIGGER validar_profesional_aprobado_en_citas_trg
BEFORE INSERT OR UPDATE OF id_paciente, id_profesional, id_disponibilidad, estado ON public."Citas"
FOR EACH ROW
EXECUTE FUNCTION public.validar_profesional_aprobado_en_citas();

REVOKE ALL ON FUNCTION
    public.validar_disponibilidad_profesional(),
    public.validar_profesional_aprobado_en_citas()
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. FUNCIONES RPC PARA EL PACIENTE: HORARIOS DISPONIBLES, SOLICITUD Y MIS CITAS
-- ---------------------------------------------------------------------------

-- 4.1 Consultar los intervalos futuros disponibles de un profesional aprobado
-- usando America/Guayaquil y ordenados por fecha y hora de inicio.
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

    -- Resuelve id_profesional tanto si se recibe Profesionales.id_profesional
    -- como si se recibe Profesionales.id_usuario (cuando ambos difieren).
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

-- 4.2 Enviar solicitud de cita (crea cita 'pendiente' y marca horario 'reservada'
-- en una unica transaccion atomica, reutilizando el orden de bloqueos de I3-01).
CREATE OR REPLACE FUNCTION public.solicitar_cita_paciente(
    p_id_profesional UUID,
    p_id_disponibilidad UUID
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
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_horario public."Disponibilidad"%ROWTYPE;
    v_cita public."Citas"%ROWTYPE;
    v_filas_actualizadas INTEGER := 0;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa para solicitar una cita.' USING ERRCODE = '42501';
    END IF;

    IF p_id_profesional IS NULL OR p_id_disponibilidad IS NULL THEN
        RAISE EXCEPTION 'Debes seleccionar un profesional y un horario disponible.' USING ERRCODE = '22023';
    END IF;

    -- Resuelve id_paciente mediante public."Pacientes".id_usuario = auth.uid()
    SELECT pa.id_paciente
    INTO v_id_paciente
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = auth.uid();

    IF v_id_paciente IS NULL OR NOT public._paciente_esta_activo(v_id_paciente) THEN
        RAISE EXCEPTION 'No se encontro un perfil de paciente activo asociado a tu sesion.' USING ERRCODE = '42501';
    END IF;

    -- Resuelve id_profesional (admite id_profesional o id_usuario del profesional)
    SELECT pr.id_profesional, pr.id_usuario
    INTO v_id_profesional, v_id_usuario_profesional
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = p_id_profesional
       OR pr.id_usuario = p_id_profesional;

    IF v_id_profesional IS NULL THEN
        RAISE EXCEPTION 'El profesional indicado no existe.' USING ERRCODE = '22023';
    END IF;

    IF v_id_paciente = v_id_profesional OR v_id_usuario_profesional = auth.uid() THEN
        RAISE EXCEPTION 'No puedes solicitar una cita contigo mismo.' USING ERRCODE = '22023';
    END IF;

    -- 1er bloqueo del orden canonico de I3-01: fila del profesional en public."Profesionales"
    PERFORM 1
    FROM public."Profesionales" pr
    WHERE pr.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT public._profesional_es_publicable(v_id_profesional) THEN
        RAISE EXCEPTION 'El profesional seleccionado no se encuentra aprobado o activo para recibir solicitudes.' USING ERRCODE = '42501';
    END IF;

    -- 2do bloqueo del orden canonico de I3-01: fila del horario en public."Disponibilidad"
    SELECT *
    INTO v_horario
    FROM public."Disponibilidad" d
    WHERE d.id_disponibilidad = p_id_disponibilidad
      AND d.id_profesional = v_id_profesional
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El horario seleccionado no existe o no pertenece al profesional indicado.' USING ERRCODE = '22023';
    END IF;

    IF (v_horario.fecha + v_horario.hora_inicio) <= v_ahora_ecuador THEN
        RAISE EXCEPTION 'El horario seleccionado ya inicio o pertenece a una fecha u hora pasada (hora de Ecuador).' USING ERRCODE = '22023';
    END IF;

    -- Prevencion de doble toque / solicitud duplicada del mismo paciente
    IF EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_horario.id_disponibilidad
          AND c.id_paciente = v_id_paciente
          AND c.estado IN ('pendiente', 'confirmada')
    ) THEN
        RAISE EXCEPTION 'Ya registraste una solicitud activa para este horario. Puedes consultarla en Mis citas.' USING ERRCODE = '23505';
    END IF;

    -- Verificacion de disponibilidad frente a otro paciente o bloqueo del profesional
    IF v_horario.estado <> 'disponible' OR EXISTS (
        SELECT 1
        FROM public."Citas" c
        WHERE c.id_disponibilidad = v_horario.id_disponibilidad
          AND c.estado IN ('pendiente', 'confirmada')
    ) THEN
        RAISE EXCEPTION 'Este horario acaba de ser ocupado por otro paciente o ya no esta disponible. Elige otro intervalo.' USING ERRCODE = '23P01';
    END IF;

    -- 1. Inserta la cita siempre con estado 'pendiente'
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

    -- 2. Cambia el horario a 'reservada' en la misma transaccion
    UPDATE public."Disponibilidad" d
    SET estado = 'reservada'
    WHERE d.id_disponibilidad = v_horario.id_disponibilidad
      AND d.id_profesional = v_id_profesional
      AND d.estado = 'disponible';

    GET DIAGNOSTICS v_filas_actualizadas = ROW_COUNT;
    IF v_filas_actualizadas <> 1 THEN
        RAISE EXCEPTION 'No fue posible reservar el horario seleccionado; la operacion se revirtio.' USING ERRCODE = '23P01';
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

-- 4.3 Listar unicamente las solicitudes y citas propias del paciente autenticado
CREATE OR REPLACE FUNCTION public.listar_citas_paciente_propias()
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
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_id_paciente UUID;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'paciente' THEN
        RAISE EXCEPTION 'Se requiere una cuenta de paciente activa para consultar tus citas.' USING ERRCODE = '42501';
    END IF;

    SELECT pa.id_paciente
    INTO v_id_paciente
    FROM public."Pacientes" pa
    WHERE pa.id_usuario = auth.uid();

    IF v_id_paciente IS NULL THEN
        RAISE EXCEPTION 'No se encontro el registro de paciente asociado a tu cuenta.' USING ERRCODE = '42501';
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
    JOIN public."Disponibilidad" d
      ON d.id_disponibilidad = c.id_disponibilidad
     AND d.id_profesional = c.id_profesional
    JOIN public."Profesionales" pr ON pr.id_profesional = c.id_profesional
    JOIN psicobloom_interno.perfiles_compat p ON p.id = pr.id_usuario
    LEFT JOIN psicobloom_interno.detalle_profesional dp ON dp.id = pr.id_profesional
    WHERE c.id_paciente = v_id_paciente
    ORDER BY d.fecha ASC, d.hora_inicio ASC, c.fecha_solicitud DESC;
END;
$$;

REVOKE ALL ON FUNCTION
    public.listar_horarios_disponibles_profesional(UUID),
    public.solicitar_cita_paciente(UUID, UUID),
    public.listar_citas_paciente_propias()
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.listar_horarios_disponibles_profesional(UUID),
    public.solicitar_cita_paciente(UUID, UUID),
    public.listar_citas_paciente_propias()
    TO authenticated;

COMMIT;
