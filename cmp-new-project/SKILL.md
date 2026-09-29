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
The contract is generated from the backend and checked live at runtime, so it
never drifts — see *Maintenance*.

## 0. Load contract + preferences + live state (silent)
1. Read `reference/contract.json` (regexes, max lengths, backend messages,
   dependency rules, `anatomy`, TR+EN `keywordMap`) and `defaults.json` (prefs).
2. Run `scripts/preflight.sh` (one call) → `{apiBase, reachable, config, versions, rateLimit}`.
   - **`reachable:false`** → tell the user the API is unreachable. If `apiBase` is
     cmpose.dev, prod may be down; they can run the backend locally and retry with
     `CMP_API=http://localhost:3000`. **Don't start the form / don't generate.**
   - Live **`config`** OVERRIDES contract.json numeric ranges + `maxModules`.
     Live **`versions`** = display versions + the build `jdk`. **`rateLimit`** feeds
     the pre-check in step 4.
3. **Pre-fill from the request:** if the user already named a field (project name,
   features, modules, "blank", a specific SDK/iOS, etc.), use it — via
   `keywordMap` / `templateKeywords` — as that field's value. This can both set the
   defaults in step 1 and skip an asked field in step 2.

## 1. Auto-defaults — DO NOT ASK these (keep the form short)
Use these silently. They appear in the confirmation (step 3); the user changes any
there if needed, or overrides them up front in their request.
- **Template type → `showcase`** by default. Use `blank` ONLY if the request clearly
  indicates it ("blank", "boş proje", "no example screens", or it names specific
  `featuresConfig` toggles; custom modules alone do not imply it). Showcase ⇒ `home` +
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
├── core/  (network, database, designsystem, multilang, …)
├── feature/home/  feature/onboarding/
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
`https://cmpose.dev/guide.html`. Offer to persist any changed preferences
(`packagePrefix`, `outputDir`, `minSdk`, `iosVersion`, `ide`, `openIde`,
`autoBuildAndroid`, `autoRunIos`) back to `defaults.json`.

## Maintenance — keeping the contract in sync
`reference/contract.json` and `reference/payload.md` are **generated** by
`scripts/sync-contract.sh` from the cmpose.dev backend source. Do not hand-edit them.
- After the backend's validation/limits change: point `CMP_BACKEND_DIR` at your
  backend checkout and run `bash scripts/sync-contract.sh`.
- Drift gate: `scripts/sync-contract.sh --check` exits non-zero if the committed
  contract is stale.
- At runtime, **live** `/api/config` + `/api/versions` (via `preflight.sh`) always
  override the static numbers; `contract.json` is the offline fallback and the
  source for the regexes / message strings the API doesn't return.

## Notes
- Endpoint resolution: env `CMP_API` > `defaults.json.apiBase` > `https://cmpose.dev`.
- Don't loop generations — prod allows 5 per 15 min per IP.
- A generated project is only as correct as the deployed cmpose.dev.
