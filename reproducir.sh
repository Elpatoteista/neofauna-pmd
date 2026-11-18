#!/usr/bin/env bash
# Reproduce TODO el proyecto desde cero, en orden:
#   capas complementarias -> PostGIS (Chile y América) -> capas -> Q3, Q2, Q1 en PostGIS -> Neo4j -> mapas
#
#   uso: ./reproducir.sh                 (Neo4j: solo la etapa final, Chile 2015–2026)
#        ETAPAS=todas ./reproducir.sh    (Neo4j: las 5 etapas del informe, ~25 min más)
#
# Requisitos (ver README): Docker Desktop, Python 3 con matplotlib y networkx, y en $DATOS_DIR (.env) los CSV/ZIP de
# GBIF. La WDPA debe estar en datos/capas/wdpa/ (requiere aceptar términos en protectedplanet.net).
# Es idempotente: cada paso recrea sus tablas. NO borra volúmenes (para eso: docker compose down -v).
# Bitácora con tiempos: resultados/reproducir_log.txt
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
export MSYS_NO_PATHCONV=1
PY=${PYTHON:-python}
LOG=resultados/reproducir_log.txt
mkdir -p resultados mapas datos/capas/naturalearth datos/capas/wdpa
: > "$LOG"
T0=$(date +%s)
paso() { echo "[$(date '+%F %T')] (+$(( $(date +%s) - T0 )) s) $*" | tee -a "$LOG"; }
PSQL="docker compose exec -T postgis psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres"

# ---- 0. Verificación de fuentes ---------------------------------------------------------------------------
paso "0. Fuentes"
for f in "$CSV_CHILE" "${CSV_AMERICA%%/*}.zip" "$CSV_TAXONES"; do
  [[ -s "$DATOS_DIR/$f" ]] || { echo "⛔ Falta $DATOS_DIR/$f (ver README, sección Datos)" >&2; exit 1; }
done
if ! ls datos/capas/wdpa/*Public.zip >/dev/null 2>&1 || ls datos/capas/wdpa/*Public.zip | grep -q _csv; then
  echo "⛔ Falta la WDPA (File Geodatabase) en datos/capas/wdpa/ — ver README" >&2; exit 1
fi
[[ -s datos/capas/griis/griis_america.tsv ]] || { paso "   bajando GRIIS"; $PY scripts/bajar_griis.py > resultados/griis_checklists.txt 2> resultados/griis_resumen.txt; }
if [[ ! -s datos/capas/naturalearth/ne_10m_urban_areas.shp ]]; then
  paso "   bajando Natural Earth urban areas (13 MB)"
  curl -sSfL -o datos/capas/naturalearth/ne_10m_urban_areas.zip https://naciscdn.org/naturalearth/10m/cultural/ne_10m_urban_areas.zip
  (cd datos/capas/naturalearth && unzip -o -q ne_10m_urban_areas.zip)
fi

# ---- 1. Bases ---------------------------------------------------------------------------------------------
paso "1. docker compose up (build)"
docker compose up -d --build --wait 2>&1 | tail -3 | tee -a "$LOG"

# ---- 2. Observaciones en PostGIS --------------------------------------------------------------------------
paso "2a. PostGIS: Chile";   ./cargar_postgis.sh chile   > resultados/carga_chile_consola.txt 2>&1
paso "2b. PostGIS: América"; ./cargar_postgis.sh america > resultados/carga_america_consola.txt 2>&1
grep -hE "COPY terminado|Índices" resultados/tiempos_carga_*.txt | tee -a "$LOG"

# ---- 3. Capas -----------------------------------------------------------------------------------------------
paso "3. Capas (taxones, GRIIS, Natural Earth, WDPA)"; ./cargar_capas.sh > resultados/capas_consola.txt 2>&1

# ---- 4. Consultas PostGIS -----------------------------------------------------------------------------------
paso "4a. Q3 Chile (25 km)"
$PSQL -v tabla=obs_chile -v celda_km=25 -v desde=2021 -v hasta=2025 -v top=15 -f /sql/q3_hotspots_riqueza.sql > resultados/q3_chile.txt 2>&1
paso "4b. Q3 América (50 km)"
$PSQL -v tabla=obs_america -v celda_km=50 -v desde=2021 -v hasta=2025 -v top=20 -f /sql/q3_hotspots_riqueza.sql > resultados/q3_america.txt 2>&1
paso "4c. Q2 Chile";   $PSQL -v tabla=obs_chile   -v top=20 -f /sql/q2_invasoras_urbanas.sql > resultados/q2_postgis_chile.txt 2>&1
paso "4d. Q2 América"; $PSQL -v tabla=obs_america -v top=25 -f /sql/q2_invasoras_urbanas.sql > resultados/q2_postgis_america.txt 2>&1
paso "4e. Q1 América"; $PSQL -v tabla=obs_america -v top=30 -f /sql/q1_amenazadas_fuera_ap.sql > resultados/q1_postgis_america.txt 2>&1

# ---- 5. Neo4j por etapas ------------------------------------------------------------------------------------
if [[ "${ETAPAS:-final}" == "todas" ]]; then
  ETAPAS_LISTA=("obs_chile CL 2024 2025" "obs_chile CL 2015 2026" "obs_america AR 1900 2026" "obs_america MX 2021 2025"
                "obs_chile CL 2015 2026")
else
  ETAPAS_LISTA=("obs_chile CL 2015 2026")
fi
for e in "${ETAPAS_LISTA[@]}"; do
  paso "5. Neo4j: $e"; ./cargar_neo4j.sh $e > "resultados/neo4j_$(echo $e | cut -d' ' -f2-4 | tr ' ' _)_consola.txt" 2>&1
done

# ---- 6. Mapas -----------------------------------------------------------------------------------------------
paso "6. Mapas"
$PY scripts/mapas.py obs_america && $PY scripts/mapas.py obs_chile && $PY scripts/mapas_q1_q2.py

paso "Listo. Tamaños:"
$PSQL -c "SELECT relname AS tabla, pg_size_pretty(pg_total_relation_size(oid)) AS total FROM pg_class
          WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace ORDER BY pg_total_relation_size(oid) DESC LIMIT 12" | tee -a "$LOG"
docker system df -v 2>/dev/null | grep -E "^neofauna-(pgdata|neo4j)" | tee -a "$LOG"
paso "FIN (total $(( $(date +%s) - T0 )) s)"
