// PREGUNTA 2 — parte Neo4j
// Especies introducidas (GRIIS) en celdas urbanas y especies NATIVAS que coocurren con ellas en esas celdas.
// COOCURRE se construyó por celda en 03_derivados.cypher.

// 1) Introducidas presentes en celdas urbanas, con su n.º de nativas acompañantes
MATCH (i:Taxon)-[x:INTRODUCIDA_EN]->(:Pais)
MATCH (i)-[pr:PRESENTE_EN]->(c:Celda {urbana: true})
WITH i, x.invasora AS invasora, count(DISTINCT c) AS celdas_urbanas, sum(pr.n) AS obs_urbanas
OPTIONAL MATCH (i)-[co:COOCURRE]->(:Taxon)
RETURN i.nombre AS introducida, invasora, celdas_urbanas, obs_urbanas, count(co) AS nativas_coocurrentes
ORDER BY celdas_urbanas DESC LIMIT 25;

// 2) Pares introducida–nativa más frecuentes (más celdas urbanas compartidas)
MATCH (i:Taxon)-[co:COOCURRE]->(n:Taxon)
MATCH (i)-[:HIJO_DE*]->(ci:Taxon {rango: 'CLASS'})
MATCH (n)-[:HIJO_DE*]->(cn:Taxon {rango: 'CLASS'})
RETURN i.nombre AS introducida, ci.nombre AS clase_i, n.nombre AS nativa, cn.nombre AS clase_n,
       co.celdas AS celdas_compartidas, co.zonas AS zonas_urbanas
ORDER BY co.celdas DESC LIMIT 25;

// 3) Nativas que más coocurren con introducidas estrictamente invasoras (las "más expuestas")
MATCH (i:Taxon)-[x:INTRODUCIDA_EN {invasora: true}]->(:Pais)
MATCH (i)-[co:COOCURRE]->(n:Taxon)
RETURN n.nombre AS nativa, n.iucn AS iucn, count(i) AS invasoras_con_las_que_coocurre,
       sum(co.celdas) AS celdas_compartidas, collect(i.nombre)[..5] AS invasoras
ORDER BY invasoras_con_las_que_coocurre DESC, celdas_compartidas DESC LIMIT 20;

// 4) Tamaño de la red de coocurrencia
MATCH ()-[co:COOCURRE]->()
RETURN count(co) AS aristas_coocurrencia, avg(co.celdas) AS celdas_promedio, max(co.celdas) AS celdas_max;
