---
name: cmp-verify
description: Use when deciding when to build, when fixing a Gradle, KSP, Koin or Compose resources failure that cmp-gates reported as open, or when reading gate output in this Compose Multiplatform project — the build schedule, how to read the output, and the recipes for common Kotlin Multiplatform failures, including NoDefinitionFoundException at runtime. The gates themselves are run with cmp-gates.
---

# Verify and fix builds

## 1. The gates

Run the gates listed in `CLAUDE.md` under *Definition of done*, in that order.

- Run them with `cmp-gates`: it runs them in a separate subagent and returns a short report, so
  the Gradle log stays out of this session. Run a gate directly only to reproduce one failure
  `cmp-gates` reported as open.
- The list names the exact commands: the Android debug build, the iOS simulator compile, detekt
  (only when the project has it) and the test run. Run each one as written, as its own command.
  `CLAUDE.md` is the source of truth; do not substitute other task names.
- `./gradlew build` is not used: it also links release iOS frameworks and runs out of memory.
- A red detekt gate is fixed with `cmp-detekt`; a red or empty test gate with `cmp-testing`.

## 2. When to build

- Run the Android gate after each screen or module is in place, not after every change. Wrong
  imports are the most common failure; one run finds all of them.
- Run the iOS gate twice: once midway, after the first module and any `expect`/`actual` code or
  `commonMain` code that touches time, files, formatting or other platform APIs, and once in the
  final pass. Android compiling says nothing about iOS.
- detekt and tests come once the code stands; the final pass runs every gate, in order.

## 3. Read the output correctly

- A success claim rests on what ran: the task lines in the log and, for tests, the test count.
  The exit code alone is not evidence.
- The test gate is green only with tests. `allTests` succeeds even when no module has a test
  (every test task shows `NO-SOURCE` or `SKIPPED`), but zero tests counts as red. Results are in
  `<module>/build/test-results/iosSimulatorArm64Test/TEST-*.xml`; the `tests="N"` attribute is the
  count. The new template also writes `testAndroidHostTest/` results (JVM run, `KoinGraphTest`);
  those are host-only and do not count toward the gate. Read them with Read or `grep`.
- A task aimed at the wrong module is green and proves nothing (for example
  `:feature:x:domain:allTests` when the tests are in `data`).
- The failing task names the layer:

| Failing task | Layer |
|---|---|
| `kspCommonMainKotlinMetadata` | Koin wiring checked by KSP |
| `compileKotlinIosSimulatorArm64` or `compileCommonMainKotlinMetadata`, while `compileAndroidMain` passes | `commonMain` uses something only Android has |
| `compileAndroidMain` fails as well | an ordinary Kotlin error: types, imports, syntax |
| `merge...Resources`, `dex...`, `package...` | Android packaging or resources |
| `detekt` | style and complexity findings (`cmp-detekt`) |
| `iosSimulatorArm64Test` | a failing test (`cmp-testing`) |

- Kotlin errors look like `e: file:///...File.kt:12:5 message`. Fix the first one; many of the
  rest are its consequences.
- "Gradle did not start" is an environment problem, not a code problem: daemon crashes, JDK
  errors, out of memory, a lost connection to the daemon. Run `./gradlew --stop` once and retry. If
  the project folder was moved and Android packaging fails on paths, `./gradlew clean` once.

## 4. Recipes

Symptoms, causes and fixes: `references/failures.md`. The most frequent:

- iOS red, Android green: `commonMain` uses a JVM or Android API (`java.*`, `System.*`,
  `String.format`, `Dispatchers.IO` without its import, `@Preview`).
- `Unresolved reference 'KoinViewModel'`: import it from `org.koin.android.annotation`.
- `[ksp] --> Unreachable definition`: add `@Provided` to that constructor parameter.
- `NoDefinitionFoundException` at runtime: the order in `cmp-feature`, `references/koin.md`.
- `Res` or a resource key does not resolve: wrong `Res` package or missing key import.
- Duplicate classes or version conflicts: align versions in `gradle/libs.versions.toml`. Never
  touch the Gradle wrapper, the Kotlin or AGP versions, or the `build-logic` plugin wiring.
- `Serializer for class ... is not found` when navigating: the destination lacks `@Serializable`.

## 5. Debugging discipline

- First decide the layer (compile, KSP, runtime, UI), then read the first real error line, then
  fix. Change one thing per attempt and rerun the same gate.
- Do not mask symptoms: no try/catch around a crash to make it quiet, no `@Suppress`, no baseline,
  no deleted or weakened test, no disabled rule to turn a gate green.
- If the same error survives two different fixes, stop and reread: the cause is usually one layer
  away from where you are looking.

## Done when

- Every gate from `CLAUDE.md` ran green in this session, after the last code change (the last
  `cmp-gates` report shows them all ✅).
- The final summary lists each gate's command and result, with the test count for the test gate.
- If a gate stays red: the summary gives its last error line and what was tried.

## Headless runs

- There is no Grep or Glob tool. Besides `./gradlew`, Bash runs read-only commands and the few the
  task prompt lists: search with `grep`, find files with `find` or `ls`, read files with Read.
- Run Gradle in the foreground and wait for it. Give each call a long Bash timeout (up to ten
  minutes): the first build of a fresh project and the iOS compile can take several minutes, and a
  timed-out call looks like a failure.
- Mind the turn budget: the Android gate per screen or module, the iOS gate midway and at the end,
  detekt and tests near the end, then all gates once more in order.
