# Model Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route mechanical skill work (gates, detekt, tests, Maestro, commit, delegated read-only jobs) to Sonnet/Haiku while every step that writes application code stays on the session model (Opus).

**Architecture:** Mechanical kit skills get `context: fork` + `background: false` + `model: sonnet`, so they run in their own subagent and return only a short report — Gradle logs never enter the Opus context. A new `cmp-gates` skill runs the finish gates; `cmp-verify` stays inline as the reference (when to build, failure recipes). `account-delegate` gains `--model`. A repo-level `scripts/check-skills.sh` guards the frontmatter rules.

**Tech Stack:** Markdown skills (YAML frontmatter), bash, jq.

**Spec:** `docs/superpowers/specs/2026-10-08-model-routing-design.md`

## Global Constraints

- Model values in frontmatter: `opus`, `sonnet`, `haiku`, `fable` or `inherit` (aliases only, no full IDs).
- Every skill with `context: fork` also has `background: false` (the caller waits for the report).
- `cmp-code-rules`, `cmp-feature`, `cmp-design-to-code` get no `model:` and no `context:`.
- `cmp-gates` fixes only failures that `cmp-verify/references/failures.md` (or `cmp-detekt` §2–4) gives a recipe for; at most 3 fix rounds per gate; anything else is reported with file:line, never fixed.
- Never: `@Suppress`, baselines, detekt config changes, deleted/skipped/weakened tests (existing rules).
- `delegate.sh --model` value: matches `^[A-Za-z0-9._\[\]-]+$`, does not start with `-`; flag wins over `DELEGATE_MODEL`; unset → no `--model` passed to `claude`.
- Skill text is English (like the existing skills); specs/plans and Kerem-facing CLAUDE.md lines are Turkish.

## Review Focus

