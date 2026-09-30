---
name: cmp-code-rules
description: Use when writing or changing any Kotlin code in this Compose Multiplatform project — commonMain, androidMain or iosMain sources, composables, ViewModels, use cases, repositories, Koin annotations, Gradle build scripts — and before declaring a code change finished. Covers layering, visibility, Kotlin Multiplatform limits, Compose state and effects, DI annotations, strings and resources, accessibility and a self-review checklist.
---

# Code rules

Rules for every Kotlin change in this project. How to scaffold a screen or a module is in
`cmp-feature`; build commands and failure recipes are in `cmp-verify`.

## 1. Read first

- Before the first edit read the existing feature module(s) under `feature/`,
  `shared/src/commonMain/.../di/initKoin.kt`, `shared/src/commonMain/.../MainScreen.kt`, the
  `core/*` modules that exist, and the convention plugins in `build-logic/src/main/kotlin/convention/`
  (read only, never edit).
- The code that works in this project sets the conventions, not this document. When the two
  disagree, follow the code and mention the difference in your final summary.

## 2. Layers and boundaries

- `contract`: navigation destinations (`@Serializable`, implementing `NavigationCommand.Destination`)
  and the interfaces and models other features may use. A feature reaches another feature
  **only through that feature's `contract`**.
- `domain`: plain Kotlin. Models, repository interfaces, one use case per operation. No Android,
  iOS, Ktor, Room or Compose imports.
- `data`: repository implementations, DTOs, database entities, mappers. DTOs and entities never
  leave `data` (or `core/database`, where shared entities live).
- `presentation`: ViewModel, UiState, actions, Route and Content composables, the navigation
  provider, test tags.
- When a `contract` type changes, find its users with `grep` and update them in the same change.

## 3. Visibility

- Default to `internal`. `Content` composables are `private`.
- `public` only for what another Gradle module uses: contract types, domain models, repository
  interfaces, use cases, and the Koin `@Module` classes that `initKoin.kt` registers.

## 4. Kotlin Multiplatform

- `commonMain` has no `java.*`, `android.*`, `System.*`, `String.format`, `synchronized {}` or
  `Thread`. Android still compiles; the iOS gate fails.
- Time comes from `kotlin.time` or kotlinx-datetime (add it through `libs.versions.toml`).
  Formatting uses string templates or a small common helper. Locking uses
  `kotlinx.coroutines.sync.Mutex`.
- `Dispatchers.IO` in `commonMain` needs `import kotlinx.coroutines.IO`.
- `expect`/`actual` only for a real platform difference (a platform API, a file path). Check first
  whether a common library already covers it. Apple APIs in `iosMain` that take pointers need
  `@OptIn(ExperimentalForeignApi::class)`.

## 5. Kotlin style

- No `!!`. Use `?:`, `requireNotNull(x) { "why" }` or a typed error.
- Qualified access inside a string template needs braces: `"${user.name}"`. `"$user.name"`
  compiles and prints the whole object followed by `.name`.
- `when` for three or more branches; `sealed interface` for closed hierarchies.
- One top-level public or internal type per file, named after it. The template's
  `contract/Screens.kt`, which holds all destinations of a feature, is the exception.
- No `GlobalScope`, no `runBlocking`.
- Dependency versions live only in `gradle/libs.versions.toml`; build scripts use `libs.*`.
  A new library goes into the module's own `build.gradle.kts`, never into `build-logic`.
- KSP, never kapt.
- The `@file:Suppress(...)` lines in generated files (`Screens.kt`, `initKoin.kt`) belong to the
  template. Leave them and add no suppressions of your own.

## 6. DI with Koin annotations

| Class | Annotation | Import |
|---|---|---|
| ViewModel | `@KoinViewModel` | `org.koin.android.annotation.KoinViewModel` (never `org.koin.core.annotation`) |
| Use case | `@Factory` | `org.koin.core.annotation.Factory` |
| Repository implementation | `@Single(binds = [XRepository::class])` | `org.koin.core.annotation.Single` |
| Other long-lived helper | `@Single` | `org.koin.core.annotation.Single` |
| Navigation provider | `@Single(binds = [NavGraphProvider::class])` + `@Named("<Name>Provider")` | `org.koin.core.annotation` |
| Mapper | none, it is an extension function | |

- Every Gradle module with injectable classes has one `@Module @ComponentScan("<its package>")`
  class in its `di/` package, and that class is added to `initKoin.kt` as
  `add(<Class>().module)`. A missing registration compiles and then crashes at runtime.
- A constructor parameter whose type is provided by another Gradle module is marked `@Provided`
  (`org.koin.core.annotation.Provided`), unless that module is listed in
  `@Module(includes = [...])`. The template turns on Koin's compile-time check, so without it
  the build stops with `Unreachable definition`.
