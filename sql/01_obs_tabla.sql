-- Tabla de observaciones (una por región: obs_chile, obs_america). Se crea VACÍA y SIN índices;
-- cargar_postgis.sh hace el COPY en la MISMA transacción, así con wal_level=minimal no se escribe WAL.
-- Solo 23 de las 50 columnas del CSV "Simple" de GBIF (las que usan las 3 preguntas).
--   uso: psql -v tabla=obs_chile -f 01_obs_tabla.sql      (dentro de BEGIN ... COPY ... COMMIT)
DROP TABLE IF EXISTS :tabla CASCADE;
CREATE TABLE :tabla (
    gbifid              bigint      NOT NULL,
    kingdom             text,
    phylum              text,
    class               text,
    "order"             text,
    family              text,
    genus               text,
    species             text,
    taxonrank           text,
    scientificname      text,
    countrycode         char(2),
    stateprovince       text,
    lat                 double precision NOT NULL,
    lon                 double precision NOT NULL,
    coord_incert_m      real,
    eventdate           text,          -- texto ISO tal cual viene (a veces sin segundos o con rangos)
    day                 smallint,
    month               smallint,
    year                smallint,
    taxonkey            text,          -- claves Catalogue of Life: alfanuméricas (p.ej. '42KZ5'), NO enteras
    specieskey          text,
    recordedby          text,
    establishmentmeans  text,
    -- Columnas derivadas, calculadas durante el COPY (sin reescribir la tabla después)
    geom   geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED,
    -- Hemisferio por latitud y estación meteorológica según hemisferio (pregunta 3)
    hemisferio char(1) GENERATED ALWAYS AS (CASE WHEN lat >= 0 THEN 'N' ELSE 'S' END) STORED,
    estacion   text GENERATED ALWAYS AS (
        -- Estaciones meteorológicas (DEF / MAM / JJA / SON), invertidas en el hemisferio sur
        CASE WHEN month IS NULL THEN NULL
             WHEN lat >= 0 THEN CASE WHEN month IN (12, 1, 2) THEN 'invierno'
                                     WHEN month IN (3, 4, 5)  THEN 'primavera'
                                     WHEN month IN (6, 7, 8)  THEN 'verano'
                                     ELSE 'otono' END
             ELSE               CASE WHEN month IN (12, 1, 2) THEN 'verano'
                                     WHEN month IN (3, 4, 5)  THEN 'otono'
                                     WHEN month IN (6, 7, 8)  THEN 'invierno'
                                     ELSE 'primavera' END
        END) STORED
);
