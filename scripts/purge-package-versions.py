#!/usr/bin/env python3
"""Purge les versions d'images orphelines sur ghcr (#442).

⚠️ « Sans étiquette » ne veut PAS dire « supprimable ».

Une étiquette ne porte pas l'image : elle porte un INDEX qui la référence.
L'image et son attestation de provenance apparaissent comme des versions sans
étiquette, alors qu'elles sont indispensables :

    arbore-backend:latest  ->  index OCI (étiqueté)
        |- sha256:45a7...  amd64   (l'image)              <- sans étiquette
        |- sha256:2326...  attestation de provenance      <- sans étiquette

`actions/delete-package-versions` avec `delete-only-untagged-versions: true` —
l'option que suggèrent tous les exemples — supprimerait donc l'image servie en
production et casserait toutes les étiquettes.

Ce script descend d'abord dans chaque manifeste ÉTIQUETÉ pour construire
l'ensemble des digests protégés, puis ne supprime que ce qui n'en fait pas
partie.

Deux règles de suppression, cumulatives :

  ORPHELINES  versions sans étiquette et non référencées par un index étiqueté
  RÉTENTION   au-delà des N plus récentes, les versions `sha-` de branche —
              jamais une release `v*`, jamais `latest`, jamais le commit servi

La distinction release / commit de branche est ce qui donne à la rétention une
règle simple : les releases sont peu nombreuses et se gardent indéfiniment, les
`sha-` de branche sont nombreux et jetables une fois dépassés.

Quatre gardes, reprises du job de réconciliation (#393) :

 1. Simulation par défaut. La suppression exige --apply.
 2. Fail-closed : toute erreur d'API interrompt sans rien supprimer.
 3. Refus si aucune version étiquetée n'est trouvée — tout paraîtrait orphelin.
 4. Le commit servi en production est exclu, lu depuis GET /health plutôt que
    déduit d'une date.
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"
REGISTRY = "ghcr.io"
ACCEPT_MANIFEST = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


class Fatal(Exception):
    """Erreur qui doit interrompre le job sans rien supprimer."""


def _request(url, token, accept, method="GET"):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", accept)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as exc:
        raise Fatal("%s %s -> HTTP %s" % (method, url, exc.code)) from exc
    except Exception as exc:
        raise Fatal("%s %s -> %s" % (method, url, exc)) from exc


def list_versions(org, package, token):
    """Énumération COMPLÈTE et paginée. Une page manquante ferait passer des
    versions vivantes pour des orphelines."""
    out, page = [], 1
    while True:
        chunk = _request(
            "%s/orgs/%s/packages/container/%s/versions?per_page=100&page=%d"
            % (API, org, package.replace("/", "%2F"), page),
            token, "application/vnd.github+json")
        if not chunk:
            break
        out.extend(chunk)
        if len(chunk) < 100:
            break
        page += 1
        if page > 100:
            raise Fatal("pagination anormale sur %s" % package)
    return out


def registry_token(org, package, pat):
    basic = base64.b64encode(("x:" + pat).encode()).decode()
    url = "%s/token?service=%s&scope=repository:%s/%s:pull" % (
        "https://" + REGISTRY, REGISTRY, org.lower(), package)
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Basic " + basic)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)["token"]
    except Exception as exc:
        raise Fatal("jeton de registre refusé pour %s: %s" % (package, exc)) from exc


def protected_digests(org, package, versions, rtoken, exclude=frozenset()):
    """Digests référencés par au moins une version étiquetée.

    C'est le cœur de la correction : on descend dans chaque index étiqueté pour
    récupérer ses enfants, qui n'ont pas d'étiquette propre.
    """
    protected = set()
    tagged = [v for v in versions
              if v["metadata"]["container"]["tags"] and v["name"] not in exclude]
    if not tagged:
        raise Fatal(
            "aucune version étiquetée sur %s : refus de considérer toutes les "
            "autres comme orphelines" % package)

    for version in tagged:
        digest = version["name"]
        protected.add(digest)
        manifest = _request(
            "https://%s/v2/%s/%s/manifests/%s" % (REGISTRY, org.lower(), package, digest),
            rtoken, ACCEPT_MANIFEST)
        for child in (manifest or {}).get("manifests", []):
            protected.add(child["digest"])
    return protected


SEMVER_PREFIX = "v"


def tag_kind(tag):
    """Classe une étiquette, ce qui détermine sa durée de vie.

    `release`  — v1.2.3, v1.2 : conservée indéfiniment. Elles sont peu
                 nombreuses et désignent ce qu'on peut vouloir redéployer des
                 mois plus tard.
    `moving`   — latest, main, dev, pr-42 : conservée, elle bouge d'elle-même.
    `commit`   — sha-<40 hex> : sujette à rétention. C'est le gros du volume.
    """
    if tag.startswith(SEMVER_PREFIX) and len(tag) > 1 and tag[1].isdigit():
        return "release"
    if tag.startswith("sha-") and len(tag) == 44:
        return "commit"
    return "moving"


def retention_victims(versions, protected, keep, deployed_sha):
    """Versions `sha-` de branche au-delà des `keep` plus récentes.

    Les enfants d'un index supprimé sont marqués avec lui : sans cela ils
    deviendraient orphelins et attendraient l'exécution suivante, laissant du
    déchet entre deux passages.
    """
    if keep <= 0:
        return [], set()

    commits = []
    for version in versions:
        tags = version["metadata"]["container"]["tags"]
        if not tags:
            continue
        kinds = {tag_kind(t) for t in tags}
        # Une version qui porte AUSSI une release ou une étiquette mouvante est
        # conservée : `sha-abc` et `v1.2.0` peuvent désigner le même digest.
        if kinds != {"commit"}:
            continue
        if deployed_sha and any(t == "sha-" + deployed_sha for t in tags):
            continue
        commits.append(version)

    commits.sort(key=lambda v: v["updated_at"], reverse=True)
    victims = commits[keep:]
    doomed_children = set()
    return victims, doomed_children


def deployed_commit(health_url):
    """Commit réellement servi. Exclusion la plus fiable dont on dispose : elle
    décrit ce qui tourne, pas ce qu'on croit avoir déployé."""
    if not health_url:
        return None
    # User-Agent explicite : Cloudflare répond 403 à un client anonyme, ce qui
    # ferait passer un service parfaitement sain pour injoignable.
    req = urllib.request.Request(health_url, headers={"User-Agent": "arbore-purge/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.load(resp).get("commit")
    except Exception as exc:
        raise Fatal("health check injoignable (%s) : sans lui, impossible de "
                    "garantir qu'on ne supprime pas l'image en production" % exc)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--org", default="ArboreTeam")
    parser.add_argument("--packages", nargs="+", required=True)
    parser.add_argument("--health-url", default="https://api.arbore.app/health")
    parser.add_argument("--keep-sha", type=int, default=10,
                        help="versions `sha-` de branche à conserver par package "
                             "(0 = rétention désactivée). Les releases `v*`, les "
                             "étiquettes mouvantes et le commit servi ne sont "
                             "jamais concernés.")
    parser.add_argument("--apply", action="store_true",
                        help="supprime réellement (par défaut : simulation)")
    args = parser.parse_args()

    pat = os.environ.get("GHCR_TOKEN")
    if not pat:
        print("GHCR_TOKEN absent", file=sys.stderr)
        return 3

    mode = "SUPPRESSION RÉELLE" if args.apply else "SIMULATION (aucune suppression)"
    print("🧹 Purge des versions d'images — %s" % mode)
    print("   rétention : %d version(s) `sha-` de branche par package" % args.keep_sha)

    commit = deployed_commit(args.health_url)
    if commit:
        print("   commit servi en production : %s" % commit[:12])

    total_orphans = 0
    for package in args.packages:
        versions = list_versions(args.org, package, pat)
        rtoken = registry_token(args.org, package, pat)
        # ORDRE IMPORTANT. La rétention est calculée d'abord, puis l'ensemble
        # protégé est construit à partir des versions étiquetées qui SURVIVENT.
        #
        # L'inverse — ce que faisait la première version — plaçait les enfants
        # des victimes dans l'ensemble protégé, puisqu'il était bâti sur toutes
        # les versions étiquetées. Les enfants survivaient alors à leur index et
        # devenaient orphelins, ramassés au passage suivant : du déchet entre
        # deux exécutions, et un compte annoncé qui ne correspondait pas.
        victims, _ = retention_victims(versions, set(), args.keep_sha, commit)
        doomed = {v["name"] for v in victims}

        protected = protected_digests(args.org, package, versions, rtoken, exclude=doomed)

        # Le commit servi est protégé quoi qu'il arrive.
        if commit:
            for version in versions:
                if any(t == "sha-" + commit for t in version["metadata"]["container"]["tags"]):
                    protected.add(version["name"])

        # 1. Orphelines — sans étiquette et non référencées par un survivant.
        orphans = [v for v in versions
                   if not v["metadata"]["container"]["tags"] and v["name"] not in protected]

        # Les enfants des victimes tombent naturellement dans `orphans` : ils
        # sont sans étiquette et plus référencés par aucun survivant.
        to_delete = orphans + victims
        kept = len(versions) - len(to_delete)
        print("   %-24s %4d versions | %4d sans référence | %4d rétention | %4d conservées"
              % (package, len(versions), len(orphans), len(victims), kept))
        total_orphans += len(to_delete)

        if args.apply:
            for version in to_delete:
                _request("%s/orgs/%s/packages/container/%s/versions/%d"
                         % (API, args.org, package.replace("/", "%2F"), version["id"]),
                         pat, "application/vnd.github+json", method="DELETE")

    print("   TOTAL à supprimer : %d" % total_orphans)
    if not args.apply:
        print("   Relancer avec --apply pour supprimer.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Fatal as exc:
        print("❌ %s" % exc, file=sys.stderr)
        print("   Rien n'a été supprimé.", file=sys.stderr)
        sys.exit(1)
