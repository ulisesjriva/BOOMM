-- =============================================================================
-- SCRIPT 22a — INSPECCION SOLO LECTURA DE QRTransferencia, Servicios,
--              Profesionales Y STORAGE (EJECUTAR ANTES DE LA MIGRACION 22)
-- Proyecto: PsicoBloom
-- Ejecutar en: Supabase > SQL Editor (solo lectura, no modifica datos)
-- =============================================================================

-- 1. Columnas de public."QRTransferencia", public."Servicios" y public."Profesionales"
SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('QRTransferencia', 'Servicios', 'Profesionales')
ORDER BY table_name, ordinal_position;

-- 2. Restricciones (PK, FK, UNIQUE, CHECK)
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    pg_get_constraintdef(c.oid) AS definicion
FROM information_schema.table_constraints tc
JOIN pg_constraint c ON c.conname = tc.constraint_name
JOIN pg_namespace n ON n.oid = c.connamespace AND n.nspname = tc.table_schema
WHERE tc.table_schema = 'public'
  AND tc.table_name IN ('QRTransferencia', 'Servicios', 'Profesionales')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- 3. Estado de RLS y politicas vigentes
SELECT
    n.nspname AS esquema,
    c.relname AS tabla,
    c.relrowsecurity AS rls_habilitado,
    c.relforcerowsecurity AS rls_forzado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('QRTransferencia', 'Servicios', 'Profesionales')
ORDER BY c.relname;

SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('QRTransferencia', 'Servicios', 'Profesionales')
ORDER BY tablename, policyname;

-- 4. Privilegios otorgados por rol
SELECT
    table_name,
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('QRTransferencia', 'Servicios', 'Profesionales')
  AND grantee IN ('PUBLIC', 'anon', 'authenticated', 'service_role')
ORDER BY table_name, grantee, privilege_type;

-- 5. Buckets existentes y politicas en storage.objects
SELECT
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
FROM storage.buckets
ORDER BY id;

SELECT
    policyname,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
ORDER BY policyname;
