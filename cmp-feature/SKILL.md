---
name: cmp-feature
description: Use when adding a new screen, feature module or data source to this Compose Multiplatform app — creating or filling feature/<name> with contract, domain, data and presentation layers, a new ViewModel with Route and Content, a repository backed by Ktor, Room or DataStore, a navigation destination, or the Koin wiring for any of these.
argument-hint: "<feature-name>"
---

# Adding a screen or a feature

This project uses one Gradle module per layer: `feature/<name>/{contract,domain,data,presentation}`.
The code rules for what goes inside the files are in `cmp-code-rules`.

## 1. Decide where it goes

- Something with its own data and its own destination is a feature module. A screen that only
  shows another view of an existing feature's data goes into that feature's `presentation`.
- Look in `settings.gradle.kts` first. The generator may already have created the module. From
  the template release with the blank guide screen on, every planned feature is a complete
  module: `contract/Screens.kt` (`<Name>Destination`), `presentation` with `<Name>Screen`
  (Route + Screen), `<Name>UiState`, `<Name>Actions`, `<Name>ViewModel`, `<Name>Provider` and
  `<Name>Entry`, and an empty `@Module` in `data` and `domain` — all three registered in
  `appModules()`. Projects generated before that have starter files only in the first planned
  feature and empty shells (four `build.gradle.kts`, no sources) for the rest. Fill an existing
  module; do not create a parallel one.
- When Compass started this run, its prompt names the module to use. Follow it.

## 2. Inspect before writing

- The four `build.gradle.kts` files of the existing feature: which convention plugin each applies
  (`libs.plugins.feature.<layer>.plugin`) and which project dependencies it declares.
- The package root, read from `contract/Screens.kt`.
- The Koin module class(es) under `*/di/` and their lines in `shared/.../di/initKoin.kt`.
- `shared/.../MainScreen.kt`: the start destination and how navigation providers are collected.
- Which `core/*` modules exist (`logging`, `network`, `database`, `presentation`, `designsystem`, `multilang`);
  the sections below apply only to what is there.

## 3. Skeleton

Full tree, build files and the checklist for a brand-new module: `references/layout.md`.

```
feature/<name>/contract/      Screens.kt: destinations (@Serializable, NavigationCommand.Destination)
feature/<name>/domain/        model/, repository/<Name>Repository.kt, usecase/ (@Factory), di/<Name>DomainModule.kt
feature/<name>/data/          repository/<Name>RepositoryImpl.kt (@Single(binds = ...)), model/ (DTOs), mapper/, di/<Name>DataModule.kt
feature/<name>/presentation/  ui/<Name>Screen.kt (Route + Content), ui/<Name>ViewModel.kt, ui/<Name>UiState.kt,
                              ui/<Name>Actions.kt, ui/<Name>TestTags.kt, di/<Name>PresentationModule.kt,
                              navigation/<Name>Provider.kt, navigation/<Name>Entry.kt
```

On a blank app, `<Name>Entry` (a `FeatureEntry`) puts a button for the module on `GuideScreen`,
which opens the module's destination. `GuideScreen` is a developer placeholder the app opens on
until you replace it (section 4), not a screen of the app. Projects generated before the blank
guide screen release have no `<Name>Entry` and no `FeatureEntry`.

- Packages follow the generated files: `<rootPackage>.feature.<name>.<layer>` (projects generated
  before the blank guide screen release: `<rootPackage>.<name>.<layer>`) plus the sub-package
  (`...feature.<name>.presentation.ui`), all lowercase. Copy the root from `Screens.kt`; do not
  invent one.
- A new module is added to `settings.gradle.kts` (`include(":feature:<name>:<layer>")`) and to the
  `commonMain` dependencies of `shared/build.gradle.kts` (`implementation(projects.feature.<name>.<layer>)`).
- Every module's `@Module @ComponentScan` classes are registered in `appModules()` in
  `initKoin.kt` (older projects: in the `buildList` inside `initKoin`). New projects already have
  presentation, data and domain registered; in older ones add the data and domain modules when
  those layers get classes.
- Dependencies point inward: `presentation → domain`, `presentation → contract`, `data → domain`.
  Another feature is reached only through its `contract`.
- Not every layer needs code. A screen with no data of its own leaves `domain` and `data` empty;
  leave a generated empty module as it is, and do not create one you do not need.

## 4. Navigation

This template navigates through Koin-registered graph providers and a `NavigationManager`, not
through callbacks or a passed-down `NavController`.

- Destinations live in `contract/Screens.kt`: `@Serializable data object XDestination` or
  `@Serializable data class XDestination(val id: String)`, both implementing
  `NavigationCommand.Destination`. Arguments are simple values such as ids, never whole objects.
- The feature's `presentation/navigation/<Name>Provider.kt` implements `NavGraphProvider` and
  registers `composable<XDestination> { XRoute() }` for each destination. `MainScreen` collects
  every provider from Koin, so a new destination needs no edit in `shared`. Only the start
  destination is set in `MainScreen.kt`.
