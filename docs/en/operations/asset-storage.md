# 3D asset storage

Where the catalogue's 372 files live — 124 light models, 124 high-definition,
124 thumbnails — and how to move them without interrupting service.

## Why this document exists

Access to the current VPS is cut off **at the end of February**. The assets
exist there in a single copy: without a migration they disappear with the
machine. This document describes the manoeuvre so it does not depend on the
memory of whoever prepared it.

## The three backing stores

A single set of variables configures all of them: R2, S3 and MinIO speak the
same protocol. Changing provider means changing **values**, not fields — that is
what the `StorageProvider` abstraction buys
(`ArboreBackend/storageprovider.go`).

| `STORAGE_PROVIDER` | Use | Specificity |
|---|---|---|
| `filesystem` | default, and current production state | serves from `MODELS_HOST_PATH` |
| `r2` / `s3` | intended production | no egress fees with R2 |
| `minio` | local development | `STORAGE_S3_USE_SSL=false` |

The full variable inventory, with one example per store, is in
[`ops/secrets/env.template`](../../../ops/secrets/env.template).

## Why Cloudflare R2

**R2 never charges for egress.** A mobile app downloading 121 MB models makes
that line item unpredictable with a provider that meters it — the only real
financial risk in this project.

Cloudflare is also already in the chain: no extra provider to operate, and a
10 GB free tier that does not expire.

> ⚠️ **Do not pick the *Infrequent Access* storage class.** It lowers storage
> price but **charges for retrieval** — reintroducing exactly the per-download
> cost R2 lets you avoid.

## Creating the bucket

Cloudflare dashboard → **R2 Object Storage** → *Create bucket*.

```
Name             arbore-assets      (permanent)
Location         Automatic
Storage class    Standard           ← never Infrequent Access
```

A payment method is required at activation, even below the free 10 GB. Set a low
**billing alert** in the account notifications.

### The API token

R2 → **Manage R2 API Tokens** → *Create **Account** API Token*.

| Setting | Value | Why |
|---|---|---|
| Type | **Account**, not User | a user token dies with its creator's access; production must not depend on that |
| Permissions | **Object Read & Write** | *Admin* would allow deleting the bucket itself |
| Scope | **this bucket only** | "all buckets, including future ones" defeats the scoping |
| TTL | unlimited | a forgotten expiry would break service silently; rotate manually instead |
| IP filter | empty | a filter turns every machine change into a hard-to-diagnose outage |

⚠️ **The secret key is shown only once.**

### The endpoint

Read it from the **bucket settings, S3 API section** — do not reconstruct it
from memory. A bucket with EU jurisdiction is addressed as
`<account-id>.eu.r2.cloudflarestorage.com`, with a `.eu.` that is easily missed.

Strip the `https://` and anything after the host: the library wants the bare
host.

## Migrating to R2 — order matters

The reverse order would have production serving from an empty bucket: every
model 404, immediately.

```
1. add the credentials to ops/secrets/prod.enc.env,
   leaving STORAGE_PROVIDER=filesystem       ← production does not move
2. deploy                                     ← the VPS receives the credentials
3. upload the 372 files from the VPS
4. verify checksums
5. set STORAGE_PROVIDER=r2 and redeploy
```

Credentials are added without ever passing through plaintext:

```bash
EDITOR=nano SOPS_AGE_KEY_FILE=~/.config/sops/age/arbore-prod.txt \
  sops ops/secrets/prod.enc.env
```

## Rolling back

**Delete nothing from disk until the switch is proven.** Rollback then fits in
one variable:

```
STORAGE_PROVIDER=filesystem
```

followed by a deploy. The files still being in `arbore-data/models`, service
resumes as before.

Only once the app has been seen actually downloading from R2 may the disk be
cleaned — and an off-machine copy must exist by then.

## The guard

`guardedStorage` wraps **every** backing store, disk included, and refuses
beyond configured thresholds. A runaway on local disk is not free either: it
saturates I/O and masks the defect causing it.

```
STORAGE_MAX_OPS_PER_MINUTE   default 200; 0 = unlimited
STORAGE_MAX_OBJECT_BYTES     default 200 MiB
```

A refusal returns **503 with `Retry-After`**, not 404: the file exists, it is the
backend refusing to serve it. Refusals are logged per window, naming the
variable to raise — a threshold set too low will not degrade service silently.

On a local MinIO, raise it generously: operations cost nothing there.

The guard counts **direct reads and presigned URLs alike**: each produces
exactly one billable operation. An earlier version exempted presigning, which
made the guard inert — with a store that can sign, that is the only path taken.

The default of 200 per minute comes from a calculation:

```
200 × 60 × 24 × 30 = 8,640,000 operations/month
R2 free tier       = 10,000,000
```

**Sustained at the ceiling for a whole month, the cost stays zero.** That is a
stronger property than "it should be fine". A realistic beta peak is measured in
tens of operations per minute, not hundreds.

> The counter is in memory, per process, reset on restart. Repeated restarts
> would therefore loosen the monthly bound. A billing alert on the provider side
> remains useful.

## References

#401 step 5 (abstraction and quotas) · #341 (assets outside the git checkout) ·
[`ops/secrets/README.md`](../../../ops/secrets/README.md) (SOPS procedure)
