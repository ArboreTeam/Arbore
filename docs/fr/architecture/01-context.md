# C4 — Niveau 1 : Context

Cette vue décrit, au plus haut niveau d'abstraction, les **acteurs utilisant Arbore et les systèmes externes avec lesquels l'application interagit**. La structure interne d'Arbore n'est pas représentée à ce niveau : seules les frontières du système et ses interfaces sont visibles.

## Diagramme

> **Note de rendu** : la sémantique C4 (Person, System, External) est préservée dans les labels. La syntaxe utilisée est `flowchart` plutôt que `C4Context` natif, car le layout du C4 Mermaid est encore expérimental et produit des chevauchements d'arêtes sur les graphes denses. Voir [README](../README.md).

```mermaid
flowchart TB
    %% Acteurs
    user["👤 [Person] Utilisateur<br/>Jardinier amateur"]
    reviewer["👤 [Person] Apple Reviewer<br/>appstore.review@arbore.app"]
    team["👤 [Person] Équipe Arbore<br/>Devs + ops"]

    %% Système central
    arbore(("🌱 [System] Arbore<br/>App de jardinage AR"))

    %% Systèmes externes runtime
    subgraph runtime["Systèmes externes — runtime"]
        firebase["[System Ext] Firebase<br/>Auth + Admin SDK"]
        mongo[("[System Ext] MongoDB Atlas<br/>Users / plants / gardens")]
        llm["[System Ext] Mistral AI · Gemini<br/>Assistant et diagnostic"]
        apple_id["[System Ext] Apple ID<br/>Sign in with Apple"]
        cloudflare["[System Ext] Cloudflare<br/>DNS proxifié · TLS · WAF"]
    end

    %% Systèmes externes operate-time
    subgraph operate["Systèmes externes — operate-time"]
        github["[System Ext] GitHub<br/>CI/CD + Dependabot"]
        appstore["[System Ext] Apple Connect<br/>TestFlight + App Store"]
        sentry["[System Ext] Sentry<br/>Crash / erreurs"]
    end

    user      -- "Conçoit et place des plantes"        --> arbore
    reviewer  -- "Valide builds TestFlight"            --> arbore
    team      -- "Développe et opère"                  --> arbore

    arbore    -- "Auth + tokens (HTTPS)"               --> firebase
    arbore    -- "Sign in with Apple"                  --> apple_id
    arbore    -- "Persistance via backend"             --> mongo
    arbore    -- "Assistant et diagnostic (relayés par le backend)" --> llm
    arbore    -- "Tout le trafic public (HTTPS)"       --> cloudflare
    arbore    -- "Télémétrie (opt-in)"                 --> sentry

    team      -- "Push + monitoring CI"                --> github
    team      -- "Upload builds + review"              --> appstore

    classDef person fill:#08427B,stroke:#073B6F,color:#fff
    classDef system fill:#1168BD,stroke:#0B4884,color:#fff
    classDef ext    fill:#999,stroke:#666,color:#fff
    class user,reviewer,team person
    class arbore system
    class firebase,mongo,llm,apple_id,cloudflare,github,appstore,sentry ext
```

## Points clés

- **Arbore vu de l'extérieur** constitue une boîte unique qui communique avec plusieurs systèmes externes en runtime (Firebase, Apple ID, MongoDB Atlas, le fournisseur d'IA, Cloudflare, Sentry) et des systèmes utilisés en operate-time (GitHub Actions, Apple Connect).
- **Trois catégories d'acteurs humains** sont distinguées : utilisateurs finaux (jardiniers), reviewer Apple (compte dédié `appstore.review@arbore.app`) et équipe interne. La review Apple est représentée comme un acteur distinct car son parcours d'usage fait l'objet d'une documentation spécifique (notes TestFlight).
- **Sign in with Apple** est intégré (Guideline 5.1.1) : à la suppression de compte, le backend révoque le token Apple associé (cf. [`03-components-backend.md`](03-components-backend.md)).
- **Sentry est opt-in** : la télémétrie n'est activée que si l'utilisateur accepte le partage de diagnostics (off par défaut), conformément au RGPD. Détails dans [`../operations/observability.md`](../operations/observability.md).
- **Le fournisseur d'IA est joint par le backend, jamais par l'app.** `/chat` et `/diagnose` sont des proxies : la clé ne quitte pas le serveur. Mistral AI est en service depuis le 2026-09-20 (#555), Gemini reste implémenté. Le microservice Python qui générait les fiches a été déposé le même jour (#558) ; cette vue l'a représenté jusqu'au 2026-11-13.
- **Unsplash n'est plus un système externe en runtime.** `UNSPLASH_ACCESS_KEY` est morte avec ce microservice : les images du catalogue sont nos propres rendus, servis par le backend. Plus aucun appel tiers au moment de l'exécution.
- **Le stockage objet n'est pas dans cette vue, et c'est voulu.** Le seau R2 existe et ses identifiants sont conservés, mais `STORAGE_PROVIDER=filesystem` des deux côtés depuis le 2026-10-21 : les modèles sont servis depuis le disque du VPS, par le backend. R2 est un repli dormant, pas une dépendance d'exécution — cf. [`../operations/stockage-assets.md`](../operations/stockage-assets.md).
- **Aucun système de paiement externe** n'est intégré à ce jour : Arbore est gratuit et ne propose pas d'achats in-app. Toute évolution dans ce sens devra mettre à jour ce diagramme (Apple In-App Purchase et éventuellement un PSP).
- **iCloud Private Relay n'est pas représenté** car il ne constitue pas une intégration mais un proxy transparent susceptible de perturber les appels HTTP sortants (cf. issue #90 résolue ; l'accès public est désormais en HTTPS via Cloudflare, voir [`../operations/vps-bootstrap.md`](../operations/vps-bootstrap.md)).

## Vue suivante

Le [niveau 2 — Container](02-containers.md) ouvre la boîte « Arbore » et expose les applications et services qui la composent : application iOS, front web Next.js et backend Go.