- A blank app generated from the blank guide screen release on starts at `GuideDestination`, the
  developer placeholder. When you build the app, point `startDestination` in
  `shared/.../MainScreen.kt` at the app's first destination (`shared` already depends on every
  feature's `contract`), then delete `GuideScreen.kt` and, in `MainScreen.kt`, the
  `composable<GuideDestination> { ... }` block, the `entries` and `uriHandler` lines and the
  imports they leave unused. The `<Name>Entry` classes may stay or go.
- The ViewModel navigates with the injected `NavigationManager`:
  `NavigationCommand.NavigateTo(XDestination(id))`, `NavigateUp`, `PopBackStackTo(...)`.
- The ViewModel reads its arguments from `SavedStateHandle` by name:
  `private val id: String = checkNotNull(savedStateHandle[XDestination::id.name]) { "id missing" }`.
  `toRoute<XDestination>()` works in the app but fails the JVM host test (`Bundle` not mocked); it
  stays for custom `NavType` arguments. Details: `references/screen.md`.
- To open another feature's screen, the presentation module depends on that feature's contract
  (`implementation(projects.feature.<other>.contract)`).

## 5. Presentation

Code shapes, imports and test tags: `references/screen.md`.

- The generated `ui/<Name>Screen.kt` is a placeholder screen (a Route and a private `<Name>Screen`
  with a Back button). Replace its content with the real Route and Content, and make the provider
  call the Route.
- The Route (`internal`) takes the ViewModel from `koinViewModel()` and collects state. The Content
  (`private`) is stateless and draws loading, empty, error and content.
- The screen root and every interactive element get a `Modifier.testTag(...)` from constants in
  `<Name>TestTags`; `cmp-maestro` builds the walkthrough on these tags.
- A module that gets `src/commonMain/composeResources/` (strings, drawables, fonts) must also enable
  Android resources in its build file (`references/screen.md`, "Resources"). Without it both gates
  stay green, but the files are left out of the APK and the app fails on Android.
- Previews: none in `commonMain` (see `references/screen.md` for the Android-only option).

## 6. Data

Details: `references/data.md`. The repository interface lives in `domain`, the implementation in
`data`. Reads are `Flow<T>` or `suspend` functions; failures come back typed. Mappers are
extension functions (`fun XDto.toDomain(): X`) that do not change their input. No silent
fallbacks.

## 7. Network

Only when `core/network` exists. Details: `references/network.md`.

- Reuse the `HttpClient` from `core/network`'s `NetworkModule`; never build a second client. The
  platform engines stay as the template set them.
- DTOs are `@Serializable`; the client already ignores unknown keys.
- The base URL is set in `core/network`'s `ApiConfig.kt` (debug and release; older projects: `NetworkModule`).
- Network failures become typed errors in `data`.
- An API that needs a key is never written into source. If no key-free public API fits, use fake
  data and say so in your summary.

## 8. Persistence

Only when the app needs local storage. Details: `references/persistence.md`.

- DataStore already exists in `core/database` when the project was generated with it; reuse the
  single instance from Koin.
- Room is not in the template. Add it to `core/database` the way `references/persistence.md`
  describes; the Room compiler generates the database constructor's `actual`s.
- DAOs read with `Flow` and write with `suspend`. Entities do not leave `core/database` and `data`.
- Before the first release, schema version 1 may change freely. After a release every schema
  change needs a migration; no destructive fallback.

## 9. Koin

Details and runtime diagnosis: `references/koin.md`.

- Annotations and imports: `cmp-code-rules`, section 6.
- A class is only resolvable if its Gradle module is on `shared`'s dependency list and its
  `@Module` is registered in `initKoin.kt`.
- A dependency provided by another Gradle module is marked `@Provided` (or that module is
  included), or KSP stops with `Unreachable definition`.
- A dependency cycle (A needs B, B needs A) is reported, not hidden.
- The template turns on Koin's compile-time check in KSP. Keep it on.
- `NoDefinitionFoundException` at runtime: go through the order in `references/koin.md`.

## Done when

- New modules are in `settings.gradle.kts` and `shared/build.gradle.kts`, and every new `@Module`
  class is in `initKoin.kt`.
- Each new destination is registered by a provider and reachable: something navigates to it, or it
  is the start destination. A `GuideScreen` button does not count for an app you ship: that app
  starts at its own first destination, not at `GuideDestination` (section 4).
- No DTO or entity appears in `domain` or `presentation`.
- The screen's `<Name>TestTags` exist and are applied.
- The Android gate is green; the iOS gate runs on the schedule in `cmp-verify`, section 2.

## Headless runs

- Write the files with Write and Edit. Run the Android gate once the screen or module's files are in
  place, not after every file and not only at the end (`cmp-verify`, section 2).
- Do not ask which layers to create. Choose by need and list the choice under `Assumptions` in
  your final message.
