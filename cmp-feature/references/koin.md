# Koin wiring

The annotation table (which annotation for which class, and the `@KoinViewModel` import trap) is in
`cmp-code-rules`, section 6. This file covers how definitions become reachable and how to find
out why one is not.

## How a class becomes injectable

1. It carries an annotation (`@KoinViewModel`, `@Factory`, `@Single`) or is a top-level `@Single`
   function.
2. Its package is inside the `@ComponentScan("...")` package of its Gradle module's `@Module` class
   (the scan includes sub-packages).
3. That `@Module` class is added to `shared/.../di/initKoin.kt`:

```kotlin
import <pkg>.data.di.<Name>DataModule
import org.koin.ksp.generated.module

// inside initKoin's buildList { ... }
add(<Name>DataModule().module)
```

4. `shared` depends on the Gradle module (`shared/build.gradle.kts`), otherwise the import above
   does not resolve.

`internal` classes are fine: the generated module code lives in the same Gradle module.

## Dependencies across Gradle modules

The template turns on Koin's compile-time check (`KOIN_CONFIG_CHECK` in `build-logic`). Every
constructor parameter must be resolvable from the same `@Module`, from a module it includes, or be
marked `@Provided`:

```kotlin
@KoinViewModel
internal class RecipesViewModel(
    @Provided private val getRecipes: GetRecipesUseCase,
    @Provided private val navigationManager: NavigationManager,
    private val savedStateHandle: SavedStateHandle
) : CoreViewModel()
```

`GetRecipesUseCase` is defined in the domain module and `NavigationManager` in `core/navigation`,
so both are `@Provided`; Koin supplies `SavedStateHandle` itself.

Without `@Provided` the build stops in `kspCommonMainKotlinMetadata`:

```
e: [ksp] --> Unreachable definition 'navigationManager:<pkg>.core.navigation.NavigationManager' in '<pkg>.presentation.ui.RecipesViewModel'. Fix your modules and configuration.
```

The check trusts `@Provided`. If the module that really provides the type is missing from
`initKoin.kt`, the build is green and the app crashes when the screen opens.

## Navigation providers

Each feature's `<Name>Provider` is `@Single(binds = [NavGraphProvider::class])` with its own
`@Named("<Name>Provider")`. `MainScreen` asks Koin for all `NavGraphProvider`s, so a provider whose
presentation module is not registered in `initKoin.kt` silently contributes no destinations, and
navigating to them crashes.

## Rules

- Keep the compile-time check on; it finds missing wiring in seconds.
- A cycle (A needs B, B needs A) is a design problem. Report it and restructure (usually a use case
  that both depend on); do not hide it with lazy lookups.
- No `get()` or `inject()` calls inside classes to dodge the check; take dependencies through the
  constructor.

## `NoDefinitionFoundException` at runtime

Go through these in order:

1. The class has no Koin annotation.
2. The `@Module` of its Gradle module is not in `initKoin.kt`.
3. The class is outside the `@ComponentScan` package (a typo in the `package` line, or a file in
   another module's package).
4. A `@Provided` dependency whose providing module is not registered (see above).

The wrong `KoinViewModel` import is not on this list: `org.koin.core.annotation.KoinViewModel` does
not resolve here, so it fails the build (`Unresolved reference 'KoinViewModel'`) instead of the app.

To see what Koin picked up in a module, read the generated code under
`<module>/build/generated/ksp/metadata/commonMain/kotlin/org/koin/ksp/generated/` (one file per `@Module`).
