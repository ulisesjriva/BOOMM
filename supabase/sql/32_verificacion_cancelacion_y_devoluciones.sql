-- Aplicar después de 31; pruebas SQL reales bajo roles de cliente, con ROLLBACK.
-- Requiere un profesional con oferta de adelanto y QR existentes, paciente activo,
-- administrador y otro paciente activo. Si falta un perfil, falla explícitamente.
-- Fixtures de ingreso verificado se preparan internamente, sin objetos ficticios
-- en storage.objects. NO sustituye las pruebas HTTP de Storage ni la prueba visual.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
DO $test$
DECLARE
 pr uuid; pu uuid; pa uuid; otro uuid; admin_uid uuid; dis uuid; ci uuid;
 f date; version_oferta text; detalle jsonb; copia jsonb; esperado boolean;
 importe jsonb; importe_despues jsonb; escenario integer; uid uuid; funcion text;
BEGIN
 -- Regla económica en sus límites exactos; el reloj del cliente no interviene.
 IF NOT psicobloom_interno._corresponde_devolucion('paciente','2030-01-02 10:00Z','2030-01-01 10:00Z',0)
 OR psicobloom_interno._corresponde_devolucion('paciente','2030-01-02 10:00Z','2030-01-01 10:00:00.001Z',0)
 OR psicobloom_interno._corresponde_devolucion('paciente','2030-01-02 10:00Z','2030-01-01 09:00Z',1)
 OR NOT psicobloom_interno._corresponde_devolucion('profesional','2030-01-02 10:00Z','2030-01-02 09:59Z',1)
 THEN RAISE EXCEPTION 'Falló la regla económica de 24 horas/reprogramación/actor'; END IF;

 SELECT cfg.id_profesional,p.id_usuario INTO pr,pu
 FROM psicobloom_interno.configuracion_cobro_profesional cfg
 JOIN public."Profesionales" p USING(id_profesional)
 WHERE cfg.requiere_adelanto AND public._profesional_es_publicable(p.id_profesional) LIMIT 1;
 SELECT p.id_usuario INTO pa FROM public."Pacientes" p JOIN psicobloom_interno.perfiles_compat pe ON pe.id=p.id_usuario
 WHERE pe.rol='paciente' AND pe.cuenta_activa IS TRUE ORDER BY p.id_paciente LIMIT 1;
 SELECT p.id_usuario INTO otro FROM public."Pacientes" p JOIN psicobloom_interno.perfiles_compat pe ON pe.id=p.id_usuario
 WHERE pe.rol='paciente' AND pe.cuenta_activa IS TRUE AND p.id_usuario<>pa LIMIT 1;
 SELECT id INTO admin_uid FROM psicobloom_interno.perfiles_compat WHERE rol='administrador' AND cuenta_activa IS TRUE LIMIT 1;
 IF pr IS NULL OR pa IS NULL OR otro IS NULL OR admin_uid IS NULL THEN
 RAISE EXCEPTION 'Verificación incompleta: faltan perfiles de prueba (profesional con oferta, paciente, otro paciente o administrador).'; END IF;

 FOR escenario IN 1..4 LOOP
  -- Buscar fecha libre; no asumir que una fecha fija está disponible/laborable.
  SELECT dia::date INTO f FROM generate_series(current_date+60,current_date+200,interval '1 day') dia
  WHERE NOT public._es_dia_no_laborable_profesional(pr,dia::date)
  AND NOT EXISTS(SELECT 1 FROM public."Disponibilidad" d WHERE d.id_profesional=pr AND d.fecha=dia::date)
  ORDER BY dia LIMIT 1;
  IF f IS NULL THEN RAISE EXCEPTION 'No hay fecha libre para los fixtures'; END IF;
  INSERT INTO public."Disponibilidad"(id_profesional,fecha,hora_inicio,hora_fin,estado)
  VALUES(pr,f,'10:00','11:00','disponible') RETURNING id_disponibilidad INTO dis;
  PERFORM set_config('request.jwt.claim.sub',pa::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',pa,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  SELECT o.version_oferta INTO version_oferta FROM public.obtener_oferta_adelanto_profesional(pr) o;
  SELECT s.id_cita INTO ci FROM public.solicitar_cita_paciente(pr,dis,'prueba32-'||gen_random_uuid()::text,true,version_oferta) s;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',pu::text,true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',pu,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM * FROM public.responder_solicitud_cita_profesional(ci,'confirmada');
  RESET ROLE;
  IF escenario=2 THEN
   -- Incidencia reportada: debe cancelar y conservar la verificación pendiente.
   PERFORM set_config('request.jwt.claim.sub',pa::text,true);
   PERFORM set_config('request.jwt.claims',json_build_object('sub',pa,'role','authenticated')::text,true);
   SET LOCAL ROLE authenticated;
   PERFORM public.registrar_incidencia_adelanto(ci,'Transferencia reportada; fallo al adjuntar comprobante','inc32-'||ci::text);
   RESET ROLE;
  END IF;
  IF escenario=3 THEN
   -- Fixture SQL de ingreso recibido, no una transferencia ni prueba Storage.
   UPDATE psicobloom_interno.adelantos_citas SET estado_adelanto='verificado',verificado_por=pu,verificado_en=now() WHERE id_cita=ci;
   UPDATE public."Citas" SET estado='confirmada' WHERE id_cita=ci;
  END IF;
  SELECT jsonb_build_array(precio_consulta,monto_adelanto,saldo_despues_adelanto) INTO importe
  FROM psicobloom_interno.adelantos_citas WHERE id_cita=ci;

  -- Una cuenta titular inactiva tampoco queda autorizada por su JWT anterior.
  UPDATE psicobloom_interno.perfiles_compat SET cuenta_activa=false WHERE id=pa;
  PERFORM set_config('request.jwt.claim.sub',pa::text,true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',pa,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  esperado:=false;
  BEGIN PERFORM public.obtener_gestion_cancelacion(ci); EXCEPTION WHEN insufficient_privilege THEN esperado:=true; END;
  RESET ROLE;
  UPDATE psicobloom_interno.perfiles_compat SET cuenta_activa=true WHERE id=pa;
  IF NOT esperado THEN RAISE EXCEPTION 'Una cuenta inactiva obtuvo acceso'; END IF;
  -- Autenticado sin perfil/otro paciente/administrador: rechazo uniforme.
  FOREACH uid IN ARRAY ARRAY[gen_random_uuid(),otro,admin_uid] LOOP
   PERFORM set_config('request.jwt.claim.sub',uid::text,true);
   PERFORM set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
   SET LOCAL ROLE authenticated;
   esperado:=false;
   BEGIN PERFORM public.obtener_gestion_cancelacion(ci); EXCEPTION WHEN insufficient_privilege THEN esperado:=true; END;
   RESET ROLE;
   IF NOT esperado THEN RAISE EXCEPTION 'Se permitió consultar una cita ajena o con rol inválido'; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  SET LOCAL ROLE anon;
  esperado:=false;
  BEGIN PERFORM public.obtener_gestion_cancelacion(ci); EXCEPTION WHEN insufficient_privilege THEN esperado:=true; END;
  RESET ROLE;
  IF NOT esperado THEN RAISE EXCEPTION 'Se permitió acceso anónimo'; END IF;

  uid:=CASE WHEN escenario=4 THEN pu ELSE pa END;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  detalle:=public.obtener_gestion_cancelacion(ci);
  esperado:=false;
  BEGIN PERFORM public.cancelar_cita_con_tratamiento_adelanto(ci,'Motivo válido','version-obsoleta',false);
  EXCEPTION WHEN exclusion_violation THEN esperado:=true; END;
  IF NOT esperado THEN RAISE EXCEPTION 'Se aceptó una confirmación obsoleta'; END IF;
  esperado:=false;
  BEGIN PERFORM public.cancelar_cita_con_tratamiento_adelanto(ci,'abcd',detalle->>'version_previa',false);
  EXCEPTION WHEN invalid_parameter_value THEN esperado:=true; END;
  IF NOT esperado THEN RAISE EXCEPTION 'Se aceptó un motivo corto'; END IF;
  detalle:=public.cancelar_cita_con_tratamiento_adelanto(ci,'Cancelación de prueba independiente',detalle->>'version_previa',escenario=4);
  copia:=public.cancelar_cita_con_tratamiento_adelanto(ci,'Otro motivo que no debe sobrescribir','otra-version',false);
  IF copia->>'cancelada_en' IS DISTINCT FROM detalle->>'cancelada_en' OR copia->>'motivo' IS DISTINCT FROM detalle->>'motivo'
  THEN RAISE EXCEPTION 'La cancelación no es idempotente'; END IF;
  IF detalle->>'estado_pago' IS DISTINCT FROM (CASE WHEN escenario=1 THEN 'no_reportado'
     WHEN escenario=3 THEN 'recibido' ELSE 'pendiente_verificacion' END)
  THEN RAISE EXCEPTION 'Clasificación de ingreso incorrecta'; END IF;
  RESET ROLE;
  IF NOT EXISTS(SELECT 1 FROM public."Citas" WHERE id_cita=ci AND estado='cancelada')
  OR NOT EXISTS(SELECT 1 FROM public."Disponibilidad" WHERE id_disponibilidad=dis AND estado='disponible')
  OR NOT EXISTS(SELECT 1 FROM psicobloom_interno.adelantos_citas WHERE id_cita=ci AND estado_adelanto='cancelado')
  THEN RAISE EXCEPTION 'La cancelación no liberó el horario de manera atómica'; END IF;
  SELECT jsonb_build_array(precio_consulta,monto_adelanto,saldo_despues_adelanto) INTO importe_despues
  FROM psicobloom_interno.adelantos_citas WHERE id_cita=ci;
  IF importe IS DISTINCT FROM importe_despues THEN RAISE EXCEPTION 'Cambió el importe congelado'; END IF;

  -- No se admiten nuevas cargas ni incidencias por el flujo original cancelado.
  PERFORM set_config('request.jwt.claim.sub',pa::text,true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',pa,'role','authenticated')::text,true);
  SET LOCAL ROLE authenticated;
  esperado:=false;
  BEGIN PERFORM public.registrar_comprobante_adelanto(ci,ci::text||'/'||pa::text||'/nuevo.png','No admitir carga','clave32-nueva');
  EXCEPTION WHEN exclusion_violation THEN esperado:=true; END;
  IF NOT esperado THEN RAISE EXCEPTION 'Se admitió comprobante después de cancelar'; END IF;
  esperado:=false;
  BEGIN PERFORM public.registrar_incidencia_adelanto(ci,'No admitir nueva incidencia','clave32-inc-nueva');
  EXCEPTION WHEN exclusion_violation THEN esperado:=true; END;
  IF NOT esperado THEN RAISE EXCEPTION 'Se admitió incidencia después de cancelar'; END IF;
  RESET ROLE;
  IF escenario IN (2,4) THEN
   -- El paciente no puede verificar el ingreso ni registrar un reembolso.
   PERFORM set_config('request.jwt.claim.sub',pa::text,true);
   PERFORM set_config('request.jwt.claims',json_build_object('sub',pa,'role','authenticated')::text,true);
   SET LOCAL ROLE authenticated;
   esperado:=false;
   BEGIN PERFORM public.revisar_pago_cita_cancelada(ci,true,'Revisión indebida del paciente');
   EXCEPTION WHEN insufficient_privilege THEN esperado:=true; END;
   IF NOT esperado THEN RAISE EXCEPTION 'Paciente verificó su ingreso'; END IF;
   RESET ROLE;
   PERFORM set_config('request.jwt.claim.sub',pu::text,true);
   PERFORM set_config('request.jwt.claims',json_build_object('sub',pu,'role','authenticated')::text,true);
   SET LOCAL ROLE authenticated;
   detalle:=public.revisar_pago_cita_cancelada(ci,escenario=2,'Verificación de la cuenta bancaria de prueba');
   IF detalle->>'estado_devolucion' IS DISTINCT FROM (CASE WHEN escenario=2 THEN 'pendiente_devolucion' ELSE 'no_aplica' END)
   THEN RAISE EXCEPTION 'Tratamiento económico posterior incorrecto'; END IF;
   IF detalle->>'estado_cita'<>'cancelada' THEN RAISE EXCEPTION 'Se reconfirmó una cita cancelada'; END IF;
   RESET ROLE;
  END IF;
  IF escenario=3 THEN
   PERFORM set_config('request.jwt.claim.sub',pu::text,true);
   PERFORM set_config('request.jwt.claims',json_build_object('sub',pu,'role','authenticated')::text,true);
   SET LOCAL ROLE authenticated;
   esperado:=false;
   BEGIN PERFORM public.registrar_devolucion_cita(ci,ci::text||'/'||pu::text||'/inexistente.png','Referencia válida');
   EXCEPTION WHEN invalid_parameter_value THEN esperado:=true; END;
   IF NOT esperado THEN RAISE EXCEPTION 'Se registró devolución sin archivo real'; END IF;
   RESET ROLE;
  END IF;
  -- Limpiar identidad antes de preparar el siguiente fixture.
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
 END LOOP;
 RAISE NOTICE 'Pruebas SQL de cancelación aprobadas. Registro positivo de devolución/Storage HTTP/Flutter pendientes de ejecución real.';
END $test$;
ROLLBACK;
