# cmp-new-project

> Generate a Compose Multiplatform (Kotlin Multiplatform) project from the terminal
> via the [cmpose.dev](https://cmpose.dev) generator — the chat equivalent of the
> cmpose.dev web wizard.

When invoked, the skill asks **only four things** (one at a time), uses smart
defaults for the rest, then calls the API, extracts the zip, sets up the project,
opens the IDE, and verifies the Android/iOS builds.

## Requirements

- [Claude Code](https://code.claude.com)
- `curl`, `unzip`, `git` (always needed)
- Internet access to `https://cmpose.dev` (or a local backend via `CMP_API`)
- Optional, for the local build/run verification:
  - **JDK 21** (the template uses AGP 9; matches `/api/versions` `jdk`) — Android build
  - **Android SDK** — Android build
  - **macOS + Xcode** — iOS simulator run
- `node` — only to (re)generate the contract with `sync-contract.sh`

The skill **degrades gracefully**: missing tools are skipped and reported, never fatal.

## Install

```bash
# from the repo root
ln -s "$PWD/cmp-new-project" ~/.claude/skills/cmp-new-project   # recommended
# or: cp -R cmp-new-project ~/.claude/skills/
```

Start a new Claude Code session and run `/cmp-new-project`.

## Usage

Invoke the skill and answer four prompts (asked one at a time):

1. **Project name** — letters only → `rootProject.name`
2. **App name** — the user-visible name
3. **Package name** — offered as `dev.cmpose.<segment>` (Android `applicationId` + iOS bundle id)
4. **Output directory** — default `~/StudioProjects/<project>`

Everything else uses smart defaults (shown on the confirmation screen, changeable
there or in your request):

- **Template** → `showcase` (full example app: home + onboarding + all modules)
- **Min SDK** → `24`   ·   **iOS** → `15.0`
- **Features / custom modules** → applied **only** if you mention them in your request

Examples:

```text
/cmp-new-project
"yeni bir compose multiplatform projesi oluştur"
"network ve theming'li blank bir proje, profile ve cart modülleriyle"
```

The last one switches to a **blank** project with networking + theming + two custom
modules — taken from the request, so no extra questions are asked.

## Configuration — `defaults.json`

| key | default | meaning |
|---|---|---|
| `apiBase` | `https://cmpose.dev` | generator endpoint |
| `packagePrefix` | `dev.cmpose` | package prefix offered for the package question |
| `outputDir` | `~/StudioProjects` | where projects are created |
| `minSdk` / `iosVersion` | `24` / `15.0` | default SDK / iOS target |
| `ide` / `openIde` | `Android Studio` / `true` | IDE opened after generation |
| `autoBuildAndroid` / `autoRunIos` | `true` / `true` | post-generation verification |

Override the endpoint per run: `CMP_API=http://localhost:3000`.

**Model / effort:** the skill runs on **Sonnet (medium effort)** via `SKILL.md`
frontmatter — the reliability/cost sweet spot for this mostly mechanical flow — and
your session model resumes afterward.

## How it works

1. `scripts/preflight.sh` → live `/api/config` + `/api/versions` + `/api/rate-limit-status` (one call).
2. Collect the four fields; validate each against `reference/contract.json`.
3. Confirm with a project **"anatomy"** preview (the module tree).
4. `scripts/generate.sh` → POST the payload → download + extract the zip.
5. `scripts/setup.sh` → write `local.properties` (`sdk.dir`) + `git init` + initial commit.
6. `scripts/doctor.sh` → capabilities → `build-android.sh` / `run-ios.sh` (background, optional).

## Contract stays in sync with the backend

`reference/contract.json` and `reference/payload.md` are **generated** from the
cmpose.dev backend source by `scripts/sync-contract.sh`, so the validation rules
never drift:

```bash
CMP_BACKEND_DIR=/path/to/backend bash scripts/sync-contract.sh              # regenerate
bash scripts/sync-contract.sh --check                                       # drift gate (CI-friendly)
```

At runtime, **live** `/api/config` + `/api/versions` always override the static
numbers; `contract.json` is the offline fallback and the source for the regexes /
message strings the API doesn't expose.

## Files

```
cmp-new-project/
├── SKILL.md            # the flow Claude follows
├── defaults.json       # your preferences
├── reference/
│   ├── contract.json   # generated, machine-readable contract
│   └── payload.md      # generated, human-readable contract
└── scripts/
    ├── preflight.sh    # live config/versions/rate-limit
    ├── sync-contract.sh# (re)generate the contract from the backend (+ --check)
    ├── doctor.sh       # environment capability probe
    ├── generate.sh     # POST + download + extract
    ├── setup.sh        # local.properties + git
    ├── build-android.sh# assembleDebug (config cache on) + APK check + detekt if enabled (JDK 21)
    └── run-ios.sh      # build + install + launch on a simulator
```

## Notes

- The cmpose.dev demo API is **rate-limited**: 5 generations per 15 minutes per IP.
- A generated project is only as correct as the deployed cmpose.dev.
