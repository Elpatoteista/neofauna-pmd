// Carga de los CSV exportados por sql/05_export_neo4j.sql (carpeta /import). Lotes de 10.000 filas.
LOAD CSV WITH HEADERS FROM 'file:///taxones.csv' AS r
CALL { WITH r
  MERGE (t:Taxon {key: r.taxonkey})
  SET t.nombre = r.nombre, t.rango = r.rango, t.iucn = r.iucn
} IN TRANSACTIONS OF 10000 ROWS;

LOAD CSV WITH HEADERS FROM 'file:///jerarquia.csv' AS r
CALL { WITH r
  MATCH (h:Taxon {key: r.hijo}), (p:Taxon {key: r.padre})
  MERGE (h)-[:HIJO_DE]->(p)
} IN TRANSACTIONS OF 10000 ROWS;

LOAD CSV WITH HEADERS FROM 'file:///celdas.csv' AS r
CALL { WITH r
  MERGE (c:Celda {id: r.celda})
  SET c.urbana = (r.urbana = 't'), c.urbano_id = toInteger(r.urbano_id), c.lat = toFloat(r.lat), c.lon = toFloat(r.lon)
} IN TRANSACTIONS OF 10000 ROWS;

LOAD CSV WITH HEADERS FROM 'file:///introducidas.csv' AS r
CALL { WITH r
  MATCH (t:Taxon {key: r.specieskey})
  MERGE (p:Pais {code: r.countrycode})
  MERGE (t)-[i:INTRODUCIDA_EN]->(p) SET i.invasora = (r.invasora = 't')
} IN TRANSACTIONS OF 10000 ROWS;

// Observadores primero (MERGE sobre pocos nodos), luego observaciones con CREATE (gbifid es único)
LOAD CSV WITH HEADERS FROM 'file:///obs.csv' AS r
WITH DISTINCT r.recordedby AS nombre
CALL { WITH nombre MERGE (:Observador {nombre: nombre}) } IN TRANSACTIONS OF 10000 ROWS;

LOAD CSV WITH HEADERS FROM 'file:///obs.csv' AS r
CALL { WITH r
  MATCH (t:Taxon {key: r.specieskey}), (p:Observador {nombre: r.recordedby}), (c:Celda {id: r.celda})
  CREATE (o:Observacion {gbifid: toInteger(r.gbifid), year: toInteger(r.year), month: toInteger(r.month),
                         estacion: r.estacion,
                         fuera_ap: CASE r.fuera_ap WHEN 't' THEN true WHEN 'f' THEN false ELSE null END})
  CREATE (p)-[:OBSERVO]->(o), (o)-[:DE_TAXON]->(t), (o)-[:EN_CELDA]->(c)
} IN TRANSACTIONS OF 10000 ROWS;
