# Neofauna — iNaturalist (GBIF) en PostGIS + Neo4j

Proyecto semestral de **Procesamiento Masivo de Datos** (USM, EIN102B/ELE051-B).
Integrantes: Patricio Aylwin · Maximiliano Del Rio · Matías Castro.
Repositorio: <https://github.com/Elpatoteista/neofauna-pmd> · Informe: [Informe final de Neofauna](https://claude.ai/artifact/3gh3DmZsDuNLZFLNDsFPCn).

Dataset: *iNaturalist Research-grade Observations* publicado en GBIF (`50c9509d-22c7-4a22-a47d-8c48425ef4a7`).
Motores: **PostgreSQL 16 + PostGIS** (geoespacial) y **Neo4j 5 + Graph Data Science** (grafos). Sin streaming.

| Pregunta | Motores | Dónde está |
|---|---|---|
| 1. Especies VU/EN/CR con observaciones fuera de áreas protegidas, conexión taxonómica y por comunidades de observadores | PostGIS (WDPA) + Neo4j | `sql/05_export_neo4j.sql` (fuera_ap), `cypher/04_comunidades.cypher`, `cypher/q1_amenazadas.cypher` |
| 2. Especies invasoras en zonas urbanas y nativas que coocurren con ellas | PostGIS (Natural Earth + GRIIS) + Neo4j | `sql/q2_invasoras_urbanas.sql`, `cypher/03_derivados.cypher`, `cypher/q2_coocurrencia.cypher` |
| 3. Hotspots de riqueza y su cambio entre estaciones (por hemisferio) | PostGIS | `sql/q3_hotspots_riqueza.sql`, `scripts/mapas.py` |

## Estructura

```
docker-compose.yml      PostGIS (imagen propia, docker/Dockerfile) + Neo4j 5.26 con GDS. Puertos solo en 127.0.0.1
.env                    rutas a los CSV de GBIF y contraseñas locales
cargar_postgis.sh       carga masiva de observaciones (chile | america)
cargar_capas.sh         taxones GBIF, GRIIS, Natural Earth y WDPA
cargar_neo4j.sh         exporta un subconjunto (país + años) de PostGIS y lo carga en Neo4j; corre Q1 y Q2
reproducir.sh           corre todo lo anterior en orden, desde cero, y genera resultados y mapas
docker/                 Dockerfile de PostGIS (+ unzip y GDAL)
sql/                    esquema, índices, capas, exportación a Neo4j y consultas Q1/Q2/Q3
cypher/                 esquema, carga, relaciones derivadas, comunidades y consultas Q1/Q2
scripts/                bajar_griis.py (GRIIS de América), mapas.py (Q3), mapas_q1_q2.py (Q1 y Q2)
datos/                  NO versionado: capas complementarias (datos/capas/...)
resultados/             salidas de texto de cada paso (tiempos, tamaños, consultas)
mapas/                  PNG de las 3 preguntas
```

## Reproducir desde cero

Requisitos: Docker Desktop (WSL2) con ~8 GB para la VM, ~60 GB libres para la base de América, Git Bash (en
Windows), Python 3 con matplotlib y networkx (`pip install matplotlib networkx`).

1. **Datos de GBIF** (formato *Simple*, taxonomía Catalogue of Life; filtros: dataset iNaturalist research-grade,
   con coordenadas, sin problemas geoespaciales). Dejar en la carpeta indicada por `DATOS_DIR` en `.env`
   (por defecto la carpeta padre del repositorio):
   * Chile 2015–2026: descarga `0014759-261110092616502` → CSV de 345 MB, 537.785 filas.
   * América (Norte + Sur, todos los años): descarga `0014768-261110092616502` → ZIP de 14,9 GB (CSV de 59,7 GB,
     96.740.492 filas). **Se carga directamente desde el ZIP**; no hace falta descomprimirlo.
   * Tabla de taxones de GBIF (`Datos GBIF - taxones y ocurrencias.csv`, 498.455 taxones, jerarquía + IUCN).
   Se bajan desde `https://api.gbif.org/v1/occurrence/download/request/<ID>.zip`.
