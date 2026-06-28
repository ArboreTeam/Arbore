# C4 — Level 1: Context

This view describes, at the highest level of abstraction, the **actors using Arbore and the external systems the application interacts with**. Arbore's internal structure is not represented at this level: only the system boundaries and its interfaces are visible.

## Diagram

> **Rendering note**: the C4 semantics (Person, System, External) are preserved in the labels. The syntax used is `flowchart` rather than native `C4Context`, because the C4 Mermaid layout is still experimental and produces edge overlaps on dense graphs. See [README](../README.md).

```mermaid
flowchart TB
    %% Actors
    user["👤 [Person] User<br/>Amateur gardener"]
    reviewer["👤 [Person] Apple Reviewer<br/>appstore.review@arbore.app"]
    team["👤 [Person] Arbore Team<br/>Devs + ops"]

    %% Central system
    arbore(("🌱 [System] Arbore<br/>AR gardening app"))

    %% External systems — runtime
    subgraph runtime["External systems — runtime"]
        firebase["[System Ext] Firebase<br/>Auth + Admin SDK"]
        mongo[("[System Ext] MongoDB Atlas<br/>Users / plants / gardens")]
        openai["[System Ext] OpenAI / Mistral<br/>LLM plant sheets"]
        unsplash["[System Ext] Unsplash<br/>Catalog photos"]
        apple_id["[System Ext] Apple ID<br/>Sign in with Apple"]
    end

    %% External systems — operate-time
    subgraph operate["External systems — operate-time"]
        github["[System Ext] GitHub<br/>CI/CD + Dependabot"]
        appstore["[System Ext] Apple Connect<br/>TestFlight + App Store"]
        sentry["[System Ext] Sentry<br/>Crash / errors"]
    end

    user      -- "Designs and places plants"          --> arbore
    reviewer  -- "Validates TestFlight builds"         --> arbore
    team      -- "Develops and operates"               --> arbore

    arbore    -- "Auth + tokens (HTTPS)"               --> firebase
    arbore    -- "Sign in with Apple"                  --> apple_id
    arbore    -- "Persistence via backend"             --> mongo
    arbore    -- "Sheet generation (via AI Gen)"       --> openai
    arbore    -- "Plant photos"                        --> unsplash
    arbore    -- "Telemetry (opt-in)"                  --> sentry

    team      -- "Push + CI monitoring"                --> github
    team      -- "Upload builds + review"              --> appstore

    classDef person fill:#08427B,stroke:#073B6F,color:#fff
    classDef system fill:#1168BD,stroke:#0B4884,color:#fff
    classDef ext    fill:#999,stroke:#666,color:#fff
    class user,reviewer,team person
    class arbore system
    class firebase,mongo,openai,unsplash,apple_id,github,appstore,sentry ext
```

## Key points

- **Arbore viewed from the outside** is a single box that communicates with several external systems at runtime (Firebase, Apple ID, MongoDB Atlas, OpenAI/Mistral, Unsplash, Sentry) and systems used at operate-time (GitHub Actions, Apple Connect).
- **Three categories of human actors** are distinguished: end users (gardeners), the Apple reviewer (dedicated account `appstore.review@arbore.app`) and the internal team. The Apple review is represented as a separate actor because its usage journey is the subject of dedicated documentation (TestFlight notes).
- **Sign in with Apple** is integrated (Guideline 5.1.1): upon account deletion, the backend revokes the associated Apple token (see [`03-components-backend.md`](03-components-backend.md)).
- **Sentry is opt-in**: telemetry is only enabled if the user accepts diagnostics sharing (off by default), in compliance with the GDPR. Details in [`../operations/observability.md`](../operations/observability.md).
- **No external payment system** is integrated to date: Arbore is free and offers no in-app purchases. Any change in this direction will require updating this diagram (Apple In-App Purchase and possibly a PSP).
- **iCloud Private Relay is not represented** because it is not an integration but a transparent proxy that may disrupt outbound HTTP calls (see resolved issue #90; public access is now over HTTPS via Cloudflare, see [`../operations/vps-bootstrap.md`](../operations/vps-bootstrap.md)).

## Next view

[Level 2 — Container](02-containers.md) opens the "Arbore" box and exposes the applications and services that make it up: the iOS application, the Next.js web front end, the Go backend and the Python AI Generator.
