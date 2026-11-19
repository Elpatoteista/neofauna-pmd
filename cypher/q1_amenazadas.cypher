// PREGUNTA 1 — parte Neo4j
// Se excluyen especies introducidas en el país según GRIIS (p.ej. conejo europeo o pino radiata en Chile: amenazados
// en su área nativa pero invasores aquí).
// Especies VU/EN/CR con observaciones FUERA de áreas protegidas (fuera_ap lo calculó PostGIS con WDPA),
// cómo se conectan taxonómicamente y mediante comunidades de observadores.

// 1) Especies amenazadas observadas fuera de áreas protegidas
MATCH (t:Taxon)<-[:DE_TAXON]-(o:Observacion)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais)
WITH t, count(o) AS obs, sum(CASE WHEN o.fuera_ap THEN 1 ELSE 0 END) AS fuera
WHERE fuera > 0
MATCH (t)-[:HIJO_DE*]->(f:Taxon {rango: 'FAMILY'})
MATCH (t)-[:HIJO_DE*]->(c:Taxon {rango: 'CLASS'})
RETURN t.nombre AS especie, t.iucn AS iucn, c.nombre AS clase, f.nombre AS familia,
       obs, fuera AS obs_fuera_ap, round(100.0 * fuera / obs, 1) AS pct_fuera
ORDER BY fuera DESC LIMIT 30;

// 2) Conexión taxonómica: familias y órdenes que concentran especies amenazadas fuera de AP
MATCH (t:Taxon)<-[:DE_TAXON]-(o:Observacion {fuera_ap: true})
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais)
WITH DISTINCT t
MATCH (t)-[:HIJO_DE*]->(f:Taxon {rango: 'FAMILY'})-[:HIJO_DE*]->(ord:Taxon {rango: 'ORDER'})
RETURN ord.nombre AS orden, f.nombre AS familia, count(t) AS especies_amenazadas,
       collect(t.nombre + ' (' + t.iucn + ')')[..6] AS ejemplos
ORDER BY especies_amenazadas DESC LIMIT 20;

// 3) Comunidades de observadores (Louvain, 04_comunidades.cypher) que registran especies amenazadas fuera de AP
MATCH (p:Observador)-[:OBSERVO]->(o:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH p.comunidad AS comunidad, count(DISTINCT p) AS observadores, count(o) AS obs,
     count(DISTINCT t) AS especies_amenazadas, collect(DISTINCT t.nombre) AS esp
RETURN comunidad, observadores, obs, especies_amenazadas, esp[..5] AS ejemplos
ORDER BY especies_amenazadas DESC LIMIT 15;

// 4) Especies amenazadas conectadas por compartir comunidad de observadores (puente entre taxones lejanos)
MATCH (p:Observador)-[:OBSERVO]->(:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH t, p.comunidad AS com, count(DISTINCT p) AS nobs WHERE nobs >= 2
WITH com, collect(t) AS esps WHERE size(esps) >= 2
UNWIND esps AS a UNWIND esps AS b
WITH com, a, b WHERE a.key < b.key
MATCH (a)-[:HIJO_DE*]->(ca:Taxon {rango: 'CLASS'})
MATCH (b)-[:HIJO_DE*]->(cb:Taxon {rango: 'CLASS'})
RETURN CASE WHEN ca = cb THEN 'misma clase' ELSE 'distinta clase' END AS relacion,
       count(*) AS pares, count(DISTINCT com) AS comunidades,
       collect(a.nombre + ' — ' + b.nombre)[..4] AS ejemplos;
