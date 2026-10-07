---
name: cmp-new-project
model: sonnet
effort: medium
description: >-
  Scaffold a new Compose Multiplatform (Kotlin Multiplatform) project via the
  cmpose.dev generator — the terminal equivalent of the cmpose.dev web wizard.
  Use whenever the user wants to create / generate / scaffold / bootstrap a new
  CMP or KMP project — e.g. "bana network ve theming'li bir proje hazırla",
  "yeni bir compose multiplatform projesi oluştur", "create a CMP project with
  networking and a profile module", "örnek uygulama oluştur". When invoked the
  skill asks ONLY four fields — project name, app name, package, output directory —
  one at a time; everything else uses smart defaults or the request (template =
  showcase, Min SDK, iOS, and any features/modules) and is NEVER asked. Then it
  calls the API, extracts the zip, sets up local.properties + git, opens the IDE,
  and verifies Android + iOS builds.
---

# cmp-new-project

Generate a Compose Multiplatform project through the cmpose.dev API. This is the
chat equivalent of the cmpose.dev web wizard, but **kept short**: ONLY four fields
are asked one at a time (project name, app name, package, output dir); everything
else uses smart defaults / the request and is shown (changeable) at the confirmation
step. Skill directory: `~/.claude/skills/cmp-new-project/`.

Run scripts with `bash ~/.claude/skills/cmp-new-project/scripts/<name>.sh`.
The contract is generated from the backend; at runtime `preflight.sh` reports
`contractCurrent`, so a stale skill is visible — see *Maintenance*.

## 0. Load contract + preferences + live state (silent)
1. Read `reference/contract.json` (regexes, max lengths, backend messages,
   dependency rules, `anatomy`, TR+EN `keywordMap`) and `defaults.json` (prefs).
2. Run `scripts/preflight.sh` (one call) → `{apiBase, reachable, config, versions, rateLimit, contractCurrent}`.
   - **`reachable:false`** → tell the user the API is unreachable. If `apiBase` is
     cmpose.dev, prod may be down; they can run the backend locally and retry with
     `CMP_API=http://localhost:3000`. **Don't start the form / don't generate.**
   - Live **`config`** OVERRIDES contract.json numeric ranges + `maxModules`.
     Live **`versions`** = display versions + the build `jdk`. **`rateLimit`** feeds
     the pre-check in step 4.
   - **`contractCurrent === false`** → tell the user one line: "Note: this skill's
     contract is older than the server's (a maintainer should run
     `sync-contract.sh`, or update your skills clone); live limits are used." and carry on. `null` → say nothing.
3. **Pre-fill from the request:** if the user already named a field (project name,
   features, modules, "blank", a specific SDK/iOS, etc.), use it — via
   `keywordMap` / `templateKeywords` — as that field's value. This can both set the
   defaults in step 1 and skip an asked field in step 2.

## 1. Auto-defaults — DO NOT ASK these (keep the form short)
Use these silently. They appear in the confirmation (step 3); the user changes any
there if needed, or overrides them up front in their request.
- **Template type → `showcase`** by default. Use `blank` ONLY if the request clearly
  indicates it ("blank", "boş proje", "no example screens", or it names specific
  `featuresConfig` toggles / a custom set of features). Showcase ⇒ `home` +
  `onboarding` + all sample core modules; `featuresConfig` is ignored. Custom modules
  are still added next to `home` and `onboarding`, fully wired (their screens are
  registered; the showcase still opens on onboarding).
- **Min SDK → `defaults.minSdk`** (validate against live `config.minSdkMin/Max`).
- **iOS Deployment Target → `defaults.iosVersion`** (validate `regex.iosVersionFormat`,
  within live `config.iosVersionMin/Max`).
