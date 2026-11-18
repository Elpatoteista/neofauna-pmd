"""Mapas y figuras de las preguntas 1 y 2.

Lee de PostGIS y de Neo4j con `docker compose exec` (no necesita drivers de Python) y dibuja con matplotlib
(+ networkx para la red de coocurrencia). Requiere haber corrido:
  sql/q1_amenazadas_fuera_ap.sql (tabla obs_america_amenazadas), sql/q2_invasoras_urbanas.sql (obs_america_urbano)
  y cargar_neo4j.sh con Chile (el grafo vigente debe ser CL).

uso:  python scripts/mapas_q1_q2.py
Salidas: mapas/q1a_america_amenazadas_fuera_ap.png, mapas/q1b_chile_amenazadas_wdpa.png,
         mapas/q2a_america_introducidas_urbanas.png, mapas/q2b_chile_red_coocurrencia.png
"""
import csv, io, json, os, subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, Normalize
from matplotlib.patches import Polygon as MplPolygon
from matplotlib.collections import PatchCollection
import networkx as nx

csv.field_size_limit(2 ** 31 - 1)   # polígonos WDPA grandes en GeoJSON superan el límite por defecto (128 KB)
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "mapas")
ENV = dict(os.environ, MSYS_NO_PATHCONV="1")
NEO4J_PASSWORD = "pmd2026neo"
for linea in open(os.path.join(RAIZ, ".env"), encoding="utf-8"):
    if linea.startswith("NEO4J_PASSWORD="):
        NEO4J_PASSWORD = linea.split("=", 1)[1].strip().strip('"')


