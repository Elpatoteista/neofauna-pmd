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

-- La lista de especies de GBIF tiene una fila por NOMBRE CON QUE SE IDENTIFICÓ cada observación, no por especie
-- aceptada: si todas las observaciones de una especie usan un sinónimo (p.ej. la rana toro identificada como
-- "Lithobates catesbeianus"), la especie aceptada (Aquarana catesbeiana, la speciesKey de las observaciones) no
-- tiene fila propia y el join por taxonKey la pierde. Se agrega una fila DERIVADA por cada speciesKey sin fila,
-- con la jerarquía de la fila de origen (sinónimo o subespecie). La IUCN queda vacía: la lista solo trae la
-- categoría del nombre usado (NE en los sinónimos), no la de la especie aceptada.
INSERT INTO taxones (taxonkey, scientificname, acceptedtaxonkey, acceptedscientificname, numberofoccurrences,
                     taxonrank, taxonomicstatus, kingdom, kingdomkey, phylum, phylumkey, class, classkey,
                     "order", orderkey, family, familykey, genus, genuskey, species, specieskey, iucn)
SELECT DISTINCT ON (x.specieskey)
       x.specieskey, x.species, x.specieskey, x.species,
       sum(x.numberofoccurrences) OVER (PARTITION BY x.specieskey),
       'SPECIES', 'DERIVADA', x.kingdom, x.kingdomkey, x.phylum, x.phylumkey, x.class, x.classkey,
       x."order", x.orderkey, x.family, x.familykey, x.genus, x.genuskey, x.species, x.specieskey, NULL
FROM taxones x
WHERE x.specieskey IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM taxones y WHERE y.taxonkey = x.specieskey)
ORDER BY x.specieskey, (x.taxonrank = 'SPECIES') DESC, x.numberofoccurrences DESC NULLS LAST;

CREATE INDEX ON taxones (species);
CREATE INDEX taxones_canon_ix ON taxones ((split_part(scientificname, ' ', 1) || ' ' || split_part(scientificname, ' ', 2)));
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
       t.specieskey
FROM (SELECT *, initcap(split_part(trim(scientificname), ' ', 1)) || ' ' ||
                lower(split_part(trim(scientificname), ' ', 2)) AS canon
      FROM griis_raw
      WHERE lower(taxonrank) = 'species'
        -- Los checklists SUBNACIONALES comparten countryCode con el país pero listan especies introducidas
        -- solo en esa isla/estado (p.ej. el zorzal o el maqui, nativos de Chile continental, son introducidos
        -- en Juan Fernández). Se excluyen para no marcar nativas como introducidas a nivel de país.
        AND pais NOT IN ('Juan Fernandez Islands, Chile', 'Alaska, United States')) g
-- El nombre GRIIS calza con el nombre ACEPTADO (columna species) o con el nombre usado, que puede ser un
-- sinónimo (scientificName sin autoría): GRIIS de AR, CO, PE… escribe "Lithobates catesbeianus", sinónimo de
-- Aquarana catesbeiana. Se toma la speciesKey aceptada. Nombres que la lista no trae ("Rana catesbeiana")
-- siguen sin calzar: resolverlos exige los sinónimos completos de Catalogue of Life.
LEFT JOIN LATERAL (SELECT t.specieskey FROM taxones t
                   WHERE t.taxonrank = 'SPECIES' AND t.specieskey IS NOT NULL
                     AND (t.species = g.canon
                          OR split_part(t.scientificname, ' ', 1) || ' ' || split_part(t.scientificname, ' ', 2) = g.canon)
                   ORDER BY (t.species = g.canon) DESC, (t.taxonomicstatus = 'ACCEPTED') DESC,
                            t.numberofoccurrences DESC NULLS LAST
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
