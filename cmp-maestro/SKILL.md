---
name: cmp-maestro
description: Use when writing or repairing a Maestro flow for this app — the .maestro/walkthrough.yaml that Compass records the demo video from, a regression flow, or a flow that fails on selectors or timing — and when adding testTags so elements can be found by id. Also for an exploratory on-device check of a screen in an interactive session. Runs in a subagent that does not see this conversation: pass what it needs as the argument.
context: fork
background: false
model: sonnet
argument-hint: "<flow (walkthrough or a regression flow) and the screens it covers>"
---

# Maestro flows and test tags

## Input and report

You run in your own subagent and did not see the caller's conversation.

Caller's request: "$ARGUMENTS"

- The request names the flow and the screens it covers. `""` means the walkthrough,
  `.maestro/walkthrough.yaml`.
- Read `CLAUDE.md` and the files involved yourself; for any Kotlin you write, follow
  `../cmp-code-rules/SKILL.md` (path relative to this skill's folder).
- Application code that is not a `testTag`, a `<Name>TestTags` object or `testTagsAsResourceId`
  is not yours to change.
- Your final message is the report, nothing else: files changed (one line each), the gate you ran
  and its result, and what is still open with file:line and why. No raw log.

After the coding step Compass installs the signed release APK on an Android emulator, starts a
screen recording and plays `.maestro/walkthrough.yaml`. It then builds the iOS app for an iPhone
simulator and plays **the same flow** there for a second video. If a step fails or the flow runs
past the limit, the walkthrough stops there and Compass reports it as not run. The flow is for the
video: it shows the app, it does not assert details.

The one flow must run on both platforms:
- Target elements only by `id:` (the testTags below; on iOS a Compose `testTag` is the
  accessibility identifier Maestro matches). Avoid `text:` selectors for anything the language
  switch changes.
- No Android-only commands: no `back`, no `pressKey: back`/`home`, no Android intents or
  `adb`-style steps, and no `hideKeyboard` (iOS number and decimal keyboards have no dismiss key, so
  Maestro fails with "Couldn't hide the keyboard" and the iOS video stops there). To go back, tap the
  app's own back button by its `id`.

## 1. How `id:` finds a composable

- Maestro's `id:` matches the Android resource id. A Compose `testTag` becomes that id only below a
  node with `testTagsAsResourceId = true`. Without it no `id:` selector matches anything.
- The property is Android-only, so turn it on once through an `expect`/`actual` modifier in
  `core/presentation`, which compiles for both platforms. This setup ran in a walkthrough Compass
  recorded:

```kotlin
// core/presentation/src/commonMain/kotlin/<pkg>/core/presentation/TestTags.kt
expect fun Modifier.testTagsAsResourceId(): Modifier

// core/presentation/src/androidMain/kotlin/<pkg>/core/presentation/TestTags.android.kt
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId

actual fun Modifier.testTagsAsResourceId(): Modifier = semantics { testTagsAsResourceId = true }

// core/presentation/src/iosMain/kotlin/<pkg>/core/presentation/TestTags.ios.kt
actual fun Modifier.testTagsAsResourceId(): Modifier = this
```

- Apply it to the outermost layout in `shared/.../MainScreen.kt`:
  `Scaffold(modifier = Modifier.fillMaxSize().testTagsAsResourceId(), ...)`. The generator does
  not make `shared` depend on `core/presentation`; add
  `implementation(projects.core.presentation)` to the `commonMain` dependencies in
  `shared/build.gradle.kts` if it is missing.
- Dialogs, bottom sheets and dropdown menus open in their own window, which does not inherit the
  flag. Apply the same modifier to the content root of each one the flow touches.

## 2. Tag catalogue

- Tags are never free strings. Each screen has `internal object <Screen>TestTags` in
  `presentation/ui/`, next to the screen (`cmp-feature`, `references/screen.md`), with
  `const val` values in `snake_case` and a screen prefix: `ROOT = "recipes_root"`.
- The flow uses the same strings verbatim.
- Every screen root has a `ROOT` tag; the flow uses it to know a transition finished.
- A screen with a text field also has a `TITLE` tag on its non-interactive title text
  (`TITLE = "recipe_detail_title"`); the flow taps it to close the keyboard.
- Put the tag on the node that is clicked or typed into (the `Button`, the `clickable` row, the
  `TextField`), not on a wrapper around it.
- List rows may share one tag; the flow picks a row with `index:`.

## 3. `walkthrough.yaml`

- Path: `.maestro/walkthrough.yaml` at the project root.
- `appId` is the `applicationId` from `build-logic/src/main/kotlin/config/AppConfig.kt`. Debug and
  release use the same id.
- The first step is `launchApp` with `clearState: true`, so the app starts empty. The flow creates
  what it wants to show, or the app shows its sample data. Onboarding and permission dialogs are
  part of the flow.
- Visit every screen in the order a user would, and do something typical on each.
- After every transition wait for the next screen's `ROOT` with `extendedWaitUntil`.
- Maestro has no sleep command (`sleep:` and `wait:` fail `check-syntax`), and
  `waitForAnimationToEnd` returns as soon as the screen is still. To let the viewer see a screen
  for 1 to 2 seconds, wait for an id that never appears, with `optional: true` and the pause as the
  timeout.
- Screens that load from the network get a 15-second timeout, and the flow must go on whether the
  content or the error state arrives.
- After `inputText`, close the keyboard by tapping the screen's `TITLE` tag before the next tap.
  Never `hideKeyboard` (see above).
- A row below the fold does not exist on screen yet: `scrollUntilVisible` first.
- Selectors: `id:` always. Text only for a system dialog that cannot carry a tag. Coordinates
  (`point:`) never without a comment saying why.
- No `takeScreenshot`: Compass records a video.
- Stay under 60 seconds. Every step costs time on an emulator: a measured flow with 59 steps and
  14 seconds of pauses produced a 95-second video. Aim for about 30 steps. Compass stops the flow
  at 120 seconds.
- A tap that takes 10 seconds or more means the screen never stops changing: a looping animation
  moves the layout or the accessibility tree (see `cmp-code-rules` section 8). Fix the animation,
  not the flow.

This shape passed `maestro check-syntax`:

```yaml
appId: com.example.cookbook
---
- launchApp:
    clearState: true
- extendedWaitUntil:
    visible:
      id: "recipes_root"
    timeout: 15000
# Network screen: wait for the list, but go on if the error state shows instead.
- extendedWaitUntil:
    visible:
      id: "recipes_list"
    timeout: 15000
    optional: true
- runFlow:
    when:
      visible:
        id: "recipes_retry"
    commands:
      - tapOn:
          id: "recipes_retry"
# Pause so the viewer can see the screen: wait for an id that never appears.
- extendedWaitUntil:
    visible:
      id: "walkthrough_pause"
    timeout: 1500
    optional: true
- tapOn:
    id: "recipes_item"
    index: 0
- extendedWaitUntil:
    visible:
      id: "recipe_detail_root"
    timeout: 10000
- tapOn:
    id: "recipe_detail_note_field"
- inputText: "Less salt"
# Close the keyboard on both platforms: tap the non-interactive title.
- tapOn:
    id: "recipe_detail_title"
- tapOn:
    id: "recipe_detail_save"
```

## 4. Pitfalls

- No `id:` matches anywhere: `testTagsAsResourceId` is missing at the root, or the element is in a
  dialog window without it.
- The tap lands but nothing happens: the tag sits on a wrapper or a text node, not on the
  clickable node.
- `runScript` runs JavaScript, not shell commands.
- While Maestro runs, another hierarchy reader (`uiautomator dump`) sees an empty tree. Use one at
  a time.
- `launchApp` with `clearState` wipes stored data every run; a flow that relies on earlier data
  must create it first.
- A deep link opens a screen directly: `openLink` with the project's scheme (project name in lower
  case), then wait for the screen's `ROOT`:

  ```yaml
  - openLink: "cookbook://recipes"
  - extendedWaitUntil:
      visible:
        id: "recipes_root"
      timeout: 10000
  ```

