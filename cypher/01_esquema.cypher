// Modelo del grafo
//   (:Observador {nombre})-[:OBSERVO]->(:Observacion {gbifid, year, month, estacion, fuera_ap})
//   (:Observacion)-[:DE_TAXON]->(:Taxon {key, nombre, rango, iucn})
//   (:Observacion)-[:EN_CELDA]->(:Celda {id, urbana, urbano_id, lat, lon})      celda = lugar (5 km, igual área)
//   (:Taxon)-[:HIJO_DE]->(:Taxon)                                               jerarquía Catalogue of Life
//   (:Taxon)-[:INTRODUCIDA_EN {invasora}]->(:Pais {code})                       GRIIS
// Derivadas (03_derivados.cypher): PRESENTE_EN (taxón-celda), REGISTRA (observador-taxón), COOCURRE (taxón-taxón)
CREATE CONSTRAINT obs_id   IF NOT EXISTS FOR (o:Observacion) REQUIRE o.gbifid IS UNIQUE;
CREATE CONSTRAINT tax_key  IF NOT EXISTS FOR (t:Taxon)       REQUIRE t.key IS UNIQUE;
CREATE CONSTRAINT obsr_nom IF NOT EXISTS FOR (p:Observador)  REQUIRE p.nombre IS UNIQUE;
CREATE CONSTRAINT celda_id IF NOT EXISTS FOR (c:Celda)       REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT pais_cod IF NOT EXISTS FOR (p:Pais)        REQUIRE p.code IS UNIQUE;
CREATE INDEX tax_iucn  IF NOT EXISTS FOR (t:Taxon) ON (t.iucn);
CREATE INDEX tax_rango IF NOT EXISTS FOR (t:Taxon) ON (t.rango);
CREATE INDEX celda_urb IF NOT EXISTS FOR (c:Celda) ON (c.urbana);
