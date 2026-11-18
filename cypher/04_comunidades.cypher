// Comunidades de observadores con Graph Data Science:
//  1) grafo bipartito Observador -REGISTRA-> Taxon (solo observadores con >= 5 especies)
//  2) similitud de Jaccard entre observadores según especies compartidas (topK = 10)
//  3) Louvain sobre la red de similitud -> propiedad Observador.comunidad
// concurrency: 1 => resultado determinista (en paralelo Louvain da comunidades distintas en cada corrida)
CALL gds.graph.drop('obs_taxon', false) YIELD graphName RETURN graphName;

MATCH (p:Observador)-[r:REGISTRA]->(t:Taxon)
WITH p, count(t) AS k WHERE k >= 5
MATCH (p)-[r:REGISTRA]->(t:Taxon)
WITH gds.graph.project('obs_taxon', p, t, {sourceNodeLabels: labels(p), targetNodeLabels: labels(t),
                                            relationshipType: 'REGISTRA'}) AS g
RETURN g.graphName AS grafo, g.nodeCount AS nodos, g.relationshipCount AS aristas;

CALL gds.nodeSimilarity.mutate('obs_taxon', {
  topK: 10, similarityCutoff: 0.05, concurrency: 1, mutateRelationshipType: 'SIMILAR', mutateProperty: 'jaccard'})
YIELD relationshipsWritten, computeMillis
RETURN relationshipsWritten, computeMillis;

CALL gds.louvain.write('obs_taxon', {
  nodeLabels: ['Observador'], relationshipTypes: ['SIMILAR'], relationshipWeightProperty: 'jaccard', concurrency: 1,
  writeProperty: 'comunidad'})
YIELD communityCount, modularity, computeMillis
RETURN communityCount, round(modularity, 3) AS modularidad, computeMillis;

// Tamaño de las comunidades (las de 1 persona son observadores sin vecinos similares)
MATCH (p:Observador) WHERE p.comunidad IS NOT NULL
WITH p.comunidad AS c, count(*) AS tam
RETURN sum(CASE WHEN tam >= 3 THEN 1 ELSE 0 END) AS comunidades_3_o_mas, max(tam) AS mayor,
       sum(CASE WHEN tam >= 3 THEN tam ELSE 0 END) AS observadores_en_ellas, count(*) AS total_comunidades;

CALL gds.graph.drop('obs_taxon', false) YIELD graphName RETURN graphName;
