"""Descarga los checklists GRIIS (Global Register of Introduced and Invasive Species) de los países de
América publicados en GBIF y los une en un único TSV: datos/capas/griis/griis_america.tsv

Cada checklist es un Darwin Core Archive con taxon.txt (nombre), distribution.txt (occurrenceStatus,
establishmentMeans) y speciesprofile.txt (isInvasive). Solo usa la biblioteca estándar.

uso:  python scripts/bajar_griis.py
"""
import csv, io, json, os, re, sys, time, urllib.request, zipfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "datos", "capas", "griis")
API = "https://api.gbif.org/v1"
ISSG = "cdef28b1-db4e-4c58-aa71-3c5238c2d0b5"  # publishingOrganizationKey de los checklists GRIIS

# País/territorio de América -> código ISO2 (como countryCode de GBIF)
AMERICA = {
    "Anguilla": "AI", "Argentina": "AR", "Aruba": "AW", "Bahamas": "BS", "Barbados": "BB", "Belize": "BZ",
    "Bermuda": "BM", "Bolivia": "BO", "Brazil": "BR", "Canada": "CA", "Cayman Islands": "KY", "Chile": "CL",
    "Colombia": "CO", "Costa Rica": "CR", "Cuba": "CU", "Curacao": "CW", "Dominica": "DM",
    "Dominican Republic": "DO", "Ecuador": "EC", "El Salvador": "SV", "French Guiana": "GF", "Greenland": "GL",
    "Grenada": "GD", "Guadeloupe": "GP", "Guatemala": "GT", "Ecuador": "EC", "Suriname": "SR", "Guyana": "GY", "Haiti": "HT", "Honduras": "HN",
    "Jamaica": "JM", "Martinique": "MQ", "Mexico": "MX", "Montserrat": "MS", "Nicaragua": "NI", "Panama": "PA",
    "Paraguay": "PY", "Peru": "PE", "Saint Barthelemy": "BL", "Sint Maarten": "SX", "Suriname": "SR",
    "Trinidad and Tobago": "TT", "United States (Contiguous)": "US", "Alaska, United States": "US",
    "Uruguay": "UY", "Venezuela": "VE", "Virgin Islands, British": "VG", "Juan Fernandez Islands, Chile": "CL",
}


def get_json(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def checklists():
    out, offset = [], 0
    while True:
        # Solo la organización que publica GRIIS (ISSG); la búsqueda por texto devuelve ~47 mil datasets
        d = get_json(f"{API}/dataset/search?publishingOrg={ISSG}&type=CHECKLIST&limit=300&offset={offset}")
        out += d["results"]
        offset += 300
        if d["endOfRecords"] or offset >= d["count"]:
            return list({d["key"]: d for d in out}.values())


def pais_de(titulo):
    if "Global Register of Introduced" not in titulo:
        return None
    resto = re.sub(r"^[\s\-–]*(GRIIS)?[\s\-–]*", "", titulo.split("Species", 1)[1])
    for nombre, iso in sorted(AMERICA.items(), key=lambda kv: -len(kv[0])):  # más largo primero
        if resto.startswith(nombre):
            return nombre, iso
    return None


def leer_tabla(z, nombre):
    cand = [n for n in z.namelist() if n.lower().endswith(nombre)]
    if not cand:
        return []
    texto = z.read(cand[0]).decode("utf-8", "replace")
    return list(csv.DictReader(io.StringIO(texto), delimiter="\t", quoting=csv.QUOTE_NONE))


def main():
    os.makedirs(SALIDA, exist_ok=True)
    filas, resumen = [], []
    for ds in checklists():
        p = pais_de(ds["title"])
        if not p:
            continue
        nombre, iso = p
        det = get_json(f"{API}/dataset/{ds['key']}")
        url = next((e["url"] for e in det.get("endpoints", []) if e["type"] == "DWC_ARCHIVE"), None)
        if not url:
            resumen.append((nombre, iso, ds["key"], "SIN DWC-A", 0)); continue
        zpath = os.path.join(SALIDA, f"{ds['key']}.zip")
        if not os.path.exists(zpath):
            urllib.request.urlretrieve(url, zpath)
            time.sleep(0.3)
        z = zipfile.ZipFile(zpath)
        taxa = {t.get("id") or t.get("taxonID"): t for t in leer_tabla(z, "taxon.txt")}
        dist = {d.get("id"): d for d in leer_tabla(z, "distribution.txt")}
        perf = {s.get("id"): s for s in leer_tabla(z, "speciesprofile.txt")}
        for tid, t in taxa.items():
            d, s = dist.get(tid, {}), perf.get(tid, {})
            filas.append({
                "pais": nombre, "countryCode": iso, "datasetKey": ds["key"],
                "scientificName": t.get("scientificName", ""), "acceptedNameUsage": t.get("acceptedNameUsage", ""),
                "taxonRank": t.get("taxonRank", ""), "kingdom": t.get("kingdom", ""),
                "establishmentMeans": d.get("establishmentMeans", ""), "occurrenceStatus": d.get("occurrenceStatus", ""),
                "isInvasive": s.get("isInvasive", ""), "habitat": s.get("habitat", ""),
            })
        resumen.append((nombre, iso, ds["key"], os.path.getsize(zpath), len(taxa)))
    campos = ["pais", "countryCode", "datasetKey", "scientificName", "acceptedNameUsage", "taxonRank", "kingdom",
              "establishmentMeans", "occurrenceStatus", "isInvasive", "habitat"]
    with open(os.path.join(SALIDA, "griis_america.tsv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, campos, delimiter="\t", quoting=csv.QUOTE_NONE, escapechar="\\")
        w.writeheader(); w.writerows(filas)
    for r in sorted(resumen):
        print("\t".join(map(str, r)))
    print(f"checklists={len(resumen)} filas={len(filas)}", file=sys.stderr)


if __name__ == "__main__":
    main()
