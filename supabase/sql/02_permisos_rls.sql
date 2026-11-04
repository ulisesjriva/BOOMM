-- PSICOBLOOM: ejecutar despues de 01_estructura.sql. Sin cambios en Auth existente.
BEGIN;
REVOKE ALL ON public.perfiles, public.perfiles_profesionales,
    public.revisiones_profesionales, public.cambios_estado_cuenta
    FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.perfiles, public.perfiles_profesionales TO authenticated;
GRANT UPDATE(nombre, apellido) ON public.perfiles TO authenticated;
GRANT UPDATE(especialidad, numero_registro, descripcion, anios_experiencia,
    telefono_contacto, foto_url) ON public.perfiles_profesionales TO authenticated;
-- Las marcas de tiempo se actualizan mediante trigger, no desde Flutter.
-- Revisiones e historial: lectura administrativa protegida por RLS; escritura solo RPC.
GRANT SELECT ON public.revisiones_profesionales, public.cambios_estado_cuenta TO authenticated;

CREATE POLICY perfiles_leer_propio ON public.perfiles
FOR SELECT TO authenticated USING(id = (SELECT auth.uid()));
CREATE POLICY perfiles_leer_admin ON public.perfiles
FOR SELECT TO authenticated USING((SELECT public._rol_activo()) = 'administrador');
CREATE POLICY perfiles_editar_propio ON public.perfiles
FOR UPDATE TO authenticated
USING(id = (SELECT auth.uid()) AND cuenta_activa)
WITH CHECK(id = (SELECT auth.uid()) AND cuenta_activa);
-- No se autoriza al administrador a cambiar nombres ajenos arbitrariamente.

CREATE POLICY prof_leer_propio ON public.perfiles_profesionales
FOR SELECT TO authenticated USING(id = (SELECT auth.uid()));
CREATE POLICY prof_leer_admin ON public.perfiles_profesionales
FOR SELECT TO authenticated USING((SELECT public._rol_activo()) = 'administrador');
CREATE POLICY prof_editar_propio ON public.perfiles_profesionales
FOR UPDATE TO authenticated
USING(id = (SELECT auth.uid()) AND (SELECT public._rol_activo()) = 'profesional')
WITH CHECK(id = (SELECT auth.uid()) AND (SELECT public._rol_activo()) = 'profesional');

CREATE POLICY revisiones_leer_admin ON public.revisiones_profesionales
FOR SELECT TO authenticated USING((SELECT public._rol_activo()) = 'administrador');
CREATE POLICY cambios_leer_admin ON public.cambios_estado_cuenta
FOR SELECT TO authenticated USING((SELECT public._rol_activo()) = 'administrador');
-- No INSERT/DELETE directos. Auth crea perfiles; las RPC registran revisiones/cambios.
COMMIT;
