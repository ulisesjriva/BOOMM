-- Ejecutar una vez en SQL Editor. Solo agrega infraestructura interna.
-- 1 unidad = 0,25 creditos: PNG 256px = 1; geocodificacion simple = 4.
-- Techo conservador de 2500 creditos para TODA la app en una ventana de
-- al menos 24 horas. Incluye intentos fallidos: nunca devuelve unidades.
BEGIN;
CREATE SCHEMA IF NOT EXISTS psicobloom_interno;
CREATE TABLE IF NOT EXISTS psicobloom_interno.consumo_geoapify (
  hora timestamptz PRIMARY KEY,
  unidades integer NOT NULL DEFAULT 0 CHECK (unidades >= 0),
  segundo timestamptz NOT NULL,
  unidades_segundo integer NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS psicobloom_interno.limites_geoapify_usuario (
  id_usuario uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  minuto timestamptz NOT NULL,
  unidades integer NOT NULL DEFAULT 0,
  busquedas integer NOT NULL DEFAULT 0
);
ALTER TABLE psicobloom_interno.consumo_geoapify ENABLE ROW LEVEL SECURITY;
ALTER TABLE psicobloom_interno.limites_geoapify_usuario ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON psicobloom_interno.consumo_geoapify,
  psicobloom_interno.limites_geoapify_usuario FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.reservar_consumo_geoapify(
  p_id_usuario uuid, p_operacion text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  instante timestamptz := clock_timestamp();
  hora_actual timestamptz := date_trunc('hour', instante);
  segundo_actual timestamptz := date_trunc('second', instante);
  minuto_actual timestamptz := date_trunc('minute', instante);
  costo integer;
  total integer;
  contador psicobloom_interno.limites_geoapify_usuario%ROWTYPE;
  consumo psicobloom_interno.consumo_geoapify%ROWTYPE;
BEGIN
  IF p_operacion NOT IN ('tesela', 'buscar') OR p_operacion IS NULL THEN
    RAISE EXCEPTION 'Operacion invalida' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM psicobloom_interno.perfiles_compat
    WHERE id = p_id_usuario AND cuenta_activa AND rol IN ('paciente','profesional','administrador')) THEN
    RETURN 'cuenta_no_activa';
  END IF;
  costo := CASE WHEN p_operacion = 'tesela' THEN 1 ELSE 4 END;
  -- Orden unico de bloqueo: serializa reservas y evita sobrepasar el techo
  -- con peticiones simultaneas o varias instancias de la Edge Function.
  PERFORM pg_advisory_xact_lock(198610, 19);
  DELETE FROM psicobloom_interno.consumo_geoapify WHERE hora < hora_actual - interval '48 hours';
  SELECT coalesce(sum(unidades),0) INTO total
    FROM psicobloom_interno.consumo_geoapify
    WHERE hora >= hora_actual - interval '24 hours';
  IF total + costo > 10000 THEN RETURN 'cuota_global'; END IF;

  INSERT INTO psicobloom_interno.consumo_geoapify(hora,segundo)
    VALUES(hora_actual,segundo_actual) ON CONFLICT DO NOTHING;
  SELECT * INTO consumo FROM psicobloom_interno.consumo_geoapify WHERE hora = hora_actual;
  IF consumo.segundo = segundo_actual AND consumo.unidades_segundo + costo > 16 THEN
    RETURN 'limite_segundo';
  END IF;
  INSERT INTO psicobloom_interno.limites_geoapify_usuario(id_usuario,minuto)
    VALUES(p_id_usuario,minuto_actual) ON CONFLICT DO NOTHING;
  SELECT * INTO contador FROM psicobloom_interno.limites_geoapify_usuario WHERE id_usuario = p_id_usuario;
  IF contador.minuto = minuto_actual AND
    (contador.unidades + costo > 240 OR (p_operacion = 'buscar' AND contador.busquedas >= 6)) THEN
    RETURN 'limite_usuario';
  END IF;
  UPDATE psicobloom_interno.consumo_geoapify SET
    unidades = unidades + costo,
    unidades_segundo = CASE WHEN segundo = segundo_actual THEN unidades_segundo ELSE 0 END + costo,
    segundo = segundo_actual WHERE hora = hora_actual;
  UPDATE psicobloom_interno.limites_geoapify_usuario SET
    unidades = CASE WHEN minuto = minuto_actual THEN unidades ELSE 0 END + costo,
    busquedas = CASE WHEN minuto = minuto_actual THEN busquedas ELSE 0 END
      + CASE WHEN p_operacion = 'buscar' THEN 1 ELSE 0 END,
    minuto = minuto_actual WHERE id_usuario = p_id_usuario;
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.reservar_consumo_geoapify(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reservar_consumo_geoapify(uuid,text) TO service_role;
COMMIT;