- No hand-written `module { }` DSL. If the template already has some, keep it.
- Only the Route obtains the ViewModel, with `koinViewModel()`; it is never passed further down.

Wiring details and runtime diagnosis: `cmp-feature`, `references/koin.md`.

## 7. ViewModel and state

- Extend the project's `CoreViewModel` when `core/presentation` has one, otherwise
  `androidx.lifecycle.ViewModel`.
- A private `MutableStateFlow<XUiState>` exposed as `StateFlow` (`asStateFlow()`), changed with
  `_uiState.update { it.copy(...) }`.
- User actions: `sealed interface XAction` and one `fun onAction(action: XAction)`. If the module
  already uses the template's `XActions` interface implemented by the ViewModel, keep that style
  instead of mixing the two.
- The Route collects with `collectAsStateWithLifecycle()`.
- An action that writes (save, add, delete, send) ignores repeats while it runs: an `isSaving`-style
  flag in the UiState, checked in the ViewModel and disabling the button. Lists the user saves are
  ordered by a stored, increasing sequence number, not by the device clock.
- Navigation is a ViewModel call on the injected `NavigationManager`
  (`navigate(NavigationCommand.NavigateTo(destination))`). Other one-off events are rare; turn
  them into state where possible (a message the UI shows and then clears with an action).
- UiState is an `@Immutable` data class, or a sealed interface of them when states exclude each
  other. Plain `List` is fine; strong skipping, on by default in this Kotlin version, handles
  it. Do not add a collections library only for stability.

## 8. Compose

Details and tables: `references/compose.md`.

- Route and Content are separate: `internal fun XRoute()` gets the ViewModel and collects state;
  `private fun XContent(uiState, onAction, modifier)` is stateless.
- `modifier: Modifier = Modifier` is the first optional parameter and is applied once, to the
  outermost element.
- Lazy lists give every item a unique, stable `key`.
- Effect keys are the real inputs. A long-lived effect that calls a changing callback reads it
  through `rememberUpdatedState`.
- Values that change every frame (scroll offset, animation) are read in lambda modifiers
  (`offset { }`, `graphicsLayer { }`, `drawBehind { }`).
- Looping animations (a flickering flame, a bobbing sprite, twinkling stars) leave the layout and
  the accessibility tree still. Maestro waits for the UI hierarchy to settle before every tap; in a
  measured walkthrough a flame that switched between a 5- and a 4-pixel-tall frame kept moving
  everything around it, and each tap on that screen took 13 to 15 seconds. Give a frame animation
  a fixed size (its largest frame), draw motion in `Canvas` / `drawBehind` or `graphicsLayer { }`
  instead of changing size or padding, and wrap purely decorative moving elements in
  `Modifier.clearAndSetSemantics { }`.
- No `@Composable` modifier factories and no `composed { }`.
- Event parameters are named `onX`, present tense (`onClick`, `onItemSelect`).
- Material3 only. Material icons (`androidx.compose.material.icons`) are not on the classpath;
  use vector drawables from `composeResources/drawable`.
- No `@Preview` in `commonMain`: the preview tooling is only on the Android classpath here, so
  it compiles for Android and breaks the iOS gate. Previews are covered in `cmp-feature`.

## 9. Loading, empty and error

Every screen that loads something shows loading, empty, error and content as separate states.
An error is never turned into an empty list.

## 10. Carrying errors

- Expected failures do not escape as exceptions. The data layer catches them and returns a typed
  result: the template's `RestResult` from `core/domain` when it exists (its `Error` carries a
  `DataError` from template-2026.09.30.1 on), otherwise a small sealed type.
- In any `catch (e: Exception)` or `runCatching` you write, rethrow `CancellationException`
  first.

## 11. Strings, languages and resources

- Every name in code is English: modules, packages, classes, files, string keys — even when the
  request or the UI language is not.
