-- SOLO LECTURA. Ejecutar antes de 01 y compartir resultados.
-- No muestra claves ni contrasenas ni correos de usuarios.
SELECT 'tabla' AS tipo, tablename AS nombre FROM pg_tables WHERE schemaname='public'
UNION ALL SELECT 'tipo enumerado',typname FROM pg_type
WHERE typnamespace='public'::regnamespace AND typtype='e'
ORDER BY tipo,nombre;

-- Los triggers existentes podrian restringir registros. No se borran ni reemplazan.
SELECT t.tgname AS trigger, n.nspname AS esquema_funcion,p.proname AS funcion,
       pg_get_triggerdef(t.oid) AS definicion
FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE t.tgrelid='auth.users'::regclass AND NOT t.tgisinternal;

SELECT p.proname AS funcion,pg_get_functiondef(p.oid) AS definicion
FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
AND p.proname IN('validar_correo','rls_auto_enable');
