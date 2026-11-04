-- =============================================================================
-- SCRIPT 1 DE 4 — ESTRUCTURA, TIPOS, TABLAS Y TRIGGERS
-- Proyecto: PsicoBloom (esquema: public)
-- Ejecutar en: Supabase > SQL Editor
-- Precondición: Supabase Auth habilitado (auth.users ya existe).
-- Ejecutar una vez, cuando se confirme que estas tablas no existen.
-- =============================================================================
-- Version revisada: estructura inicial; no es migracion sobre tablas existentes.
-- No altera las funciones rls_auto_enable ni validar_correo.
BEGIN;

-- ---------------------------------------------------------------------------
-- 0. TIPOS ENUMERADOS
-- ---------------------------------------------------------------------------

-- Roles disponibles en la plataforma.
-- 'administrador' no se puede asignar desde el formulario público.
CREATE TYPE public.rol_usuario AS ENUM (
    'paciente',
    'profesional',
    'administrador'
);

-- Estados de aprobación para cuentas de tipo 'profesional'.
-- Paciente y administrador siempre tienen 'no_aplica'.
CREATE TYPE public.estado_aprobacion AS ENUM (
    'pendiente',   -- registro recibido, en espera de revisión
    'aprobado',    -- administrador activo aprobó el perfil
    'rechazado',   -- administrador activo rechazó el perfil
    'no_aplica'    -- para pacientes y administradores
);

-- ---------------------------------------------------------------------------
-- 1. TABLA perfiles
-- ---------------------------------------------------------------------------
CREATE TABLE public.perfiles (
    -- UUID idéntico al de auth.users. No se genera un ID propio.
    id              UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    nombre          TEXT        NOT NULL CHECK (char_length(trim(nombre))  >= 2),
    apellido        TEXT        NOT NULL CHECK (char_length(trim(apellido)) >= 2),

    -- Copia de lectura rápida del correo. Fuente de verdad: auth.users.email.
    -- No editable directamente; se sincroniza por trigger.
    correo          TEXT        NOT NULL,

    -- Campos protegidos. Solo modificables mediante funciones SECURITY DEFINER
    -- o desde el panel de Supabase. Los permisos de columna del Script 2
    -- impiden que authenticated los toque directamente.
    rol             public.rol_usuario       NOT NULL DEFAULT 'paciente',
    aprobacion      public.estado_aprobacion NOT NULL DEFAULT 'no_aplica',

    -- Permite desactivar una cuenta sin borrarla.
    -- Los usuarios desactivados solo pueden leer su propio perfil.
    cuenta_activa   BOOLEAN                  NOT NULL DEFAULT TRUE,

    creado_en       TIMESTAMPTZ              NOT NULL DEFAULT NOW(),
    actualizado_en  TIMESTAMPTZ              NOT NULL DEFAULT NOW(),

    -- Restricción de coherencia entre rol y aprobacion.
    -- Impide estados imposibles (p.ej. paciente con aprobacion='pendiente').
    CONSTRAINT chk_rol_aprobacion CHECK (
        (rol = 'profesional'  AND aprobacion IN ('pendiente', 'aprobado', 'rechazado'))
        OR
        (rol IN ('paciente', 'administrador') AND aprobacion = 'no_aplica')
    )
);

-- RLS se habilita inmediatamente; las políticas se añaden en el Script 2.
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_perfiles_rol        ON public.perfiles (rol);
CREATE INDEX idx_perfiles_aprobacion ON public.perfiles (aprobacion);

