---
name: cmp-gates
description: Use to run the finish gates of this Compose Multiplatform project — before saying a change is done, after a screen or module is in place, or before a commit — in a separate subagent that returns a short pass/fail report instead of the Gradle log, fixing only mechanical failures that have a written recipe. Runs in a subagent that does not see this conversation: pass what it needs as the argument.
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

Caller's request: "$ARGUMENTS"

- The request above says which gates to run, in any wording: a name (`android`, `ios`,
  `detekt`, `tests`), a sentence ("only the Android gate") or a gate's command. Run exactly
  those, nothing else, and leave the others out of the report. `""` means all gates.
- The gate commands are in `CLAUDE.md` under *Definition of done*, in order. Run only the gates
  listed there: a project without detekt has no detekt gate, and that is not a failure.
- Read before running: `../cmp-verify/SKILL.md` sections 1 and 3 (how to read the output; the
  test gate counts tests and zero is red) and, when a gate is red, `../cmp-verify/references/failures.md`.
  These paths are relative to this skill's folder.

## 2. Run

- With an argument, run only the requested gates, even when the list in `CLAUDE.md` or
  `cmp-verify` says to run every gate in order: those rules are for a run without an argument.
  `tests` alone means only the test command, not the Android and iOS gates before it.
- Each gate as written, as its own command, in the foreground, with a long Bash timeout (up to
  ten minutes). `./gradlew build` is never used.
- Stop at the first red gate and go to section 3; continue with the next requested gate once it
  is green.

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
