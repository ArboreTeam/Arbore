# Environments: prod, dev, and how to target either

This document is for **whoever develops the iOS app** and wants to work against
the development backend rather than production.

For the server-side mechanics (two Docker stacks, nginx, deployment), see
[`../architecture/05-infrastructure.md`](../architecture/05-infrastructure.md).
For provisioning, [`vps-bootstrap.md`](vps-bootstrap.md).

---

## The two environments

|          | branch | address              | database     | deployed  |
|----------|--------|----------------------|--------------|-----------|
| **prod** | `main` | `api.arbore.app`     | `arbore`     | manually  |
| **dev**  | `dev`  | `api-dev.arbore.app` | `arbore_dev` | manually  |

Breaking dev has no effect on beta testers. That is its purpose.

### ⚠️ They are no longer on the same machine

Recorded on 2026-11-02. The #652 migration is **under way**, and the two
environments now live on two different VPSs:

| | machine | path | user |
|---|---|---|---|
| **prod** | old VPS, `79.137.92.154` | `/home/fedora/Arbore` | `fedora` |
| **dev** | new VPS, `162.19.13.82` | `/home/debian/Arbore` | `debian` |

`generator.arbore.app` (the 3D workshop) and `api-dev.arbore.app` point at the
**new** VPS; `api.arbore.app` and `web.arbore.app` at the old one.

**And the layout changed in kind.** The old machine held two separate git
checkouts — `Arbore` and `Arbore-dev` — which kept each environment's data
apart without anyone having to think about it: the `docker-compose.yml`
defaults are **relative to the compose file**.

The new machine holds a **single checkout** for two compose stacks
(`arbore-prod` and `arbore-dev`). The same defaults therefore converge on the
same directories. That is what made both backends share their thumbnail
directory **writable** until 2026-11-02.

What is partitioned today, and what is not, is tracked in #434. `deploy.sh`
now refuses to start when another environment already mounts the target
directory.

---

## The three iOS build configurations

| configuration | backend called | use                                         |
|---------------|----------------|---------------------------------------------|
| `Debug`       | **production** | everyday debugging, against real data       |
| `Dev`         | **dev**        | test a backend feature not yet promoted     |
| `Release`     | production     | TestFlight build                            |

**`Debug` targets production, deliberately.** That is what you want most of the
time: reproducing a bug reported by a beta tester requires their data. Pointing
`Debug` at dev would have made that common case impossible without
reconfiguration.

Hence a third configuration rather than two: choosing an environment becomes
explicit, instead of a side effect of "am I debugging or shipping".

### Where it is wired

```
ArboreUi/Dev.xcconfig            Dev configuration — host, protocol
  └── #include? Secrets.dev.xcconfig    API key (gitignored, absent from the repo)

ArboreUi/Debug.xcconfig          Debug and Release configurations
ArboreUi/Release.xcconfig
  └── #include? Secrets.xcconfig        same, for production
```

The `#include?` with a question mark is an **optional include**: if the secrets
file is missing, the build still succeeds, with an empty key. That is what lets
CI compile without secrets — but it is also why a forgotten file shows up as a
runtime `401`, not as a compile error.

---

## Switching to dev

**1. Obtain `ArboreUi/Secrets.dev.xcconfig`.**

It carries the dev backend's API key, so it is not in the repository
(`.gitignore`). Two ways to get it:

- ask a maintainer;
- or, if you hold the `dev` age key, generate it:

  ```sh
  cp ArboreUi/Secrets.dev.xcconfig.example ArboreUi/Secrets.dev.xcconfig
  SOPS_AGE_KEY_FILE=~/.config/sops/age/arbore-dev.txt \
    sops --decrypt ops/secrets/dev.enc.env | grep '^ARBORE_API_KEY='
  ```

  then copy the value into `ARBORE_API_KEY`.

**2. Place the file in `ArboreUi/`.**

**3. In Xcode, select the "ArboreUi Dev" scheme.**

**4. Run.** To go back to production, switch back to the "ArboreUi" scheme.

### Check which backend you are hitting

```sh
curl https://api.arbore.app/health
curl https://api-dev.arbore.app/health
```

Each returns the commit it is running. Two different commits means dev is ahead
of prod, which is the normal state while a feature is in flight.

---

## Contributing: `dev` no longer accepts direct pushes

Since 2026-09-08 the `dev` branch is protected. Every change goes through a
**pull request**, administrators included.

```sh
git checkout dev && git pull
git checkout -b feat/my-feature
# … commits …
git push -u origin feat/my-feature
gh pr create --base dev
```

