---
name: cmp-matrix-test
model: sonnet
effort: medium
description: >-
  Run the cmpose.dev generator's release matrix — the smoke gate of the (private)
  cmpose.dev backend (`npm run smoke`). It generates every variant (showcase and the
  blank feature combinations) from one CmpTemplate ref, checks each project, builds
  Android and iOS, runs detekt, launches every variant's RELEASE build on an Android
  emulator and an iOS simulator, and reports PASS/FAIL with screenshots. Use when the
  user says "matris testini koş", "smoke", "run the generator matrix", "şablonu
  yayınlamadan önce doğrula", "release'leri emülatörde dene", or before tagging a
  template or deploying the backend.
---

# cmp-matrix-test

Runs the cmpose.dev backend's smoke gate and reports the result. Skill directory:
`~/.claude/skills/cmp-matrix-test/`. The matrix itself lives in the backend
(`scripts/smoke/`); this skill never hard-codes variants, check counts or feature names.

## 1. Locate the backend

`$CMP_BACKEND_DIR`, else `~/StudioProjects/ProjectGenerator/cmp/Cmp-wizard-backend`. If
there is no `package.json` with a `smoke` script there, stop and tell the user to set
`CMP_BACKEND_DIR`.

## 2. Show what will run

Print the variants from the backend (the single source of truth):

    node -e "console.table(require('$B/scripts/smoke/variants.js').map(v => ({ name: v.name, type: v.templateType, package: v.packageName, modules: (v.features || []).join(' '), featuresConfig: JSON.stringify(v.featuresConfig || 'showcase defaults') })))"

## 3. Pick the arguments from the request

- A tag or branch of CmpTemplate ("template-2026.09.28", "TURKER") → `--ref <it>`.
- A template directory (e.g. the upstream checkout) → `--dir <path>`.
- "quick", "sadece build", "hızlı" → add `--build-only` (skips the emulator/simulator runs).
- Nothing given → no arguments: the backend's pinned template, full run.

Tell the user the expected duration (full ≈ 25–35 min, `--build-only` ≈ 7 min).

## 4. Run it

Start `bash ~/.claude/skills/cmp-matrix-test/scripts/run.sh <args>` in the **background**
and wait for its completion notification — do not poll. Do not change the command, the
backend or the template while it runs. The smoke script only ever talks to `emulator-NNNN`
serials and deletes only the simulator it created; never run adb against a physical device.

## 5. Report

- The final `== N passed, M failed (logs: <dir>)` line.
- Every `FAIL` line with the log file it names; open that log and say whether the cause is
  the product (build error, crash, residue, verification 500) or the environment (emulator
  did not boot, missing AVD/runtime, disk). `PREREQ:` lines are environment problems.
- For a full run, open every screenshot in `<dir>/shots/` with Read and describe what is on
  screen per variant (first screen shown? any dialog, especially a notification-permission
  prompt, which must not appear in release builds?).

## 6. When the generator gains a feature

Nothing to change here. Add a variant to the backend's `scripts/smoke/variants.js`
(`test/smokeVariants.test.js` fails until every `featuresConfig` flag and template type is
covered) and run this skill.
