// Línea base para "el 90 % de los pares que comparten comunidad son de clases distintas" (pregunta 1, Neo4j).
// Mismo filtro que cypher/q1_amenazadas.cypher (consulta 4): VU/EN/CR, no introducidas, obs. fuera de AP, con clase.

// (a1) Observado tal como en el informe: pares contados por comunidad (un par puede repetirse en varias comunidades)
MATCH (p:Observador)-[:OBSERVO]->(:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH t, p.comunidad AS com, count(DISTINCT p) AS nobs WHERE nobs >= 2
WITH com, collect(t) AS esps WHERE size(esps) >= 2
UNWIND esps AS a UNWIND esps AS b
WITH com, a, b WHERE a.key < b.key
MATCH (a)-[:HIJO_DE*]->(ca:Taxon {rango: 'CLASS'})
MATCH (b)-[:HIJO_DE*]->(cb:Taxon {rango: 'CLASS'})
RETURN 'a1 observado (por comunidad)' AS medida, count(*) AS pares,
       round(100.0 * sum(CASE WHEN ca <> cb THEN 1 ELSE 0 END) / count(*), 1) AS pct_distinta_clase;

// (a2) Observado, pares distintos (cada par una vez aunque comparta varias comunidades)
MATCH (p:Observador)-[:OBSERVO]->(:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH t, p.comunidad AS com, count(DISTINCT p) AS nobs WHERE nobs >= 2
WITH com, collect(t) AS esps WHERE size(esps) >= 2
UNWIND esps AS a UNWIND esps AS b
WITH DISTINCT a, b WHERE a.key < b.key
MATCH (a)-[:HIJO_DE*]->(ca:Taxon {rango: 'CLASS'})
MATCH (b)-[:HIJO_DE*]->(cb:Taxon {rango: 'CLASS'})
RETURN 'a2 observado (pares distintos)' AS medida, count(*) AS pares,
       round(100.0 * sum(CASE WHEN ca <> cb THEN 1 ELSE 0 END) / count(*), 1) AS pct_distinta_clase;

// (b) Línea base: TODOS los pares posibles entre las mismas especies que entran al análisis de comunidades
MATCH (p:Observador)-[:OBSERVO]->(:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH t, p.comunidad AS com, count(DISTINCT p) AS nobs WHERE nobs >= 2
WITH collect(DISTINCT t) AS esps
UNWIND esps AS a UNWIND esps AS b
WITH a, b WHERE a.key < b.key
MATCH (a)-[:HIJO_DE*]->(ca:Taxon {rango: 'CLASS'})
MATCH (b)-[:HIJO_DE*]->(cb:Taxon {rango: 'CLASS'})
RETURN 'b base: todos los pares, mismas especies' AS medida, count(*) AS pares,
       round(100.0 * sum(CASE WHEN ca <> cb THEN 1 ELSE 0 END) / count(*), 1) AS pct_distinta_clase;

// (c) Línea base amplia: todos los pares entre todas las amenazadas (no introducidas) observadas fuera de AP
MATCH (t:Taxon)<-[:DE_TAXON]-(:Observacion {fuera_ap: true})
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais)
WITH collect(DISTINCT t) AS esps
UNWIND esps AS a UNWIND esps AS b
WITH a, b WHERE a.key < b.key
MATCH (a)-[:HIJO_DE*]->(ca:Taxon {rango: 'CLASS'})
MATCH (b)-[:HIJO_DE*]->(cb:Taxon {rango: 'CLASS'})
RETURN 'c base: todas las amenazadas fuera de AP' AS medida, count(*) AS pares,
       round(100.0 * sum(CASE WHEN ca <> cb THEN 1 ELSE 0 END) / count(*), 1) AS pct_distinta_clase;

// Composición por clase de las especies que entran al análisis (explica la línea base)
MATCH (p:Observador)-[:OBSERVO]->(:Observacion {fuera_ap: true})-[:DE_TAXON]->(t:Taxon)
WHERE t.iucn IN ['VU', 'EN', 'CR'] AND NOT (t)-[:INTRODUCIDA_EN]->(:Pais) AND p.comunidad IS NOT NULL
WITH t, p.comunidad AS com, count(DISTINCT p) AS nobs WHERE nobs >= 2
WITH DISTINCT t
MATCH (t)-[:HIJO_DE*]->(c:Taxon {rango: 'CLASS'})
RETURN c.nombre AS clase, count(*) AS especies ORDER BY especies DESC LIMIT 8;
