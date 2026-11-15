-- =============================================================================
-- PSICOBLOOM — INSPECCION COMPLETA DEL ESQUEMA REMOTO (SOLO LECTURA)
-- Incluye public, psicobloom_interno, auth (triggers) y storage.
-- No modifica tablas, funciones, politicas ni datos; no expone correos ni claves.
-- =============================================================================

SELECT jsonb_pretty(
  jsonb_build_object(
    '1_tipos_enumerados', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', n.nspname,
          'tipo', t.typname,
          'valores', (
            SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
            FROM pg_enum e WHERE e.enumtypid = t.oid
          )
        ) ORDER BY n.nspname, t.typname
      ), '[]'::jsonb)
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname IN ('public', 'psicobloom_interno') AND t.typtype = 'e'
    ),
    '2_relaciones_tablas_y_vistas', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', n.nspname,
          'nombre', c.relname,
          'clase', c.relkind,
          'rls_activo', c.relrowsecurity,
          'rls_forzado', c.relforcerowsecurity,
          'definicion_vista', CASE WHEN c.relkind = 'v' THEN pg_get_viewdef(c.oid, true) END
        ) ORDER BY n.nspname, c.relname
      ), '[]'::jsonb)
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public', 'psicobloom_interno') AND c.relkind IN ('r', 'v')
    ),
    '3_columnas', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', c.table_schema,
          'tabla', c.table_name,
          'posicion', c.ordinal_position,
          'columna', c.column_name,
          'tipo', c.data_type,
          'udt', c.udt_name,
          'anulable', c.is_nullable,
          'defecto', c.column_default
        ) ORDER BY c.table_schema, c.table_name, c.ordinal_position
      ), '[]'::jsonb)
      FROM information_schema.columns c
      WHERE c.table_schema IN ('public', 'psicobloom_interno')
    ),
    '4_restricciones_y_claves', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', n.nspname,
          'tabla', rel.relname,
          'nombre', con.conname,
          'tipo', con.contype,
          'definicion', pg_get_constraintdef(con.oid)
        ) ORDER BY n.nspname, rel.relname, con.conname
      ), '[]'::jsonb)
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = rel.relnamespace
      WHERE n.nspname IN ('public', 'psicobloom_interno')
    ),
    '5_funciones', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', n.nspname,
          'nombre', p.proname,
          'argumentos', pg_get_function_identity_arguments(p.oid),
          'retorno', pg_get_function_result(p.oid),
          'security_definer', p.prosecdef,
          'definicion', pg_get_functiondef(p.oid)
        ) ORDER BY n.nspname, p.proname
      ), '[]'::jsonb)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname IN ('public', 'psicobloom_interno')
    ),
    '6_triggers', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema_tabla', n.nspname,
          'tabla', c.relname,
          'trigger', t.tgname,
          'definicion', pg_get_triggerdef(t.oid)
        ) ORDER BY n.nspname, c.relname, t.tgname
      ), '[]'::jsonb)
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE NOT t.tgisinternal
        AND n.nspname IN ('public', 'psicobloom_interno', 'auth')
    ),
    '7_politicas_rls', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'esquema', p.schemaname,
          'tabla', p.tablename,
          'politica', p.policyname,
          'comando', p.cmd,
          'roles', p.roles,
          'using', p.qual,
          'with_check', p.with_check
        ) ORDER BY p.schemaname, p.tablename, p.policyname
      ), '[]'::jsonb)
      FROM pg_policies p
      WHERE p.schemaname IN ('public', 'psicobloom_interno', 'storage')
    ),
    '8_permisos_tablas_y_columnas', (
      SELECT jsonb_build_object(
        'tablas', (
          SELECT coalesce(jsonb_agg(
            jsonb_build_object(
              'esquema', g.table_schema,
              'grantee', g.grantee,
              'tabla', g.table_name,
              'privilegio', g.privilege_type
            ) ORDER BY g.table_schema, g.table_name, g.grantee, g.privilege_type
          ), '[]'::jsonb)
          FROM information_schema.role_table_grants g
          WHERE g.table_schema IN ('public', 'psicobloom_interno')
            AND g.grantee IN ('anon', 'authenticated', 'PUBLIC')
        ),
        'columnas', (
          SELECT coalesce(jsonb_agg(
            jsonb_build_object(
              'esquema', cg.table_schema,
              'grantee', cg.grantee,
              'tabla', cg.table_name,
              'columna', cg.column_name,
              'privilegio', cg.privilege_type
            ) ORDER BY cg.table_schema, cg.table_name, cg.column_name, cg.grantee
          ), '[]'::jsonb)
          FROM information_schema.role_column_grants cg
          WHERE cg.table_schema IN ('public', 'psicobloom_interno')
            AND cg.grantee IN ('anon', 'authenticated', 'PUBLIC')
        )
      )
    ),
    '9_buckets_storage', (
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'name', b.name,
          'public', b.public,
          'file_size_limit', b.file_size_limit,
          'allowed_mime_types', b.allowed_mime_types
        ) ORDER BY b.id
      ), '[]'::jsonb)
      FROM storage.buckets b
    )
  )
) AS exportacion_esquema_psicobloom;