2. **Capas complementarias**
   * GRIIS (América): `python scripts/bajar_griis.py` → `datos/capas/griis/griis_america.tsv`.
   * Natural Earth 10m Urban Areas: descargar `https://naciscdn.org/naturalearth/10m/cultural/ne_10m_urban_areas.zip`
     y descomprimir en `datos/capas/naturalearth/`.
   * WDPA / WDPCA (áreas protegidas): en <https://www.protectedplanet.net/en/thematic-areas/wdpa> botón *Download* →
     **File Geodatabase** (no CSV: el CSV no trae geometrías) → uso no comercial (aceptar términos). Se usó
     `WDPA_Nov2026_Public.zip` (2,0 GB, servido desde `d1gam3xoknrgr2.cloudfront.net/current/`). Dejar el ZIP en
     `datos/capas/wdpa/`; se lee directo del ZIP.
3. **Todo de una vez:** `./reproducir.sh` (≈ 50 min; Neo4j solo con la etapa final de Chile) o
   `ETAPAS=todas ./reproducir.sh` (las 5 etapas de Neo4j). Si faltan GRIIS o Natural Earth los descarga; la WDPA
   y los datos de GBIF deben estar. Deja la bitácora con tiempos en `resultados/reproducir_log.txt`.

Paso a paso (lo mismo que hace `reproducir.sh`):

3. `docker compose up -d --build --wait`
4. `./cargar_postgis.sh chile` y `./cargar_postgis.sh america`
5. `./cargar_capas.sh`
6. Pregunta 3:
   `docker compose exec -T postgis psql -U postgres -v tabla=obs_america -v celda_km=50 -v desde=2021 -v hasta=2025 -v top=20 -f /sql/q3_hotspots_riqueza.sql`
   y `python scripts/mapas.py obs_america`
7. Pregunta 2 (PostGIS): `docker compose exec -T postgis psql -U postgres -v tabla=obs_america -v top=25 -f /sql/q2_invasoras_urbanas.sql`
8. Pregunta 1 (PostGIS, requiere la WDPA cargada): `docker compose exec -T postgis psql -U postgres -v tabla=obs_america -v top=30 -f /sql/q1_amenazadas_fuera_ap.sql`
9. Preguntas 1 y 2 (Neo4j, por etapas): `./cargar_neo4j.sh obs_chile CL 2024 2025`, luego `./cargar_neo4j.sh obs_chile CL 2015 2026`, etc.
10. Mapas: `python scripts/mapas.py obs_america`, `python scripts/mapas.py obs_chile` y `python scripts/mapas_q1_q2.py`.

(En Git Bash para Windows los scripts exportan `MSYS_NO_PATHCONV=1` para que no se traduzcan las rutas `/sql`, `/datos`.)

## Decisiones técnicas

* **Columnas**: de las 50 columnas del CSV *Simple* se cargan 23 (`cut`). `taxonKey`/`speciesKey` son claves
  alfanuméricas de Catalogue of Life (p.ej. `42KZ5`), por eso son `text`. El CSV **no** trae `iucnRedListCategory`:
  la categoría IUCN se obtiene uniendo `specieskey` con la tabla de taxones.
* **Carga masiva**: `CREATE TABLE` + `COPY` en la misma transacción con `wal_level=minimal` (no escribe WAL);
  `COPY ... FROM PROGRAM` lee el archivo dentro del contenedor; índices (PK, GiST, `specieskey`, `year`) **después**
  de cargar, y luego `VACUUM ANALYZE`. `FORMAT csv` con `QUOTE` = byte `0x01` para que comillas y barras invertidas
  del texto de GBIF se lean literales.
* **Columnas generadas** (`STORED`, se calculan durante el COPY, sin reescribir la tabla): `geom` (Point, 4326),
  `hemisferio` y `estacion` (meteorológica: DEF/MAM/JJA/SON, invertida en el hemisferio sur).
