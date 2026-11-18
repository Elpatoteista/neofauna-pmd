"""Mapas de la pregunta 3 a partir de las celdas calculadas en PostGIS (tabla <region>_q3 y <region>_q3_estacion).

Lee directamente de PostGIS con `docker compose exec psql` (no necesita drivers de Python) y dibuja con
matplotlib, cada celda como un cuadrado coloreado según la riqueza (escala logarítmica).

uso:  python scripts/mapas.py obs_america   (o obs_chile)
"""
import csv, io, os, subprocess, sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLA = sys.argv[1] if len(sys.argv) > 1 else "obs_america"
ENV = dict(os.environ, MSYS_NO_PATHCONV="1")


def consulta(sql):
    out = subprocess.run(["docker", "compose", "exec", "-T", "postgis", "psql", "-X", "-U", "postgres", "-c",
                          f"COPY ({sql}) TO STDOUT WITH (FORMAT csv, HEADER true)"],
                         cwd=RAIZ, env=ENV, check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return list(csv.DictReader(io.StringIO(out)))


def dibujar(ax, filas, campo, titulo, vmax=None):
    # Aleutianas: celdas al otro lado del antimeridiano (+170°) se llevan a -190° para no estirar el mapa
    xs = [float(f["lon"]) - 360 if float(f["lon"]) > 0 else float(f["lon"]) for f in filas]
    ys = [float(f["lat"]) for f in filas]
    vs = [max(1, int(f[campo])) for f in filas]
    sc = ax.scatter(xs, ys, c=vs, s=2 if len(filas) > 5000 else 6, marker="s", linewidths=0, cmap="viridis",
                    norm=LogNorm(vmin=1, vmax=vmax or max(vs)))
    ax.set_title(titulo, fontsize=10)
    ax.set_aspect(1.0)
    ax.set_xlabel("longitud"); ax.set_ylabel("latitud")
    ax.grid(alpha=0.2)
    return sc


def main():
    os.makedirs(os.path.join(RAIZ, "mapas"), exist_ok=True)
    total = consulta(f"SELECT ST_Y(ST_Centroid(geom)) lat, ST_X(ST_Centroid(geom)) lon, riqueza, n_obs FROM {TABLA}_q3")
    fig, ax = plt.subplots(figsize=(9, 11))
    sc = dibujar(ax, total, "riqueza", f"Riqueza de especies por celda de igual área ({TABLA}, últimos años)")
    top = sorted(total, key=lambda f: -int(f["riqueza"]))[:20]
    ax.scatter([float(f["lon"]) - 360 if float(f["lon"]) > 0 else float(f["lon"]) for f in top], [float(f["lat"]) for f in top], s=40, facecolors="none",
               edgecolors="red", linewidths=1.2, label="top 20 hotspots")
    ax.legend(loc="lower left")
    fig.colorbar(sc, ax=ax, shrink=0.6, label="n.º de especies (log)")
    fig.tight_layout()
    fig.savefig(os.path.join(RAIZ, "mapas", f"q3_riqueza_{TABLA}.png"), dpi=150)

    est = consulta(f"""SELECT e.estacion, ST_Y(ST_Centroid(q.geom)) lat, ST_X(ST_Centroid(q.geom)) lon, e.riqueza
                        FROM {TABLA}_q3_estacion e JOIN {TABLA}_q3 q USING (i, j)""")
    vmax = max(int(f["riqueza"]) for f in est)
    fig, axs = plt.subplots(2, 2, figsize=(12, 13), sharex=True, sharey=True)
    for ax, e in zip(axs.flat, ["verano", "otono", "invierno", "primavera"]):
        sc = dibujar(ax, [f for f in est if f["estacion"] == e], "riqueza", f"Riqueza en {e} (según hemisferio)", vmax)
    fig.colorbar(sc, ax=axs, shrink=0.5, label="n.º de especies (log)")
    fig.savefig(os.path.join(RAIZ, "mapas", f"q3_riqueza_estaciones_{TABLA}.png"), dpi=130, bbox_inches="tight")
    print("mapas listos en mapas/")


if __name__ == "__main__":
    main()