- **Features + custom modules → from the request ONLY, NEVER asked.** Parse via
  `keywordMap` / module names. For the default `showcase` the `featuresConfig`
  toggles are ignored by the backend, but named modules go in `features`. If the
  request says `blank` but names no features, use blank-minimal (all
  `featuresConfig` false, `features: []`). Apply dependency rules
  (`networkInspector ⇒ network`, `theming || multiLang ⇒ dataStore`).
  **Turn on `purchases` / `ads` only when the user explicitly asks for in-app
  purchases / a paywall (RevenueCat) or for ads (AdMob).** Never infer them from
  words like "premium", "subscription", "purchases" or "satın alma" alone (a
  "premium-feeling recipe app" or a "subscription tracker" is not a paywall
  request); if unsure, leave them off and ask on the confirmation screen (step 3).
  `purchases` (RevenueCat paywall) and `ads` (AdMob banner/interstitial/rewarded)
  are independent; with both on, premium hides the ads. Either one adds
  `feature/monetization`, so `monetization` is a reserved module name (see
  `reference/payload.md` → *Monetization*).
  **Turn on `room` only when the user asks for a local database or offline storage
  of structured data; DataStore (`dataStore`) is for preferences.** `room` implies
  nothing and adds `core/room` plus, in blank, a `feature/notes` demo (so `notes` is a
  reserved module name; see `reference/payload.md` → *Room*).

## 2. Ask ONLY these four — ONE at a time, in order
Ask one question → wait → validate (below) → ask the next. **Don't batch. Ask
nothing beyond these four.** Skip any the user already gave in their request.

1. **Project Name** — free text. Letters only (`regex.projectName`),
   ≤ `maxLengths.projectName`. Becomes `rootProject.name`.
2. **App Name** — free text. User-visible name; spaces OK, ≤ `maxLengths.appName`.
3. **Package Name** — offer the saved `packagePrefix` (e.g. `dev.cmpose`) and ask for
   the last segment ("I'll build it as `dev.cmpose.<seg>`"), or let them type the
   full package. Validate `regex.packageName`, ≤ `maxLengths.packageName`.
4. **Output directory** — free text: default `{outputDir}/{projectName}`; show the
   resolved absolute path (expand `~`).

### Validate each answer immediately
Apply `contract.json.regex` + `maxLengths` + live ranges. If invalid, re-ask that
same field and quote the exact `contract.json.messages` string; don't advance until
valid (cap ~2 re-asks). The server's `400` is the final authority.

## 3. Confirm with an anatomy preview
Show a one-screen summary + a module tree from `contract.json.anatomy` and the chosen
config. **Surface the auto-defaulted Template / Min SDK / iOS and say they can be
changed here.** Mark forced/auto modules.

```
Project: Sepetim          Package: dev.cmpose.sepetim
App:     Sepetim          Template: showcase (default — change if you want)
Min SDK: 24 (default)   iOS: 15.0 (default)   Output: ~/StudioProjects/Sepetim
Versions: Kotlin 2.x · AGP 9.x · CMP 1.x · Gradle 9.x · JDK 21 (live)

Sepetim/                              (showcase: full example app)
├── androidApp/  iosApp/  shared/ (Koin + Navigation)   always
├── core/  (logging (always), review (always), network, database (DataStore), room, designsystem, multilang, purchases, ads, …)
├── feature/home/  feature/monetization/  feature/onboarding/  (blank + room: feature/notes/)
└── build-logic/
```
Get a single yes/no before generating.

## 4. Generate
- **Rate-limit pre-check**: if `rateLimit.isLimited` or `rateLimit.remaining == 0`,
  report the reset time (`resetSeconds` → minutes) and offer to wait / use the local
  backend. **Don't POST** — it would be a guaranteed 429.
- Build the payload exactly per `reference/payload.md`. **showcase** →
  `templateType:"showcase"`, `features` = the requested custom modules (`[]` if none;
  a `featuresConfig` is harmless).
  **blank** → the chosen `featuresConfig` + `features`.
- Write the payload to a temp file (`mktemp`), then run
  `scripts/generate.sh <payload.json> <outputDir> <projectName>`.
- Handle the exit code:
  - `0` → extracted to `<outputDir>/<projectName>`; continue.
  - `2` RATE_LIMIT (429) → report `retryAfterMinutes`; **don't auto-loop** (prod = 5/15 min).
  - `3` VALIDATION (400) → show the backend `error` verbatim, map it to the field, re-ask, retry once.
  - `4` PAYLOAD_TOO_LARGE (413) → almost always a large `detektYamlContent`; offer to drop it or shrink it; retry.
  - `5` BUSY (503) → too many generations running on the server; no quota was spent. Wait ~10 s and retry once.
  - `1` other/network/500 → show the message and stop; suggest checking prod or the local backend.