def sql(q):
    out = subprocess.run(["docker", "compose", "exec", "-T", "postgis", "psql", "-X", "-U", "postgres", "-c",
                          f"COPY ({q}) TO STDOUT WITH (FORMAT csv, HEADER true)"],
                         cwd=RAIZ, env=ENV, check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return list(csv.DictReader(io.StringIO(out)))


def cypher(q):
    out = subprocess.run(["docker", "compose", "exec", "-T", "neo4j", "cypher-shell", "-u", "neo4j", "-p",
                          NEO4J_PASSWORD, "--format", "plain", q],
                         cwd=RAIZ, env=ENV, check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return list(csv.DictReader(io.StringIO(out), skipinitialspace=True))


def lon_america(x):
    """Aleutianas: +170° -> -190° para que el mapa de América no se estire."""
    x = float(x)
    return x - 360 if x > 0 else x


def ejes_mapa(ax, titulo):
    ax.set_title(titulo, fontsize=10)
    ax.set_aspect(1.0)
    ax.set_xlabel("longitud"); ax.set_ylabel("latitud")
    ax.grid(alpha=0.2)


# Celda de igual área (EPSG:6933) de 50 km, igual que en la pregunta 3
CELDA = """floor(ST_X(ST_Transform(geom, 6933)) / 50000)::int AS i, floor(ST_Y(ST_Transform(geom, 6933)) / 50000)::int AS j"""
CENTRO = """ST_Y(ST_Transform(ST_SetSRID(ST_MakePoint((i + 0.5) * 50000, (j + 0.5) * 50000), 6933), 4326)) AS lat,
            ST_X(ST_Transform(ST_SetSRID(ST_MakePoint((i + 0.5) * 50000, (j + 0.5) * 50000), 6933), 4326)) AS lon"""


def q1a():
    filas = sql(f"""
        WITH c AS (SELECT {CELDA}, specieskey, fuera_ap FROM obs_america_amenazadas WHERE NOT introducida)
        SELECT {CENTRO}, n, esp_fuera, pct_fuera FROM (
            SELECT i, j, count(*) AS n, count(DISTINCT specieskey) FILTER (WHERE fuera_ap) AS esp_fuera,
                   round(100.0 * count(*) FILTER (WHERE fuera_ap) / count(*), 1) AS pct_fuera
            FROM c GROUP BY i, j) s""")
    fig, axs = plt.subplots(1, 2, figsize=(16, 10), sharex=True, sharey=True)
    xs = [lon_america(f["lon"]) for f in filas]; ys = [float(f["lat"]) for f in filas]
    v = [max(1, int(f["esp_fuera"])) for f in filas]
    sc = axs[0].scatter(xs, ys, c=v, s=3, marker="s", linewidths=0, cmap="magma_r", norm=LogNorm(1, max(v)))
    fig.colorbar(sc, ax=axs[0], shrink=0.6, label="especies VU/EN/CR con obs. fuera de AP (log)")
    ejes_mapa(axs[0], "Especies amenazadas observadas FUERA de áreas protegidas\n(celdas de 50 km de igual área)")
    sel = [f for f in filas if int(f["n"]) >= 20]
    sc = axs[1].scatter([lon_america(f["lon"]) for f in sel], [float(f["lat"]) for f in sel],
                        c=[float(f["pct_fuera"]) for f in sel], s=3, marker="s", linewidths=0, cmap="RdYlGn_r",
                        norm=Normalize(0, 100))
    fig.colorbar(sc, ax=axs[1], shrink=0.6, label="% de obs. amenazadas fuera de AP")
    ejes_mapa(axs[1], "% de observaciones amenazadas fuera de áreas protegidas\n(celdas con ≥ 20 obs.)")
    fig.suptitle("Pregunta 1 — América: especies IUCN VU/EN/CR vs. WDPA (sin especies introducidas en el país)")
    fig.tight_layout()
    fig.savefig(os.path.join(SALIDA, "q1a_america_amenazadas_fuera_ap.png"), dpi=140, bbox_inches="tight")
    plt.close(fig)


def q1b():
    caja = "ST_MakeEnvelope(-76.5, -56, -66, -17, 4326)"
    poli = sql(f"""SELECT ST_AsGeoJSON(ST_SimplifyPreserveTopology(ST_Intersection(geom, {caja}), 0.005), 4) AS g, realm
                   FROM wdpa WHERE iso3 LIKE '%CHL%' AND status <> 'Proposed' AND geom && {caja}""")
    pts = sql(f"""SELECT ST_X(geom) AS lon, ST_Y(geom) AS lat, fuera_ap FROM obs_america_amenazadas
                  WHERE countrycode = 'CL' AND NOT introducida AND geom && {caja}""")
    top = sql("""SELECT species, iucn, count(*) AS n, count(*) FILTER (WHERE fuera_ap) AS fuera
                 FROM obs_america_amenazadas WHERE countrycode = 'CL' AND NOT introducida
                 GROUP BY 1, 2 ORDER BY fuera DESC LIMIT 15""")
    fig = plt.figure(figsize=(14, 12))
    ax = fig.add_axes([0.04, 0.05, 0.42, 0.88])
    parches = {"terr": [], "mar": []}
    for p in poli:
        g = json.loads(p["g"])
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]] if g["type"] == "Polygon" else []
        for pg in polys:
            parches["mar" if p["realm"] == "Marine" else "terr"].append(MplPolygon(pg[0], closed=True))
    ax.add_collection(PatchCollection(parches["mar"], facecolor="#9ecae1", edgecolor="#6baed6", linewidth=0.2, alpha=0.4))
    ax.add_collection(PatchCollection(parches["terr"], facecolor="#a1d99b", edgecolor="#31a354", linewidth=0.2, alpha=0.6))
    dentro = [f for f in pts if f["fuera_ap"] == "f"]; fuera = [f for f in pts if f["fuera_ap"] == "t"]
    ax.scatter([float(f["lon"]) for f in fuera], [float(f["lat"]) for f in fuera], s=1, c="#d7301f", alpha=0.35,
               label=f"fuera de AP ({len(fuera):,})".replace(",", "."))
    ax.scatter([float(f["lon"]) for f in dentro], [float(f["lat"]) for f in dentro], s=1, c="#08519c", alpha=0.5,
               label=f"dentro de AP ({len(dentro):,})".replace(",", "."))
    ax.set_xlim(-76.5, -66); ax.set_ylim(-56, -17)
    ejes_mapa(ax, "Chile: observaciones de especies VU/EN/CR\n(verde: AP terrestres WDPA, celeste: AP marinas)")
    ax.legend(loc="lower left", markerscale=8, fontsize=9)

    ax2 = fig.add_axes([0.6, 0.08, 0.37, 0.82])
    nombres = [f"{t['species']} ({t['iucn']})" for t in top][::-1]
    fuera_n = [int(t["fuera"]) for t in top][::-1]
    dentro_n = [int(t["n"]) - int(t["fuera"]) for t in top][::-1]
    ax2.barh(nombres, fuera_n, color="#d7301f", label="fuera de AP")
    ax2.barh(nombres, dentro_n, left=fuera_n, color="#08519c", label="dentro de AP")
    for k, (fu, de) in enumerate(zip(fuera_n, dentro_n)):
        ax2.text(fu + de, k, f" {100 * fu / (fu + de):.0f}% fuera", va="center", fontsize=8)
    ax2.set_xlabel("observaciones (todas las de la descarga de América en Chile)")
    ax2.set_title("15 especies amenazadas con más observaciones fuera de AP", fontsize=10)
    ax2.legend(loc="lower right", fontsize=9)
    ax2.tick_params(axis="y", labelsize=8)
    ax2.set_xlim(0, max(f + d for f, d in zip(fuera_n, dentro_n)) * 1.22)
    fig.suptitle("Pregunta 1 — Chile: especies amenazadas y áreas protegidas (WDPA nov-2026)")
    fig.savefig(os.path.join(SALIDA, "q1b_chile_amenazadas_wdpa.png"), dpi=140, bbox_inches="tight")
    plt.close(fig)


