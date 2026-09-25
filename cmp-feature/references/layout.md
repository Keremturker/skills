# Feature module layout

## Full tree

Sources live under `src/commonMain/kotlin/<package path>/`. `<pkg>` below is
`<rootPackage>.<name>`, for example `com.example.cookbook.recipes` for a `recipes` feature in an
app whose root package is `com.example.cookbook`. Copy the real root from the generated
`contract/Screens.kt`.

```
feature/<name>/
├── contract/
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/<pkg>/contract/
│       └── Screens.kt                    all destinations of this feature
├── domain/
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/<pkg>/domain/
│       ├── model/<Thing>.kt              plain data classes
│       ├── repository/<Name>Repository.kt
│       ├── usecase/Get<Thing>UseCase.kt  one class per operation, @Factory
│       └── di/<Name>DomainModule.kt
├── data/
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/<pkg>/data/
│       ├── model/<Thing>Response.kt      DTOs (@Serializable), network only
│       ├── mapper/<Thing>Mapper.kt       fun <Thing>Response.toDomain()
│       ├── repository/<Name>RepositoryImpl.kt
│       └── di/<Name>DataModule.kt
└── presentation/
    ├── build.gradle.kts
    └── src/commonMain/kotlin/<pkg>/presentation/
        ├── ui/<Name>Screen.kt            Route + Content (generated as a placeholder)
        ├── ui/<Name>ViewModel.kt
        ├── ui/<Name>UiState.kt
        ├── ui/<Name>Action.kt
        ├── ui/<Name>TestTags.kt
        ├── ui/<sub>/...                  further screens of the feature, same file set
        ├── di/<Name>PresentationModule.kt   (generated)
        └── navigation/<Name>Provider.kt     (generated)
```

Platform-specific code goes into `src/androidMain/kotlin/...` and `src/iosMain/kotlin/...` of the
same module, with the same package.

## Build files

These are the files the generator writes. The convention plugins already bring Koin (with
annotations and KSP), kotlinx-serialization and the `core/*` modules listed below; do not add them
again.

```kotlin
// contract/build.gradle.kts          (plugin brings :core:navigation)
plugins {
    alias(libs.plugins.feature.contract.plugin)
}

// domain/build.gradle.kts            (plugin brings :core:domain, kotlinx-coroutines)
plugins {
    alias(libs.plugins.feature.domain.plugin)
}

// data/build.gradle.kts              (plugin brings :core:domain, and :core:network with Ktor when present)
plugins {
    alias(libs.plugins.feature.data.plugin)
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            implementation(dependencyNotation = projects.feature.<name>.domain)
        }
    }
}

// presentation/build.gradle.kts      (plugin brings Compose with Material3 and resources,
//                                     lifecycle and navigation for Compose, Koin for Compose,
//                                     :core:navigation, :core:presentation, :core:domain, and
//                                     :core:designsystem / :core:multilang when present)
plugins {
    alias(libs.plugins.feature.presentation.plugin)
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            implementation(dependencyNotation = projects.feature.<name>.contract)
            implementation(dependencyNotation = projects.feature.<name>.domain)
        }
    }
}
```

Extra dependencies of one module (for example `projects.core.database` in `data`, or
`libs.kotlinx.datetime`) are added to that module's `commonMain.dependencies`, with the version in
`gradle/libs.versions.toml`.

## Names

| Thing | Name |
|---|---|
| Koin module classes | `<Name>DomainModule`, `<Name>DataModule`, `<Name>PresentationModule` |
| Destination of the first screen | `<Name>ScreenDestination` (generated); others `<Thing>Destination` |
| Navigation provider | `<Name>Provider`, with `@Named("<Name>Provider")` |
| Route and Content | `<Screen>Route` (`internal`), `<Screen>Content` (`private`) |
| Test tag constants | `<Screen>TestTags`, values `snake_case` with a screen prefix |

## Checklist for a brand-new feature module

Only when `settings.gradle.kts` does not list the feature yet.

1. Create the four module folders with the build files above.
2. `settings.gradle.kts`: `include(":feature:<name>")` and one `include(":feature:<name>:<layer>")`
   per layer, next to the existing includes.
3. `shared/build.gradle.kts`, `commonMain.dependencies`: `implementation(projects.feature.<name>.<layer>)`
   for each layer.
4. `contract/Screens.kt` with the first destination; start the file like the generated one.
5. A `@Module @ComponentScan("<pkg>.<layer>")` class in each layer's `di/` package that has
   injectable classes, each added to `initKoin.kt`:

```kotlin
import <pkg>.presentation.di.<Name>PresentationModule
// ...
add(<Name>PresentationModule().module)
```

6. `presentation/navigation/<Name>Provider.kt`, copied from an existing provider.
7. Run the Android gate; then the iOS gate once the module compiles.
