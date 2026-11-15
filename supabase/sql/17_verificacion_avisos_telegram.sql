-- Ejecutar completa como postgres DESPUES del archivo 16 revisado.
-- Crea solo cuentas ficticias. Todo se revierte con ROLLBACK.
-- No realiza llamadas a Telegram. No prueba concurrencia entre conexiones.
BEGIN;
CREATE TEMP TABLE resultados_telegram(numero INTEGER GENERATED ALWAYS AS IDENTITY, prueba TEXT, resultado TEXT);
CREATE FUNCTION pg_temp.comprobar(p_prueba TEXT, p_ok BOOLEAN) RETURNS VOID
LANGUAGE plpgsql AS $$ BEGIN
 IF p_ok IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'FALLO: %', p_prueba; END IF;
 INSERT INTO pg_temp.resultados_telegram(prueba,resultado) VALUES(p_prueba,'OK');
END $$;

DO $$
DECLARE
 u1 UUID:=gen_random_uuid(); u2 UUID:=gen_random_uuid(); up UUID:=gen_random_uuid();
 p1 UUID; p2 UUID; d UUID; cita UUID; evento UUID; r RECORD; filas INTEGER;
 h1 TEXT:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
 h2 TEXT:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
 h3 TEXT:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
 h4 TEXT:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
 h5 TEXT:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
 chat BIGINT:=4000000000000+(floor(random()*1000000000))::bigint;
 fecha DATE:=((now() AT TIME ZONE 'America/Guayaquil')::date+30);
 n INTEGER; usr UUID; rol TEXT; total INTEGER; condicion BOOLEAN;