* **Lectura desde el ZIP**: el montaje de Windows en Docker Desktop lee a ~40 MB/s; leer el ZIP (14,9 GB) y
  descomprimirlo dentro del contenedor es ~4 veces menos E/S que leer el CSV (59,7 GB).
* **Grilla de igual área**: Q3 y la coocurrencia usan celdas cuadradas en EPSG:6933 (EASE-Grid 2.0), así todas
  las celdas tienen la misma superficie a cualquier latitud.
* **GRIIS**: 44 checklists de países/territorios de América; cruce con Catalogue of Life por nombre canónico
  (género + epíteto) → 81 % de coincidencia. Se excluyen los checklists **subnacionales** (Juan Fernández, Alaska)
  porque listan como introducidas especies nativas del resto del país (p.ej. el zorzal o el maqui en Chile).
  `establishmentMeans` de GBIF viene **vacío** en estas descargas, así que no sirve como complemento.
* **Neo4j por etapas**: la coocurrencia se calcula **por celda** (taxón–celda–taxón) y no entre pares de
  observaciones. Las comunidades de observadores: similitud de Jaccard entre observadores según especies
  compartidas (GDS `nodeSimilarity`) + Louvain.

## Resultados y tiempos (medidos el 18-11-2026)

Equipo: Ryzen 7 5800H (8 núcleos / 16 hilos), 16 GB RAM (7,5 GB para la VM de Docker), NVMe 512 GB.
PostgreSQL: `shared_buffers=2GB`, `work_mem=64MB`, `maintenance_work_mem=1GB`, 4 workers paralelos.
Neo4j: heap 2 GB, pagecache 1,5 GB.

### Carga en PostGIS (`resultados/tiempos_carga_*.txt`)

| Región | Filas | COPY | PK + GiST + 2 B-tree + VACUUM ANALYZE | Total | Datos | Índices |
|---|---:|---:|---:|---:|---:|---:|
| Chile 2015–2026 | 537.785 | 2,7 s | 2,1 s | 6 s | 162 MB | 40 MB |
| América (todos los años) | 96.740.492 | 12 min 2 s | 7 min 6 s (PK 1:14, GiST 2:53, specieskey 1:13, year 0:32, VACUUM 1:14) | 19 min 10 s | 27 GB | 7,2 GB |

Capas (`cargar_capas.sh`, 3 min 55 s): taxones 498.455 filas; GRIIS 23.678 → 22.494 pares país–especie; Natural
Earth 11.878 polígonos (2.137 en América); **WDPA** 80.170 polígonos en la caja de América (de 500.347 globales;
lectura 1 min 51 s; 552 "Proposed" excluidas) subdivididos con `ST_Subdivide(256)` en 890.248 trozos + GiST
(1 min 53 s). Todo EPSG:4326, 0 geometrías inválidas.

### Pregunta 1 — amenazadas fuera de áreas protegidas (`resultados/q1_postgis_america.txt`, `neo4j_CL_2015_2026_q1.txt`)

* PostGIS, América completa (**1 min 35 s**: filtrar amenazadas 15 s + punto-en-polígono 63 s): 1.193.504
  observaciones de especies VU/EN/CR. Se excluyen 73.811 obs. de 66 especies que GRIIS lista como **introducidas**
  en ese país (p.ej. *Hibiscus rosa-sinensis*, conejo europeo): amenazadas en su área nativa pero no aquí.
* Resultado: 1.119.693 obs. de 6.092 especies; **71,5 % fuera de áreas protegidas** (CR 69,0 %, EN 66,2 %,
  VU 73,5 %); 5.250 especies tienen al menos una observación fuera. Más observadas fuera: *Terrapene carolina*,
  *Bombus pensylvanicus*, *Pluvialis squatarola*, *Gopherus polyphemus*; CR: *Castanea dentata*, fresnos
  *Fraxinus*, *Bombus affinis*, cóndor de California, carey, corales *Acropora*.
