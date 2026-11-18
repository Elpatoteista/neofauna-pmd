# PostgreSQL 16 + PostGIS 3 + herramientas para la carga masiva (misma base que la Tarea 1):
#   unzip     -> se lee el ZIP de GBIF directamente (14,9 GB) en vez del CSV descomprimido (59,7 GB)
#   gdal-bin  -> ogr2ogr para cargar WDPA (File Geodatabase) y Natural Earth (Shapefile)
FROM postgres:16-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16-postgis-3 postgis gdal-bin unzip procps \
 && rm -rf /var/lib/apt/lists/* \
 && echo "CREATE EXTENSION IF NOT EXISTS postgis;" > /docker-entrypoint-initdb.d/10_postgis.sql
