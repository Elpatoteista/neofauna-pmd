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
   * Lista de especies de GBIF con la misma consulta de América (descarga `0000783-261118162104854`,
     DOI 10.15468/dl.k54msh, 219.104 taxones, Catalogue of Life 2026-10-16 XR): tabla de taxones (jerarquía + IUCN).
     `.env` → `CSV_TAXONES`. Para recargarla y rehacer las preguntas 1 y 2: `./actualizar_taxones.sh "<archivo>"`.
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

## Citación de los datos y licencias

Las descargas de GBIF exigen citar su DOI en cualquier publicación:

* GBIF.org (18 November 2026) GBIF Occurrence Download <https://doi.org/10.15468/dl.8hgded> (América, `0014768-261110092616502`).
* GBIF.org (18 November 2026) GBIF Occurrence Download <https://doi.org/10.15468/dl.5gu3zk> (Chile 2015–2026, `0014759-261110092616502`).
* iNaturalist contributors, iNaturalist (2026). iNaturalist Research-grade Observations. iNaturalist.org. Occurrence dataset <https://doi.org/10.15468/ab3s5x> accessed via GBIF.org on 2026-11-18. Licencia CC BY-NC 4.0.
* Bánki, O., Roskov, Y., Döring, M., Ower, G., et al. (2026). Catalogue of Life (2026-10-16 XR). <https://doi.org/10.48580/dgzlf>. CC BY 4.0.
* GBIF.org (19 November 2026) GBIF Occurrence Download <https://doi.org/10.15468/dl.k54msh> (lista de especies = tabla de taxones, `0000783-261118162104854`).
* UNEP-WCMC and IUCN (2026), Protected Planet: The World Database on Protected and Conserved Areas (WDPCA) [On-line], November 2026, Cambridge, UK: UNEP-WCMC and IUCN. Available at: www.protectedplanet.net. Solo uso no comercial y sin redistribución: por eso la WDPA **no** está en este repositorio.
* GRIIS (ISSG): las 44 citas, con su DOI, en `resultados/griis_citas.txt` (42 CC BY 4.0, 2 CC0 1.0).
* Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com (Urban Areas 1:10m, v4.1.0, dominio público).

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
  (género + epíteto, aceptado o sinónimo) → 75,1 % de los pares país–especie con clave (los que faltan son,
  en su mayoría, especies sin observaciones en la descarga). Se excluyen los checklists **subnacionales** (Juan Fernández, Alaska)
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

Capas (`cargar_capas.sh`, 3 min 38 s con la tabla nueva): taxones 219.104 filas + 6.899 derivadas; GRIIS 23.678 → 22.494 pares país–especie; Natural
Earth 11.878 polígonos (2.137 en América); **WDPA** 80.170 polígonos en la caja de América (de 500.347 globales;
lectura 1 min 51 s; 552 "Proposed" excluidas) subdivididos con `ST_Subdivide(256)` en 890.248 trozos + GiST
(1 min 53 s). Todo EPSG:4326, 0 geometrías inválidas.

### Pregunta 1 — amenazadas fuera de áreas protegidas (`resultados/q1_postgis_america.txt`, `neo4j_CL_2015_2026_q1.txt`)

* PostGIS, América completa (**1 min 29 s**: filtrar amenazadas 16 s + punto-en-polígono 66 s): 1.054.764
  observaciones de especies VU/EN/CR (categorías IUCN asignadas por GBIF en noviembre de 2026). Se excluyen 28.414 obs.
  de 52 especies que GRIIS lista como **introducidas** en ese país (p.ej. *Amazona viridigenalis* en EE.UU., conejo
  europeo): amenazadas en su área nativa pero no aquí.
* Resultado: 1.026.350 obs. de 5.968 especies; **71,0 % fuera de áreas protegidas** (CR 72,5 %, EN 66,0 %,
  VU 72,5 %); 5.102 especies tienen al menos una observación fuera; con solo observaciones de error ≤ 1 km, 68,3 %.
  Más observadas fuera: *Terrapene carolina*, *Bombus pensylvanicus*, *Pluvialis squatarola*, *Tringa flavipes*;
  CR: *Gopherus polyphemus* (VU en la asignación de agosto), *Castanea dentata*, fresnos *Fraxinus*,
  *Bombus affinis*, cóndor de California, *Pycnopodia helianthoides*.
