#!/usr/bin/env python3
"""Collecte la liste ASPCA des plantes toxiques et non toxiques.

Source : https://www.aspca.org/pet-care/aspca-poison-control/toxic-and-non-toxic-plants

Quatre listes filtrées suffisent (toxique chiens / chats / chevaux, et non
toxique), ce qui évite d'ouvrir les 472 fiches de détail une par une.

Sortie : aspca.json — { "scientific_name_normalisé": {...} }
"""
import json, re, time, urllib.parse, urllib.request, html, pathlib, sys

BASE = "https://www.aspca.org/pet-care/aspca-poison-control/toxic-and-non-toxic-plants"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36"

LISTES = {
    "dogs":   {"field_toxicity_value[]": "01"},
    "cats":   {"field_toxicity_value[]": "02"},
    "horses": {"field_toxicity_value[]": "03"},
    "safe":   {"field_non_toxicity_value[]": "01"},   # non toxique chiens
}


def fetch(params, page):
    q = dict(params); q["page"] = str(page)
    url = BASE + "?" + urllib.parse.urlencode(q)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def parse(page_html):
    """Retourne [(nom commun, nom scientifique)] pour une page."""
    out = []
    for row in re.findall(r'<div class="views-row.*?(?=<div class="views-row|<div class="item-list)', page_html, re.S):
        common = re.search(r'<div class="plant-title-name">([^<]+)</div>', row)
        sci_block = re.search(r'views-field-title-scientific-name.*?<span class="field-content">(.*?)</span>', row, re.S)
        sci = ""
        if sci_block:
            sci = re.sub(r"<[^>]+>", "", sci_block.group(1))
        if common:
            out.append((html.unescape(common.group(1)).strip(),
                        html.unescape(sci).strip()))
    return out


def normalise(nom):
    """Nom scientifique comparable : minuscules, sans auteur ni cultivar."""
    n = nom.lower().strip()
    n = re.sub(r"\(.*?\)", " ", n)          # (Fam. …)
    n = re.sub(r"['\"].*?['\"]", " ", n)     # cultivars 'Nom'
    n = re.sub(r"[^a-z× ]", " ", n)
    n = re.sub(r"\s+", " ", n).strip()
    return n


def collecte(nom_liste, params):
    vus, page = {}, 0
    while True:
        h = fetch(params, page)
        lignes = parse(h)
        if not lignes:
            break
        for common, sci in lignes:
            if not sci:
                continue
            for variante in [s.strip() for s in re.split(r"[,;]", sci) if s.strip()]:
                cle = normalise(variante)
                if cle:
                    vus.setdefault(cle, common)
        page += 1
        if page > 60:                        # garde-fou
            break
        time.sleep(0.4)                      # ne pas marteler la source
    print(f"  {nom_liste:7} : {len(vus)} noms scientifiques sur {page} pages", file=sys.stderr)
    return vus


def main():
    resultat = {}
    for nom, params in LISTES.items():
        for cle, common in collecte(nom, params).items():
            e = resultat.setdefault(cle, {"commonName": common, "toxicTo": [], "safeFor": []})
            (e["safeFor"] if nom == "safe" else e["toxicTo"]).append(nom)
    out = pathlib.Path(__file__).with_name("aspca.json")
    out.write_text(json.dumps(resultat, ensure_ascii=False, indent=1, sort_keys=True))
    toxiques = sum(1 for v in resultat.values() if v["toxicTo"])
    print(f"  total   : {len(resultat)} espèces, dont {toxiques} toxiques", file=sys.stderr)
    print(f"  écrit   : {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
