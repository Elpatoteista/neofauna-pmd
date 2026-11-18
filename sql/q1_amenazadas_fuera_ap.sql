-- PREGUNTA 1 — parte PostGIS (conjunto completo)
-- ¿Qué especies con estatus IUCN VU, EN o CR tienen observaciones FUERA de áreas protegidas?
-- (la conexión taxonómica y por comunidades de observadores la resuelve Neo4j: cypher/q1_amenazadas.cypher)
--
-- * La categoría IUCN viene de la tabla de taxones (el CSV de ocurrencias no la trae): join por specieskey.
-- * Primero se filtran las observaciones amenazadas (pocas) y solo esas se prueban contra los polígonos WDPA:
--   NOT EXISTS (ST_Intersects) con índice GiST. Se excluyen las áreas con estado 'Proposed'.
--   uso: psql -v tabla=obs_america -v top=30 -f q1_amenazadas_fuera_ap.sql
\timing on
\set am :tabla _amenazadas

DROP TABLE IF EXISTS :am;
-- introducida = la especie está en el GRIIS del país de la observación. Una especie amenazada en su área
-- nativa pero introducida/cultivada en ese país (p.ej. Hibiscus rosa-sinensis, Oxalis corniculata) no es una
-- población de interés de conservación ahí: esas observaciones se cuentan aparte y se excluyen de los rankings.
CREATE TABLE :am AS
SELECT o.gbifid, o.specieskey, t.species, t.iucn, t.kingdom, t.class, t.family, o.countrycode, o.recordedby, o.geom,
       EXISTS (SELECT 1 FROM griis g WHERE g.specieskey = o.specieskey AND g.countrycode = o.countrycode) AS introducida
FROM :tabla o JOIN taxones t ON t.taxonkey = o.specieskey
WHERE t.iucn IN ('VU', 'EN', 'CR');
CREATE INDEX ON :am USING gist (geom);
ANALYZE :am;

ALTER TABLE :am ADD COLUMN fuera_ap boolean;
-- wdpa_sub = polígonos WDPA vigentes (sin 'Proposed') subdivididos, ver 04_capas_indices.sql
UPDATE :am a SET fuera_ap = NOT EXISTS (SELECT 1 FROM wdpa_sub w WHERE ST_Intersects(w.geom, a.geom));

\echo
\echo '== Resumen (sin observaciones de especies introducidas en ese país según GRIIS) =='
SELECT count(*) AS obs_amenazadas, count(DISTINCT specieskey) AS especies_amenazadas,
       count(*) FILTER (WHERE fuera_ap) AS obs_fuera_ap,
       count(DISTINCT specieskey) FILTER (WHERE fuera_ap) AS especies_con_obs_fuera_ap,
       round(100.0 * count(*) FILTER (WHERE fuera_ap) / count(*), 1) AS pct_obs_fuera_ap
FROM :am WHERE NOT introducida;
SELECT count(*) AS obs_excluidas_por_introducidas, count(DISTINCT specieskey) AS especies_excluidas
FROM :am WHERE introducida;

\echo
\echo '== Por categoría IUCN =='
SELECT iucn, count(DISTINCT specieskey) AS especies, count(*) AS obs,
       round(100.0 * count(*) FILTER (WHERE fuera_ap) / count(*), 1) AS pct_fuera_ap
FROM :am WHERE NOT introducida GROUP BY 1 ORDER BY array_position(ARRAY['CR', 'EN', 'VU'], iucn::text);

\echo
\echo '== Especies amenazadas con más observaciones fuera de áreas protegidas =='
SELECT species AS especie, iucn, class AS clase, family AS familia,
       count(*) FILTER (WHERE fuera_ap) AS obs_fuera_ap, count(*) AS obs,
       round(100.0 * count(*) FILTER (WHERE fuera_ap) / count(*), 1) AS pct_fuera,
       count(DISTINCT countrycode) FILTER (WHERE fuera_ap) AS paises
FROM :am WHERE NOT introducida GROUP BY 1, 2, 3, 4 ORDER BY obs_fuera_ap DESC LIMIT :top;

\echo
\echo '== Especies CR (en peligro crítico) observadas fuera de áreas protegidas =='
SELECT species AS especie, class AS clase, string_agg(DISTINCT countrycode, ',') AS paises,
       count(*) FILTER (WHERE fuera_ap) AS obs_fuera_ap, count(*) AS obs
FROM :am WHERE iucn = 'CR' AND NOT introducida GROUP BY 1, 2 HAVING count(*) FILTER (WHERE fuera_ap) > 0
ORDER BY obs_fuera_ap DESC LIMIT :top;