* Neo4j (Chile 2015–2026, 389.141 obs. fuera de AP): *Porlieria chilensis* (VU), *Bombus dahlbomii* (EN), cóndor,
  *Citronella mucronata*, palma chilena, chungungo. Taxonómicamente se concentran en Cactaceae (33 especies), Liolaemidae (20),
  Alsodidae (16) y Procellariiformes. Louvain: 13 comunidades de observadores (modularidad 0,697); las 2 con más
  amenazadas registran 194 y 138 especies fuera de AP. El 81,5 % de los 12.126 pares distintos de especies
  amenazadas unidos por una misma comunidad son de clases distintas, pero **no es distintivo**: la línea base (todos
  los pares posibles de las mismas 172 especies, 14.706) da 83,9 %, y todas las amenazadas fuera de AP 86,6 %
  (`cypher/q1_linea_base.cypher` → `resultados/neo4j_CL_2015_2026_q1_linea_base.txt`). El porcentaje refleja la
  mezcla de clases, no que las comunidades crucen el árbol taxonómico más que el azar.
* Alcance: la parte PostGIS de las preguntas 1 y 2 es continental; la parte de grafo es de Chile (Argentina y
  México solo como etapas de escalamiento y contraste de la pregunta 2). No se extrapola a América.

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
  2.079 zonas, 84.140 especies; 4.789 introducidas según GRIIS, 763 marcadas *invasive* (16,7 % de las
  observaciones urbanas). GRIIS se agrupa por (país, especie) antes del join para no duplicar observaciones.
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
  por eso GDS corre con `concurrency: 1` (verificado: dos corridas iguales; con la tabla de taxones nueva, 13 comunidades, modularidad 0,697).
* `sql/experimentos.sql` → `resultados/experimentos.txt`:

| Experimento | Resultado |
|---|---|
| E1 punto-en-polígono WDPA, 46.150 puntos (CL+BR): polígonos enteros vs. `ST_Subdivide(256)` | > 1.197,6 s (cancelado) vs. **2,17 s** (> 550×; 552,6, cota inferior). Vértices medios 952 → 86; el mayor polígono tiene 1,87 M |
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
* La lista de especies de GBIF trae una fila por nombre usado: 6.899 especies aceptadas (2,57 M obs.) solo aparecen
  bajo un sinónimo o subespecie. Se agregan como filas derivadas (100 % de cobertura), pero sin categoría IUCN.
  La primera versión usaba una lista global de agosto y unía por `taxonKey`: 7,1 % de especies sin match.
* Las categorías IUCN cambian entre versiones de GBIF (agosto → noviembre: 155 especies VU → NE; *Gopherus
  polyphemus* VU → CR; *Porlieria chilensis* sin categoría → VU).
* GRIIS de BR, CL, CR, DO, GT y PA escribe la rana toro "*Rana catesbeiana*", nombre que la lista no trae: ahí no
  cuenta como introducida (sí donde se escribe "*Lithobates catesbeianus*"). De sus 30.132 obs. urbanas, 29.992
  están en EE.UU. y Canadá, donde es nativa.
* Un `MATCH` con dos patrones de linaje descartaba pares con aristas `HIJO_DE` compartidas (Neo4j no reutiliza una
  relación en un patrón); se separó en dos `MATCH`. La línea base pasó de ~90 % a 82 % y ahora cuadra (14.706 pares).
* La categoría IUCN es global: especies cultivadas que GRIIS no lista en un país (p.ej. *Persea americana*,
  *Citrus aurantium*, *Oxalis corniculata* en algunos países) siguen apareciendo como "amenazadas".
* "Fuera de área protegida" = no intersecta ningún polígono WDPA vigente; los sitios WDPA publicados solo como
  punto (capa `WDPA_point_*`, sin polígono) no se consideran.
* El grafo vigente en Neo4j es Chile 2015–2026 (la etapa final). Vaciar el grafo de México tomó ~3 min.
* Riqueza observada ≠ riqueza real: depende del esfuerzo (ver corrección en Q3).