## 5. When a flow fails (interactive)

In a forked run there is no one to ask: do the check and put what you would have asked under
*Open* in the report.

- Classify the failure: `SELECTOR_MISS` (the id is wrong or not visible yet), `RACE` (the step ran
  before the screen was ready), `TAG_MISSING` (the element has no tag), `CRASH` (the app died).
- Fix `SELECTOR_MISS` and `RACE` in the flow: a better selector, a wait, a scroll. At most two
  attempts per step.
- `TAG_MISSING`: add the tag in the code (in the owner's session, propose the change first).
- `CRASH`: read the top frame of the stack trace in `adb logcat` and stop; fixing the app comes
  before the flow.
- The same step failing twice: stop and report `FLOW / STEP / CLASS / HINT / ARTIFACTS`.

## 6. Exploration mode (interactive only)

In a forked run there is no one to ask: do the check and put what you would have asked under
*Open* in the report.

For a quick look at a screen on a device when no permanent flow is needed.

- Read the screen with `maestro hierarchy` (or `adb shell uiautomator dump`), do one action, read
  it again.
- Before trusting a negative result ("the change does not work on the device"), make sure the
  installed app contains the change: `./gradlew :androidApp:installDebug`, then retry. An old build
  is the first suspect.
- "Test it" is ambiguous: ask whether the owner means unit tests (`cmp-testing`) or the device.

## Done when

- Every `id:` in the flow, except the pause id, equals a constant in a `*TestTags` object (check
  each with `grep`). The pause id matches no tag.
- `testTagsAsResourceId` is on at the UI root and in every dialog the flow opens.
- `appId` matches `AppConfig.applicationId`.
- The flow starts with `launchApp` and `clearState: true`, visits every screen, has no
  `takeScreenshot` and stays within about 30 steps.
- Interactive session: `maestro check-syntax .maestro/walkthrough.yaml` prints `OK` and
  `maestro test .maestro/walkthrough.yaml` passed once.

## Headless runs

- `maestro check-syntax .maestro/walkthrough.yaml` runs here: run it after writing the flow and fix
  the flow until it prints `OK`. `maestro test` and `adb` do not run here (the connected device may
  be the owner's phone); Compass plays the flow on an emulator after the coding step.
- Verification is static: `grep` every `id:` value in the flow against the `*TestTags` objects and
  fix any mismatch.
- You will not see the run, so prefer generous timeouts over tight timing. Only pauses and waits
  for content that may legitimately not arrive are `optional`; a tap stays mandatory, or a broken
  flow looks like a working one.