- No user-visible text is hard-coded in a composable.
- If the project has `core/multilang` (Compass turns it on for every app):
  - Each text is a property of `StringResourcesUiModel` with an English name (`expenseListTitle`).
    When `LanguageManagerImpl` has `resourcesFor` (projects from template-2026.09.29.2 on), the
    properties have no default value: every language object sets every property or the build
    fails, and a device language the app does not ship shows the English object
    (`fallbackResources`). In older projects each property's default value is its English text;
    keep it that way.
  - Fill the language objects (`resourceEN`, `resourceTR`, …) for every UI language the task
    names (Compass's prompt lists them). Delete the languages it does not name from `AppLanguage`
    (keep `SYSTEM`), `languageResources` and their `Resource<XX>.kt` files (`grep` for each entry
    first). In a later task that names no languages, keep the languages already in
    `languageResources`. A language object left with empty strings shows a blank UI.
  - Read texts in composables with `LocalStringResources.current.<property>`.
  - The app's root composable (`shared/src/commonMain/kotlin/<package path>/MainScreen.kt`) provides
    the strings: it collects `languageManager.currentResources`, wraps the app in
    `CompositionLocalProvider(LocalStringResources provides resources)` and calls
    `languageManager.setSystemLanguage()` once in `LaunchedEffect(Unit)` (the root runs once per
    launch, so this is not the screen-loading effect `references/self-review.md` flags), with
    `LanguageManager` from `koinInject()` (`org.koin.compose.koinInject`): it is a composable, not
    a ViewModel.
    - `shared/.../AppTheme.kt` exists: the project was generated from the release that added it or
      later. Generated with this wiring: the showcase, and a blank app with Multi-Language. Keep it
      when you change `MainScreen`; it sits inside `AppTheme { … }`.
    - A blank app without `AppTheme.kt` has a `MainScreen` without it: add it as above (collect
      with `collectAsStateWithLifecycle()`). Without it every screen shows the English strings and
      the picker has no effect.
  - Older projects only (`LanguageManagerImpl` has `updateResource`, not `resourcesFor`): fall back
    to `resourceEN` there when `languageResources` has no entry for the language (for example
    `SYSTEM` on a device language the app does not ship); that template keeps the previous
    language otherwise.
  - Language picker: `LanguageManager.setLanguage(AppLanguage.X)`, with `LanguageManager`
    injected into the ViewModel as `@Provided`; "System default" is `AppLanguage.SYSTEM`; the
    current choice comes from `getCurrentLanguageFlow()` into the ViewModel's state; each language
    row shows a flag emoji and `AppLanguage.displayName` (the language's own name, not
    translated); the "System default" label is a `StringResourcesUiModel` property, because
    `SYSTEM.displayName` is a fixed English "System"; the picker and each row get a `testTag`
    (`cmp-maestro`).
- If there is no `core/multilang`: texts live in `src/commonMain/composeResources/values/strings.xml`
  of the module that shows them, read with `stringResource(Res.string.key)` from
  `org.jetbrains.compose.resources`.
- A module that gets `composeResources` (fonts, drawables, sounds, or strings in the second case)
  must enable Android resources in its build file, or its files are silently left out of the APK
  (`cmp-feature`, `references/screen.md`).
- Never `androidx.compose.ui.res.*`; it is Android-only and detekt forbids it.
- If you add a machine translation, say so in your final message.

## 12. Accessibility

- Touch targets are at least 48dp.
- An icon-only button has a `contentDescription` from resources; a decorative icon gets `null`.
- Put the click on the text or row itself, or merge the parts into one node
  (`Modifier.semantics(mergeDescendants = true) { }` or `clearAndSetSemantics { }`).
- Boxes that contain text use `heightIn(min = ...)`, not a fixed `height`, so large fonts fit.

## 13. Abstraction threshold

- A new interface only when a second implementation exists today.
- A new parameter or flag only when this change calls it with a non-default value.
- No sealed hierarchy with a single subtype.
- The seams required by section 2 (use case, repository interface, contract, Route and
  Content, mapper) are exempt.

## 14. Comments

A comment explains a non-obvious *why*. No decorative separators, emoji, phase or task numbers,
"temporary" notes, `TODO` or `FIXME` (detekt rejects `FIXME:` and `STOPSHIP:`).

## 15. Generated-code blind spot

A symbol that carries a Koin, Room, `@Preview` or `@Serializable` annotation is used by generated
code. "No references found" is not a reason to delete it.

## References

- `references/compose.md`: stability, state and effect tables, modifier order, lazy lists, crash
  patterns, accessibility, composable API shape.
- `references/self-review.md`: what to search the diff for before finishing, and how to filter
  false positives.

## Done when

- Every new or changed file follows the layer, visibility and KMP rules above.
- The `references/self-review.md` pass is done; each finding is fixed or reported with its reason.
- The gates in `cmp-verify` are green.

## Headless runs

- This skill only tells you what to read and write; it runs nothing.
- There is no internet in a headless run, so library documentation cannot be looked up. Look for
  an existing use of the API in the project, read the version in `gradle/libs.versions.toml`,
  write the smallest call and let the Android gate confirm it. Libraries in the Gradle cache are
  packed jars and klibs that the file tools cannot read.
- Do not ask questions. Pick the reasonable option and list it under `Assumptions` in your final
  message.
