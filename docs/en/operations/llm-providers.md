# LLM providers — state, quotas and failover

Arbore calls a language model on two routes: the gardening assistant
(`POST /chat`) and plant health diagnosis (`POST /diagnose`). This page records
what runs today, what the free quotas cost, and what the code would need to
learn in order to switch providers.

## Measured state, 2026-09-20

| | Value | Source |
|---|---|---|
| Abstraction | `LLMProvider` (Name, Generate) | [`ArboreBackend/llmprovider.go`](../../../ArboreBackend/llmprovider.go) |
| Implementations | **exactly one** — Gemini | [`gemini_provider.go`](../../../ArboreBackend/gemini_provider.go) |
| Model | `gemini-2.5-flash`, overridable via `GEMINI_MODEL` | `defaultGeminiModel` |
| Selection | `AI_PROVIDER`, read **once at startup** | `initLLMProvider()` |
| Key | **a single key, shared by every user** | `GEMINI_API_KEY` |
| Timeout | 60 s | `http.Client{Timeout: ...}` |
| Max image | 6 MB once base64-decoded | `validateAIImage` |

The abstraction itself is sound: handlers deal in neutral types (`LLMRequest`,
`LLMResult`) and know nothing of the concrete provider. Adding Mistral or Groq
means writing one implementation — `initLLMProvider()` already holds a
commented-out `case "mistral"`.

Three limits, however, are structural.

**The provider is frozen at startup.** `activeLLMProvider` is a global set once.
Nothing can change it at runtime, so nothing can react to an exhausted quota
short of restarting the container with a different environment variable.

**Both routes share one model.** `generateLLM` is called identically from
`handleGeminiChat` and `handleGeminiDiagnose`: the request carries no notion of
purpose. There is no way today to send chat to a light model and diagnosis to a
vision model, even though their costs have nothing in common.

**Neither route queries the database.** See below.

## Diagnosis is not augmented with our catalogue

Recurring question, measured answer: **no, the health scan does no RAG**. The
`/chat` and `/diagnose` handlers contain **zero** Mongo access.

What `/diagnose` sends to the model:

- the base64 JPEG image;
- the plant name typed by the user, sanitised and explicitly presented as data
  rather than as an instruction;
- four colour ratios computed **on the device** (green, yellow, brown, white
  spots);
- a phytopathology system prompt.

The 123 catalogue entries — their care data, toxicity, `botanicalProfile` — are
never consulted. Nor is the species the model returns reconciled against the
catalogue: it is normalised (`normalizeDiagnose`) and returned as-is.

This is a default, not a documented decision. Two consequences: the model may
name a species absent from the catalogue, and it knows nothing of the conditions
the user has already declared for that garden.

## Arbore quotas, not to be confused with the provider's

The backend enforces its own limits, per user and per tier
(anonymous / signed-in / premium):

| Route | Per minute | Per 24 h (anon / signed-in / premium) |
|---|---|---|
| `/chat` | 20 | 10 / 100 / 500 |
| `/diagnose` | 6 | 3 / 20 / 100 |

These figures protect the project's **shared key**; they know nothing of
Google's actual quotas. Nothing connects the two today: Arbore may well allow a
call that Gemini then refuses with a 429.

The 1-to-5 ratio between diagnosis and chat already reflects the right
intuition — a request carrying an image costs far more than a conversation turn.

## How free tiers treat your data — verified 2026-09-20

This is the criterion that decides, ahead of quota and ahead of speed. Arbore
transmits **photos taken by people inside their homes**. Here is what the terms
say, read at the source.

### What Google says about its free tier

The Gemini API terms separate "Unpaid Services" from "Paid Services". For the
free tier:

> Google uses the content you submit to the Services and any generated responses
> to provide, improve, and develop Google products and services

> human reviewers may read, annotate, and process your API input and output

And the sentence that settles it:

> **Do not submit sensitive, confidential, or personal information to the Unpaid
> Services.**

Google disconnects the data from the account and API key before review, but
human review of the images remains expected. The paid tier excludes improvement
use — *"Google doesn't use your prompts or responses to improve our products"* —
with retention limited to abuse detection.

**Arbore runs on the free tier today and sends photos of people's interiors
through it.** That is precisely what the sentence above asks you not to do.
Tracked in a dedicated issue.

### Mistral is not the obvious refuge

