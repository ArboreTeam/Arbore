# TestFlight Deploy — Fastlane

Procedure for submitting a new iOS app build to TestFlight and
automatically distributing it to the internal "Internal QA" group. Main
lane: `bundle exec fastlane beta`.

The one-command pipeline:

1. Bump `CFBundleVersion` to `latest_testflight + 1`
2. `xcodebuild archive` (export `app-store`)
3. Upload to App Store Connect via the API Key
4. Wait for Apple processing to finish (5-30 min)
5. Distribute to the "Internal QA" group (no Beta App Review)

---

## Initial setup (one-shot)

### 1. Create the App Store Connect API Key

Required role: **Admin** on ArboreTeam in App Store Connect.

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Click **"+"** to generate a new key.
3. Name: `arbore-fastlane-beta`. Access: **App Manager** (sufficient for TestFlight upload, no need for Admin).
4. Download the `.p8` file (downloadable **only once** — lost = start over).
5. Note the **Key ID** (shown on the key's row after creation) and the **Issuer ID** (at the top of the page).

> **Why this key**: it replaces interactive Apple ID + 2FA authentication. Without it, fastlane fails 80% of the time because of 2FA codes received on a third-party device.

### 2. Place `fastlane/AuthKey.json`

Reformat the `.p8` content into JSON:

```bash
cat > fastlane/AuthKey.json << EOF
{
  "key_id": "<Key ID>",
  "issuer_id": "<Issuer ID>",
  "key": "$(cat ~/Downloads/AuthKey_<KeyID>.p8 | awk '{printf "%s\\n", $0}')",
  "in_house": false
}
EOF
chmod 600 fastlane/AuthKey.json
```

Verify that the file is properly gitignored:

```bash
git check-ignore -v fastlane/AuthKey.json
# → .gitignore:172:fastlane/AuthKey.json   fastlane/AuthKey.json
```

> ⚠️ If `git check-ignore` returns nothing, do NOT continue — the file would be committed on the next `git add .`. The gitleaks pre-commit hook should also catch it, but don't rely on that.

### 3. Create the "Internal QA" group in App Store Connect

1. App Store Connect → ArboreUi → **TestFlight → Internal Testing → "+"**.
2. Group Name: `Internal QA`.
3. Check **"Enable automatic distribution"** — every new build will be pushed to them with no configuration on the Fastfile side.
4. Add only active members who are authorized to test the build and, if needed,
   the internal review address. Maintain that list in App Store Connect rather
   than hard-coding it in this document.

> The name **must** match the `INTERNAL_GROUP` constant in `fastlane/Fastfile`. If it changes, update the Fastfile accordingly.

### 4. Install fastlane on the deploying machine

On macOS with Ruby installed via Homebrew, the system gems folder is
not writable by default. Always install gems locally to the project:

```bash
bundle config set --local path 'vendor/bundle'   # one-shot — writes .bundle/config
bundle install
```

This installs the version pinned in `Gemfile` into `vendor/bundle/`
(gitignored). Then verify:

```bash
bundle exec fastlane --version
```

> If `bundle install` fails with `Bundler::PermissionError` on
> `/opt/homebrew/lib/ruby/...`, it means the `bundle config set` was not
> done. The config is per-project (in `.bundle/config`), not global —
> every clone of the repo must redo it.

> Bundler-free alternative: `brew install fastlane`. Simpler but without
> a version pin — risk of drifting between machines.

### 5. Verify Xcode code signing

Open `ArboreUi.xcworkspace` in Xcode:

- Target `ArboreUi` → **Signing & Capabilities** tab
- **Automatically manage signing** enabled
- Team: `ArboreTeam (582QH9652J)` (enforced by `.githooks/pre-commit`)

The lane passes `-allowProvisioningUpdates` to `build_app`: with automatic
signing enabled, Xcode **creates or renews the profile itself during the
archive**. Without that flag, a stale profile made the lane fail on a signing
error after roughly ten minutes of building — at the most expensive moment,
compilation being already done.

If "Automatically manage signing" is disabled, however, Xcode has nothing to
renew and `build_app` will fail for lack of a valid profile.

### 6. Fill in the App Review info (for `upload_metadata` / `sync_beta_info`)

The **`fastlane/metadata/review_information/` folder is entirely gitignored** (same reason as `fastlane/AuthKey.json`: creds outside the repo). Each machine that pushes the metadata must therefore **recreate these files locally**, otherwise `upload_metadata` fails at the "Uploading app review information" step with:

```
You must provide a value for the attribute 'contactFirstName'/'contactLastName'/'contactEmail'/'contactPhone'
The phone number must be in a valid format. Preface with '+' followed by the country code
```

Expected files (one per line, no quotes):

```bash
cd fastlane/metadata/review_information
printf 'Arbore\n'                 > first_name.txt
printf 'Team\n'                   > last_name.txt
printf 'contact@arbore.app\n'     > email_address.txt
printf '+33XXXXXXXXX\n'           > phone_number.txt   # international format required (+country code)
printf '<demo account email>\n' > demo_user.txt
printf '<demo password>\n'    > demo_password.txt
printf 'Steps for the reviewer…\n'> notes.txt
```

> The phone (`phone_number.txt`) is also explicitly gitignored (`.gitignore`) — never commit it.

**`sync_beta_info` lane (TestFlight Beta App Review)**: this one does **not** read these files but **environment variables** (never in git). To push the demo account + contact to the TestFlight side:

```bash
ARBORE_DEMO_USER='…' ARBORE_DEMO_PASSWORD='…' ARBORE_REVIEW_PHONE='+33XXXXXXXXX' \
  bundle exec fastlane sync_beta_info
```

(optional: `ARBORE_REVIEW_FIRST_NAME` / `ARBORE_REVIEW_LAST_NAME`, default "Arbore" / "Team"). Without these variables, the lane cleanly skips the demo account part.

---

## Day-to-day usage

### Submit a new internal build

```bash
bundle exec fastlane beta
```

The command:

- Fails immediately if `fastlane/AuthKey.json` is missing.
- Fetches the latest `build_number` on TestFlight.
- Increments it by 1 and writes it into `ArboreUi.xcodeproj`.
- Archives the app (~ 3-5 min on M2/M3).
- Uploads to App Store Connect (~ 30-60 s).
- Waits for Apple processing to finish (5-30 min, can be longer if Apple's queue is loaded).
- Automatically distributes to the "Internal QA" group.

Total: 10-40 min depending on Apple processing.

### Ship to the public beta

```bash
bundle exec fastlane public_beta \
  fr:fastlane/changelogs/fr-FR.txt \
  en:fastlane/changelogs/en-US.txt \
  es:fastlane/changelogs/es-ES.txt \
  de:fastlane/changelogs/de-DE.txt
```

All four languages are **required**. The lane refuses to start if one is
missing, and also refuses a path that points at no file.

Same flow as `beta`, with three differences that matter.

| | `beta` | `public_beta` |
|---|---|---|
| group | Internal QA (3 testers) | Bêta privée (10 testers, public link) |
| Apple review | none | Beta App Review |
| delay before testers get it | after processing | after approval, hours to a day |

The build **reaches nobody** until Apple approves it. Do not confuse "shipped"
with "received": `current_build` will show the number long before anyone can
install it.

### Release notes

They live in `fastlane/changelogs/<locale>.txt`, one per language the app
serves: `fr-FR`, `en-US`, `es-ES`, `de-DE`. Version-controlled, so they get
reviewed like everything else.

Neither an environment variable nor generated from the git log: a tester has no
use for commit subjects, and text you reread is text you write better.

#### The four paths are named by hand

`fastlane/changelogs/` is a convention, **not a default**. No lane reads that
directory on its own.

That is the point. A lane that went looking there would publish the previous
release's notes the day someone forgets to update them, silently, and the text
would stay readable by testers until the next build. Having to name the four
files forces you to look at them.

For the same reason, a path pointing at no file is an **error**, never literal
text: accepting both would publish `notes/33-de.txt` on the smallest typo.

```bash
bundle exec fastlane verifier_notes \
  fr:fastlane/changelogs/fr-FR.txt \
  en:fastlane/changelogs/en-US.txt \
  es:fastlane/changelogs/es-ES.txt \
  de:fastlane/changelogs/de-DE.txt

bundle exec fastlane notes build:33 \
  fr:fastlane/changelogs/fr-FR.txt \
  en:fastlane/changelogs/en-US.txt \
  es:fastlane/changelogs/es-ES.txt \
  de:fastlane/changelogs/de-DE.txt
```

Relative paths resolve from the **repo root**, not from `fastlane/` where
fastlane chdirs at startup. Absolute paths work too.

`public_beta` runs this check **before archiving**. Failing on a turn of phrase
after two and a half minutes of compilation would be a gratuitous punishment.

#### What the check rejects

- a missing or empty file, in any of the four languages;
- more than 4,000 characters (the App Store Connect limit);
- a **long dash** (`—` or `–`): it is not typed by accident, and its presence
  marks text produced elsewhere;
- a list of turns of phrase that keep coming back, per language: "nous sommes
  ravis", "we're excited", "sumérgete", "wir freuen uns", "feel free to",
  "seamless", "unlock"…

The lane **refuses to ship** rather than let it through. That is deliberate: a
badly written note stays readable by ten people until the next build, whereas a
failed lane costs thirty seconds.

> The phrase list is not a guarantee of style. It catches what repeats; it does
> not replace a proofread. The lane therefore prints the first line of each
> language before sending.

#### How to write these notes

One line per change, present tense, saying what changes for the user rather than
what changed in the code. "The catalog no longer freezes when you scroll
quickly" rather than "optimised thumbnail decoding".

End with what you want tested first: that is the only part testers actually
follow.

### Check the latest build on TestFlight

```bash
bundle exec fastlane current_build
```

Useful to confirm the previous upload was properly registered on the ASC side before starting another one.

### Cancel a build in progress

`Ctrl-C` during `build_app`: the local archive is discarded, nothing is uploaded. During `upload_to_testflight`: the upload is interrupted, ASC may or may not have registered the build (check in the ASC UI). If an orphaned build lingers in TestFlight, delete it via the ASC UI.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Fastlane API key missing` at launch | `fastlane/AuthKey.json` missing or misread | Redo setup step 2 |
| `Couldn't find bundle identifier` | `fastlane/Appfile` out of sync with the Xcode project | Check `PRODUCT_BUNDLE_IDENTIFIER` in `ArboreUi.xcodeproj/project.pbxproj` |
| `No provisioning profile found` | Automatic signing disabled or different Team | Re-enable Automatic signing with `ArboreTeam (582QH9652J)` |
| `Build number 42 already exists` | Race condition with another upload in progress | Wait for processing to finish, check `current_build`, retry |
| `App Store Connect timeout` | Abnormally long Apple processing | Check the status on [Apple System Status](https://www.apple.com/support/systemstatus/), retry later |
| Diverging `Code signing entitlements` | Xcode capabilities changed without updating ASC | Toggle the capability in Xcode, build again |
| `Could not set changelog: SSL_connect ... unexpected eof` | Network drop to Apple **after** the binary upload | No longer fails the lane since #511: the binary is shipped and the dSYMs already went out. Set the changelog by hand in App Store Connect |

### The lane's ordering, and why it changed

`beta` runs: bump → archive → **dSYMs to Sentry** → `upload_to_testflight`.

Symbols go out **before** the binary. A build must never reach a tester without
the means to read its crashes.

That was not the case before 2026-09-10. The order was archive → upload →
changelog → dSYMs, and on build 31 an SSL drop to Apple during the changelog step
stopped the lane **36 minutes after a successful upload** — that is, before the
symbols were sent. The build was in testers' hands, its crashes bound for
unreadable stacks.

Two guardrails follow:

- **dSYMs first.** If delivery then fails, we will have uploaded symbols for a
  build that does not exist: a few orphaned megabytes, no harm done;
- **a failing changelog no longer fails the lane.** It is cosmetic. The failure
  is reported and the lane carries on — but only for that error: a failure to
  upload the binary stays fatal, otherwise the lane would announce a delivery
  that never happened.

If the dSYM upload fails anyway, the lane says so loudly and continues: shipping
without symbols beats not shipping. Recovery:

```bash
export SENTRY_AUTH_TOKEN=$(grep -m1 -E '^\s*token\s*=' .sentryclirc | sed 's/^[^=]*=[[:space:]]*//')
sentry-cli debug-files upload -o epi-apps -p arbore-frontend ./fastlane/builds/
```

After any lane failure, **check the two things separately**: is the build on
TestFlight (`bundle exec fastlane current_build`), and are its symbols in Sentry
(`Settings → Debug Files`).

### Detailed logs

```bash
bundle exec fastlane beta --verbose
```

Junit reports are written to `fastlane/report.xml` (gitignored).

---

## Out of scope (separate issues if needed)

- **macOS GitHub Actions CI** running `fastlane beta` on tag push: doable but requires macOS Actions minutes (10× more expensive than Ubuntu) + a secret for the API key. Not urgent as long as the internal deploy stays manual.
- **match (fastlane)** for multi-machine code signing: requires a separate private repo for the encrypted certificates. Worth considering if several people upload.
- **Automating a lane to external testers**: **external** distribution (public TestFlight link) is in place and **approved by Apple** (Beta App Review passed). The `beta` lane intentionally stays **internal only** (`distribute_external: false`, `skip_submission: true`); adding the build to the external group and any new Beta App Review submission are done on the App Store Connect side. A dedicated lane could automate this later.

---

## References

- Setup issue: [#156](https://github.com/ArboreTeam/Arbore/issues/156)
- [Apple — App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Fastlane — `upload_to_testflight`](https://docs.fastlane.tools/actions/upload_to_testflight/)
- [Fastlane — `app_store_connect_api_key`](https://docs.fastlane.tools/actions/app_store_connect_api_key/)