BEGIN
 PERFORM pg_temp.comprobar('RLS en tres tablas', (SELECT count(*)=3 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace WHERE ns.nspname='psicobloom_interno' AND c.relname IN ('vinculaciones_telegram','codigos_vinculacion_telegram','eventos_avisos_telegram') AND c.relrowsecurity));
 FOREACH rol IN ARRAY ARRAY['anon','authenticated'] LOOP
  PERFORM pg_temp.comprobar('Sin lectura ni escritura directa: '||rol,
   NOT EXISTS (SELECT 1 FROM (VALUES ('vinculaciones_telegram'),('codigos_vinculacion_telegram'),('eventos_avisos_telegram')) t(nombre)
    CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) a(permiso)
    WHERE has_table_privilege(rol,'psicobloom_interno.'||t.nombre,a.permiso)));
  PERFORM pg_temp.comprobar('Sin RPC de servidor: '||rol,
   NOT has_function_privilege(rol,'public.crear_codigo_vinculacion_telegram(uuid,text,timestamp with time zone)','EXECUTE')
   AND NOT has_function_privilege(rol,'public.consumir_codigo_vinculacion_telegram(text,bigint)','EXECUTE')
   AND NOT has_function_privilege(rol,'public.reclamar_eventos_avisos_telegram(integer,integer)','EXECUTE')
   AND NOT has_function_privilege(rol,'public.finalizar_evento_aviso_telegram(uuid,text,text,timestamp with time zone,integer)','EXECUTE'));
 END LOOP;
 PERFORM pg_temp.comprobar('RPC propias con permisos correctos',has_function_privilege('authenticated','public.estado_telegram_profesional_propio()','EXECUTE') AND NOT has_function_privilege('anon','public.estado_telegram_profesional_propio()','EXECUTE') AND has_function_privilege('authenticated','public.desconectar_telegram_profesional_propio()','EXECUTE') AND NOT has_function_privilege('anon','public.desconectar_telegram_profesional_propio()','EXECUTE'));
 PERFORM pg_temp.comprobar('RPC de despacho disponible a service_role',has_function_privilege('service_role','public.reclamar_eventos_avisos_telegram(integer,integer)','EXECUTE') AND has_function_privilege('service_role','public.finalizar_evento_aviso_telegram(uuid,text,text,timestamp with time zone,integer)','EXECUTE'));

 -- Aislar de la prueba los avisos previos sin borrarlos ni enviarlos. ROLLBACK restaura todo.
 UPDATE psicobloom_interno.eventos_avisos_telegram SET proximo_intento_en=now()+interval '1 day', bloqueado_hasta=now()+interval '1 day' WHERE estado IN ('pendiente','procesando');

 FOR n IN 1..3 LOOP
  usr:=CASE n WHEN 1 THEN u1 WHEN 2 THEN u2 ELSE up END;
  rol:=CASE WHEN n=3 THEN 'paciente' ELSE 'profesional' END;
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES(usr,'telegram-prueba-'||usr||'@example.invalid',jsonb_build_object('nombre','Prueba','apellido','Telegram','rol',rol));
 END LOOP;
 UPDATE psicobloom_interno.perfiles_compat SET aprobacion='aprobado' WHERE id IN (u1,u2);
 SELECT id_profesional INTO STRICT p1 FROM public."Profesionales" WHERE id_usuario=u1;
 SELECT id_profesional INTO STRICT p2 FROM public."Profesionales" WHERE id_usuario=u2;

 -- Solicitud anterior a la vinculación: no debe producir un aviso histórico.
 PERFORM set_config('request.jwt.claim.sub',u1::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u1,'role','authenticated')::text,true);
 SELECT id_disponibilidad INTO STRICT d FROM public.crear_disponibilidad_profesional_propia(fecha,'08:00'::time,'09:00'::time);
 PERFORM set_config('request.jwt.claim.sub',up::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',up,'role','authenticated')::text,true);
 SELECT id_cita INTO STRICT cita FROM public.solicitar_cita_paciente(p1,d);
 PERFORM pg_temp.comprobar('Sin aviso cuando no hay vinculación',NOT EXISTS(SELECT 1 FROM psicobloom_interno.eventos_avisos_telegram e WHERE e.id_cita=cita));

 PERFORM public.crear_codigo_vinculacion_telegram(p1,h1,now()+interval '10 minutes');
 PERFORM pg_temp.comprobar('Vinculación válida', public.consumir_codigo_vinculacion_telegram(h1,chat)='vinculado');
 PERFORM pg_temp.comprobar('Update repetido es idempotente',public.consumir_codigo_vinculacion_telegram(h1,chat)='ya_vinculado');
 PERFORM pg_temp.comprobar('Código usado no vincula otro chat',public.consumir_codigo_vinculacion_telegram(h1,chat+1)='codigo_usado');
 PERFORM pg_temp.comprobar('No se encolaron solicitudes históricas',NOT EXISTS(SELECT 1 FROM psicobloom_interno.eventos_avisos_telegram e WHERE e.id_cita=cita));
 PERFORM public.crear_codigo_vinculacion_telegram(p2,h2,now()+interval '10 minutes');
 PERFORM pg_temp.comprobar('Chat ajeno protegido',public.consumir_codigo_vinculacion_telegram(h2,chat)='chat_en_uso_por_otro');
 PERFORM public.crear_codigo_vinculacion_telegram(p1,h3,now()+interval '10 minutes');
 UPDATE psicobloom_interno.codigos_vinculacion_telegram SET expira_en=now()-interval '1 minute' WHERE hash_codigo=h3;
 PERFORM pg_temp.comprobar('Código vencido rechazado',public.consumir_codigo_vinculacion_telegram(h3,chat)='codigo_expirado');
 PERFORM public.crear_codigo_vinculacion_telegram(p1,h4,now()+interval '10 minutes');
 PERFORM pg_temp.comprobar('Generar otro código anula el anterior',public.consumir_codigo_vinculacion_telegram(h3,chat)='codigo_anulado');

 PERFORM set_config('request.jwt.claim.sub',u1::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u1,'role','authenticated')::text,true);
 PERFORM pg_temp.comprobar('Profesional ve su conexión',(SELECT conectado FROM public.estado_telegram_profesional_propio()));
 PERFORM set_config('request.jwt.claim.sub',u2::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 PERFORM pg_temp.comprobar('Otro profesional no ve la conexión ajena',NOT (SELECT conectado FROM public.estado_telegram_profesional_propio()));
 PERFORM set_config('request.jwt.claim.sub',up::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',up,'role','authenticated')::text,true);
 condicion:=false;
 BEGIN PERFORM public.estado_telegram_profesional_propio(); EXCEPTION WHEN SQLSTATE '42501' THEN condicion:=true; END;
 PERFORM pg_temp.comprobar('Paciente no consulta vinculación profesional',condicion);

 FOR n IN 1..5 LOOP
  PERFORM set_config('request.jwt.claim.sub',u1::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u1,'role','authenticated')::text,true);
  SELECT id_disponibilidad INTO STRICT d FROM public.crear_disponibilidad_profesional_propia(fecha+n,'09:00'::time,'10:00'::time);
  PERFORM set_config('request.jwt.claim.sub',up::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',up,'role','authenticated')::text,true);
  SELECT id_cita INTO STRICT cita FROM public.solicitar_cita_paciente(p1,d);
  SELECT e.id_evento INTO STRICT evento FROM psicobloom_interno.eventos_avisos_telegram e WHERE e.id_cita=cita;
  PERFORM pg_temp.comprobar('Evento único de nueva solicitud '||n,(SELECT count(*)=1 FROM psicobloom_interno.eventos_avisos_telegram e WHERE e.id_cita=cita));
  IF n=1 THEN
   SELECT * INTO STRICT r FROM public.reclamar_eventos_avisos_telegram(1,60);
   PERFORM pg_temp.comprobar('Reclamo con destinatario correcto',r.id_evento=evento AND r.chat_id=chat AND r.intentos=1);
   PERFORM pg_temp.comprobar('Una reserva vigente no se reclama dos veces',NOT EXISTS(SELECT 1 FROM public.reclamar_eventos_avisos_telegram(1,60)));
   UPDATE psicobloom_interno.eventos_avisos_telegram SET bloqueado_hasta=now()-interval '1 second' WHERE id_evento=evento;
   SELECT * INTO STRICT r FROM public.reclamar_eventos_avisos_telegram(1,60);
   PERFORM pg_temp.comprobar('Reserva vencida recuperable',r.id_evento=evento AND r.intentos=2);
   PERFORM pg_temp.comprobar('Trabajador viejo no puede finalizar',NOT public.finalizar_evento_aviso_telegram(evento,'enviado',NULL,NULL,1));
   PERFORM pg_temp.comprobar('Trabajador actual puede finalizar',public.finalizar_evento_aviso_telegram(evento,'enviado',NULL,NULL,2));
   PERFORM pg_temp.comprobar('Evento enviado no reaparece',NOT EXISTS(SELECT 1 FROM public.reclamar_eventos_avisos_telegram(1,60)));
  ELSIF n=2 THEN
   UPDATE psicobloom_interno.eventos_avisos_telegram SET estado='procesando',intentos=5,bloqueado_hasta=now()-interval '1 second' WHERE id_evento=evento;
   PERFORM public.reclamar_eventos_avisos_telegram(1,60);
   PERFORM pg_temp.comprobar('Caída del quinto intento no produce reintentos infinitos',(SELECT estado='fallido' AND intentos=5 FROM psicobloom_interno.eventos_avisos_telegram WHERE id_evento=evento));
  ELSIF n=3 THEN
   UPDATE psicobloom_interno.perfiles_compat SET cuenta_activa=false WHERE id=u1;
   PERFORM public.reclamar_eventos_avisos_telegram(1,60);
   PERFORM pg_temp.comprobar('Cuenta inactiva no recibe avisos',(SELECT estado='omitido' FROM psicobloom_interno.eventos_avisos_telegram WHERE id_evento=evento));
   UPDATE psicobloom_interno.perfiles_compat SET cuenta_activa=true WHERE id=u1;
  ELSIF n=4 THEN
   PERFORM public.crear_codigo_vinculacion_telegram(p1,h5,now()+interval '10 minutes');
   PERFORM pg_temp.comprobar('Cambio de chat válido',public.consumir_codigo_vinculacion_telegram(h5,chat+1)='vinculado');
   PERFORM pg_temp.comprobar('Aviso anterior no se traslada al nuevo chat',(SELECT estado='omitido' FROM psicobloom_interno.eventos_avisos_telegram WHERE id_evento=evento));
   chat:=chat+1;
  ELSIF n=5 THEN
   h5:=encode(sha256(gen_random_uuid()::text::bytea),'hex');
   PERFORM public.crear_codigo_vinculacion_telegram(p1,h5,now()+interval '10 minutes');
   PERFORM set_config('request.jwt.claim.sub',u1::text,true);
   PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u1,'role','authenticated')::text,true);
   PERFORM public.desconectar_telegram_profesional_propio();
   PERFORM pg_temp.comprobar('Desconexión cancela avisos pendientes',(SELECT estado='omitido' FROM psicobloom_interno.eventos_avisos_telegram WHERE id_evento=evento));
   PERFORM pg_temp.comprobar('Desconexión anula códigos',public.consumir_codigo_vinculacion_telegram(h5,chat)='codigo_anulado');
   PERFORM pg_temp.comprobar('Desconexión elimina solo el vínculo propio',NOT (SELECT conectado FROM public.estado_telegram_profesional_propio()));
  END IF;
 END LOOP;
END $$;
SELECT numero,prueba,resultado FROM pg_temp.resultados_telegram ORDER BY numero;
ROLLBACK;
