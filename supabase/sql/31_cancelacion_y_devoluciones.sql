-- PsicoBloom: aplicar DESPUES del script 30. No ejecutado en producción.
-- Cancelación atómica, decisión económica congelada y devolución manual privada.
-- No modifica Telegram. No realiza transferencias bancarias.
BEGIN;

ALTER TABLE public."Citas" ADD COLUMN IF NOT EXISTS veces_reprogramada integer NOT NULL DEFAULT 0
 CHECK (veces_reprogramada IN (0,1));
ALTER TABLE psicobloom_interno.adelantos_citas DROP CONSTRAINT adelantos_citas_estado_adelanto_check;
ALTER TABLE psicobloom_interno.adelantos_citas ADD CONSTRAINT adelantos_citas_estado_adelanto_check
 CHECK (estado_adelanto IN ('pendiente_aceptacion','pendiente_adelanto','comprobante_en_revision',
 'observado','verificado','vencido_sin_pago','incidencia_pago','rechazado_sin_pago','cancelado'));

CREATE TABLE psicobloom_interno.cancelaciones_citas (
 id_cita uuid PRIMARY KEY REFERENCES public."Citas"(id_cita) ON DELETE RESTRICT,
 actor text NOT NULL CHECK (actor IN ('paciente','profesional')),
 motivo text NOT NULL CHECK (char_length(trim(motivo)) BETWEEN 5 AND 500),
 cancelada_por uuid NOT NULL REFERENCES auth.users(id),
 cancelada_en timestamptz NOT NULL,
 inicio_cita_en timestamptz NOT NULL,
 veces_reprogramada integer NOT NULL CHECK (veces_reprogramada IN (0,1)),
 corresponde_devolucion boolean NOT NULL,
 monto_adelanto numeric(10,2) NOT NULL CHECK (monto_adelanto >= 0),
 estado_pago text NOT NULL CHECK (estado_pago IN ('no_reportado','pendiente_verificacion','recibido','no_recibido')),
 pago_revisado_por uuid REFERENCES auth.users(id),
 pago_revisado_en timestamptz,
 motivo_revision text,
 ruta_comprobante_devolucion text,
 referencia_devolucion text,
 devolucion_registrada_por uuid REFERENCES auth.users(id),
 devolucion_registrada_en timestamptz,
 CHECK ((pago_revisado_por IS NULL AND pago_revisado_en IS NULL AND motivo_revision IS NULL)
     OR (pago_revisado_por IS NOT NULL AND pago_revisado_en IS NOT NULL AND char_length(trim(motivo_revision)) BETWEEN 5 AND 500)),
 CHECK ((ruta_comprobante_devolucion IS NULL AND referencia_devolucion IS NULL
         AND devolucion_registrada_por IS NULL AND devolucion_registrada_en IS NULL)
     OR (ruta_comprobante_devolucion IS NOT NULL AND char_length(trim(referencia_devolucion)) BETWEEN 5 AND 150
         AND devolucion_registrada_por IS NOT NULL AND devolucion_registrada_en IS NOT NULL
         AND corresponde_devolucion AND estado_pago='recibido' AND monto_adelanto>0))
);
ALTER TABLE psicobloom_interno.cancelaciones_citas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON psicobloom_interno.cancelaciones_citas FROM PUBLIC,anon,authenticated;

CREATE FUNCTION psicobloom_interno._corresponde_devolucion(
 p_actor text,p_inicio timestamptz,p_cancelada timestamptz,p_veces integer)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
 SELECT p_actor='profesional' OR
 (p_actor='paciente' AND p_veces=0 AND p_inicio-p_cancelada >= interval '24 hours');
$$;
REVOKE ALL ON FUNCTION psicobloom_interno._corresponde_devolucion(text,timestamptz,timestamptz,integer) FROM PUBLIC,anon,authenticated;

