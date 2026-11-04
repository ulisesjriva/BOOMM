-- OBSOLETO. Conservado como aviso para evitar ejecutar la version antigua.
-- La copia anterior se conserva en el respaldo que se realiza antes de actualizar.
-- Orden vigente: 00 inspeccion, 01 estructura, 02 RLS, 03 funciones_aplicacion, 04 pruebas.
DO $$ BEGIN
    RAISE EXCEPTION 'Archivo obsoleto: no ejecutar. Usa 03_funciones_aplicacion.sql y 04_verificacion.sql.';
END $$;