def q2a():
    # pais = país más frecuente de las observaciones de la zona; con_griis = ese país tiene checklist GRIIS
    filas = sql("""WITH z AS (SELECT urbano_id, count(*) AS obs,
                                     count(DISTINCT specieskey) FILTER (WHERE introducida) AS intro,
                                     count(DISTINCT specieskey) AS total, mode() WITHIN GROUP (ORDER BY countrycode) AS pais
                              FROM obs_america_urbano GROUP BY urbano_id)
                   SELECT ST_Y(ST_Centroid(u.geom)) AS lat, ST_X(ST_Centroid(u.geom)) AS lon, z.*,
                          z.pais IN (SELECT DISTINCT countrycode FROM griis) AS con_griis
                   FROM z JOIN urbano u ON u.id = z.urbano_id ORDER BY z.obs""")
    fig, axs = plt.subplots(1, 2, figsize=(17, 10), gridspec_kw={"width_ratios": [1.25, 1]})
    con = [f for f in filas if f["con_griis"] == "t"]; sin = [f for f in filas if f["con_griis"] != "t"]
    tam = lambda fs: [max(2, (int(f["obs"]) ** 0.5) / 4) for f in fs]
    axs[0].scatter([lon_america(f["lon"]) for f in sin], [float(f["lat"]) for f in sin], s=tam(sin), c="#bbbbbb",
                   edgecolors="k", linewidths=0.15,
                   label="sin checklist GRIIS (" + ", ".join(sorted({f["pais"] for f in sin})) + ")")
    intro = [max(1, int(f["intro"])) for f in con]
    sc = axs[0].scatter([lon_america(f["lon"]) for f in con], [float(f["lat"]) for f in con], s=tam(con), c=intro,
                        cmap="plasma", norm=LogNorm(1, max(intro)), alpha=0.75, edgecolors="k", linewidths=0.15)
    fig.colorbar(sc, ax=axs[0], shrink=0.6, label="especies introducidas (GRIIS) observadas en la zona (log)")
    ejes_mapa(axs[0], "Zonas urbanas (Natural Earth): tamaño ∝ √observaciones, color = n.º de introducidas")
    for n in (1000, 100000, 1000000):
        axs[0].scatter([], [], s=(n ** 0.5) / 4, c="w", edgecolors="k", label=f"{n:,} obs.".replace(",", "."))
    axs[0].legend(loc="lower left", fontsize=8, labelspacing=1.5)
    # Panel derecho: fracción de especies introducidas vs. esfuerzo (¿más introducidas solo por más muestreo?)
    sel = [f for f in con if int(f["total"]) >= 20]
    sc2 = axs[1].scatter([int(f["obs"]) for f in sel], [100 * int(f["intro"]) / int(f["total"]) for f in sel], s=6,
                         alpha=0.6, c=[float(f["lat"]) for f in sel], cmap="coolwarm_r", norm=Normalize(-45, 55))
    fig.colorbar(sc2, ax=axs[1], shrink=0.6, label="latitud del centro de la zona")
    axs[1].set_xscale("log")
    axs[1].set_xlabel("observaciones en la zona urbana (log)")
    axs[1].set_ylabel("% de las especies observadas que son introducidas en ese país")
    axs[1].set_title("Proporción de introducidas por zona urbana\n(color: latitud; zonas con ≥ 20 especies)", fontsize=10)
    axs[1].grid(alpha=0.2)
    fig.suptitle("Pregunta 2 — América: especies introducidas en zonas urbanas")
    fig.tight_layout()
    fig.savefig(os.path.join(SALIDA, "q2a_america_introducidas_urbanas.png"), dpi=140, bbox_inches="tight")
    plt.close(fig)


