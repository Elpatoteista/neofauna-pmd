-- Experimentos de rendimiento para el informe (planes y tiempos). Requiere el pipeline completo cargado.
--   uso: psql -f experimentos.sql > resultados/experimentos.txt
\timing on
\pset pager off

\echo '===== E1. Punto en polígono contra la WDPA: polígonos enteros vs. ST_Subdivide(256) ====='
\echo '      (observaciones amenazadas de Chile y Brasil; mismo resultado, distinto costo)'
DROP TABLE IF EXISTS exp_pts;
CREATE TEMP TABLE exp_pts AS SELECT gbifid, geom FROM obs_america_amenazadas WHERE countrycode IN ('CL', 'BR');
CREATE INDEX ON exp_pts USING gist (geom); ANALYZE exp_pts;
SELECT count(*) AS puntos FROM exp_pts;
SELECT (SELECT round(avg(ST_NPoints(geom))) FROM wdpa)     AS vertices_medios_wdpa,
       (SELECT max(ST_NPoints(geom)) FROM wdpa)            AS vertices_max_wdpa,
       (SELECT round(avg(ST_NPoints(geom))) FROM wdpa_sub) AS vertices_medios_sub;
\echo '-- E1a polígonos enteros'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM wdpa w WHERE w.status <> 'Proposed' AND ST_Intersects(w.geom, p.geom)))
FROM exp_pts p;
\echo '-- E1b polígonos subdivididos'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM wdpa_sub w WHERE ST_Intersects(w.geom, p.geom)))
FROM exp_pts p;

\echo
\echo '===== E2. Cruce con zonas urbanas (Chile): con y sin índice GiST ====='
\echo '-- E2a con índices'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FROM obs_chile o JOIN urbano u ON ST_Intersects(u.geom, o.geom);
\echo '-- E2b sin índices (enable_indexscan / bitmapscan = off)'
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*) FROM obs_chile o JOIN urbano u ON ST_Intersects(u.geom, o.geom);
RESET enable_indexscan; RESET enable_bitmapscan;

\echo
\echo '===== E3. Q3: plan de la asignación a celdas (Chile, mismo SQL que América) ====='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT floor(ST_X(ST_Transform(geom, 6933)) / 25000)::int AS i, floor(ST_Y(ST_Transform(geom, 6933)) / 25000)::int AS j,
       estacion, count(DISTINCT specieskey)
FROM obs_chile WHERE year BETWEEN 2021 AND 2025 AND specieskey IS NOT NULL GROUP BY 1, 2, 3;

\echo
\echo '===== E4. Mitigación de la coocurrencia: pares de observaciones vs. pares de especies por celda (neo_obs = Chile 2015–2026) ====='
WITH c AS (SELECT celda, count(*) AS n_obs, count(DISTINCT specieskey) AS n_esp FROM neo_obs GROUP BY celda),
     u AS (SELECT celda, count(*) AS n_obs, count(DISTINCT specieskey) AS n_esp FROM neo_obs WHERE urbano_id IS NOT NULL GROUP BY celda)
SELECT 'todas las celdas' AS ambito, count(*) AS celdas, sum(n_obs) AS obs,
       sum(n_obs::numeric * (n_obs - 1) / 2) AS pares_de_observaciones,
       sum(n_esp::numeric * (n_esp - 1) / 2) AS pares_de_especies_por_celda,
       (SELECT sum(n::numeric * (n - 1) / 2) FROM (SELECT count(*) AS n FROM neo_obs) x) AS pares_obs_sin_celdas
FROM c
UNION ALL
SELECT 'celdas urbanas', count(*), sum(n_obs), sum(n_obs::numeric * (n_obs - 1) / 2), sum(n_esp::numeric * (n_esp - 1) / 2), NULL
FROM u;

\echo
\echo '===== E5. Índices: tamaño y uso real (pg_stat_user_indexes) ====='
SELECT relname AS tabla, indexrelname AS indice, idx_scan AS lecturas, pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes ORDER BY pg_relation_size(indexrelid) DESC LIMIT 15;