-- ---------------------------------------------------------------------------
-- 2. TABLA perfiles_profesionales
--    Datos que el profesional completa progresivamente.
--    No contiene datos de revisión interna (ver tabla siguiente).
-- ---------------------------------------------------------------------------
CREATE TABLE public.perfiles_profesionales (
    id                  UUID    PRIMARY KEY REFERENCES public.perfiles(id) ON DELETE CASCADE,

    especialidad        TEXT,
    numero_registro     TEXT,
    descripcion         TEXT,
    anios_experiencia   INTEGER CHECK (anios_experiencia >= 0),
    telefono_contacto   TEXT,
    foto_url            TEXT,       -- URL en Supabase Storage

    actualizado_en      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.perfiles_profesionales ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. TABLA revisiones_profesionales
--    Datos internos de revisión administrativa. SOLO el administrador puede
--    leerlos y escribirlos. El profesional solo accede a motivo_rechazo
--    a través de la función consultar_motivo_rechazo_propio() del Script 3.
--    nota_interna nunca se expone al profesional.
--    bloqueo_motivo y bloqueo_por registran el responsable de activar
--    o desactivar la cuenta, conforme a los requisitos de auditoría.
-- ---------------------------------------------------------------------------
CREATE TABLE public.revisiones_profesionales (
    id              UUID    PRIMARY KEY REFERENCES public.perfiles(id) ON DELETE CASCADE,

    revisado_en     TIMESTAMPTZ,
    revisado_por    UUID REFERENCES public.perfiles(id),  -- UUID del admin revisor

    -- Motivo que SÍ se muestra al profesional cuando es rechazado.
    -- Obligatorio cuando la decision es 'rechazado' (validado en la función).
    motivo_rechazo  TEXT,

    -- Nota interna libre del administrador; nunca se muestra al profesional.
    nota_interna    TEXT,

    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.revisiones_profesionales ENABLE ROW LEVEL SECURITY;

-- Historial de bloqueos y reactivaciones de pacientes y profesionales.
CREATE TABLE public.cambios_estado_cuenta (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID NOT NULL REFERENCES public.perfiles(id) ON DELETE CASCADE,
    responsable_id UUID REFERENCES public.perfiles(id) ON DELETE SET NULL,
    estado_anterior BOOLEAN NOT NULL,
    estado_nuevo BOOLEAN NOT NULL,
    motivo TEXT NOT NULL CHECK (char_length(trim(motivo)) >= 5),
    creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cambios_estado_cuenta ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_cambios_estado_usuario ON public.cambios_estado_cuenta(usuario_id, creado_en);

-- Cierre explicito desde la primera transaccion, antes de conceder acceso.
REVOKE ALL ON public.perfiles, public.perfiles_profesionales,
    public.revisiones_profesionales, public.cambios_estado_cuenta
    FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. FUNCIÓN INTERNA: _rol_activo()
--    Devuelve el rol del usuario autenticado SOLO si su cuenta está activa.
--    Devuelve NULL si no hay sesión, el usuario no tiene perfil o está inactivo.
--    Se usa en políticas RLS y en las comprobaciones de las funciones RPC.
--    Sin parámetro UUID: no permite consultar el rol de otro usuario.
--    SECURITY DEFINER: lee perfiles sin quedar atrapada en RLS.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._rol_activo()
RETURNS public.rol_usuario
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT rol
    FROM public.perfiles
    WHERE id = auth.uid()
      AND cuenta_activa = TRUE;
$$;

-- Revocar de PUBLIC; solo las políticas lo necesitan internamente.
-- authenticated recibe EXECUTE porque las políticas se ejecutan
-- en el contexto del usuario que consulta.
REVOKE ALL ON FUNCTION public._rol_activo() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._rol_activo() FROM anon;
REVOKE ALL ON FUNCTION public._rol_activo() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._rol_activo() TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. TRIGGER: crear_perfil_al_registrarse
--    Se activa en auth.users después de cada INSERT (nuevo usuario).
--    Crea la fila en perfiles y, si el rol es profesional,
--    también en perfiles_profesionales y revisiones_profesionales.
--    Cualquier valor distinto de 'profesional' en raw_user_meta_data.rol
--    se normaliza a 'paciente'. 'administrador' nunca se acepta aquí.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_perfil_al_registrarse()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_nombre     TEXT;
    v_apellido   TEXT;
    v_rol_raw    TEXT;
    v_rol        public.rol_usuario;
    v_aprobacion public.estado_aprobacion;
BEGIN
    v_nombre   := trim(COALESCE(NEW.raw_user_meta_data->>'nombre',   ''));
    v_apellido := trim(COALESCE(NEW.raw_user_meta_data->>'apellido', ''));
    v_rol_raw  := lower(trim(COALESCE(NEW.raw_user_meta_data->>'rol', 'paciente')));

    -- Valores de respaldo si el formulario envió cadenas muy cortas.
    IF char_length(v_nombre) < 2 THEN
        v_nombre := 'Usuario';
    END IF;
    IF char_length(v_apellido) < 2 THEN
        v_apellido := 'Nuevo';
    END IF;

    -- Solo se acepta 'profesional' o 'paciente'. Cualquier otro valor,
    -- incluido 'administrador', se convierte en 'paciente'.
    IF v_rol_raw = 'profesional' THEN
        v_rol        := 'profesional';
        v_aprobacion := 'pendiente';
    ELSE
        v_rol        := 'paciente';
        v_aprobacion := 'no_aplica';
    END IF;

    INSERT INTO public.perfiles (id, nombre, apellido, correo, rol, aprobacion)
    VALUES (
        NEW.id,
        v_nombre,
        v_apellido,
        COALESCE(NEW.email, ''),
        v_rol,
        v_aprobacion
    );

    IF v_rol = 'profesional' THEN
        INSERT INTO public.perfiles_profesionales (id) VALUES (NEW.id);
        INSERT INTO public.revisiones_profesionales (id) VALUES (NEW.id);
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.crear_perfil_al_registrarse() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crear_perfil_al_registrarse() FROM anon;
REVOKE ALL ON FUNCTION public.crear_perfil_al_registrarse() FROM authenticated;

CREATE TRIGGER trigger_crear_perfil
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.crear_perfil_al_registrarse();

-- ---------------------------------------------------------------------------
-- 6. TRIGGER: sincronizar_correo
--    Actualiza perfiles.correo cuando cambia auth.users.email.
--    Resuelve el problema de duplicación sin exponer correo como campo editable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sincronizar_correo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        UPDATE public.perfiles
        SET
            correo         = COALESCE(NEW.email, ''),
            actualizado_en = NOW()
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sincronizar_correo() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sincronizar_correo() FROM anon;
REVOKE ALL ON FUNCTION public.sincronizar_correo() FROM authenticated;

CREATE TRIGGER trigger_sincronizar_correo
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.sincronizar_correo();

-- ---------------------------------------------------------------------------
-- 7. TRIGGER: actualizar_timestamp
--    Mantiene actualizado_en sin duplicar lógica en cada tabla.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    NEW.actualizado_en := NOW();
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.actualizar_timestamp() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_timestamp() FROM anon;
REVOKE ALL ON FUNCTION public.actualizar_timestamp() FROM authenticated;

CREATE TRIGGER trigger_ts_perfiles
    BEFORE UPDATE ON public.perfiles
    FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();

CREATE TRIGGER trigger_ts_perfiles_profesionales
    BEFORE UPDATE ON public.perfiles_profesionales
    FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();

CREATE TRIGGER trigger_ts_revisiones
    BEFORE UPDATE ON public.revisiones_profesionales
    FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();

-- ---------------------------------------------------------------------------
-- 8. NOTA SOBRE LA CUENTA DE PRUEBA EXISTENTE
--    La cuenta creada por invitación NO se toca en este script.
--    No tendrá fila en perfiles hasta que se ejecute el bloque manual
--    del Script 3 (sección 8) con su UUID real.
-- ---------------------------------------------------------------------------

COMMIT;