-- Devuelve error uniforme para no revelar citas ajenas; rol NULL nunca autoriza.
CREATE FUNCTION psicobloom_interno._autorizar_cancelacion(p_id_cita uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_rol text:=public._rol_activo();
BEGIN
 IF auth.uid() IS NULL OR v_rol IS NULL OR v_rol NOT IN ('paciente','profesional') OR NOT EXISTS (
 SELECT 1 FROM public."Citas" c JOIN public."Pacientes" pa USING(id_paciente)
 JOIN public."Profesionales" pr USING(id_profesional) WHERE c.id_cita=p_id_cita
 AND ((v_rol='paciente' AND pa.id_usuario=auth.uid()) OR
 (v_rol='profesional' AND pr.id_usuario=auth.uid() AND public._profesional_es_publicable(pr.id_profesional))))
 THEN RAISE EXCEPTION 'No tienes acceso a la gestión de esta cita.' USING ERRCODE='42501'; END IF;
 RETURN v_rol;
END $$;
REVOKE ALL ON FUNCTION psicobloom_interno._autorizar_cancelacion(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.obtener_gestion_cancelacion(p_id_cita uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE
 v_rol text:=psicobloom_interno._autorizar_cancelacion(p_id_cita);
 c public."Citas"%ROWTYPE; a psicobloom_interno.adelantos_citas%ROWTYPE;
 x psicobloom_interno.cancelaciones_citas%ROWTYPE;
 v_inicio timestamptz; v_ahora timestamptz:=clock_timestamp(); v_criterio boolean;
 v_pago text; v_monto numeric; v_estado text; v_version text;
BEGIN
 SELECT * INTO STRICT c FROM public."Citas" WHERE id_cita=p_id_cita;
 SELECT (d.fecha+d.hora_inicio) AT TIME ZONE 'America/Guayaquil' INTO v_inicio
 FROM public."Disponibilidad" d WHERE d.id_disponibilidad=c.id_disponibilidad;
 SELECT * INTO a FROM psicobloom_interno.adelantos_citas WHERE id_cita=p_id_cita;
 SELECT * INTO x FROM psicobloom_interno.cancelaciones_citas WHERE id_cita=p_id_cita;
 v_criterio:=psicobloom_interno._corresponde_devolucion(v_rol,v_inicio,v_ahora,c.veces_reprogramada);
 v_monto:=coalesce(a.monto_adelanto,0);
 v_pago:=CASE WHEN a.verificado_en IS NOT NULL THEN 'recibido'
 WHEN EXISTS(SELECT 1 FROM psicobloom_interno.comprobantes_adelanto WHERE id_cita=p_id_cita)
 OR EXISTS(SELECT 1 FROM psicobloom_interno.incidencias_adelanto WHERE id_cita=p_id_cita)
 THEN 'pendiente_verificacion' ELSE 'no_reportado' END;
 v_version:=md5(jsonb_build_array(c.estado,a.estado_adelanto,v_pago,v_monto,c.veces_reprogramada,v_criterio)::text);
 IF x.id_cita IS NOT NULL THEN
  v_criterio:=x.corresponde_devolucion; v_monto:=x.monto_adelanto; v_pago:=x.estado_pago;
 END IF;
 v_estado:=CASE WHEN x.ruta_comprobante_devolucion IS NOT NULL THEN 'registrada'
 WHEN v_pago='pendiente_verificacion' THEN 'pendiente_verificacion'
 WHEN v_pago='recibido' AND v_criterio AND v_monto>0 THEN 'pendiente_devolucion' ELSE 'no_aplica' END;
 RETURN jsonb_build_object('id_cita',p_id_cita,'rol',v_rol,'estado_cita',c.estado,
 'puede_cancelar',x.id_cita IS NULL AND c.estado IN ('pendiente','confirmada') AND v_inicio>v_ahora,
 'version_previa',v_version,'hora_servidor',v_ahora,'monto_adelanto',v_monto,'moneda','USD',
 'corresponde_devolucion',v_criterio,'estado_pago',v_pago,'estado_devolucion',v_estado,
 'cancelada_en',x.cancelada_en,'actor',x.actor,'motivo',x.motivo,
 'motivo_revision',x.motivo_revision,'pago_revisado_en',x.pago_revisado_en,
 'ruta_comprobante_devolucion',x.ruta_comprobante_devolucion,
 'referencia_devolucion',x.referencia_devolucion,'devolucion_registrada_en',x.devolucion_registrada_en,
 'puede_revisar_pago',v_rol='profesional' AND x.id_cita IS NOT NULL AND v_pago='pendiente_verificacion',
 'puede_registrar_devolucion',v_rol='profesional' AND x.id_cita IS NOT NULL AND v_estado='pendiente_devolucion');
END $$;

CREATE FUNCTION public.cancelar_cita_con_tratamiento_adelanto(
 p_id_cita uuid,p_motivo text,p_version_previa text,p_pago_reportado boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE
 v_rol text:=psicobloom_interno._autorizar_cancelacion(p_id_cita);
 c public."Citas"%ROWTYPE; a psicobloom_interno.adelantos_citas%ROWTYPE;
 d public."Disponibilidad"%ROWTYPE; v_ahora timestamptz; v_previa jsonb;
 v_contexto text:=coalesce(current_setting('psicobloom.contexto_respuesta_cita',true),'');
BEGIN
 IF char_length(trim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 500 OR p_pago_reportado IS NULL THEN
 RAISE EXCEPTION 'Indica un motivo de 5 a 500 caracteres.' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT c FROM public."Citas" WHERE id_cita=p_id_cita;
 -- Orden canónico compatible con aceptación/vencimiento: profesional, horario, cita, adelanto.
 PERFORM 1 FROM public."Profesionales" WHERE id_profesional=c.id_profesional FOR UPDATE;
 SELECT * INTO STRICT d FROM public."Disponibilidad" WHERE id_disponibilidad=c.id_disponibilidad FOR UPDATE;
 SELECT * INTO STRICT c FROM public."Citas" WHERE id_cita=p_id_cita FOR UPDATE;
 SELECT * INTO a FROM psicobloom_interno.adelantos_citas WHERE id_cita=p_id_cita FOR UPDATE;
 PERFORM psicobloom_interno._autorizar_cancelacion(p_id_cita);
 -- Reintento tras respuesta perdida: no cambia actor, fecha, motivo ni cálculo originales.
 IF EXISTS(SELECT 1 FROM psicobloom_interno.cancelaciones_citas WHERE id_cita=p_id_cita) THEN
 RETURN public.obtener_gestion_cancelacion(p_id_cita); END IF;
 v_previa:=public.obtener_gestion_cancelacion(p_id_cita);
 IF NOT (v_previa->>'puede_cancelar')::boolean THEN
 RAISE EXCEPTION 'La cita ya no permite cancelación.' USING ERRCODE='23P01'; END IF;
 IF p_version_previa IS DISTINCT FROM v_previa->>'version_previa' THEN
 RAISE EXCEPTION 'Cambió el estado o la consecuencia económica. Actualiza y confirma nuevamente.' USING ERRCODE='23P01'; END IF;
 IF p_pago_reportado AND a.id_cita IS NULL THEN
 RAISE EXCEPTION 'Esta cita no tiene un adelanto registrado.' USING ERRCODE='22023'; END IF;
 v_ahora:=(v_previa->>'hora_servidor')::timestamptz;
 INSERT INTO psicobloom_interno.cancelaciones_citas(id_cita,actor,motivo,cancelada_por,cancelada_en,
 inicio_cita_en,veces_reprogramada,corresponde_devolucion,monto_adelanto,estado_pago)
 VALUES(p_id_cita,v_rol,trim(p_motivo),auth.uid(),v_ahora,
 (d.fecha+d.hora_inicio) AT TIME ZONE 'America/Guayaquil',c.veces_reprogramada,
 (v_previa->>'corresponde_devolucion')::boolean,coalesce(a.monto_adelanto,0),
 CASE WHEN p_pago_reportado AND v_previa->>'estado_pago'='no_reportado' THEN 'pendiente_verificacion'
 ELSE v_previa->>'estado_pago' END);
 PERFORM set_config('psicobloom.contexto_respuesta_cita','cancelacion_con_tratamiento',true);
 UPDATE public."Citas" SET estado='cancelada' WHERE id_cita=p_id_cita;
 -- El estado del pago cancelado se conserva aparte; nunca vuelve a confirmar esta cita.
 UPDATE psicobloom_interno.adelantos_citas SET estado_adelanto='cancelado',actualizado_en=v_ahora WHERE id_cita=p_id_cita;
 IF NOT EXISTS(SELECT 1 FROM public."Citas" WHERE id_disponibilidad=c.id_disponibilidad
 AND id_cita<>p_id_cita AND estado IN ('pendiente','confirmada')) THEN
 UPDATE public."Disponibilidad" SET estado=CASE
 WHEN public._es_dia_no_laborable_profesional(c.id_profesional,d.fecha) THEN 'bloqueada' ELSE 'disponible' END
 WHERE id_disponibilidad=c.id_disponibilidad AND estado='reservada'; END IF;
 PERFORM set_config('psicobloom.contexto_respuesta_cita',v_contexto,true);
 RETURN public.obtener_gestion_cancelacion(p_id_cita);
END $$;

CREATE FUNCTION public.revisar_pago_cita_cancelada(p_id_cita uuid,p_recibido boolean,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_rol text:=psicobloom_interno._autorizar_cancelacion(p_id_cita);
 x psicobloom_interno.cancelaciones_citas%ROWTYPE; v_estado text;
BEGIN
 IF v_rol IS DISTINCT FROM 'profesional' THEN RAISE EXCEPTION 'Solo el profesional titular puede verificar el ingreso.' USING ERRCODE='42501'; END IF;
 IF p_recibido IS NULL OR char_length(trim(coalesce(p_motivo,''))) NOT BETWEEN 5 AND 500 THEN
 RAISE EXCEPTION 'Indica el resultado y un motivo de 5 a 500 caracteres.' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public."Profesionales" pr JOIN public."Citas" c USING(id_profesional) WHERE c.id_cita=p_id_cita FOR UPDATE OF pr;
 SELECT * INTO x FROM psicobloom_interno.cancelaciones_citas WHERE id_cita=p_id_cita FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'La cita no tiene una cancelación registrada.' USING ERRCODE='23P01'; END IF;
 v_estado:=CASE WHEN p_recibido THEN 'recibido' ELSE 'no_recibido' END;
 IF x.estado_pago=v_estado THEN RETURN public.obtener_gestion_cancelacion(p_id_cita); END IF;
 IF x.estado_pago<>'pendiente_verificacion' THEN RAISE EXCEPTION 'El ingreso ya no está pendiente de verificación.' USING ERRCODE='23P01'; END IF;
 UPDATE psicobloom_interno.cancelaciones_citas SET estado_pago=v_estado,pago_revisado_por=auth.uid(),
 pago_revisado_en=clock_timestamp(),motivo_revision=trim(p_motivo) WHERE id_cita=p_id_cita;
 RETURN public.obtener_gestion_cancelacion(p_id_cita);
END $$;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('comprobantes-devoluciones','comprobantes-devoluciones',false,5242880,ARRAY['image/png','image/jpeg']);

CREATE FUNCTION public._puede_acceder_comprobante_devolucion(p_ruta text,p_es_carga boolean)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_id uuid; v_partes text[]:=string_to_array(p_ruta,'/'); v_rol text:=public._rol_activo();
BEGIN
 IF auth.uid() IS NULL OR v_rol IS NULL OR v_rol NOT IN ('paciente','profesional')
 OR cardinality(v_partes)<>3 OR p_ruta LIKE '%..%' THEN RETURN false; END IF;
 BEGIN v_id:=v_partes[1]::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
 RETURN EXISTS(SELECT 1 FROM psicobloom_interno.cancelaciones_citas x
 JOIN public."Citas" c USING(id_cita) JOIN public."Profesionales" pr USING(id_profesional)
 JOIN public."Pacientes" pa USING(id_paciente)
 WHERE x.id_cita=v_id AND v_partes[2]=pr.id_usuario::text
 AND ((p_es_carga AND v_rol='profesional' AND pr.id_usuario=auth.uid()
 AND public._profesional_es_publicable(pr.id_profesional) AND x.estado_pago='recibido'
 AND x.corresponde_devolucion AND x.monto_adelanto>0 AND x.ruta_comprobante_devolucion IS NULL)
 OR (NOT p_es_carga AND ((v_rol='paciente' AND pa.id_usuario=auth.uid()) OR
 (v_rol='profesional' AND pr.id_usuario=auth.uid() AND public._profesional_es_publicable(pr.id_profesional))))));
END $$;
CREATE POLICY devoluciones_insertar_titular ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='comprobantes-devoluciones' AND public._puede_acceder_comprobante_devolucion(name,true));
CREATE POLICY devoluciones_leer_titulares ON storage.objects FOR SELECT TO authenticated
USING(bucket_id='comprobantes-devoluciones' AND public._puede_acceder_comprobante_devolucion(name,false));
-- Sin políticas UPDATE/DELETE: evidencia inmutable, igual que los comprobantes de adelanto.

CREATE FUNCTION public.registrar_devolucion_cita(p_id_cita uuid,p_ruta_storage text,p_referencia text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_rol text:=psicobloom_interno._autorizar_cancelacion(p_id_cita);
 x psicobloom_interno.cancelaciones_citas%ROWTYPE;
BEGIN
 IF v_rol IS DISTINCT FROM 'profesional' THEN RAISE EXCEPTION 'Solo el profesional titular puede registrar la devolución.' USING ERRCODE='42501'; END IF;
 IF char_length(trim(coalesce(p_referencia,''))) NOT BETWEEN 5 AND 150 THEN
 RAISE EXCEPTION 'La referencia debe tener entre 5 y 150 caracteres.' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM public."Profesionales" pr JOIN public."Citas" c USING(id_profesional) WHERE c.id_cita=p_id_cita FOR UPDATE OF pr;
 SELECT * INTO x FROM psicobloom_interno.cancelaciones_citas WHERE id_cita=p_id_cita FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'No existe la cancelación indicada.' USING ERRCODE='23P01'; END IF;
 IF x.ruta_comprobante_devolucion IS NOT NULL THEN
 IF x.ruta_comprobante_devolucion=trim(p_ruta_storage) AND x.referencia_devolucion=trim(p_referencia)
 THEN RETURN public.obtener_gestion_cancelacion(p_id_cita); END IF;
 RAISE EXCEPTION 'La devolución ya tiene un comprobante registrado; no se sobrescribe.' USING ERRCODE='23P01'; END IF;
 IF NOT public._puede_acceder_comprobante_devolucion(p_ruta_storage,true) OR
 split_part(p_ruta_storage,'/',1)<>p_id_cita::text THEN
 RAISE EXCEPTION 'La ruta no corresponde a una devolución autorizada.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='comprobantes-devoluciones' AND name=p_ruta_storage) THEN
 RAISE EXCEPTION 'Primero debes subir el comprobante privado de devolución.' USING ERRCODE='22023'; END IF;
 UPDATE psicobloom_interno.cancelaciones_citas SET ruta_comprobante_devolucion=trim(p_ruta_storage),
 referencia_devolucion=trim(p_referencia),devolucion_registrada_por=auth.uid(),
 devolucion_registrada_en=clock_timestamp() WHERE id_cita=p_id_cita;
 RETURN public.obtener_gestion_cancelacion(p_id_cita);
END $$;

-- Se conservan las validaciones previas de disponibilidad.
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

            -- Regla del script 14: jamas habilitar como 'disponible' en dia no laborable
            IF NEW.estado = 'disponible'
               AND public._es_dia_no_laborable_profesional(NEW.id_profesional, NEW.fecha) THEN
                RAISE EXCEPTION 'No se puede desbloquear ni habilitar un horario en una fecha marcada como dia no laborable. Retira primero la excepcion del dia.' USING ERRCODE = '22023';
            END IF;

            -- Solo permitir 'reservada' -> 'bloqueada' desde flujos autorizados (rechazo o vencimiento)
            IF OLD.estado = 'reservada'
               AND NEW.estado = 'bloqueada'
               AND v_contexto_respuesta NOT IN ('rechazo_profesional', 'vencimiento_adelanto', 'cancelacion_con_tratamiento') THEN
                RAISE EXCEPTION 'No se puede bloquear directamente un horario reservado.' USING ERRCODE = '22023';
            END IF;

            -- Solo permitir 'reservada' -> 'disponible' desde flujos autorizados
            IF OLD.estado = 'reservada'
               AND NEW.estado = 'disponible'
               AND v_contexto_respuesta NOT IN ('rechazo_profesional', 'vencimiento_adelanto', 'cancelacion_con_tratamiento') THEN
                RAISE EXCEPTION 'No se puede liberar manualmente un horario reservado fuera de los flujos autorizados.' USING ERRCODE = '22023';
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

-- El contexto por sí solo no autoriza: exige registro interno de la RPC.
CREATE OR REPLACE FUNCTION public.validar_profesional_aprobado_en_citas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_ahora_ecuador TIMESTAMP WITHOUT TIME ZONE := (now() AT TIME ZONE 'America/Guayaquil');
    v_horario public."Disponibilidad"%ROWTYPE;
    v_contexto TEXT := COALESCE(current_setting('psicobloom.contexto_respuesta_cita', TRUE), '');
    v_estado_adelanto TEXT;
BEGIN
    -- Permitir vencimiento automatico de reservas sin pago incluso si el
    -- profesional fue desactivado despues de aceptar la cita.
    IF NOT (
        TG_OP = 'UPDATE'
        AND NEW.estado = 'cancelada'
        AND v_contexto IN ('vencimiento_adelanto','cancelacion_con_tratamiento')
    ) THEN
        IF NOT public._profesional_es_publicable(NEW.id_profesional) THEN
            RAISE EXCEPTION 'No se permiten operaciones de citas con profesionales pendientes de aprobacion o inactivos.' USING ERRCODE = '42501';
        END IF;
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

        -- Regla del script 14: impedir nuevas solicitudes en dia no laborable
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
           OR NEW.veces_reprogramada IS DISTINCT FROM OLD.veces_reprogramada
           OR NEW.fecha_solicitud IS DISTINCT FROM OLD.fecha_solicitud THEN
            RAISE EXCEPTION 'No se permite modificar los identificadores ni la fecha de solicitud de una cita existente.' USING ERRCODE = '42501';
        END IF;

        IF NEW.estado IS DISTINCT FROM OLD.estado THEN
            IF NEW.estado = 'pendiente' THEN
                RAISE EXCEPTION 'No se puede revertir una cita respondida al estado pendiente.' USING ERRCODE = '22023';
            END IF;

            -- Proteccion contra cancelaciones que omitan el tratamiento de adelanto
            IF NEW.estado = 'cancelada' AND v_contexto='cancelacion_con_tratamiento' AND NOT EXISTS (
                SELECT 1 FROM psicobloom_interno.cancelaciones_citas x
                WHERE x.id_cita=OLD.id_cita AND x.cancelada_por=auth.uid()
            ) THEN RAISE EXCEPTION 'La cancelación requiere tratamiento económico autorizado.' USING ERRCODE='42501'; END IF;
            IF NEW.estado = 'cancelada' AND v_contexto NOT IN ('vencimiento_adelanto','cancelacion_con_tratamiento') THEN
                SELECT a.estado_adelanto
                INTO v_estado_adelanto
                FROM psicobloom_interno.adelantos_citas a
                WHERE a.id_cita = OLD.id_cita;

                IF v_estado_adelanto IN ('comprobante_en_revision', 'observado', 'incidencia_pago', 'verificado') THEN
                    RAISE EXCEPTION 'Esta cita tiene un adelanto reportado o verificado y requiere revisión; la cancelación con tratamiento de adelanto aún no está habilitada.'
                        USING ERRCODE = '23P01';
                END IF;
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

REVOKE ALL ON FUNCTION public.obtener_gestion_cancelacion(uuid),
 public.cancelar_cita_con_tratamiento_adelanto(uuid,text,text,boolean),
 public.revisar_pago_cita_cancelada(uuid,boolean,text),
 public.registrar_devolucion_cita(uuid,text,text),
 public._puede_acceder_comprobante_devolucion(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.obtener_gestion_cancelacion(uuid),
 public.cancelar_cita_con_tratamiento_adelanto(uuid,text,text,boolean),
 public.revisar_pago_cita_cancelada(uuid,boolean,text),
 public.registrar_devolucion_cita(uuid,text,text),
 public._puede_acceder_comprobante_devolucion(text,boolean) TO authenticated;
COMMIT;
