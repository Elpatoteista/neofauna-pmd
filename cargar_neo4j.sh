#!/usr/bin/env bash
# Carga POR ETAPAS un subconjunto (país + rango de años) desde PostGIS a Neo4j y corre las preguntas 1 y 2.
#   uso: ./cargar_neo4j.sh <tabla_postgis> <pais ISO2> <desde> <hasta>     p.ej.  ./cargar_neo4j.sh obs_chile CL 2024 2025
# Cada etapa VACÍA el grafo y lo recarga (los nodos de la etapa anterior se borran con DETACH DELETE en lotes).
# Tiempos y tamaños -> resultados/neo4j_<pais>_<desde>_<hasta>_*.txt
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
export MSYS_NO_PATHCONV=1
TABLA=${1:?tabla}; PAIS=${2:?pais}; DESDE=${3:?desde}; HASTA=${4:?hasta}; CELDA_KM=${CELDA_KM:-5}
ETQ="neo4j_${PAIS}_${DESDE}_${HASTA}"
LOG=resultados/${ETQ}_tiempos.txt; : > "$LOG"
PSQL="docker compose exec -T postgis psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres"
CY="docker compose exec -T neo4j cypher-shell -u neo4j -p $NEO4J_PASSWORD --format plain"
paso() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
cronometro() { local t0=$(date +%s); "$@"; paso "   -> $(( $(date +%s) - t0 )) s"; }

mkdir -p resultados/neo4j_import
paso "Exportando $TABLA ($PAIS $DESDE-$HASTA, celda ${CELDA_KM} km) desde PostGIS"
cronometro $PSQL -v tabla="$TABLA" -v pais="$PAIS" -v desde="$DESDE" -v hasta="$HASTA" -v celda_km="$CELDA_KM" \
     -f /sql/05_export_neo4j.sql 2>&1 | grep -vE '^(Time|Timing|COPY|DROP|SELECT|CREATE|ANALYZE|UPDATE)' | tee -a "$LOG"
ls -la resultados/neo4j_import | tee -a "$LOG"

docker compose up -d --wait neo4j
paso "Vaciando el grafo de la etapa anterior"
# Primero aristas y luego nodos, en lotes: DETACH DELETE de un nodo con 100 mil aristas excede la memoria de transacción
cronometro $CY "MATCH ()-[r]->() CALL { WITH r DELETE r } IN TRANSACTIONS OF 50000 ROWS" | tee -a "$LOG"
cronometro $CY "MATCH (n) CALL { WITH n DELETE n } IN TRANSACTIONS OF 50000 ROWS" | tee -a "$LOG"
paso "Esquema";            cronometro $CY -f /cypher/01_esquema.cypher    | tee -a "$LOG"
$CY "CALL db.awaitIndexes(300)"
paso "Carga (LOAD CSV)";   cronometro $CY -f /cypher/02_carga.cypher      | tee -a "$LOG"
paso "Derivadas (PRESENTE_EN, REGISTRA, COOCURRE por celda)"
cronometro $CY -f /cypher/03_derivados.cypher | tee -a "$LOG"
paso "Comunidades de observadores (GDS)"
cronometro $CY -f /cypher/04_comunidades.cypher | tee -a "$LOG"
paso "Tamaño del grafo"
$CY "MATCH (n) RETURN labels(n)[0] AS etiqueta, count(*) AS nodos ORDER BY nodos DESC" | tee -a "$LOG"
$CY "MATCH ()-[r]->() RETURN type(r) AS tipo, count(*) AS aristas ORDER BY aristas DESC" | tee -a "$LOG"

paso "Pregunta 1"; cronometro $CY -f /cypher/q1_amenazadas.cypher  > resultados/${ETQ}_q1.txt 2>&1
paso "Pregunta 2"; cronometro $CY -f /cypher/q2_coocurrencia.cypher > resultados/${ETQ}_q2.txt 2>&1
paso "Listo: resultados/${ETQ}_q1.txt y _q2.txt"
