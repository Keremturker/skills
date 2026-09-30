---
name: cmp-matrix-test
model: sonnet
effort: medium
description: >-
  Run the cmpose.dev generator's release matrix — the smoke gate of the (private)
  cmpose.dev backend (`npm run smoke`). It generates every variant (showcase and the blank
  feature combinations) from one CmpTemplate ref, checks each project, builds Android and
  iOS, runs detekt (the project's config, then compass-kit's) and the unit tests (Koin
  graph check included), launches every variant's RELEASE build on an Android emulator and
  an iOS simulator, and reports PASS/FAIL with screenshots. Use when the user says "matris
  testini koş", "smoke", "run the generator matrix", "şablonu yayınlamadan önce doğrula",
  "release'leri emülatörde dene", or before tagging a template or deploying the backend.
---

# cmp-matrix-test

Runs the cmpose.dev backend's smoke gate and reports the result. Skill directory:
`~/.claude/skills/cmp-matrix-test/`. The matrix itself lives in the backend
(`scripts/smoke/`) and is the source of truth; the variant list and check counts in step 2 are
a snapshot to check a run against.

## 1. Locate the backend

`$CMP_BACKEND_DIR`, else `~/StudioProjects/ProjectGenerator/cmp/Cmp-wizard-backend`. If
there is no `package.json` with a `smoke` script there, stop and tell the user to set
`CMP_BACKEND_DIR`.

## 2. Show what will run

Print the variants from the backend (the single source of truth). `$B` is the backend path from
step 1 (`$CMP_BACKEND_DIR`, else `~/StudioProjects/ProjectGenerator/cmp/Cmp-wizard-backend`):

    B=${CMP_BACKEND_DIR:-$HOME/StudioProjects/ProjectGenerator/cmp/Cmp-wizard-backend}
    node -e "console.table(require('$B/scripts/smoke/variants.js').map(v => ({ name: v.name, type: v.templateType, package: v.packageName, modules: (v.features || []).join(' '), featuresConfig: JSON.stringify(v.featuresConfig || 'showcase defaults') })))"

Snapshot (compass-kit follow-up release, `template-2026.09.30`): 7 variants — `Showcase`, `ShowcaseMod`, `BlankMin`, `BlankNet`,
`BlankTheme`, `BlankLang` (these two came with the B release, for the blank shell's Theming and
Multi-Language layers) and `BlankFull`. A full run has 101 checks, `--build-only` 49. On every variant with detekt the smoke runs detekt
twice: with the project's own config, then with compass-kit's (`detekt (compass-kit rules)`, the
gate Compass applies). If the table or the final count differs, the backend changed: go
by the backend and mention the difference in the report.

## 3. Pick the arguments from the request

- A tag or branch of CmpTemplate ("template-2026.09.28", "TURKER") → `--ref <it>`. Templates
  from before the test-infrastructure release fail the "unit tests (Android host + iOS
  simulator) incl. Koin graph" check of every variant that generates, by design: report them as
  expected, not as product failures.
- A ref older than the B release (no `blank/layers/` in it) fails `generated` for every blank
  variant by design (HTTP 500, "template older than the B release"); those variants run no further
  checks. Only the showcase variants are meaningful there: report the blank failures as expected.
- A ref older than `template-2026.09.30` fails the five "detekt (compass-kit rules)" rows by
  design: its sources predate the compass-kit formatting. Report those as expected, not as
  product failures.
- A template directory (e.g. the upstream checkout) → `--dir <path>`.
- "quick", "sadece build", "hızlı" → add `--build-only` (skips the emulator/simulator runs).
- Nothing given → no arguments: the backend's pinned template, full run.

Tell the user the expected duration (full ≈ 30–40 min, `--build-only` ≈ 5–10 min).

A full run needs `ffmpeg` (the dark-screenshot check); without it the script stops with a
`PREREQ:` line. `--build-only` does not need it.

The compass-kit detekt check needs a local clone of this skills repo: `CMP_SKILLS_DIR`, default
`../../skills` relative to the backend checkout. If `compass-kit/detekt.yml` is missing there,
the smoke exits 2 with a message before any long work; set `CMP_SKILLS_DIR` and rerun.

## 4. Run it

Start `bash ~/.claude/skills/cmp-matrix-test/scripts/run.sh <args>` in the **background**
and wait for its completion notification — do not poll. Do not change the command, the
backend or the template while it runs. The smoke script only ever talks to `emulator-NNNN`
serials and deletes only the simulator it created; never run adb against a physical device.

Release runs happen in dark mode: the script switches the emulator (`cmd uimode night yes`) and
the simulator (`simctl ui … appearance dark`) to dark and checks that each release screenshot's
background is dark. A reused emulator or simulator gets its previous appearance back when the
script exits.

## 5. Report

- The final `== N passed, M failed (logs: <dir>)` line.
- Every `FAIL` line with the log file it names; open that log and say whether the cause is
  the product (build error, crash, residue, verification 500) or the environment (emulator
  did not boot, missing AVD/runtime, disk). `PREREQ:` lines are environment problems.
- For a full run, open every screenshot in `<dir>/shots/` with Read and describe what is on
  screen per variant (first screen shown? any dialog, especially a notification-permission
  prompt, which must not appear in release builds?). Screenshots are expected dark; a light one
  also shows up as a FAIL of "release background is dark".

## 6. When the generator gains a feature

Add a variant to the backend's `scripts/smoke/variants.js`
(`test/smokeVariants.test.js` fails until every `featuresConfig` flag and template type is
covered) and run this skill. Then update the snapshot in step 2 (variants and check counts) and
the duration estimate in step 3.
