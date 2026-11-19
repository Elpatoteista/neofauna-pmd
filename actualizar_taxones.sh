#!/usr/bin/env bash
# Recarga la tabla de taxones desde una lista de especies nueva de GBIF ("Species list", misma consulta que la
# descarga de América y taxonomía Catalogue of Life 2026-10-16 XR) y rehace todo lo que depende de ella:
# taxones + GRIIS (cargar_capas.sh), preguntas 1 y 2 en PostGIS, la etapa final de Neo4j (Chile), la línea base de
# comunidades y los mapas de Q1/Q2. La pregunta 3 no usa la tabla de taxones y no se rehace.
#   uso: ./actualizar_taxones.sh "<nombre del CSV nuevo dentro de DATOS_DIR>"      (~22 min)
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
export MSYS_NO_PATHCONV=1
NUEVO=${1:?uso: ./actualizar_taxones.sh "<archivo.csv en $DATOS_DIR>"}
[[ -s "$DATOS_DIR/$NUEVO" ]] || { echo "⛔ No existe $DATOS_DIR/$NUEVO" >&2; exit 1; }

# 1) El encabezado debe ser idéntico al de la tabla anterior (sql/03_taxones_griis.sql carga por posición)
ESPERADO=$'taxonKey\tscientificName\tacceptedTaxonKey\tacceptedScientificName\tnumberOfOccurrences\ttaxonRank\ttaxonomicStatus\tkingdom\tkingdomKey\tphylum\tphylumKey\tclass\tclassKey\torder\torderKey\tfamily\tfamilyKey\tgenus\tgenusKey\tspecies\tspeciesKey\tiucnRedListCategory'
REAL=$(head -1 "$DATOS_DIR/$NUEVO" | sed -e 's/\r$//' -e $'1s/^\xef\xbb\xbf//')   # sin CR ni BOM
if [[ "$REAL" != "$ESPERADO" ]]; then
  echo "⛔ El encabezado no coincide con el formato esperado; no se cambió nada." >&2
  diff <(tr '\t' '\n' <<<"$ESPERADO") <(tr '\t' '\n' <<<"$REAL") >&2 || true
  exit 1
fi
echo "Encabezado OK · $(($(wc -l < "$DATOS_DIR/$NUEVO") - 1)) filas"

# 2) Apuntar .env al archivo nuevo (se guarda el anterior en .env.bak)
cp .env .env.bak
sed -i "s|^CSV_TAXONES=.*|CSV_TAXONES=\"$NUEVO\"|" .env
set -a; source .env; set +a

LOG=resultados/actualizar_taxones_log.txt; : > "$LOG"
T0=$(date +%s)
paso() { echo "[$(date '+%F %T')] (+$(( $(date +%s) - T0 )) s) $*" | tee -a "$LOG"; }
PSQL="docker compose exec -T postgis psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres"
docker compose up -d --wait >/dev/null

paso "Capas (taxones + GRIIS + Natural Earth + WDPA)"; ./cargar_capas.sh > resultados/capas_consola.txt 2>&1
grep -A3 "Cruce GRIIS" resultados/capas_consola.txt | tee -a "$LOG"
paso "Q2 Chile";   $PSQL -v tabla=obs_chile   -v top=20 -f /sql/q2_invasoras_urbanas.sql > resultados/q2_postgis_chile.txt 2>&1
paso "Q2 América"; $PSQL -v tabla=obs_america -v top=25 -f /sql/q2_invasoras_urbanas.sql > resultados/q2_postgis_america.txt 2>&1
paso "Q1 América"; $PSQL -v tabla=obs_america -v top=30 -f /sql/q1_amenazadas_fuera_ap.sql > resultados/q1_postgis_america.txt 2>&1
paso "Neo4j Chile 2015–2026"; ./cargar_neo4j.sh obs_chile CL 2015 2026 > resultados/neo4j_CL_2015_2026_consola.txt 2>&1
paso "Línea base de comunidades"
docker compose exec -T neo4j cypher-shell -u neo4j -p "$NEO4J_PASSWORD" --format plain -f /cypher/q1_linea_base.cypher \
  > resultados/neo4j_CL_2015_2026_q1_linea_base.txt 2>&1
paso "Mapas Q1/Q2"; ${PYTHON:-python} scripts/mapas_q1_q2.py >> "$LOG" 2>&1

paso "Métricas después"
$PSQL -c "SELECT 'taxones' t, count(*) FROM taxones UNION ALL
          SELECT 'griis con clave', count(*) FILTER (WHERE specieskey IS NOT NULL) FROM griis UNION ALL
          SELECT 'obs amenazadas', count(*) FROM obs_america_amenazadas UNION ALL
          SELECT 'obs urbanas introducidas', count(*) FILTER (WHERE introducida) FROM obs_america_urbano" | tee -a "$LOG"
paso "FIN"
