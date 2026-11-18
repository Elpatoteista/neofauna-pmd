-- Índices GiST, validación y CRS de las capas poligonales.
\timing on
CREATE INDEX IF NOT EXISTS urbano_geom_gix ON urbano USING gist (geom);
ANALYZE urbano;

\echo '== CRS y validez de las capas =='
SELECT 'urbano' AS capa, count(*) AS poligonos, min(ST_SRID(geom)) AS srid,
       count(*) FILTER (WHERE NOT ST_IsValid(geom)) AS invalidos,
       count(*) FILTER (WHERE geom && ST_MakeEnvelope(-170, -60, -25, 85, 4326)) AS en_america
FROM urbano;

DO $$
BEGIN
  IF to_regclass('public.wdpa') IS NOT NULL THEN
    -- WDPA de América: los puntos (sin polígono) no se usan; se descartan las propuestas (STATUS='Proposed')
    -- y las áreas solo marinas no se excluyen (las observaciones costeras pueden caer en ellas).
    -- Polígonos grandes y muy detallados: se SUBDIVIDEN (ST_Subdivide, máx. 256 vértices) para que el índice
    -- GiST filtre bien y cada ST_Intersects pruebe un trozo chico y no un polígono de cientos de miles de vértices.
    EXECUTE 'DROP TABLE IF EXISTS wdpa_sub';
    EXECUTE 'CREATE TABLE wdpa_sub AS SELECT id, site_id, status, ST_Subdivide(geom, 256) AS geom FROM wdpa
             WHERE status <> ''Proposed''';
    EXECUTE 'CREATE INDEX wdpa_sub_gix ON wdpa_sub USING gist (geom)';
    EXECUTE 'ANALYZE wdpa_sub';
  END IF;
END $$;

SELECT to_regclass('public.wdpa') IS NOT NULL AS hay_wdpa \gset
\if :hay_wdpa
SELECT 'wdpa' AS capa, count(*) AS poligonos, min(ST_SRID(geom)) AS srid,
       count(*) FILTER (WHERE NOT ST_IsValid(geom)) AS invalidos,
       count(*) FILTER (WHERE status = 'Proposed') AS propuestas,
       count(DISTINCT iso3) AS paises_iso3,
       (SELECT count(*) FROM wdpa_sub) AS trozos_subdivididos
FROM wdpa;
\endif
