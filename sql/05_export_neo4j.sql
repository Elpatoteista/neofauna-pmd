-- Exporta un SUBCONJUNTO (un país y un rango de años) a CSV para Neo4j (carpeta resultados/neo4j_import).
-- PostGIS hace todo lo espacial antes del grafo: celda de coocurrencia, zona urbana y "fuera de área protegida".
--   uso: psql -v tabla=obs_chile -v pais=CL -v desde=2024 -v hasta=2025 -v celda_km=5 -f 05_export_neo4j.sql
\timing on
SELECT to_regclass('public.wdpa_sub') IS NOT NULL AS hay_wdpa \gset

DROP TABLE IF EXISTS neo_obs;
CREATE UNLOGGED TABLE neo_obs AS
SELECT o.gbifid, o.specieskey, o.species, o.recordedby, o.year, o.month, o.estacion, o.geom,
       floor(ST_X(ST_Transform(o.geom, 6933)) / (:celda_km * 1000))::int || '_' ||
       floor(ST_Y(ST_Transform(o.geom, 6933)) / (:celda_km * 1000))::int AS celda,
       (SELECT u.id FROM urbano u WHERE ST_Intersects(u.geom, o.geom) LIMIT 1) AS urbano_id,
       NULL::boolean AS fuera_ap
FROM :tabla o
WHERE o.countrycode = :'pais' AND o.year BETWEEN :desde AND :hasta
  AND o.specieskey IS NOT NULL AND o.recordedby IS NOT NULL;
CREATE INDEX ON neo_obs USING gist (geom);

\if :hay_wdpa
  -- Dentro de un área protegida = intersecta algún polígono WDPA vigente (no "Proposed")
  UPDATE neo_obs n SET fuera_ap = NOT EXISTS (SELECT 1 FROM wdpa_sub w WHERE ST_Intersects(w.geom, n.geom));
\else
  \echo 'AVISO: no hay tabla wdpa; fuera_ap queda vacío (pregunta 1 incompleta)'
\endif
ANALYZE neo_obs;

-- ---- Observaciones ---------------------------------------------------------------------------------------
COPY (SELECT gbifid, specieskey, recordedby, year, month, estacion, celda, urbano_id, fuera_ap FROM neo_obs)
TO '/resultados/neo4j_import/obs.csv' WITH (FORMAT csv, HEADER true);

-- ---- Celdas (lugar): centroide y si es urbana --------------------------------------------------------------
COPY (SELECT celda, bool_or(urbano_id IS NOT NULL) AS urbana, min(urbano_id) AS urbano_id,
             round(avg(ST_Y(geom))::numeric, 4) AS lat, round(avg(ST_X(geom))::numeric, 4) AS lon
      FROM neo_obs GROUP BY celda)
TO '/resultados/neo4j_import/celdas.csv' WITH (FORMAT csv, HEADER true);

-- ---- Taxones: especies observadas + todos sus ancestros (jerarquía COL de la tabla de taxones) -------------
DROP TABLE IF EXISTS neo_tax;
CREATE UNLOGGED TABLE neo_tax AS
SELECT t.* FROM taxones t WHERE t.taxonkey IN (SELECT DISTINCT specieskey FROM neo_obs);

COPY (
  WITH niveles(rango, k, nombre) AS (
    SELECT 'SPECIES', taxonkey, species FROM neo_tax UNION
    SELECT 'GENUS',   genuskey, genus   FROM neo_tax UNION
    SELECT 'FAMILY',  familykey, family FROM neo_tax UNION
    SELECT 'ORDER',   orderkey, "order" FROM neo_tax UNION
    SELECT 'CLASS',   classkey, class   FROM neo_tax UNION
    SELECT 'PHYLUM',  phylumkey, phylum FROM neo_tax UNION
    SELECT 'KINGDOM', kingdomkey, kingdom FROM neo_tax)
  SELECT DISTINCT ON (k) k AS taxonkey, nombre, rango,
         (SELECT iucn FROM neo_tax x WHERE x.taxonkey = niveles.k) AS iucn
  FROM niveles WHERE k IS NOT NULL
  UNION ALL
  -- Especies observadas que NO están en la tabla de taxones (≈6 % de las claves): nodo sin jerarquía ni IUCN,
  -- con el nombre que trae la observación. Sin esto sus observaciones se perderían en el MATCH de la carga.
  SELECT DISTINCT ON (specieskey) specieskey, species, 'SPECIES', NULL
  FROM neo_obs WHERE specieskey NOT IN (SELECT taxonkey FROM taxones)
  ORDER BY 1)
TO '/resultados/neo4j_import/taxones.csv' WITH (FORMAT csv, HEADER true);

-- Aristas hijo -> padre saltando niveles vacíos (p.ej. especie sin género asignado)
COPY (
  SELECT DISTINCT hijo, padre FROM (
    SELECT taxonkey AS hijo, coalesce(genuskey, familykey, orderkey, classkey, phylumkey, kingdomkey) AS padre FROM neo_tax UNION ALL
    SELECT genuskey,  coalesce(familykey, orderkey, classkey, phylumkey, kingdomkey) FROM neo_tax UNION ALL
    SELECT familykey, coalesce(orderkey, classkey, phylumkey, kingdomkey) FROM neo_tax UNION ALL
    SELECT orderkey,  coalesce(classkey, phylumkey, kingdomkey) FROM neo_tax UNION ALL
    SELECT classkey,  coalesce(phylumkey, kingdomkey) FROM neo_tax UNION ALL
    SELECT phylumkey, kingdomkey FROM neo_tax) a
  WHERE hijo IS NOT NULL AND padre IS NOT NULL AND hijo <> padre)
TO '/resultados/neo4j_import/jerarquia.csv' WITH (FORMAT csv, HEADER true);

-- ---- Estatus de introducción (GRIIS) en el país del subconjunto -------------------------------------------
COPY (SELECT DISTINCT g.specieskey, g.countrycode, g.invasora
      FROM griis g JOIN neo_tax t ON t.taxonkey = g.specieskey WHERE g.countrycode = :'pais')
TO '/resultados/neo4j_import/introducidas.csv' WITH (FORMAT csv, HEADER true);

\echo '== Tamaño del subconjunto exportado =='
SELECT :'pais' AS pais, :desde || '-' || :hasta AS anios, count(*) AS observaciones,
       count(DISTINCT specieskey) AS especies, count(DISTINCT recordedby) AS observadores,
       count(DISTINCT celda) AS celdas, count(*) FILTER (WHERE urbano_id IS NOT NULL) AS obs_urbanas,
       count(*) FILTER (WHERE fuera_ap) AS obs_fuera_ap
FROM neo_obs;