| Rule | Value |
|---|---|
| Pull request | required |
| Required approvals | **0** — you merge your own PR |
| Required checks | `build_summary`, `security` |
| Direct push, force-push, deletion | refused |

**Zero approvals** is deliberate: with two people on the repository, requiring a
review would block solo work. The PR becomes mandatory, not third-party sign-off.

These two checks are the only ones that can **never** be skipped:
`build_summary` has `if: always()` and aggregates the four build jobs;
`security` has no path condition, so it runs on every PR. The other jobs are
conditioned on the PR's content and would be `skipped` — hence treated as
satisfied — on a docs or iOS pull request.

> **Why it applies to administrators.** The first configuration left
> `enforce_admins: false`. A direct push then went through anyway, leaving only
> a `remote: Bypassed rule violations` line behind. A rule that can be stepped
> over informs; it does not protect.

The next day, the `security` check blocked an unrelated PR over an
[unauthenticated RCE in Next.js](https://github.com/advisories/GHSA-2xp9-vwfh-vxw4)
published in the meantime. Without this configuration the PR would have merged.

`main` stays less strict: its protection mainly forbids direct pushes, and a PR
promoted from `dev` has already passed the upstream gate.

---

## Deploying an environment

Deployment is **manual**, by choice: nobody ships to production without knowing
it. On the VPS, one checkout per environment.

```sh
# production — old VPS
cd /home/fedora/Arbore && ./deploy.sh

# development — new VPS
cd /home/debian/Arbore && ARBORE_ENV=dev ARBORE_DEPLOY_BRANCH=dev ./deploy.sh
```

Three traps, all hit for real:

**`ARBORE_DEPLOY_BRANCH=dev` is mandatory for dev.** Without it the script
refuses: `Checkout sur 'dev', attendu 'main' — déploiement refusé`. This guard
(#384) exists because a checkout left on a working branch would deploy that
branch silently. The default is `main`, so production does not set the variable.

**Do not run `deploy.sh` under `sudo`.** The script handles Docker elevation
itself: the user does not need to be in the `docker` group.

> ⚠️ **The symptom described here is gone, the reason is not.** This warning
> announced a `Permission denied (publickey)` on `git pull`, back when the
> remote used SSH. It moved to **public HTTPS**: under `sudo`, the pull now
> **succeeds**. The warning went silent, and it was ignored all through
> 2026-11-02.
>
> The two real consequences, measured that day:
>
> | | |
> |---|---|
> | `$HOME` becomes `/root` | the age key is not found, `apply_secrets` **warns then returns 0** — the deployment reports "finished" while running on the **old** secrets |
> | files are written by root | **167 entries out of 1021** in `.git`, and the next manual `git pull` fails |
>
> Verified without `sudo`: secrets decrypted, images pulled, health 200, and
> **0 root-owned entries** in `.git`.
>
> Since #716 the script tolerates being run under `sudo` — it recovers the real
> user through `SUDO_USER` and works under that identity. That is a safety net,
> not a licence: run it without.

**Wait for images to be published.** `deploy.sh` pulls the image tagged
`sha-<commit>`; if the publish workflow has not finished, the pull fails and the
script falls back to a local build — slow, and the running image is then no
longer the one CI produced. Check before deploying:

```sh
gh api "repos/ArboreTeam/Arbore/actions/runs?head_sha=$(git rev-parse origin/main)" \
  --jq '.workflow_runs[] | select(.name|test("Build")) | .conclusion'
```

`gh run list --commit <sha>` sometimes returns stale results, including deleted
workflows. The direct API call above is reliable.

---

## What differs on dev

**Sentry is off.** Without a DSN the SDK does not start, so test crashes do not
pollute production reports. `Secrets.dev.xcconfig` therefore leaves the three
`SENTRY_DSN_*` variables empty — that is intended, do not fill them in.

**3D models are read from disk**, not from R2. Dev has no bucket credentials:
giving it any would have meant a dev age key opens write access to production
storage.

**The Firebase project is shared with production.** This is a decision, not a
missing step: one project per environment would mean duplicating accounts,
security rules and Apple certificates for every environment, for little benefit
at our scale.

> ⚠️ **Consequence worth remembering.** An account created on dev also exists on
> production, and deleting an account on dev deletes the Firebase identity for
> good. Give notice before testing deletion flows.

---

## References

- Umbrella issue: [#401](https://github.com/ArboreTeam/Arbore/issues/401)
- Dev environment: [#434](https://github.com/ArboreTeam/Arbore/issues/434)
- Remaining hardcoded constants: [#456](https://github.com/ArboreTeam/Arbore/issues/456)