1. A forked skill is invoked while Opus is mid-feature: its report must be short (no raw Gradle log), and Opus must still be the model for the rest of the turn — pinned by `check-skills.sh` (no inline `model:` on any skill except `cmp-commit`, `cmp-new-project`, `cmp-matrix-test`).
2. A red test gate caused by a bug in app (non-test) code: forked `cmp-testing` (Sonnet) must report it, not change app code — pinned by the "Input and report" text in Task 3 and checked in Task 7's manual run.
3. A plan in `account-delegate` whose later job passes a different `--model` than the first: refused with exit 2, not silently mixed — test in Task 5.
4. `--model` values that look like flags or carry shell metacharacters (`-x`, `a b`, `x;y`, empty): refused with exit 2 — test in Task 5.
5. A project without detekt: `cmp-gates` must skip the detekt gate (only gates listed in that project's `CLAUDE.md` run), not report it red — pinned by the Task 2 text and checked in Task 7.

---

### Task 1: `scripts/check-skills.sh` — frontmatter guard

**Files:**
- Create: `scripts/check-skills.sh`
- Create: `scripts/test_check_skills.sh`

**Interfaces:**
- Produces: `bash scripts/check-skills.sh [root]` — exit 0 when every rule holds, exit 1 and one `FAIL: <skill>: <reason>` line per violation otherwise. `root` defaults to the repo root (the script's parent dir).

Rules (from Global Constraints):
- R1 `name:` equals the folder name.
- R2 `model:` if present is one of `opus|sonnet|haiku|fable|inherit`.
- R3 `context: fork` ⇒ `background: false`.
- R4 `model:` without `context: fork` only in `cmp-commit`, `cmp-new-project`, `cmp-matrix-test` (inline model switches the caller's turn).
- R5 `cmp-code-rules`, `cmp-feature`, `cmp-design-to-code` have neither `model:` nor `context:`.
- R6 every skill named in `compass-kit/kit.json` (`.skills[]` string or `.name`) has `<name>/SKILL.md`.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Behavior test for check-skills.sh. Run: bash scripts/test_check_skills.sh
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-skills.sh"
fail=0
check() { local d="$1"; shift; if "$@"; then echo "ok: $d"; else echo "FAIL: $d"; fail=1; fi; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-skills.XXXXXX")" && [ -d "$TMP" ] || { echo "FAIL: mktemp"; exit 1; }
skill() { # $1 = dir, rest = frontmatter lines
  local d="$TMP/$1"; shift; mkdir -p "$d"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# x"; } > "$d/SKILL.md"
}
reset() { rm -rf "${TMP:?}"/*; mkdir -p "$TMP/compass-kit"; echo '{"skills":["a",{"name":"b","requires":"detekt"}]}' > "$TMP/compass-kit/kit.json"; skill a "name: a"; skill b "name: b"; }
runc() { OUT="$(bash "$CHECK" "$TMP" 2>&1)"; CODE=$?; }

reset; runc; check "clean tree passes" test "$CODE" -eq 0
check "real repo passes" bash "$CHECK"

reset; skill c "name: other"; runc
check "R1 name mismatch fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: name" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: gpt" "context: fork" "background: false"; runc
check "R2 unknown model fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: model" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: sonnet" "context: fork"; runc
check "R3 fork without background false fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: background" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "model: sonnet"; runc
check "R4 inline model outside allowlist fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: c: inline model" <<<"$2"' _ "$CODE" "$OUT"
reset; skill cmp-commit "name: cmp-commit" "model: sonnet"; runc
check "R4 inline model in cmp-commit passes" test "$CODE" -eq 0
reset; skill cmp-feature "name: cmp-feature" "context: fork" "background: false"; runc
check "R5 code skill with context fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: cmp-feature: code skill" <<<"$2"' _ "$CODE" "$OUT"
reset; rm -rf "${TMP:?}/b"; runc
check "R6 kit skill without folder fails" bash -c '[ "$1" -eq 1 ] && grep -q "FAIL: b: listed in kit.json" <<<"$2"' _ "$CODE" "$OUT"
reset; skill c "name: c" "description: >-" "  model: opus in text" "context: fork" "background: false"; runc
check "indented text inside a folded value is not a key" test "$CODE" -eq 0

rm -rf "${TMP:?}"
exit "$fail"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/test_check_skills.sh`
Expected: FAIL lines (check-skills.sh does not exist).

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
# Checks the frontmatter rules of every <skill>/SKILL.md and that compass-kit/kit.json names
# existing skills. See docs/superpowers/specs/2026-10-08-model-routing-design.md.
# Usage: check-skills.sh [repo root]. Exit 0 ok, 1 violations (one "FAIL: <skill>: ..." each).
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
fail=0
bad() { echo "FAIL: $1: $2"; fail=1; }
fm() { # $1 = SKILL.md, $2 = key → top-level value (unquoted), empty when absent
  awk -v k="$2" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit}
    NR>1 && index($0, k": ")==1 {v=substr($0, length(k)+3); gsub(/^["'\'']|["'\'']$/, "", v); print v; exit}' "$1"
}
INLINE_OK=" cmp-commit cmp-new-project cmp-matrix-test "
CODE_SKILLS=" cmp-code-rules cmp-feature cmp-design-to-code "
for f in "$ROOT"/*/SKILL.md; do
  [ -f "$f" ] || continue
  d="$(basename "$(dirname "$f")")"
  name="$(fm "$f" name)" model="$(fm "$f" model)" ctx="$(fm "$f" context)" bg="$(fm "$f" background)"
  [ "$name" = "$d" ] || bad "$d" "name '$name' does not match the folder"
  case "$model" in ''|opus|sonnet|haiku|fable|inherit) ;; *) bad "$d" "model '$model' is not opus|sonnet|haiku|fable|inherit" ;; esac
  [ "$ctx" != fork ] || [ "$bg" = false ] || bad "$d" "background must be false with context: fork"
  if [ -n "$model" ] && [ "$ctx" != fork ] && [[ "$INLINE_OK" != *" $d "* ]]; then
    bad "$d" "inline model switches the caller's turn; use context: fork"
  fi
  if [[ "$CODE_SKILLS" == *" $d "* ]] && { [ -n "$model" ] || [ -n "$ctx" ]; }; then
    bad "$d" "code skill must run on the session model (no model:, no context:)"
  fi
done
KIT="$ROOT/compass-kit/kit.json"
if [ -f "$KIT" ]; then
  while IFS= read -r s; do
    [ -f "$ROOT/$s/SKILL.md" ] || bad "$s" "listed in kit.json but $s/SKILL.md is missing"
  done < <(jq -r '.skills[] | if type == "string" then . else .name end' "$KIT")
fi
exit "$fail"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `chmod +x scripts/check-skills.sh && bash scripts/test_check_skills.sh`
Expected: every line `ok:`, exit 0 (the real repo passes today: `cmp-new-project` and `cmp-matrix-test` are on the inline allowlist).

- [ ] **Step 5: Commit**

```bash
git add scripts/check-skills.sh scripts/test_check_skills.sh
git commit -m "test: add check-skills.sh frontmatter guard"
```

---

### Task 2: `cmp-gates` skill and kit routing

**Files:**
- Create: `cmp-gates/SKILL.md`
- Modify: `compass-kit/kit.json` (add `"cmp-gates"` after `"cmp-verify"`)
- Modify: `compass-kit/CLAUDE.md` ("Which skill when" list)
- Modify: `cmp-verify/SKILL.md` §1 and "Done when"

**Interfaces:**
- Consumes: `check-skills.sh` (Task 1).
- Produces: skill `cmp-gates`, argument `[android|ios|detekt|tests ...]` (none = all gates in `CLAUDE.md` order); returns the report format below. Tasks 3 and 4 refer to it by name.

- [ ] **Step 1: Write `cmp-gates/SKILL.md`**

````markdown
---
name: cmp-gates
description: Use to run the finish gates of this Compose Multiplatform project — before saying a change is done, after a screen or module is in place, or before a commit — in a separate subagent that returns a short pass/fail report instead of the Gradle log, fixing only mechanical failures that have a written recipe.
context: fork
background: false
model: sonnet
effort: medium
argument-hint: "[android|ios|detekt|tests ...]"
---

# Gates

You run in your own subagent. The session that called you sees only your final report, not your
tool output. You did not see its conversation: everything you need is in the project files.

## 1. Input

- `$ARGUMENTS` names the gates to run (`android`, `ios`, `detekt`, `tests`); empty means all.
- The gate commands are in `CLAUDE.md` under *Definition of done*, in order. Run only the gates
  listed there: a project without detekt has no detekt gate, and that is not a failure.
- Read before running: `../cmp-verify/SKILL.md` sections 1 and 3 (how to read the output; the
  test gate counts tests and zero is red) and, when a gate is red, `../cmp-verify/references/failures.md`.
  These paths are relative to this skill's folder.

## 2. Run

- Each gate as written, as its own command, in the foreground, with a long Bash timeout (up to
  ten minutes). `./gradlew build` is never used.
- Stop at the first red gate and go to section 3; continue with the next gate once it is green.

## 3. Red gate: fix only what has a recipe

- Match the first real error line against `../cmp-verify/references/failures.md` (and for
  detekt, `../cmp-detekt/SKILL.md` sections 2–4: auto-correct, then the listed fixes).
- A match whose fix is mechanical — an import, the `Res` package or a resource key import, a Koin
  or KSP annotation, `@Serializable` on a destination, detekt formatting — is yours: fix it,
  following `../cmp-code-rules/SKILL.md`, and rerun the same gate. At most 3 rounds per gate.
- Everything else is reported, not fixed: no recipe, a fix that changes behaviour or logic, a
  detekt finding that needs a function split or a rename across files, any failing test (never
  edit a test or the code under test), anything still red after 3 rounds.
- Never: `@Suppress`, baselines, detekt config changes, version or wrapper changes, try/catch to
  hide a crash, deleted or skipped tests.

## 4. Report (your final message, nothing else)

```
Gates: Android ✅ · iOS ✅ · detekt ❌ · Tests ✅ (42 tests)
Fixed (mechanical): feature/x/data/src/commonMain/.../XRepository.kt:12 — missing import kotlinx.coroutines.IO
Open:
- detekt LongMethod — feature/x/presentation/.../XContent.kt:88 — needs the function split (logic)
```

- One line of gate results: each gate run, ✅ or ❌, the test count for the test gate; gates not
  listed in `CLAUDE.md` are left out.
- `Fixed`: file:line and one line per fix. Omit when empty.
- `Open`: per item the gate, file:line, the first error line shortened to one line, and why you
  did not fix it. Omit when empty.
- No raw log, no command transcript.
````

- [ ] **Step 2: Kit wiring**

`compass-kit/kit.json` — the `skills` array becomes:

```json
  "skills": [
    "cmp-code-rules",
    "cmp-feature",
    "cmp-design-to-code",
    "cmp-maestro",
    "cmp-testing",
    "cmp-verify",
    "cmp-gates",
    "cmp-commit",
    { "name": "cmp-detekt", "requires": "detekt" }
  ],
```

`compass-kit/CLAUDE.md` — replace the line
`- Build failure, or before saying you are done: \`cmp-verify\``
with:

```markdown
- Run the gates (after a screen or module, before saying you are done): `cmp-gates`; it returns
  a short report and fixes only mechanical failures
- A failure `cmp-gates` left open, or when and how to build: `cmp-verify`
```

- [ ] **Step 3: `cmp-verify` becomes the reference**

In `cmp-verify/SKILL.md`, frontmatter `description` becomes:

```
description: Use when deciding when to build, when fixing a Gradle, KSP, Koin or Compose resources failure that cmp-gates reported as open, or when reading gate output in this Compose Multiplatform project — the build schedule, how to read the output, and the recipes for common Kotlin Multiplatform failures, including NoDefinitionFoundException at runtime. The gates themselves are run with cmp-gates.
```

In §1, after the first bullet list item ("Run the gates listed in `CLAUDE.md` …"), insert:

```markdown
- Run them with `cmp-gates`: it runs them in a separate subagent and returns a short report, so
  the Gradle log stays out of this session. Run a gate directly only to reproduce one failure
  `cmp-gates` reported as open.
```

In "Done when", replace the first bullet with:

```markdown
- Every gate from `CLAUDE.md` ran green in this session, after the last code change (the last
  `cmp-gates` report shows them all ✅).
```

- [ ] **Step 4: Run the guard**

Run: `bash scripts/check-skills.sh && bash scripts/test_check_skills.sh`
Expected: exit 0, all `ok:`.

- [ ] **Step 5: Commit**

```bash
git add cmp-gates compass-kit/kit.json compass-kit/CLAUDE.md cmp-verify/SKILL.md
git commit -m "feat(cmp-gates): run the finish gates in a Sonnet subagent and return a short report"
```

---

### Task 3: Fork `cmp-detekt`, `cmp-testing`, `cmp-maestro`; Sonnet for `cmp-commit`

**Files:**
- Modify: `cmp-detekt/SKILL.md`, `cmp-testing/SKILL.md`, `cmp-maestro/SKILL.md`, `cmp-commit/SKILL.md`

**Interfaces:**
- Consumes: `cmp-gates` (Task 2), `check-skills.sh` (Task 1).
- Produces: three fork skills with the `argument-hint`s below.

- [ ] **Step 1: Frontmatter**

Add after `description:` in each file:

`cmp-detekt`:
```yaml
context: fork
background: false
model: sonnet
```

`cmp-testing`:
```yaml
context: fork
background: false
model: sonnet
argument-hint: "<class, module or bug to test, or the red test gate's report>"
```

`cmp-maestro`:
```yaml
context: fork
background: false
model: sonnet
argument-hint: "<flow (walkthrough or a regression flow) and the screens it covers>"
```

`cmp-commit` (keeps `disable-model-invocation` and `argument-hint`):
```yaml
model: sonnet
```

- [ ] **Step 2: "Input and report" section in each fork skill**

Insert directly under the `# …` title of `cmp-detekt`, `cmp-testing` and `cmp-maestro` (adjust the
first bullet per skill as shown):

```markdown
## Input and report

You run in your own subagent and did not see the caller's conversation.

- Input: `$ARGUMENTS` — <per skill, see below>. Read `CLAUDE.md` and the files involved yourself;
  for any Kotlin you write, follow `../cmp-code-rules/SKILL.md` (path relative to this skill's
  folder).
- Application code that is not <per skill> is not yours to change: when the fix belongs there,
  stop and report it.
- Your final message is the report, nothing else: files changed (one line each), the gate you ran
  and its result, and what is still open with file:line and why. No raw log.
```

Per-skill fill-ins:
- `cmp-detekt`: input "which modules, or empty for all"; second bullet: "Application code that is not a mechanical detekt fix (formatting, an import, a constant, a visibility modifier) is not yours to change: a finding that needs a function split, a rename across files or a behaviour change is reported, not fixed."
- `cmp-testing`: input "the class, module or bug to test, or the red test gate's report"; second bullet: "Application code that is not a test, a fake or a test dependency is not yours to change: when a test fails because the code under test is wrong, report the failing test and the line in the code, do not change that code."
- `cmp-maestro`: input "the flow and the screens it covers"; second bullet: "Application code that is not a `testTag`, a `<Name>TestTags` object or `testTagsAsResourceId` is not yours to change."

In `cmp-maestro`, at the top of §5 and §6 (both "interactive"), add one line: "In a forked run there is no one to ask: do the check and put what you would have asked under *Open* in the report."

- [ ] **Step 3: Gate references inside these skills**

`cmp-commit/SKILL.md` §4, first bullet becomes:

```markdown
- Run the gates with `cmp-gates` (all of them; for a quick commit the owner asked for, at least
  `cmp-gates android detekt`, detekt only when the project has it).
```

- [ ] **Step 4: Run the guard**

Run: `bash scripts/check-skills.sh && bash scripts/test_check_skills.sh`
Expected: exit 0, all `ok:`.

- [ ] **Step 5: Commit**

```bash
git add cmp-detekt/SKILL.md cmp-testing/SKILL.md cmp-maestro/SKILL.md cmp-commit/SKILL.md
git commit -m "feat(kit): run detekt, tests and Maestro skills in Sonnet subagents; commit on Sonnet"
```

---

### Task 4: Point gate references at `cmp-gates`; README

**Files:**
- Modify: `cmp-code-rules/SKILL.md:239`, `cmp-feature/SKILL.md:178,182-183`, `cmp-feature/references/layout.md:163-164`, `cmp-design-to-code/SKILL.md:126`
- Modify: `README.md` (skills table + model note)

**Interfaces:**
- Consumes: `cmp-gates` (Task 2).

- [ ] **Step 1: Replace the "run the gates" references** (the "schedule"/"recipes" ones stay on `cmp-verify`)

- `cmp-code-rules/SKILL.md`: `- The gates in \`cmp-verify\` are green.` → `- The gates are green (the last \`cmp-gates\` report).`
- `cmp-feature/SKILL.md` "Done when": `- The Android gate is green; the iOS gate runs on the schedule in \`cmp-verify\`, section 2.` → `- The Android gate is green (\`cmp-gates android\`); the iOS gate runs on the schedule in \`cmp-verify\`, section 2.`
- `cmp-feature/SKILL.md` "Headless runs": `Run the Android gate once the screen or module's files are in place` → `Run the Android gate (\`cmp-gates android\`) once the screen or module's files are in place`
- `cmp-feature/references/layout.md`: `7. Run the Android gate once the module's files are in place;` → `7. Run the Android gate (\`cmp-gates android\`) once the module's files are in place;`
- `cmp-design-to-code/SKILL.md` §6: `Then run the gates (\`cmp-verify\`).` → `Then run the gates (\`cmp-gates\`).`

- [ ] **Step 2: Verify no gate-running reference is left on `cmp-verify`**

Run: `grep -rn "cmp-verify" --include=SKILL.md --include=*.md cmp-* compass-kit | grep -iE "run the gates|gates in|gates listed"`
Expected: no output.

- [ ] **Step 3: README**

In the skills table, after the `cmp-verify` row add:

```markdown
| [`cmp-gates`](./cmp-gates) | Run the finish gates in a separate Sonnet subagent and get a short pass/fail report; fixes only mechanical failures with a written recipe and reports the rest. |
```

and change the `cmp-verify` row's text to: `When to build, how to read gate output, and recipes for the common Kotlin Multiplatform, KSP, Koin and Compose resources failures.`

Add `cmp-gates` to the kit sentence (`` `cmp-verify`, `cmp-gates`, `cmp-commit` ``). After the table add:

```markdown
**Models.** Skills that write application code (`cmp-code-rules`, `cmp-feature`,
`cmp-design-to-code`) run on your session model. Mechanical skills run in their own subagent on
Sonnet and return a short report (`cmp-gates`, `cmp-detekt`, `cmp-testing`, `cmp-maestro`);
`cmp-commit`, `cmp-new-project` and `cmp-matrix-test` run on Sonnet. `scripts/check-skills.sh`
enforces these rules.
```

- [ ] **Step 4: Run the guard**

Run: `bash scripts/check-skills.sh`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add cmp-code-rules/SKILL.md cmp-feature cmp-design-to-code/SKILL.md README.md
git commit -m "docs(kit): run gates through cmp-gates; document the model split"
```

---

### Task 5: `delegate.sh --model`

**Files:**
- Modify: `account-delegate/scripts/delegate.sh` (usage lines 3-4 and 15; arg loop ~66-79; validation after line 105; plan reuse ~123-126; plan.json write ~279-285; FLAGS ~291; write_meta ~205-219)
- Test: `account-delegate/tests/test_delegate.sh`, `account-delegate/tests/test_delegate_plan.sh`

**Interfaces:**
- Produces: `delegate.sh ... [--model <alias|id>]`; env `DELEGATE_MODEL`; `meta.json.model` (string or null); `plan.json.model` (string or null).

- [ ] **Step 1: Write the failing tests**

Append to `test_delegate.sh` right before its final `rm -rf "$TMP"` (reuse its `run`, `has_arg`, `lacks_arg`, `meta`, `$TMP/proj`):

```bash
# --- model
for bad in -x 'a b' 'x;y' ''; do
  run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --model "$bad"
  check "--model '$bad' exits 2" test "$CODE" -eq 2
done
DELEGATE_MODEL='x;y' run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "invalid DELEGATE_MODEL exits 2" test "$CODE" -eq 2
FAKE_MODE=ok run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "no model: --model not passed" lacks_arg --model
check "no model: meta.model is null" test "$(meta .model)" = null
FAKE_MODE=ok run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --model sonnet
check "--model sonnet is passed" bash -c 'grep -qxF -- --model "$1" && grep -qxF sonnet "$1"' _ "$FAKE_LOG/args"
check "meta.model is sonnet" test "$(meta .model)" = sonnet
FAKE_MODE=ok DELEGATE_MODEL=haiku run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md"
check "DELEGATE_MODEL is used without the flag" has_arg haiku
FAKE_MODE=ok DELEGATE_MODEL=haiku run --mode ro --cwd "$TMP/proj" --brief "$TMP/brief.md" --model 'opus[1m]'
check "flag wins over DELEGATE_MODEL" bash -c 'grep -qxF "opus[1m]" "$1" && ! grep -qxF haiku "$1"' _ "$FAKE_LOG/args"
```

Append to `test_delegate_plan.sh` right before its final `rm -rf "$TMP"` (it uses a fresh repo, because earlier checks leave `$REPO` with uncommitted changes; reuse `$B`, `run`, `meta`):

```bash
# --- model is fixed per plan
MREPO="$TMP/mrepo"; mkdir -p "$MREPO"
git -C "$MREPO" init -q && echo base > "$MREPO/README" && git -C "$MREPO" add . && git -C "$MREPO" commit -qm base
MAIN="$(git -C "$MREPO" symbolic-ref --short HEAD)" REPO="$MREPO"
PM="$TMP/plans/pm"
FAKE_MODE=write FAKE_FILE=m1.txt run --mode write --plan "$PM" --cwd "$REPO" --brief "$B" --base "$MAIN" --model opus
check "first plan job with --model exits 0" test "$CODE" -eq 0
check "plan.json stores the model" test "$(jq -r .model "$PM/plan.json")" = opus
FAKE_MODE=write FAKE_FILE=m2.txt run --mode write --plan "$PM" --cwd "$REPO" --brief "$B"
check "later job reuses the plan model" bash -c 'grep -qxF -- --model "$1" && grep -qxF opus "$1"' _ "$FAKE_LOG/args"
check "later job meta.model is opus" test "$(meta .model)" = opus
FAKE_MODE=write FAKE_FILE=m3.txt run --mode write --plan "$PM" --cwd "$REPO" --brief "$B" --model sonnet
check "later job with a different --model exits 2" test "$CODE" -eq 2
FAKE_MODE=write FAKE_FILE=m4.txt run --mode write --plan "$PM" --cwd "$REPO" --brief "$B" --model opus
check "later job with the same --model exits 0" test "$CODE" -eq 0
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bash account-delegate/tests/test_delegate.sh 2>&1 | grep -E "FAIL" ; bash account-delegate/tests/test_delegate_plan.sh 2>&1 | grep FAIL`
Expected: FAIL lines for the new model checks (unknown flag `--model` → usage exit 2, so "is passed" checks fail).

- [ ] **Step 3: Implement**

Usage comment (lines 3-4) and `usage()`: add ` [--model <m>]` to both forms, and a comment line:
`#   --model <alias|id> (or DELEGATE_MODEL): the second account's model; unset = its default. A plan keeps the model of its first job.`

Arg loop: `MODEL="" MODEL_GIVEN=0` added to the initial assignment line; new case
```bash
    --model) MODEL="$2"; MODEL_GIVEN=1 ;;
```

After `case "$RESUME" ...` (line ~105):
```bash
if [ "$MODEL_GIVEN" -eq 0 ] && [ -n "${DELEGATE_MODEL:-}" ]; then MODEL="$DELEGATE_MODEL"; MODEL_GIVEN=1; fi
if [ "$MODEL_GIVEN" -eq 1 ]; then
  case "$MODEL" in ''|-*|*[!A-Za-z0-9._\[\]-]*) die "invalid --model (letters, digits, . _ - [ ], not starting with -): $MODEL" ;; esac
fi
```

In the existing-plan block (after `[ "$(pj .cwd)" = "$CWD" ] || die ...`):
```bash
  PLAN_MODEL="$(pj .model)"
  if [ "$MODEL_GIVEN" -eq 1 ] && [ "$MODEL" != "$PLAN_MODEL" ]; then
    die "--model was fixed to '${PLAN_MODEL:-default}' when plan $PLAN_ID was created; drop --model"
  fi
  MODEL="$PLAN_MODEL"
```

plan.json write: add `--arg model "$MODEL"` and `model: (if $model == "" then null else $model end),` to the object.

Both mode branches set `FLAGS` (ro ~247, write ~293). Right before the `env "${UNSET[@]}"` call (~315) add once:
```bash
[ -z "$MODEL" ] || FLAGS+=(--model "$MODEL")
```

write_meta: add `--arg model "$MODEL"` and `model: ($model | opt),` after `permission_mode`.

- [ ] **Step 4: Run all account-delegate tests**

Run: `for t in account-delegate/tests/test_*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"; done`
Expected: PASS for all five files.

- [ ] **Step 5: Commit**

```bash
git add account-delegate/scripts/delegate.sh account-delegate/tests
git commit -m "feat(account-delegate): --model and DELEGATE_MODEL, fixed per plan"
```

---

### Task 6: `account-delegate` SKILL.md and README defaults

**Files:**
- Modify: `account-delegate/SKILL.md` (§2 Offer ~74-90, the run command ~104, plan-mode command ~254)
- Modify: `account-delegate/README.md` (options/env list)

**Interfaces:**
- Consumes: `--model` (Task 5).

- [ ] **Step 1: Defaults and offer wording**

In §2 Offer add:

```markdown
- **Model.** Read-only jobs (analysis, research, review) run with `--model sonnet`; write jobs and
  plan execution with `--model opus`. The offer names it ("…şirket hesabında Sonnet ile
  çalıştırayım mı?"). If the user names another model, use that. `DELEGATE_MODEL` set in the
  environment replaces these defaults.
```

Add ` --model <sonnet|opus>` to both command lines (single job ~104, plan mode ~254), and in plan
mode note: "Pass `--model` on the first job only; later jobs inherit it (a different value is
refused)."

- [ ] **Step 2: README**

Add to the options/env list:
```markdown
- `--model <alias|id>` / `DELEGATE_MODEL` — model for the second account's run (flag wins; unset =
  that account's default). A plan keeps its first job's model. Recorded as `model` in `meta.json`.
```

- [ ] **Step 3: Check**

Run: `bash scripts/check-skills.sh && grep -n -- "--model" account-delegate/SKILL.md account-delegate/README.md`
Expected: exit 0; the offer bullet, both commands and the README line listed.

- [ ] **Step 4: Commit**

```bash
git add account-delegate/SKILL.md account-delegate/README.md
git commit -m "docs(account-delegate): Sonnet for read-only jobs, Opus for write and plan jobs"
```

---

### Task 7 (controller, with Kerem — not a subagent task): global rule and end-to-end check

- [ ] **Step 1: Global `~/.claude/CLAUDE.md`** — append to "Kerem'in genel tercihleri":

```markdown
- **Model yönlendirme:** Ana oturum Opus. Subagent açarken Agent tool'a `model` ver:
  implementer (kod yazan) → verme/`inherit` (Opus); görev başına spec-uyum reviewer'ı → `sonnet`;
  kod kalitesi reviewer'ı ve son genel review → `opus`; dosya arama/keşif (Explore) → `haiku`;
  doküman/web araştırması, log/transcript özeti → `sonnet`. (8 Ekim 2026)
```

- [ ] **Step 2: Manual check in one generated project** (from the spec's "Test ve doğrulama" 3-4)
  1. `cmp-matrix-test` on one variant, or `cmp-new-project` → the project has `.claude/skills/cmp-gates`.
  2. In an Opus session in that project: remove one import from a repository file → call `cmp-gates android` → the subagent runs on Sonnet (transcript), the main session receives only the report, the import is back.
  3. Introduce a logic bug that a unit test catches → `cmp-gates tests` → reported under *Open*, code and test unchanged.
  4. In a variant without detekt, `cmp-gates` → no detekt entry in the gate line.
  5. `/cmp-testing <a use case>` → tests written by the Sonnet subagent; no non-test file in `git status`.

- [ ] **Step 3: Report results to Kerem**; on failures, fix in the owning task's files and rerun its checks.
