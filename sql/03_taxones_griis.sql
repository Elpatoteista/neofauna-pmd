-- Tabla de taxones de GBIF (Catalogue of Life) y registro GRIIS de especies introducidas de América.
--   uso: psql -v csv_taxones=/datos/'Datos GBIF - taxones y ocurrencias.csv' -f 03_taxones_griis.sql
\timing on

-- ---- Taxones: una fila por taxón, claves alfanuméricas COL; iucn = categoría de la Lista Roja ----------
DROP TABLE IF EXISTS taxones CASCADE;
CREATE TABLE taxones (
    taxonkey text PRIMARY KEY, scientificname text, acceptedtaxonkey text, acceptedscientificname text,
    numberofoccurrences bigint, taxonrank text, taxonomicstatus text,
    kingdom text, kingdomkey text, phylum text, phylumkey text, class text, classkey text,
    "order" text, orderkey text, family text, familykey text, genus text, genuskey text,
    species text, specieskey text, iucn text
);
\set copy_tax 'COPY taxones FROM ' :'csv_taxones' ' WITH (FORMAT csv, DELIMITER E''\t'', QUOTE E''\x01'', NULL '''', HEADER true)'
:copy_tax;
CREATE INDEX ON taxones (species);
CREATE INDEX ON taxones (iucn) WHERE iucn IN ('VU', 'EN', 'CR');
ANALYZE taxones;

-- ---- GRIIS -------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS griis_raw, griis CASCADE;
CREATE TABLE griis_raw (pais text, countrycode char(2), datasetkey text, scientificname text,
    acceptednameusage text, taxonrank text, kingdom text, establishmentmeans text, occurrencestatus text,
    isinvasive text, habitat text);
COPY griis_raw FROM '/capas/griis/griis_america.tsv' WITH (FORMAT csv, DELIMITER E'\t', QUOTE E'\x01', NULL '', HEADER true);

-- Normalización: nombre canónico = género + epíteto (sin autoría), rango especie, invasora sí/no.
-- Se cruza con la tabla de taxones por nombre canónico para obtener la specieskey de COL (la que trae cada
-- observación). Es el cruce "por nombre científico" que la propuesta identificó como riesgo; se mide abajo.
CREATE TABLE griis AS
SELECT DISTINCT ON (g.countrycode, canon)
       g.countrycode, g.pais, canon AS especie,
       bool_or(lower(coalesce(g.isinvasive, '')) LIKE 'invasive%')
           OVER (PARTITION BY g.countrycode, canon) AS invasora,
       t.taxonkey AS specieskey
FROM (SELECT *, initcap(split_part(trim(scientificname), ' ', 1)) || ' ' ||
                lower(split_part(trim(scientificname), ' ', 2)) AS canon
      FROM griis_raw
      WHERE lower(taxonrank) = 'species'
        -- Los checklists SUBNACIONALES comparten countryCode con el país pero listan especies introducidas
        -- solo en esa isla/estado (p.ej. el zorzal o el maqui, nativos de Chile continental, son introducidos
        -- en Juan Fernández). Se excluyen para no marcar nativas como introducidas a nivel de país.
        AND pais NOT IN ('Juan Fernandez Islands, Chile', 'Alaska, United States')) g
LEFT JOIN LATERAL (SELECT taxonkey FROM taxones t
                   WHERE t.species = g.canon AND t.taxonrank = 'SPECIES'
                   ORDER BY (t.taxonomicstatus = 'ACCEPTED') DESC, t.numberofoccurrences DESC NULLS LAST
                   LIMIT 1) t ON true
ORDER BY g.countrycode, canon;
CREATE INDEX ON griis (specieskey, countrycode);
ANALYZE griis;

\echo '== Cruce GRIIS <-> taxones COL por nombre canónico =='
SELECT count(*) AS registros_pais_especie,
       count(DISTINCT especie) AS especies_distintas,
       count(*) FILTER (WHERE specieskey IS NOT NULL) AS con_specieskey,
       round(100.0 * count(*) FILTER (WHERE specieskey IS NOT NULL) / count(*), 1) AS pct_match,
       count(*) FILTER (WHERE invasora) AS marcadas_invasoras
FROM griis;
