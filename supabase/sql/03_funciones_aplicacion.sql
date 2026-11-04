-- PSICOBLOOM: ejecutar despues de 02. Nunca ejecutar el antiguo 03_funciones_verificacion.
BEGIN;

CREATE FUNCTION public.perfil_del_usuario_actual()
RETURNS TABLE(id UUID, nombre TEXT, apellido TEXT, correo TEXT,
    rol public.rol_usuario, aprobacion public.estado_aprobacion,
    cuenta_activa BOOLEAN, creado_en TIMESTAMPTZ, actualizado_en TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
    SELECT p.id,p.nombre,p.apellido,p.correo,p.rol,p.aprobacion,
           p.cuenta_activa,p.creado_en,p.actualizado_en
    FROM public.perfiles p WHERE p.id = auth.uid();
$$;

CREATE FUNCTION public.verificar_acceso_usuario()
RETURNS TABLE(tiene_perfil BOOLEAN, rol public.rol_usuario,
    aprobacion public.estado_aprobacion, cuenta_activa BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
    SELECT TRUE,p.rol,p.aprobacion,p.cuenta_activa
    FROM public.perfiles p WHERE p.id = auth.uid()
    UNION ALL
    SELECT FALSE,NULL,NULL,NULL
    WHERE NOT EXISTS(SELECT 1 FROM public.perfiles p WHERE p.id = auth.uid());
$$;

CREATE FUNCTION public.actualizar_nombre_apellido(p_nombre TEXT,p_apellido TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE filas INTEGER;
BEGIN
    IF public._rol_activo() IS NULL THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa.' USING ERRCODE='42501';
    END IF;
    IF char_length(trim(coalesce(p_nombre,''))) < 2 OR
       char_length(trim(coalesce(p_apellido,''))) < 2 THEN
        RAISE EXCEPTION 'Nombre y apellido requieren al menos 2 caracteres.' USING ERRCODE='22023';
    END IF;
    UPDATE public.perfiles SET nombre=trim(p_nombre),apellido=trim(p_apellido)
    WHERE id=auth.uid() AND cuenta_activa;
    GET DIAGNOSTICS filas=ROW_COUNT;
    IF filas <> 1 THEN
        RAISE EXCEPTION 'No se actualizo el perfil esperado.';
    END IF;
END;
$$;

CREATE FUNCTION public.directorio_profesionales()
RETURNS TABLE(id UUID,nombre TEXT,apellido TEXT,especialidad TEXT,
    descripcion TEXT,anios_experiencia INTEGER,foto_url TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    IF public._rol_activo() IS NULL THEN
        RAISE EXCEPTION 'Se requiere una cuenta activa.' USING ERRCODE='42501';
    END IF;
    RETURN QUERY SELECT p.id,p.nombre,p.apellido,pp.especialidad,
        pp.descripcion,pp.anios_experiencia,pp.foto_url
    FROM public.perfiles p JOIN public.perfiles_profesionales pp ON pp.id=p.id
    WHERE p.rol='profesional' AND p.aprobacion='aprobado' AND p.cuenta_activa;
END;
$$;

CREATE FUNCTION public.listar_profesionales_pendientes()
RETURNS TABLE(id UUID,nombre TEXT,apellido TEXT,correo TEXT,especialidad TEXT,
    numero_registro TEXT,creado_en TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE='42501';
    END IF;
    RETURN QUERY SELECT p.id,p.nombre,p.apellido,p.correo,
        pp.especialidad,pp.numero_registro,p.creado_en
    FROM public.perfiles p JOIN public.perfiles_profesionales pp ON pp.id=p.id
    WHERE p.rol='profesional' AND p.aprobacion='pendiente' AND p.cuenta_activa
    ORDER BY p.creado_en;
END;
$$;

CREATE FUNCTION public.aprobar_profesional(p_profesional_id UUID,
    p_decision public.estado_aprobacion,p_motivo TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE filas INTEGER;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE='42501';
    END IF;
    IF p_profesional_id IS NULL OR p_decision IS NULL OR
       p_decision NOT IN ('aprobado','rechazado') THEN
        RAISE EXCEPTION 'Indica un profesional y una decision valida.' USING ERRCODE='22023';
    END IF;
    IF p_profesional_id=auth.uid() THEN
        RAISE EXCEPTION 'No puedes revisar tu propia cuenta.' USING ERRCODE='42501';
    END IF;
    IF p_decision='rechazado' AND char_length(trim(coalesce(p_motivo,'')))<5 THEN
        RAISE EXCEPTION 'Indica un motivo de rechazo de al menos 5 caracteres.' USING ERRCODE='22023';
    END IF;
    -- Bloqueo de fila: serializa las decisiones simultaneas sobre este profesional.
    PERFORM 1 FROM public.perfiles p
    WHERE p.id=p_profesional_id AND p.rol='profesional' AND p.cuenta_activa FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe un profesional activo con ese identificador.' USING ERRCODE='22023';
    END IF;
    UPDATE public.perfiles SET aprobacion=p_decision WHERE id=p_profesional_id;
    UPDATE public.revisiones_profesionales
    SET revisado_en=now(),revisado_por=auth.uid(),
        motivo_rechazo=CASE WHEN p_decision='rechazado' THEN trim(p_motivo) END,
        nota_interna=CASE WHEN p_decision='aprobado' THEN nullif(trim(p_motivo),'') END
    WHERE id=p_profesional_id;
    GET DIAGNOSTICS filas=ROW_COUNT;
    IF filas<>1 THEN
        RAISE EXCEPTION 'Falta la fila de revision. La operacion se revierte.';
    END IF;
END;
$$;

CREATE FUNCTION public.consultar_motivo_rechazo_propio()
RETURNS TABLE(aprobacion public.estado_aprobacion,motivo_rechazo TEXT,revisado_en TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
    SELECT p.aprobacion,
        CASE WHEN p.aprobacion='rechazado' THEN r.motivo_rechazo END,r.revisado_en
    FROM public.perfiles p JOIN public.revisiones_profesionales r ON r.id=p.id
    WHERE p.id=auth.uid() AND p.rol='profesional';
$$;

CREATE FUNCTION public.cambiar_estado_cuenta(p_usuario_id UUID,p_activo BOOLEAN,p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE estado_anterior BOOLEAN; rol_destino public.rol_usuario;
BEGIN
    IF public._rol_activo() IS DISTINCT FROM 'administrador' THEN
        RAISE EXCEPTION 'Se requiere administrador activo.' USING ERRCODE='42501';
    END IF;
    IF p_usuario_id IS NULL OR p_activo IS NULL OR
       char_length(trim(coalesce(p_motivo,'')))<5 THEN
        RAISE EXCEPTION 'Indica usuario, estado y motivo de al menos 5 caracteres.' USING ERRCODE='22023';
    END IF;
    IF p_usuario_id=auth.uid() THEN
        RAISE EXCEPTION 'No puedes cambiar tu propio estado.' USING ERRCODE='42501';
    END IF;
    SELECT p.cuenta_activa,p.rol INTO estado_anterior,rol_destino
    FROM public.perfiles p WHERE p.id=p_usuario_id FOR UPDATE;
    IF NOT FOUND OR rol_destino='administrador' THEN
        RAISE EXCEPTION 'Selecciona una cuenta de paciente o profesional.' USING ERRCODE='22023';
    END IF;
    IF estado_anterior=p_activo THEN
        RAISE EXCEPTION 'La cuenta ya tiene ese estado.' USING ERRCODE='22023';
    END IF;
    UPDATE public.perfiles SET cuenta_activa=p_activo WHERE id=p_usuario_id;
    INSERT INTO public.cambios_estado_cuenta(usuario_id,responsable_id,
        estado_anterior,estado_nuevo,motivo)
    VALUES(p_usuario_id,auth.uid(),estado_anterior,p_activo,trim(p_motivo));
END;
$$;

-- Solo funciones propias, nunca revocaciones globales del esquema.
REVOKE ALL ON FUNCTION public.perfil_del_usuario_actual(),
    public.verificar_acceso_usuario(), public.actualizar_nombre_apellido(TEXT,TEXT),
    public.directorio_profesionales(),public.listar_profesionales_pendientes(),
    public.aprobar_profesional(UUID,public.estado_aprobacion,TEXT),
    public.consultar_motivo_rechazo_propio(),public.cambiar_estado_cuenta(UUID,BOOLEAN,TEXT)
    FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.perfil_del_usuario_actual(),
    public.verificar_acceso_usuario(),public.actualizar_nombre_apellido(TEXT,TEXT),
    public.directorio_profesionales(),public.listar_profesionales_pendientes(),
    public.aprobar_profesional(UUID,public.estado_aprobacion,TEXT),
    public.consultar_motivo_rechazo_propio(),public.cambiar_estado_cuenta(UUID,BOOLEAN,TEXT)
    TO authenticated;
COMMIT;