* Neo4j (Chile 2015–2026, 389.141 obs. fuera de AP): *Bombus dahlbomii* (EN), cóndor, *Citronella mucronata*,
  palma chilena, chungungo. Taxonómicamente se concentran en Cactaceae (33 especies), Liolaemidae (20),
  Alsodidae (16) y Procellariiformes. Louvain: 15 comunidades de observadores (modularidad 0,69); las 2 mayores
  registran 197 y 142 especies amenazadas fuera de AP. El 90 % de los pares de especies amenazadas unidos por una
  misma comunidad son de **clases distintas** (p.ej. tortuga laúd — cactus *Eriosyce*): las comunidades de
  observadores conectan taxones lejanos en el árbol taxonómico.

### Pregunta 3 — hotspots de riqueza (`resultados/q3_*.txt`, `mapas/q3_*.png`)

* América 2021–2025, celdas de 50 km de igual área: 59,3 M de observaciones en 14.735 celdas; asignación a celdas
  **6 min 9 s**, consultas posteriores < 50 ms. Riqueza máxima 7.982 especies (Washington DC–Baltimore).
* **Sin corregir**, el top 20 es casi todo noreste de EE.UU. + Bahía de San Francisco: la riqueza observada sigue al
  esfuerzo de muestreo (log riqueza ~ log n_obs, R² = 0,81, pendiente 0,51).
* **Corregido por esfuerzo** (residuo de esa regresión): Guayana Francesa, Amazonía ecuatoriana, Mata Atlántica
  (Santa Catarina, Río de Janeiro), sur de EE.UU. — con ~2× las especies esperadas para su esfuerzo.
* Estaciones (8.935 celdas con datos en las 4): riqueza media verano 404 > primavera 300 > otoño 283 > invierno 143.
  En los hotspots templados del norte la razón máx/mín llega a 3–9×; en California y Texas es 1,3–1,9×.
* Chile (celdas de 25 km): Santiago (1.490 especies), Concepción, costa de Valparaíso, Valdivia; ~2 s en total.

### Pregunta 2 — parte PostGIS (`resultados/q2_postgis_*.txt`)

* América: intersección de 96,7 M de puntos con polígonos urbanos **7 min 38 s** → 27,06 M observaciones urbanas en
  2.079 zonas, 84.140 especies; 4.490 introducidas según GRIIS (16,2 % de las observaciones urbanas).
* Más observadas: *Apis mellifera*, *Passer domesticus*, *Harmonia axyridis*, *Columba livia*, *Sturnus vulgaris*.
  Desglose por país en `q2_postgis_america_por_pais.txt` (Chile: *Bombus terrestris*; Argentina y Canadá:
  *Harmonia axyridis*; México: *Passer domesticus*).

### Neo4j por etapas (`resultados/neo4j_<pais>_<años>_*.txt`)

| Etapa | Observaciones | Observadores | Especies | Celdas 5 km | Export PostGIS | LOAD CSV | Derivadas | GDS | Total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Chile 2024–2025 | 189.732 | 6.894 | 6.618 | 10.854 | 11 s | 18 s | 8 s | 7 s | 1 min 14 s |
| Chile 2015–2026 | 525.767 | 14.207 | 9.075 | 16.482 | 24 s | 35 s | 17 s | 10 s | 2 min 3 s |
| Argentina (todos) | 1.360.056 | 15.149 | 15.430 | 31.739 | 69 s | 88 s | 33 s | 12 s | 4 min 20 s |
| México 2021–2025 | 2.483.100 | 61.927 | 31.120 | 41.523 | 188 s | 178 s | 60 s | 36 s | 9 min 20 s |

El costo crece de forma aproximadamente lineal con las observaciones; la coocurrencia por celda se mantiene en
0,2–1,2 M aristas (no explota). México ocupa ~1 GB de store en Neo4j.

### Reproducción completa y experimentos

* `./reproducir.sh` desde volúmenes vacíos (18-11-2026): **47 min 53 s**, sin errores. Resultados idénticos a la
  primera corrida en todo lo determinista. Las comunidades de Louvain variaban entre corridas (ejecución paralela),
  por eso GDS corre con `concurrency: 1` (verificado: dos corridas iguales; 15 comunidades, modularidad 0,694).
