---
name: cmp-detekt
description: Use when the detekt gate is red, or before finishing a change in a project that has detekt — running ./gradlew detekt from the template's convention plugin with the owner's detekt/detekt.yml, auto-correcting formatting first, then fixing the remaining findings at their cause, without suppressions, baselines or config changes.
context: fork
background: false
model: sonnet
---

# detekt

## Input and report

You run in your own subagent and did not see the caller's conversation.

- Input: `$ARGUMENTS` — which modules, or empty for all. Read `CLAUDE.md` and the files involved
  yourself; for any Kotlin you write, follow `../cmp-code-rules/SKILL.md` (path relative to this
  skill's folder).
- Application code that is not a mechanical detekt fix (formatting, an import, a constant, a
  visibility modifier) is not yours to change: a finding that needs a function split, a rename
  across files or a behaviour change is reported, not fixed.
- Your final message is the report, nothing else: files changed (one line each), the gate you ran
  and its result, and what is still open with file:line and why. No raw log.

Only for projects that have `build-logic/src/main/kotlin/convention/DetektConventionPlugin.kt`.
Without that file the project has no detekt gate and this skill does not apply.

## 1. How it runs

- The template's `DetektConventionPlugin` adds a `detekt` task to every module. It reads the
  owner's configuration from `detekt/detekt.yml` on top of detekt's defaults and includes the
  ktlint formatting rules.
- It scans the main source sets (`commonMain`, `androidMain`, `iosMain`, `main`), not tests.
- The gate is `./gradlew detekt` from the project root; it covers every module, template code
  included.
- While fixing, add `--continue` so every module reports in one run; without it Gradle may stop
  starting modules after the first failure.
- Each finding is one line:
  `e: /abs/path/File.kt:22:1 Unexpected blank line(s) before "}" [NoBlankLineBeforeRbrace]`.
  Each red module ends with `Analysis failed with N issues`. The console has everything; the HTML
  report (`<module>/build/reports/detekt/detekt.html`) adds nothing you need.
- Do not use `--quiet`; it hides the findings.
- The task runs without type resolution, so rules that need it stay silent (measured: `println`,
  `!!` and `Dispatchers.IO` passed). The gate does not catch them; `cmp-code-rules` still forbids
  them.

## 2. Auto-correct first

```
./gradlew detekt --auto-correct --continue
```

- Run it once, then count with a plain `./gradlew detekt --continue`; the count an auto-correct run
  prints is not reliable. The pass can rewrap code into a few new wrapping findings: fix them by hand
  with the rest instead of running auto-correct again. Measured: an app built by the coding step went
  from 436 findings to 26, a fresh project from the template from 77 to 10. Both gates stayed green
  after the rewrite.
- Nearly all of what it fixes is formatting: trailing commas, argument and parameter wrapping,
  function and class signature layout, blank lines, import order.
- Findings in template files count like yours; a fresh project already has some with this
  configuration.
- Then fix what is left by hand.

## 3. Write it right the first time

What this configuration expects, so new code does not add findings:

- No trailing commas, neither at call sites nor in declarations.
- A function signature with two or more parameters puts each parameter on its own line.
- A class header (constructor and supertypes) stays on one line when it fits in 120 characters,
  whatever the number of parameters; only a longer one gets one parameter per line.
- No comment after a parameter on the same line, and no extra spaces to align trailing comments.
- When one branch of a `when` spans several lines, a blank line separates every branch.
- Lines are at most 120 characters.
- `MagicNumber`: numbers other than -1, 0, 1, 2 and 3 need a name, except inside `@Composable`
  functions, in property and constant declarations (not local `val`s), as named arguments, as the
  receiver of an extension such as `16.dp`, and in files under a `theme` package.
- `LongMethod` (120 lines) and `LongParameterList` (7) do not apply to composables;
  `CyclomaticComplexMethod` (15) applies to everything, and each `when` branch counts.
- `const val` names are `SCREAMING_SNAKE_CASE`. A file with a single top-level type is named after
  that type.
- Forbidden: `FIXME:` and `STOPSHIP:` comments; imports of `android.util.Log`,
  `androidx.compose.ui.res.*` and `GlobalScope`; wildcard imports; unused parameters.

## 4. Fix at the cause

| Rule | Fix |
|---|---|
| `MagicNumber` | a named `private const val` at the top of the file, or move colours and sizes into the theme |
| `MaxLineLength`, `MaximumLineLength` | wrap the expression; long texts belong in string resources anyway |
| `CyclomaticComplexMethod` | split the function; a long `when` that maps ids to values becomes a map or data on the model |
| `LongMethod`, `LongParameterList` | extract functions; group related parameters into a data class |
| `PropertyName`, `TopLevelPropertyNaming` | rename to `SCREAMING_SNAKE_CASE` and update every use (`grep`) |
| `MatchingDeclarationName` | rename the file after its single top-level declaration |
| `DocumentationOverPrivateProperty` | give the property a name that explains it and drop the comment |
| `ForbiddenComment` | remove the `FIXME:` or `STOPSHIP:` marker; do the work, or list it in your summary |
| `ForbiddenImport` (`androidx.compose.ui.res`) | `org.jetbrains.compose.resources` (`cmp-code-rules`, section 11) |
| `ForbiddenImport`, `GlobalCoroutineUsage` (`GlobalScope`) | `viewModelScope`, or a scope passed in |
| `WildcardImport`, `NoWildcardImports` | import each name |
| `UnusedParameter` | remove the parameter and update the callers |
| `UnusedPrivateFunction`, `UnusedPrivateProperty`, `UnusedImport` | delete, unless generated code uses it (`cmp-code-rules`, section 15) |

- Projects generated from `template-2026.09.30` on pass compass-kit detekt clean for any
  package name and any valid module name.
- Older projects: `internal const val dataStoreFileName` in `core/database` is reported as
  `[PropertyName]` (the ktlint wrapper's rule; the file already suppresses detekt's own
  `TopLevelPropertyNaming`) and becomes `DATA_STORE_FILE_NAME`. Renaming changes no behaviour;
  the value stays.
- A composable too long to read: extract sub-composables, even though `LongMethod` allows it.
- Fix the finding and nothing around it. No unrelated refactoring on the way.
- After a batch of manual fixes run the Android gate: a rename that missed a use shows there.

## 5. Never

- `@Suppress`, `@file:Suppress`, a baseline file, `ignoreFailures`, or `--auto-correct` treated as
  a pass while findings remain.
- Changing `detekt/detekt.yml`: it is the owner's configuration, installed by Compass.
- Touching `DetektConventionPlugin.kt` or any other convention plugin.
- A wire format never needs a suppression: keep the Kotlin name conventional and put the wire name
  in `@SerialName`.

The template's own `@file:Suppress` lines (for example in `Screens.kt`, `initKoin.kt`, the
palette, `DataStore.kt`) stay as they are; add none.

## 6. Loop

Fix every finding from the last run in one batch, then run `./gradlew detekt` once; repeat only for what is
left, until it is clean. If one finding survives two different
fixes, reread the rule's message and the line; if it still resists, report it with the reason in
your final message. The gate stays red until it is fixed; silencing it is not an option.

## Done when

- `./gradlew detekt` ran green in this session after the last code change.
- The diff contains no new suppression, no baseline and no change to `detekt/detekt.yml` or
  `build-logic`.
- The Android gate is green after the fixes.

## Headless runs

- Read the findings from the `./gradlew` console output. `--auto-correct` is allowed and expected.
- Run Gradle in the foreground with a long Bash timeout. detekt itself takes seconds; the first
  build of the convention plugins takes longer.
- Do not ask whether a finding is worth fixing: every finding is fixed. A finding you could not
  fix goes into your final message with the reason; a judgement call you made (a constant's name,
  where a moved colour lives) goes under `Assumptions`.