## 5. Setup
`scripts/setup.sh <projectDir>` → `local.properties` (`sdk.dir`) + `git init` +
initial commit. Reports cleanly and continues if the Android SDK is absent.

## 6. Open IDE + verify (capability-aware, background)
Run `scripts/doctor.sh` once → capabilities JSON.
- If `defaults.openIde` and an IDE is available: `open -a "{ide}" <projectDir>`.
- If `defaults.autoBuildAndroid` **and** `doctor.canBuildAndroid`: run
  `scripts/build-android.sh <projectDir>` **in the background**; report
  `BUILD SUCCESSFUL` + the APK path when done, the unit tests (Android host) when the
  project has any (`UNIT TESTS PASS`, or skipped for older templates), and the detekt
  result: `DETEKT CLEAN`, or skipped when the project was generated without detekt. A red
  detekt or a red unit test on a freshly generated project is a generator/template defect,
  not the user's code: show the `e:` / FAILED lines and say so; report it, do not patch the
  project.
- If `defaults.autoRunIos` **and** `doctor.canRunIos`: run
  `scripts/run-ios.sh <projectDir>` **in the background**; report when the app launches.
- If a capability is missing, say so briefly and skip — never fail the whole flow.
  The build JDK must match preflight `versions.jdk` (currently 21); if
  `doctor.jdk21` is false, tell the user to install JDK 21 (e.g. Temurin 21).
Builds are long → background them and report results as they finish; never block.

## 7. Report + remember
Summarize: the absolute project path, the modules included (the anatomy), how to
run (Android Studio Run / iOS `iosApp` scheme), and the guide
`https://cmpose.dev/guide.html`. If the project has `core/purchases`, say it ships
with a RevenueCat Test Store key that must be replaced with the user's own platform
keys before shipping (a release build that still has the Test Store key keeps
purchases disabled and the paywall shows a message); if it has `core/ads`, say it
uses Google's test ad unit IDs and asks for UMP/ATT consent on the first visit to the
ads screen (a real app should ask at launch; the EEA consent debug geography is
debug-only). If it has `feature/notes`, say Notes is a demo: replace it or remove it.
Add one line for deep links: "deep link: `<scheme>://`" (scheme = project name in lower
case; showcase opens `<scheme>://user/{username}` and `<scheme>://settings`, blank opens
`<scheme>://` and `<scheme>://<module>` for each custom module).
Offer to persist any changed preferences
(`packagePrefix`, `outputDir`, `minSdk`, `iosVersion`, `ide`, `openIde`,
`autoBuildAndroid`, `autoRunIos`) back to `defaults.json`.

## Maintenance — keeping the contract in sync
`reference/contract.json` and `reference/payload.md` are **generated** by
`scripts/sync-contract.sh` from the cmpose.dev backend source. Do not hand-edit them.
- After the backend's validation/limits change: point `CMP_BACKEND_DIR` at your
  backend checkout and run `bash scripts/sync-contract.sh`.
- Command: `CMP_BACKEND_DIR=<backend checkout> bash scripts/sync-contract.sh`. The
  contract facts and `contractVersion` come from the backend's single contract
  module; the version is computed only there, never in the skill.
- Drift gate: `scripts/sync-contract.sh --check` exits 0 (in sync), 1 (drift:
  contract is stale) or 2 (configuration error: node / `CMP_BACKEND_DIR`).
- `preflight.sh` compares the committed `contractVersion` with the live
  `/api/config` one and reports `contractCurrent` (true / false / null).
- At runtime, **live** `/api/config` + `/api/versions` (via `preflight.sh`) always
  override the static numbers; `contract.json` is the offline fallback and the
  source for the regexes / message strings the API doesn't return.

## Notes
- Endpoint resolution: env `CMP_API` > `defaults.json.apiBase` > `https://cmpose.dev`.
- Don't loop generations — prod allows 5 per 15 min per IP.
- A generated project is only as correct as the deployed cmpose.dev.
