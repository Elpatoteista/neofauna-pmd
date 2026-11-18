#!/usr/bin/env bash
# Capas complementarias -> PostGIS (todas en EPSG:4326):
#   taxones   : tabla de taxones GBIF (jerarquía + iucnRedListCategory)        <- $DATOS_DIR/$CSV_TAXONES
#   griis     : GRIIS de los países de América (scripts/bajar_griis.py)          <- datos/capas/griis/griis_america.tsv
#   urbano    : Natural Earth 10m Urban Areas                                     <- datos/capas/naturalearth/*.shp
#   wdpa      : áreas protegidas WDPA/WDPCA de América (si el .gdb/.zip está)     <- datos/capas/wdpa/*
# uso: ./cargar_capas.sh
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
export MSYS_NO_PATHCONV=1
PSQL="docker compose exec -T postgis psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres"
OGR="docker compose exec -T postgis ogr2ogr"
PG="PG:dbname=postgres user=postgres"
LOG=resultados/tiempos_capas.txt; : > "$LOG"
paso() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

paso "taxones"
$PSQL -f /sql/03_taxones_griis.sql -v csv_taxones="/datos/$CSV_TAXONES" 2>&1 | tee -a "$LOG"

paso "Natural Earth urban areas"
$OGR -f PostgreSQL "$PG" /capas/naturalearth/ne_10m_urban_areas.shp -nln urbano -overwrite \
     -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=id -t_srs EPSG:4326 -makevalid 2>&1 | tee -a "$LOG"

# File Geodatabase de Protected Planet (WDPA_<Mes><Año>_Public.zip, ~2 GB). Se lee directo del ZIP (/vsizip/).
WDPA=$(ls -1 datos/capas/wdpa/*Public.zip 2>/dev/null | grep -v _csv | head -1 || true)
if [[ -n "$WDPA" ]]; then
  SRC="/vsizip//capas/${WDPA#datos/capas/}/$(basename "$WDPA" .zip).gdb"
  CAPA=$(docker compose exec -T postgis ogrinfo -ro -q "$SRC" | grep -ioE 'WDPA_poly_[A-Za-z0-9]+' | head -1)
  paso "WDPA: $SRC  capa $CAPA  (solo polígonos que tocan la caja de América)"
  $OGR -f PostgreSQL "$PG" "$SRC" "$CAPA" -nln wdpa -overwrite -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom \
       -lco FID=id -lco SPATIAL_INDEX=NONE -lco LAUNDER=YES -t_srs EPSG:4326 -makevalid \
       -spat -180 -60 -20 84 \
       -select SITE_ID,SITE_TYPE,NAME,DESIG_ENG,IUCN_CAT,REALM,STATUS,STATUS_YR,ISO3,GIS_AREA \
       --config PG_USE_COPY YES 2>&1 | tail -3 | tee -a "$LOG"
else
  paso "WDPA: no hay archivo en datos/capas/wdpa/ (descargar desde protectedplanet.net, ver README)"
fi

paso "Índices, recortes a América y validación"
$PSQL -f /sql/04_capas_indices.sql 2>&1 | tee -a "$LOG"
paso "Listo"
