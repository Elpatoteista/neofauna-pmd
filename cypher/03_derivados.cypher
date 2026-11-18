// Relaciones agregadas. La COOCURRENCIA se calcula POR CELDA (taxón-celda-taxón) y no entre pares de
// observaciones: así el costo depende de (especies por celda)^2 y no de (observaciones)^2.

// Presencia de cada especie en cada celda (n = n.º de observaciones)
MATCH (c:Celda)
CALL { WITH c
  MATCH (c)<-[:EN_CELDA]-(:Observacion)-[:DE_TAXON]->(t:Taxon)
  WITH c, t, count(*) AS n
  CREATE (t)-[:PRESENTE_EN {n: n}]->(c)
} IN TRANSACTIONS OF 500 ROWS;

// Observador -> especie (n = n.º de observaciones de esa especie por esa persona)
MATCH (p:Observador)
CALL { WITH p
  MATCH (p)-[:OBSERVO]->(:Observacion)-[:DE_TAXON]->(t:Taxon)
  WITH p, t, count(*) AS n
  CREATE (p)-[:REGISTRA {n: n}]->(t)
} IN TRANSACTIONS OF 1000 ROWS;

// Coocurrencia en celdas URBANAS entre especies introducidas en el país y especies nativas (no listadas en GRIIS)
MATCH (i:Taxon)-[:INTRODUCIDA_EN]->(:Pais)
CALL { WITH i
  MATCH (i)-[:PRESENTE_EN]->(c:Celda {urbana: true})<-[:PRESENTE_EN]-(n:Taxon)
  WHERE NOT (n)-[:INTRODUCIDA_EN]->(:Pais)
  WITH i, n, count(DISTINCT c) AS celdas, count(DISTINCT c.urbano_id) AS zonas
  CREATE (i)-[:COOCURRE {celdas: celdas, zonas: zonas}]->(n)
} IN TRANSACTIONS OF 50 ROWS;
