-- PsicoBloom: programacion final del despachador con clave exclusiva de despacho.
-- Ejecutar una vez por proyecto Supabase, despues de 16, 17 y el despliegue corregido.
-- Los valores se crean en Vault desde el panel; no pegar credenciales en este archivo.
BEGIN;
DO $$
BEGIN
 IF (SELECT count(*) FROM vault.secrets WHERE name IN (
   'psicobloom_supabase_url','psicobloom_service_role_key',
   'psicobloom_telegram_dispatch_secret')) <> 3 THEN
   RAISE EXCEPTION 'Faltan los tres secretos requeridos en Vault.';
 END IF;
 IF to_regclass('cron.job') IS NULL OR to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') IS NULL THEN
   RAISE EXCEPTION 'Verifica que pg_cron y pg_net estén habilitados.';
 END IF;
END $$;
SELECT cron.schedule(
 'despachar-avisos-telegram-cada-minuto','* * * * *',
 $tarea$
 SELECT net.http_post(
   url := (SELECT rtrim(decrypted_secret,'/') FROM vault.decrypted_secrets
     WHERE name='psicobloom_supabase_url') || '/functions/v1/despachar-avisos-telegram',
   headers := jsonb_build_object(
     'Content-Type','application/json',
     'Authorization','Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets
       WHERE name='psicobloom_service_role_key'),
     'X-Telegram-Dispatch-Secret',(SELECT decrypted_secret FROM vault.decrypted_secrets
       WHERE name='psicobloom_telegram_dispatch_secret')
   ),
   body := '{}'::jsonb, timeout_milliseconds := 45000
 ) WHERE EXISTS (
   SELECT 1 FROM psicobloom_interno.eventos_avisos_telegram
   WHERE (estado='pendiente' AND proximo_intento_en<=now())
      OR (estado='procesando' AND bloqueado_hasta<=now())
 );
 $tarea$
);
COMMIT;
SELECT jobid, jobname, schedule, active FROM cron.job
WHERE jobname='despachar-avisos-telegram-cada-minuto';
