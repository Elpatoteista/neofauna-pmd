-- Índices y estadísticas DESPUÉS de la carga (mucho más rápido que mantenerlos durante el COPY).
--   uso: psql -v tabla=obs_chile -f 02_obs_indices.sql
\timing on
\set pk :tabla _pk
\set gix :tabla _geom_gix
\set ixs :tabla _specieskey_ix
\set ixy :tabla _year_ix
SET maintenance_work_mem = '1GB';
SET max_parallel_maintenance_workers = 4;

ALTER TABLE :tabla ADD CONSTRAINT :pk PRIMARY KEY (gbifid);
CREATE INDEX :gix ON :tabla USING gist (geom);
CREATE INDEX :ixs ON :tabla (specieskey);
CREATE INDEX :ixy ON :tabla (year);
VACUUM (ANALYZE) :tabla;

SELECT :'tabla' AS tabla,
       pg_size_pretty(pg_table_size(:'tabla'))          AS datos,
       pg_size_pretty(pg_indexes_size(:'tabla'))        AS indices,
       pg_size_pretty(pg_total_relation_size(:'tabla')) AS total,
       (SELECT reltuples::bigint FROM pg_class WHERE oid = :'tabla'::regclass) AS filas_aprox;
