-- PREGUNTA 3 (PostGIS puro)
-- ¿Cuáles son los hotspots de riqueza de especies según observaciones research-grade de los últimos años,
-- y cómo cambia esa riqueza entre estaciones?
--
-- Método
--   * Riqueza = n.º de especies distintas (specieskey, Catalogue of Life) por celda.
--   * Celdas cuadradas de :celda_km km en EPSG:6933 (WGS84 / EASE-Grid 2.0, cilíndrica de IGUAL ÁREA): todas las
--     celdas tienen la misma superficie a cualquier latitud (una grilla en grados no, y sesgaría hacia el ecuador).
--   * "Últimos años" = :desde .. :hasta (años completos).
--   * Estación por hemisferio de cada observación (columna generada `estacion`, ver 01_obs_tabla.sql).
--   * El esfuerzo de muestreo (n.º de observaciones) se reporta junto a la riqueza: en datos de ciencia
--     ciudadana la riqueza observada crece con el esfuerzo, así que un hotspot debe leerse con esa columna.
--
--   uso: psql -v tabla=obs_chile -v celda_km=25 -v desde=2021 -v hasta=2025 -v top=20 -f q3_hotspots_riqueza.sql
\timing on
\set q3 :tabla _q3
\set q3e :tabla _q3_estacion

-- 1) Asignación de cada observación a su celda (una pasada sobre la tabla) -------------------------------
DROP TABLE IF EXISTS :q3, :q3e;
CREATE TABLE :q3e AS
SELECT floor(ST_X(p) / (:celda_km * 1000))::int AS i,
       floor(ST_Y(p) / (:celda_km * 1000))::int AS j,
       estacion,
       count(*)                    AS n_obs,
       count(DISTINCT specieskey)  AS riqueza,
       count(DISTINCT recordedby)  AS n_observadores
FROM (SELECT ST_Transform(geom, 6933) AS p, estacion, specieskey, recordedby
      FROM :tabla
      WHERE year BETWEEN :desde AND :hasta AND specieskey IS NOT NULL) s
GROUP BY ROLLUP (1, 2, 3);   -- incluye el total anual por celda (estacion IS NULL)

-- Total por celda (todas las estaciones) con su geometría en 4326 para mapear
CREATE TABLE :q3 AS
SELECT i, j, n_obs, riqueza, n_observadores,
       ST_Transform(ST_MakeEnvelope(i * :celda_km * 1000, j * :celda_km * 1000,
                                    (i + 1) * :celda_km * 1000, (j + 1) * :celda_km * 1000, 6933), 4326) AS geom
FROM :q3e WHERE estacion IS NULL AND j IS NOT NULL;
DELETE FROM :q3e WHERE estacion IS NULL;
CREATE INDEX ON :q3 USING gist (geom);
ANALYZE :q3; ANALYZE :q3e;

\echo
\echo '== Resumen de la grilla =='
SELECT :celda_km AS celda_km, :desde || '-' || :hasta AS periodo, count(*) AS celdas_con_datos,
       sum(n_obs) AS observaciones, max(riqueza) AS riqueza_max,
       round(avg(riqueza), 1) AS riqueza_media,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY riqueza) AS riqueza_mediana
FROM :q3;

\echo
\echo '== Top hotspots de riqueza (todas las estaciones) =='
SELECT rank() OVER (ORDER BY riqueza DESC) AS rk, i, j,
       round(ST_Y(ST_Centroid(geom))::numeric, 3) AS lat_centro,
       round(ST_X(ST_Centroid(geom))::numeric, 3) AS lon_centro,
       riqueza, n_obs, n_observadores,
       round(riqueza::numeric / n_obs, 3) AS especies_por_obs
FROM :q3 ORDER BY riqueza DESC LIMIT :top;

\echo
\echo '== Hotspots CORREGIDOS POR ESFUERZO: más especies de las esperadas para su n.º de observaciones =='
\echo '   (residuo de la regresión log(riqueza) ~ log(n_obs) entre celdas con >= 1000 observaciones)'
WITH c AS (SELECT * FROM :q3 WHERE n_obs >= 1000),
     r AS (SELECT regr_slope(ln(riqueza), ln(n_obs)) AS b, regr_intercept(ln(riqueza), ln(n_obs)) AS a,
                  regr_r2(ln(riqueza), ln(n_obs)) AS r2 FROM c)
SELECT i, j, round(ST_Y(ST_Centroid(geom))::numeric, 3) AS lat_centro, round(ST_X(ST_Centroid(geom))::numeric, 3) AS lon_centro,
       riqueza, n_obs, round(exp(a + b * ln(n_obs))) AS riqueza_esperada,
       round((riqueza / exp(a + b * ln(n_obs)))::numeric, 2) AS razon_obs_esperada,
       round(b::numeric, 3) AS pendiente, round(r2::numeric, 3) AS r2
FROM c, r ORDER BY ln(riqueza) - (a + b * ln(n_obs)) DESC LIMIT :top;

\echo
\echo '== Riqueza por estación en esos hotspots (y variación estacional) =='
WITH top AS (SELECT i, j, riqueza FROM :q3 ORDER BY riqueza DESC LIMIT :top),
     est AS (SELECT t.i, t.j, t.riqueza AS riqueza_anual,
                    max(e.riqueza) FILTER (WHERE e.estacion = 'verano')    AS verano,
                    max(e.riqueza) FILTER (WHERE e.estacion = 'otono')     AS otono,
                    max(e.riqueza) FILTER (WHERE e.estacion = 'invierno')  AS invierno,
                    max(e.riqueza) FILTER (WHERE e.estacion = 'primavera') AS primavera
             FROM top t JOIN :q3e e USING (i, j) GROUP BY 1, 2, 3)
SELECT i, j, riqueza_anual, verano, otono, invierno, primavera,
       round(greatest(verano, otono, invierno, primavera)::numeric
             / nullif(least(verano, otono, invierno, primavera), 0), 2) AS razon_max_min
FROM est ORDER BY riqueza_anual DESC;

\echo
\echo '== Cambio estacional agregado: celdas con datos en las 4 estaciones =='
WITH c4 AS (SELECT i, j FROM :q3e GROUP BY 1, 2 HAVING count(*) = 4)
SELECT e.estacion, count(*) AS celdas, sum(e.n_obs) AS observaciones,
       round(avg(e.riqueza), 1) AS riqueza_media, max(e.riqueza) AS riqueza_max
FROM :q3e e JOIN c4 USING (i, j)
GROUP BY 1 ORDER BY array_position(ARRAY['verano', 'otono', 'invierno', 'primavera'], e.estacion);

\echo
\echo '== Hotspot de cada estación (celda con mayor riqueza en esa estación) =='
SELECT DISTINCT ON (estacion) estacion, i, j, riqueza, n_obs
FROM :q3e ORDER BY estacion, riqueza DESC;
