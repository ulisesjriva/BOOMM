-- =============================================================================
-- SCRIPT 28 — PROGRAMACION PERIODICA DE VENCIMIENTOS Y AVISOS DE ADELANTOS
-- Ejecutar en Supabase > SQL Editor DESPUES de 18, 26, 27 y del redespliegue
-- de la Edge Function `despachar-avisos-telegram`.
-- NO incluir credenciales ni secretos en este archivo (usa Vault existente).
-- =============================================================================
BEGIN;

DO $$
BEGIN
    IF (SELECT count(*) FROM vault.secrets WHERE name IN (
        'psicobloom_supabase_url',
        'psicobloom_service_role_key',
        'psicobloom_telegram_dispatch_secret'
    )) <> 3 THEN
        RAISE EXCEPTION 'Faltan los tres secretos requeridos en Vault.';
    END IF;

    IF to_regclass('cron.job') IS NULL
       OR to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') IS NULL THEN
        RAISE EXCEPTION 'Verifica que pg_cron y pg_net estén habilitados.';
    END IF;
END $$;

-- 1. Mantenimiento interno cada 5 minutos (SQL puro, sin HTTP):
--    vence reservas expiradas sin pago reportado y encola avisos de revision demorada (>12h).
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'mantener-adelantos-cada-5-min';

SELECT cron.schedule(
    'mantener-adelantos-cada-5-min',
    '*/5 * * * *',
    $tarea$
    SELECT public.vencer_adelantos_expirados();
    SELECT public.encolar_avisos_revision_demorada();
    $tarea$
);

-- 2. Actualizar el despachador Telegram existente para activarse ante eventos
--    pendientes tanto de nuevas solicitudes como de adelantos (sin datos bancarios).
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'despachar-avisos-telegram-cada-minuto';

SELECT cron.schedule(
    'despachar-avisos-telegram-cada-minuto',
    '* * * * *',
    $tarea$
    SELECT net.http_post(
        url := (SELECT rtrim(decrypted_secret, '/') FROM vault.decrypted_secrets
                WHERE name = 'psicobloom_supabase_url') || '/functions/v1/despachar-avisos-telegram',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets
                WHERE name = 'psicobloom_service_role_key'),
            'X-Telegram-Dispatch-Secret', (SELECT decrypted_secret FROM vault.decrypted_secrets
                WHERE name = 'psicobloom_telegram_dispatch_secret')
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 45000
    )
    WHERE EXISTS (
        SELECT 1 FROM psicobloom_interno.eventos_avisos_telegram
        WHERE (estado = 'pendiente' AND proximo_intento_en <= now())
           OR (estado = 'procesando' AND bloqueado_hasta <= now())
    )
    OR EXISTS (
        SELECT 1 FROM psicobloom_interno.eventos_avisos_adelanto
        WHERE (estado = 'pendiente' AND proximo_intento_en <= now())
           OR (estado = 'procesando' AND bloqueado_hasta <= now())
    );
    $tarea$
);

COMMIT;

SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname IN ('mantener-adelantos-cada-5-min', 'despachar-avisos-telegram-cada-minuto');
