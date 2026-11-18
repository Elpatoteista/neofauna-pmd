-- PREGUNTA 2 — parte PostGIS
-- ¿Qué especies invasoras aparecen en zonas urbanas? (la coocurrencia con nativas la resuelve Neo4j)
--
-- * Zona urbana = polígono de Natural Earth 10m Urban Areas (ST_Intersects punto-polígono, índice GiST).
-- * Especie introducida en el país de la observación = está en el GRIIS de ese país (griis.countrycode).
--   "invasora_estricta" = además GRIIS la marca isInvasive = invasive. Se reportan ambas definiciones.
-- * Nativa (para Neo4j) = especie observada que NO está en el GRIIS de ese país.
--   uso: psql -v tabla=obs_chile -v top=25 -f q2_invasoras_urbanas.sql
\timing on
\set urb :tabla _urbano

-- 1) Observaciones dentro de zonas urbanas (una fila por observación) ------------------------------------
DROP TABLE IF EXISTS :urb;
CREATE TABLE :urb AS
SELECT o.gbifid, u.id AS urbano_id, o.specieskey, o.countrycode,
       g.specieskey IS NOT NULL AS introducida,
       coalesce(g.invasora, false) AS invasora_estricta
FROM :tabla o
JOIN urbano u ON ST_Intersects(u.geom, o.geom)
LEFT JOIN griis g ON g.specieskey = o.specieskey AND g.countrycode = o.countrycode
WHERE o.specieskey IS NOT NULL;
CREATE INDEX ON :urb (gbifid);
ANALYZE :urb;

\echo
\echo '== Resumen: observaciones urbanas e introducidas =='
SELECT count(*) AS obs_urbanas,
       (SELECT count(*) FROM :tabla WHERE specieskey IS NOT NULL) AS obs_totales,
       count(DISTINCT urbano_id) AS zonas_urbanas,
       count(DISTINCT specieskey) AS especies_urbanas,
       count(DISTINCT specieskey) FILTER (WHERE introducida) AS especies_introducidas,
       count(DISTINCT specieskey) FILTER (WHERE invasora_estricta) AS especies_invasoras_estrictas,
       round(100.0 * count(*) FILTER (WHERE introducida) / count(*), 1) AS pct_obs_introducidas
FROM :urb;

\echo
\echo '== Especies introducidas (GRIIS) más observadas en zonas urbanas =='
SELECT t.species AS especie, t.kingdom AS reino, t.class AS clase, u.countrycode AS pais,
       bool_or(u.invasora_estricta) AS invasora_estricta,
       count(*) AS obs_urbanas, count(DISTINCT u.urbano_id) AS zonas_urbanas
FROM :urb u JOIN taxones t ON t.taxonkey = u.specieskey
WHERE u.introducida
GROUP BY 1, 2, 3, 4 ORDER BY obs_urbanas DESC LIMIT :top;

\echo
\echo '== Por país: obs. urbanas, n.º de introducidas y la introducida urbana más observada =='
\echo '   (EE.UU. domina los totales; el GRIIS de EE.UU. v2.0 no informa isInvasive, por eso "estricta" sale falso allí)'
WITH p AS (SELECT countrycode, specieskey, count(*) AS n FROM :urb WHERE introducida GROUP BY 1, 2),
     tot AS (SELECT countrycode, count(*) AS obs_urbanas FROM :urb GROUP BY 1)
SELECT tot.countrycode AS pais, tot.obs_urbanas, count(p.specieskey) AS especies_introducidas,
       (array_agg(t.species ORDER BY p.n DESC))[1] AS mas_observada, max(p.n) AS obs_de_esa
FROM tot LEFT JOIN p USING (countrycode) LEFT JOIN taxones t ON t.taxonkey = p.specieskey
GROUP BY 1, 2 HAVING tot.obs_urbanas >= 5000 ORDER BY tot.obs_urbanas DESC LIMIT :top;

\echo
\echo '== Zonas urbanas con más especies introducidas =='
-- Primero se agrega por zona (sin geometría) y recién al final se calcula centroide y área de las :top zonas
WITH z AS (SELECT urbano_id,
                  count(DISTINCT specieskey) FILTER (WHERE introducida) AS especies_introducidas,
                  count(DISTINCT specieskey) AS especies_totales, count(*) AS obs
           FROM :urb GROUP BY urbano_id ORDER BY especies_introducidas DESC LIMIT :top)
SELECT z.urbano_id, round(ST_Y(ST_Centroid(u.geom))::numeric, 2) AS lat, round(ST_X(ST_Centroid(u.geom))::numeric, 2) AS lon,
       round((ST_Area(u.geom::geography) / 1e6)::numeric, 0) AS km2,
       z.especies_introducidas, z.especies_totales, z.obs
FROM z JOIN urbano u ON u.id = z.urbano_id ORDER BY z.especies_introducidas DESC;
