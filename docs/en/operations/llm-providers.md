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

## The point that matters most: how free tiers treat your data

**To verify before any decision, and to re-verify regularly.**

Almost every generative API's terms separate the free tier from the paid tier on
something other than price: **what may be done with submitted content**. Several
providers, Google included, reserve the right on free tiers to use submitted
content to improve their products, with possible human review; paid tiers
exclude this.

Arbore transmits **photos taken by users inside their homes**, plus their
messages. If the free tier carries that regime, then:

- the privacy policy must say so — it currently announces transmission "to be
  analysed", which covers neither training nor human review;
- it becomes a strong argument for a European provider, or for a paid tier even
  a symbolic one.

This page does not settle it: it flags that **the verification governs
everything else**, including which providers in the next table are eligible.

## Catalogue of free APIs

⚠️ **The figures below age, and must be re-checked at the source before being
hard-coded.** Free tiers change without notice, sometimes month to month, and
vary by region. This table exists to choose *who to test*, never to feed a
constant.

"Vision" = able to process an image, hence eligible for `/diagnose`. Without it,
a provider can only serve `/chat`.

| Provider | Vision | Free-tier order of magnitude | Verify first |
|---|---|---|---|
| **Google Gemini** (AI Studio) | ✅ | tens of requests/min, hundreds/day depending on model | data regime, EU availability |
| **Mistral** (La Plateforme) | ✅ Pixtral | experimentation tier, phone verification required | **EU hosting** — no transfer outside the EU |
| **Groq** | ✅ Llama 4 | generous daily request counts, very fast | training policy, vision model availability |
| **Cerebras** | ❌ mostly text | daily token allowance | covers `/chat` only |
| **OpenRouter** | ✅ model-dependent | `:free` variants, low ceiling without credit | which underlying model, and its terms |
| **Cloudflare Workers AI** | ✅ model-dependent | daily allowance | already a project provider (R2, CDN) |
| **GitHub Models** | ✅ model-dependent | tiers tied to the GitHub account | is production use permitted? |
| **Cohere** | ✅ Aya Vision | trial key, monthly ceiling | commercial use excluded from the trial tier |

Two selection notes:

**Mistral deserves separate consideration.** It is the only entry hosted in
Europe. The privacy policy currently handles a non-EU transfer with standard
contractual clauses; a European provider would make that moot for these two
routes. And `initLLMProvider()` is already waiting for it.

**Cloudflare is already a project processor** (R2, CDN, WAF). Routing AI through
it adds no new processor to declare.

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