* `sql/experimentos.sql` → `resultados/experimentos.txt`:

| Experimento | Resultado |
|---|---|
| E1 punto-en-polígono WDPA, 46.150 puntos (CL+BR): polígonos enteros vs. `ST_Subdivide(256)` | > 1.197 s (cancelado) vs. **2,2 s** (> 550×). Vértices medios 952 → 86; el mayor polígono tiene 1,87 M |
| E2 obs. de Chile × zonas urbanas: con vs. sin GiST | **2,9 s** vs. 654 s (×229; 1.597 M de pares descartados) |
| E3 asignación a celdas (Q3, Chile) | Parallel Seq Scan + Sort + GroupAggregate, 0,41 s: no usa índices |
| E4 coocurrencia Chile: pares de especies por celda vs. pares de observaciones | 15,1 M vs. 240 M dentro de celdas (×16) vs. 138.215 M sin celdas |
| E5 uso de índices | `obs_america_geom_gix` (3,8 GB) y `obs_america_pk` (2 GB): **0 lecturas**. Las consultas recorren los puntos en secuencia y usan el GiST del lado de los polígonos (`wdpa_sub_gix`: 1,77 M lecturas) |

### Mapas y figuras (`mapas/`)

Generar con `python scripts/mapas.py obs_america` (Q3) y `python scripts/mapas_q1_q2.py` (Q1 y Q2; requiere las
tablas `obs_america_amenazadas`, `obs_america_urbano` y el grafo de Chile en Neo4j; ~2,5 min).

| Archivo | Contenido |
|---|---|
| `q1a_america_amenazadas_fuera_ap.png` | Celdas de 50 km: n.º de especies VU/EN/CR con obs. fuera de AP, y % de obs. amenazadas fuera de AP |
| `q1b_chile_amenazadas_wdpa.png` | Polígonos WDPA de Chile (terrestres y marinos) con obs. amenazadas dentro/fuera + top 15 especies |
| `q2a_america_introducidas_urbanas.png` | Zonas urbanas (tamaño ∝ obs., color = n.º de introducidas; en gris países sin GRIIS) y % de introducidas vs. esfuerzo |
| `q2b_cl_red_coocurrencia.png` | Red bipartita desde Neo4j: 12 introducidas × nativas con más celdas urbanas compartidas |
| `q3_riqueza_*.png` | Riqueza por celda (top 20 hotspots) y por estación, América y Chile |

Lectura de `q2a`: las ciudades del hemisferio norte tienen ~15–20 % de especies introducidas y las del sur ~5–10 %,
sin relación clara con el esfuerzo. Parte de la diferencia puede deberse a que los checklists GRIIS del norte son
mucho más extensos (EE.UU. 8.527 especies, Canadá 1.581, la mayoría de Sudamérica < 1.000).

### Limitaciones conocidas

* `establishmentMeans` viene vacío en ambas descargas → no sirve para complementar GRIIS.
* GRIIS tiene vacíos: p.ej. *Apis mellifera* no está en el checklist de Chile (sí en otros 17 de América), por eso en
  Chile aparece como "nativa" en la coocurrencia. Ecuador y Puerto Rico no tienen checklist GRIIS en GBIF.
  El GRIIS de EE.UU. (v2.0, 2022) no informa `isInvasive`.
* ~6 % de las `specieskey` observadas no están en la tabla de taxones: entran al grafo sin jerarquía ni IUCN.
* La categoría IUCN es global: especies cultivadas que GRIIS no lista en un país (p.ej. *Persea americana*,
  *Citrus aurantium*, *Oxalis corniculata* en algunos países) siguen apareciendo como "amenazadas".
* "Fuera de área protegida" = no intersecta ningún polígono WDPA vigente; los sitios WDPA publicados solo como
  punto (capa `WDPA_point_*`, sin polígono) no se consideran.
* El grafo vigente en Neo4j es Chile 2015–2026 (la etapa final). Vaciar el grafo de México tomó ~3 min.
* Riqueza observada ≠ riqueza real: depende del esfuerzo (ver corrección en Q3).
