#!/usr/bin/env bash
# Carga las observaciones de GBIF en PostGIS:  ./cargar_postgis.sh chile | america
#   - COPY masivo dentro de la misma transacción que crea la tabla (sin WAL, con wal_level=minimal)
#   - el CSV se lee DENTRO del contenedor (COPY ... FROM PROGRAM) y para América directamente desde el ZIP
#   - 23 de 50 columnas (cut), índices DESPUÉS de cargar
# Los tiempos de cada paso quedan en resultados/tiempos_carga_<region>.txt
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
export MSYS_NO_PATHCONV=1            # Git Bash en Windows: no traducir rutas /datos/...

REGION=${1:?uso: ./cargar_postgis.sh chile|america}
case "$REGION" in
  chile)   TABLA=obs_chile;   FUENTE="cat '/datos/$CSV_CHILE'" ;;
  america) TABLA=obs_america; FUENTE="unzip -p '/datos/${CSV_AMERICA%%/*}.zip'" ;;
  *) echo "región desconocida: $REGION" >&2; exit 1 ;;
esac
# Columnas del CSV Simple de GBIF (1-based), en el orden de la tabla (ver sql/01_obs_tabla.sql)
COLS="1,4,5,6,7,8,9,10,12,13,16,18,22,23,24,30,31,32,33,34,35,45,47"
PSQL="docker compose exec -T postgis psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres"
LOG=resultados/tiempos_carga_${REGION}.txt
: > "$LOG"
paso() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

docker compose up -d --wait postgis
paso "INICIO carga $REGION -> $TABLA  (fuente: $FUENTE)"
T0=$(date +%s)
# FORMAT csv con QUOTE = byte 0x01: GBIF no entrecomilla y así las barras invertidas se leen literales
$PSQL -v tabla="$TABLA" <<SQL 2>&1 | tee -a "$LOG"
\timing on
BEGIN;
\i /sql/01_obs_tabla.sql
COPY $TABLA (gbifid, kingdom, phylum, class, "order", family, genus, species, taxonrank, scientificname,
             countrycode, stateprovince, lat, lon, coord_incert_m, eventdate, day, month, year,
             taxonkey, specieskey, recordedby, establishmentmeans)
FROM PROGRAM \$\$ $FUENTE | tail -n +2 | cut -f $COLS \$\$
WITH (FORMAT csv, DELIMITER E'\t', QUOTE E'\x01', NULL '');
COMMIT;
SQL
T1=$(date +%s); paso "COPY terminado en $((T1 - T0)) s"

$PSQL -v tabla="$TABLA" -f /sql/02_obs_indices.sql 2>&1 | tee -a "$LOG"
T2=$(date +%s); paso "Índices + VACUUM ANALYZE en $((T2 - T1)) s   (total $((T2 - T0)) s)"