Counter-intuitive, which is why it must be read: **Mistral's free "Experiment"
tier is opted IN by default** to the improvement programme. Paid tiers are not
used for training, and the Scale plan is excluded outright.

**Two settings, not one**, at <https://admin.mistral.ai/plateforme/privacy>:

| Setting | Desired state | Why |
|---|---|---|
| *Data usage for improving our services* | **off** | the opt-out proper; the free tier is opted IN |
| *Enable Labs models* | **off** | its own wording says data may train Mistral models *"regardless of my subscription plan or opt-out settings"* — enabling it **voids** the first |

The second is the trap. It does not override the opt-out by design accident: it
says so in the checkbox itself. Enabling Labs models means accepting training
whatever else you set.

**Corollary for `MISTRAL_MODEL`**: never point it at a Labs model. The model
name comes from the environment, so no line of code can prevent that switch —
only configuration discipline can.

⚠️ The Privacy page visible in the navigation **governs Vibe, not the API**. The
two sets of toggles are independent, and `/api/privacy` does not exist: it is
`/plateforme/privacy`.

Mistral therefore remains the best candidate — but **at the cost of two explicit
actions to take and to verify**, not by default.

### The three that do not train, with nothing to do

| Provider | Commitment | Caveat |
|---|---|---|
| **Groq** | contractually not permitted to use inputs or outputs to train or fine-tune, **with no free/paid split** | data held in GCP buckets **in the United States**; 30-day abuse retention, zero-data-retention option |
| **Cloudflare Workers AI** | *"Cloudflare does not use your Customer Content to (1) train any AI models made available on Workers AI or (2) improve any Cloudflare or third-party services"* | **already a project processor** (R2, CDN, WAF) |
| **Cerebras** | no training right over service content, inputs and outputs not retained | **US** data centres; mostly text, so `/chat` only |

### To rule out as they stand

**OpenRouter**: the platform itself does not train, but it only routes. Its own
documentation warns that **most free endpoints train on the prompts they
receive, or even publish them**. Usable only by restricting routing to
zero-data-retention providers.

**GitHub**: since April 2026, Copilot interactions on Free, Pro and Pro+ tiers
feed training by default, with opt-out available. That covers Copilot; the
GitHub Models regime was not verified here and must not be inferred from it.

### What this means for Arbore

Two families of answers, at different costs:

1. **Stay outside the EU but without training** — Groq or Cloudflare. Nothing to
   enable, but the non-EU transfer remains, under the standard contractual
   clauses the privacy policy already describes.
2. **Stay in the EU** — Mistral, with the toggle turned off. Removes the non-EU
   transfer for these two routes, at the cost of a setting to maintain and
   re-verify.

In every case, **Gemini's free tier is the only entry whose terms explicitly ask
you not to send personal data**.

## What the code would need to learn

Three distinct steps, in the order they depend on each other:

1. **Distinguish purpose.** Add a purpose field to `LLMRequest` (or a parameter
   to `generateLLM`) so `/chat` and `/diagnose` can target different models.
   It is the prerequisite for the other two, and it is small.

2. **Make selection dynamic.** `activeLLMProvider` becomes a registry of
   providers rather than a single global, with a preference order per purpose.

3. **Fail over on exhaustion.** On `429` or on a local quota breach, try the
   next provider. This requires recognising a quota refusal — each API signals
   it differently — and avoiding retry loops.

## One key per user?

The idea: each user supplies their own key, consumes their own free quota, and
the project's shared key disappears.

Technically it is feasible — `GeminiProvider` already carries its key as a
field, so taking it per request is a small change. But three obstacles decide
before the technical question does:

- **Terms of service.** A personal key is issued to a person for their own use.
  Having a third-party application consume it falls outside that framing with
  some providers. **To verify provider by provider before any development.**
- **Experience.** Asking a gardener to create a Google AI Studio account and
  paste a key loses most users over a secondary feature.
- **Storage.** A personal key is a secret: iOS keychain on device, never the
  database, never the logs — and a new category to declare in the privacy
  labels.

One middle path holds up: shared key by default with today's quotas, and an
**optional** personal key for users who want their limits lifted. That
presupposes the three steps above.

## See also

- [`observability.md`](observability.md) — what the backend logs
- [`prepublication-security.md`](prepublication-security.md) — secret handling
