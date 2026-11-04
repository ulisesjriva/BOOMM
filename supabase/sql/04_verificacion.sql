-- PSICOBLOOM: ejecutar COMPLETO despues de 01,02,03, en SQL Editor como postgres.
-- Crea cuentas ficticias SOLO dentro de esta transaccion. No envia correos.
-- El ROLLBACK final elimina las cuentas y todas las modificaciones de prueba.
-- Si algo falla, NO ejecutar COMMIT: ejecutar ROLLBACK y compartir el error completo.
BEGIN;
CREATE TEMP TABLE resultados_bloom(numero INTEGER GENERATED ALWAYS AS IDENTITY, prueba TEXT, resultado TEXT);
GRANT INSERT,SELECT ON pg_temp.resultados_bloom TO anon,authenticated;
GRANT USAGE ON SEQUENCE pg_temp.resultados_bloom_numero_seq TO anon,authenticated;

CREATE FUNCTION pg_temp.comprobar(prueba TEXT, condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
    IF condicion IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FALLO: %',prueba;
    END IF;
    INSERT INTO pg_temp.resultados_bloom(prueba,resultado) VALUES(prueba,'OK');
END;
$$;
CREATE FUNCTION pg_temp.comprobar_error(prueba TEXT,consulta TEXT,codigo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE codigo_obtenido TEXT;
BEGIN
    BEGIN
        EXECUTE consulta;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS codigo_obtenido=RETURNED_SQLSTATE;
    END;
    PERFORM pg_temp.comprobar(prueba,codigo_obtenido=codigo);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.comprobar(TEXT,BOOLEAN),
    pg_temp.comprobar_error(TEXT,TEXT,TEXT) TO anon,authenticated;

-- UUID aleatorios: no toca las cuentas existentes, incluida la invitacion.

SELECT set_config('bloom.paciente',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.otro',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.pendiente',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.aprobado',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.admin',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.inactivo',gen_random_uuid()::text,TRUE);
SELECT set_config('bloom.falso_admin',gen_random_uuid()::text,TRUE);

INSERT INTO auth.users(id,email,raw_user_meta_data)
SELECT current_setting('bloom.'||nombre)::uuid,
       'prueba-'||current_setting('bloom.'||nombre)||'@example.invalid',
       jsonb_build_object('nombre','Prueba','apellido','Bloom','rol',rol)
FROM (VALUES ('paciente','paciente'),('otro','paciente'),('pendiente','profesional'),
    ('aprobado','profesional'),('admin','paciente'),('inactivo','paciente'),
    ('falso_admin','administrador')) AS cuentas(nombre,rol);
-- Promocion SOLO de las cuentas temporales de este script; se revierte al final.
UPDATE public.perfiles SET rol='administrador'
WHERE id IN(current_setting('bloom.admin')::uuid,current_setting('bloom.inactivo')::uuid);
UPDATE public.perfiles SET cuenta_activa=FALSE WHERE id=current_setting('bloom.inactivo')::uuid;
UPDATE public.perfiles SET aprobacion='aprobado' WHERE id=current_setting('bloom.aprobado')::uuid;
SELECT pg_temp.comprobar('Metadatos no asignan administrador',
    (SELECT rol='paciente' FROM public.perfiles WHERE id=current_setting('bloom.falso_admin')::uuid));
SELECT pg_temp.comprobar('Trigger crea perfil profesional y revision',
    EXISTS(SELECT 1 FROM public.perfiles_profesionales WHERE id=current_setting('bloom.pendiente')::uuid)
    AND EXISTS(SELECT 1 FROM public.revisiones_profesionales WHERE id=current_setting('bloom.pendiente')::uuid));
UPDATE auth.users SET email='cambio-'||id::text||'@example.invalid'
WHERE id=current_setting('bloom.otro')::uuid;
SELECT pg_temp.comprobar('Correo sincronizado desde Auth',
    (SELECT p.correo=u.email FROM public.perfiles p JOIN auth.users u ON u.id=p.id
     WHERE p.id=current_setting('bloom.otro')::uuid));
SELECT pg_temp.comprobar_error('Restriccion rol y aprobacion',
    'UPDATE public.perfiles SET aprobacion=''pendiente'' WHERE id=current_setting(''bloom.paciente'')::uuid','23514');

-- Permisos efectivos: incluye concesiones directas y heredadas.
DO $$
DECLARE objeto TEXT; funcion TEXT;
BEGIN
    FOREACH objeto IN ARRAY ARRAY['perfiles','perfiles_profesionales','revisiones_profesionales','cambios_estado_cuenta'] LOOP
        PERFORM pg_temp.comprobar('RLS habilitado: '||objeto,
            (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid=('public.'||objeto)::regclass));
        PERFORM pg_temp.comprobar('Anon sin SELECT: '||objeto,
            NOT has_table_privilege('anon','public.'||objeto,'SELECT'));
        PERFORM pg_temp.comprobar('Sin INSERT ni DELETE: '||objeto,
            NOT has_table_privilege('authenticated','public.'||objeto,'INSERT') AND
            NOT has_table_privilege('authenticated','public.'||objeto,'DELETE'));
    END LOOP;
    FOREACH objeto IN ARRAY ARRAY['rol','aprobacion','cuenta_activa','correo','id','creado_en','actualizado_en'] LOOP
        PERFORM pg_temp.comprobar('Columna protegida: '||objeto,
            NOT has_column_privilege('authenticated','public.perfiles',objeto,'UPDATE'));
    END LOOP;
    FOREACH funcion IN ARRAY ARRAY[
      'public._rol_activo()', 'public.perfil_del_usuario_actual()',
      'public.verificar_acceso_usuario()', 'public.actualizar_nombre_apellido(text,text)',
      'public.directorio_profesionales()', 'public.listar_profesionales_pendientes()',
      'public.aprobar_profesional(uuid,public.estado_aprobacion,text)',
      'public.consultar_motivo_rechazo_propio()', 'public.cambiar_estado_cuenta(uuid,boolean,text)'] LOOP
        PERFORM pg_temp.comprobar('Anon sin EXECUTE: '||funcion,
            NOT has_function_privilege('anon',funcion,'EXECUTE'));
        PERFORM pg_temp.comprobar('Authenticated con EXECUTE: '||funcion,
            has_function_privilege('authenticated',funcion,'EXECUTE'));
    END LOOP;
END;
$$;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',TRUE);
SELECT set_config('request.jwt.claims','{}',TRUE);
SELECT pg_temp.comprobar_error('Anon no lee perfiles',$consulta$SELECT * FROM public.perfiles$consulta$,'42501');
SELECT pg_temp.comprobar_error('Anon no llama directorio',$consulta$SELECT * FROM public.directorio_profesionales()$consulta$,'42501');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.paciente'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.paciente'),'role','authenticated')::text,TRUE);
SELECT pg_temp.comprobar('Paciente lee solo su perfil',(SELECT count(*)=1 FROM public.perfiles));
SELECT pg_temp.comprobar('Paciente no ve revisiones',(SELECT count(*)=0 FROM public.revisiones_profesionales));
SELECT pg_temp.comprobar('Paciente no ve auditoria',(SELECT count(*)=0 FROM public.cambios_estado_cuenta));
SELECT public.actualizar_nombre_apellido('Nombre','Actualizado');
SELECT pg_temp.comprobar('Paciente actualiza nombre propio',(SELECT nombre='Nombre' FROM public.perfiles WHERE id=auth.uid()));
WITH cambios AS(UPDATE public.perfiles SET nombre='Intruso' WHERE id=current_setting('bloom.otro')::uuid RETURNING id) SELECT pg_temp.comprobar('No modifica perfil ajeno',count(*)=0) FROM cambios;
SELECT pg_temp.comprobar_error('No cambia rol',$consulta$UPDATE public.perfiles SET rol='administrador' WHERE id=auth.uid()$consulta$,'42501');
SELECT pg_temp.comprobar_error('No cambia aprobacion',$consulta$UPDATE public.perfiles SET aprobacion='aprobado' WHERE id=auth.uid()$consulta$,'42501');
SELECT pg_temp.comprobar_error('No cambia estado',$consulta$UPDATE public.perfiles SET cuenta_activa=FALSE WHERE id=auth.uid()$consulta$,'42501');
SELECT pg_temp.comprobar_error('No lista pendientes',$consulta$SELECT * FROM public.listar_profesionales_pendientes()$consulta$,'42501');
SELECT pg_temp.comprobar_error('No aprueba profesional',$consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,'aprobado',NULL)$consulta$,'42501');
SELECT pg_temp.comprobar_error('No bloquea cuentas',$consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.otro')::uuid,FALSE,'Prueba bloqueo')$consulta$,'42501');
SELECT pg_temp.comprobar('Directorio incluye aprobado',(SELECT EXISTS(SELECT 1 FROM public.directorio_profesionales() WHERE id=current_setting('bloom.aprobado')::uuid)));
SELECT pg_temp.comprobar('Directorio excluye pendiente',(SELECT NOT EXISTS(SELECT 1 FROM public.directorio_profesionales() WHERE id=current_setting('bloom.pendiente')::uuid)));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.pendiente'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.pendiente'),'role','authenticated')::text,TRUE);
UPDATE public.perfiles_profesionales SET especialidad='Clinica' WHERE id=auth.uid();
SELECT pg_temp.comprobar('Pendiente edita perfil propio',(SELECT especialidad='Clinica' FROM public.perfiles_profesionales WHERE id=auth.uid()));
SELECT pg_temp.comprobar('Profesional solo lee su perfil extendido',(SELECT count(*)=1 FROM public.perfiles_profesionales));
SELECT pg_temp.comprobar_error('Profesional no se autoaprueba',$consulta$SELECT public.aprobar_profesional(auth.uid(),'aprobado',NULL)$consulta$,'42501');
SELECT pg_temp.comprobar('Profesional no lee notas internas',(SELECT count(*)=0 FROM public.revisiones_profesionales));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.admin'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.admin'),'role','authenticated')::text,TRUE);
SELECT pg_temp.comprobar('Admin lista pendientes',(SELECT EXISTS(SELECT 1 FROM public.listar_profesionales_pendientes() WHERE id=current_setting('bloom.pendiente')::uuid)));
SELECT pg_temp.comprobar_error('Decision nula rechazada',$consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,NULL,NULL)$consulta$,'22023');
SELECT pg_temp.comprobar_error('Rechazo exige motivo',$consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,'rechazado',NULL)$consulta$,'22023');
SELECT pg_temp.comprobar_error('Estado nulo rechazado',$consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid,NULL,'Motivo prueba')$consulta$,'22023');
SELECT pg_temp.comprobar_error('Bloqueo exige motivo',$consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid,FALSE,NULL)$consulta$,'22023');
SELECT pg_temp.comprobar_error('Admin no revisa su cuenta',$consulta$SELECT public.aprobar_profesional(auth.uid(),'aprobado',NULL)$consulta$,'42501');
SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,'rechazado','Documento incompleto');
SELECT pg_temp.comprobar('Rechazo registrado',(SELECT aprobacion='rechazado' FROM public.perfiles WHERE id=current_setting('bloom.pendiente')::uuid));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.pendiente'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.pendiente'),'role','authenticated')::text,TRUE);
SELECT pg_temp.comprobar('Profesional consulta su rechazo',(SELECT motivo_rechazo='Documento incompleto' FROM public.consultar_motivo_rechazo_propio()));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.admin'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.admin'),'role','authenticated')::text,TRUE);
SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,'aprobado','Nota interna de prueba');
SELECT pg_temp.comprobar('Aprobacion registrada',(SELECT aprobacion='aprobado' FROM public.perfiles WHERE id=current_setting('bloom.pendiente')::uuid));
SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid,FALSE,'Bloqueo de prueba');
SELECT pg_temp.comprobar('Historial registra bloqueo de paciente',(SELECT count(*)=1 FROM public.cambios_estado_cuenta WHERE usuario_id=current_setting('bloom.paciente')::uuid AND responsable_id=auth.uid() AND estado_nuevo=FALSE));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.paciente'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.paciente'),'role','authenticated')::text,TRUE);
SELECT pg_temp.comprobar('Inactivo puede leer estado propio',(SELECT cuenta_activa=FALSE FROM public.perfiles WHERE id=auth.uid()));
SELECT pg_temp.comprobar_error('Inactivo no edita mediante RPC',$consulta$SELECT public.actualizar_nombre_apellido('Nombre','Prohibido')$consulta$,'42501');
WITH cambios AS(UPDATE public.perfiles SET nombre='Prohibido' WHERE id=auth.uid() RETURNING id) SELECT pg_temp.comprobar('Inactivo no edita directamente',count(*)=0) FROM cambios;
SELECT pg_temp.comprobar_error('Inactivo no consulta directorio',$consulta$SELECT * FROM public.directorio_profesionales()$consulta$,'42501');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.inactivo'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.inactivo'),'role','authenticated')::text,TRUE);
SELECT pg_temp.comprobar_error('Admin inactivo no lista pendientes',$consulta$SELECT * FROM public.listar_profesionales_pendientes()$consulta$,'42501');
SELECT pg_temp.comprobar_error('Admin inactivo no aprueba',$consulta$SELECT public.aprobar_profesional(current_setting('bloom.pendiente')::uuid,'aprobado',NULL)$consulta$,'42501');
SELECT pg_temp.comprobar_error('Admin inactivo no reactiva',$consulta$SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid,TRUE,'Reactivacion prohibida')$consulta$,'42501');
SELECT pg_temp.comprobar('Admin inactivo solo lee su perfil',(SELECT count(*)=1 FROM public.perfiles));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.admin'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.admin'),'role','authenticated')::text,TRUE);
SELECT public.cambiar_estado_cuenta(current_setting('bloom.paciente')::uuid,TRUE,'Reactivacion de prueba');
SELECT pg_temp.comprobar('Historial conserva bloqueo y reactivacion',(SELECT count(*)=2 FROM public.cambios_estado_cuenta WHERE usuario_id=current_setting('bloom.paciente')::uuid));
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('bloom.paciente'),TRUE);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('bloom.paciente'),'role','authenticated')::text,TRUE);
SELECT public.actualizar_nombre_apellido('Cuenta','Reactivada');
SELECT pg_temp.comprobar('Cuenta reactivada vuelve a operar',(SELECT nombre='Cuenta' FROM public.perfiles WHERE id=auth.uid()));
RESET ROLE;
SELECT numero,prueba,resultado FROM pg_temp.resultados_bloom ORDER BY numero;
ROLLBACK;