def q2b():
    pais = cypher("MATCH (p:Pais) RETURN p.code AS code")
    pais = pais[0]["code"].strip('"') if pais else "?"
    aristas = cypher("""
        MATCH (i:Taxon)-[x:INTRODUCIDA_EN]->(:Pais)
        MATCH (i)-[co:COOCURRE]->(n:Taxon)
        WITH i, x, n, co ORDER BY co.celdas DESC
        WITH i, x, collect({n: n, c: co.celdas})[..6] AS top, sum(co.celdas) AS peso
        ORDER BY peso DESC LIMIT 12
        UNWIND top AS t
        WITH i, x, t.n AS n, t.c AS celdas
        MATCH (n)-[:HIJO_DE*]->(cn:Taxon {rango: 'CLASS'})
        MATCH (i)-[:HIJO_DE*]->(ci:Taxon {rango: 'CLASS'})
        RETURN i.nombre AS introducida, ci.nombre AS clase_i, x.invasora AS invasora,
               n.nombre AS nativa, cn.nombre AS clase_n, celdas""")
    G = nx.Graph()
    for a in aristas:
        i, n = a["introducida"].strip('"'), a["nativa"].strip('"')
        G.add_node(i, tipo="intro", clase=a["clase_i"].strip('"'), invasora=a["invasora"] == "TRUE")
        G.add_node(n, tipo="nativa", clase=a["clase_n"].strip('"'))
        G.add_edge(i, n, w=int(a["celdas"]))
    intro = sorted([v for v, d in G.nodes(data=True) if d["tipo"] == "intro"])
    nat = sorted([v for v, d in G.nodes(data=True) if d["tipo"] == "nativa"], key=lambda v: -G.degree(v))
    pos = {v: (0, -k * (len(nat) / max(1, len(intro)))) for k, v in enumerate(intro)}
    pos.update({v: (1, -k) for k, v in enumerate(nat)})
    clases = sorted({d["clase"] for _, d in G.nodes(data=True)})
    cmap = plt.get_cmap("tab10")
    color = {c: cmap(k % 10) for k, c in enumerate(clases)}
    fig, ax = plt.subplots(figsize=(13, max(9, len(nat) * 0.32)))
    wmax = max(d["w"] for *_, d in G.edges(data=True))
    nx.draw_networkx_edges(G, pos, ax=ax, width=[0.4 + 4 * d["w"] / wmax for *_, d in G.edges(data=True)],
                           alpha=0.35, edge_color="#555")
    for tipo, forma in (("intro", "s"), ("nativa", "o")):
        nodos = [v for v, d in G.nodes(data=True) if d["tipo"] == tipo]
        nx.draw_networkx_nodes(G, pos, nodelist=nodos, ax=ax, node_shape=forma, node_size=[60 + 25 * G.degree(v) for v in nodos],
                               node_color=[color[G.nodes[v]["clase"]] for v in nodos],
                               edgecolors=["red" if G.nodes[v].get("invasora") else "k" for v in nodos], linewidths=1.2)
    for v, (x, y) in pos.items():
        ax.text(x - 0.03 if x == 0 else x + 0.03, y, v, ha="right" if x == 0 else "left", va="center", fontsize=8,
                style="italic")
    for c in clases:
        ax.scatter([], [], c=[color[c]], label=c, s=50)
    ax.scatter([], [], marker="s", c="w", edgecolors="red", label="invasora (GRIIS isInvasive)", s=50)
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.01), ncol=5, fontsize=8, title="clase")
    ax.set_xlim(-0.75, 1.75)
    ax.axis("off")
    if "Apis mellifera" in nat:
        ax.text(0.5, 0.005, "Nota: Apis mellifera figura como nativa solo porque no está en el checklist GRIIS de este país "
                "(sí en el de otros 17 de América).", transform=ax.transAxes, ha="center", fontsize=8, color="#a00")
    ax.set_title(f"Pregunta 2 — Neo4j ({pais}): 12 introducidas con más coocurrencia en celdas urbanas de 5 km\n"
                 "y sus 6 nativas más frecuentes (grosor ∝ n.º de celdas compartidas). Izq.: introducidas; der.: nativas",
                 fontsize=10)
    fig.tight_layout()
    fig.savefig(os.path.join(SALIDA, f"q2b_{pais.lower()}_red_coocurrencia.png"), dpi=140, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    os.makedirs(SALIDA, exist_ok=True)
    for f in (q1a, q1b, q2a, q2b):
        f()
        print("listo:", f.__name__)
