# Failure recipes

Symptom, cause, fix. Error texts marked *measured* were reproduced on an app generated from this
template; match on the quoted part.

## iOS red, Android green

The iOS gate compiles `commonMain` without the Android classpath. Anything Android or JVM only
compiles for Android and fails for iOS (and in `compileCommonMainKotlinMetadata`).

| Error (measured) | Cause | Fix |
|---|---|---|
| `Unresolved reference 'System'` | `System.currentTimeMillis()` or similar | `kotlin.time` or kotlinx-datetime |
| `Unresolved reference 'format'` | `String.format(...)` | string template or a small common formatter |
| `Cannot access 'val IO: CoroutineDispatcher': it is internal` (iOS), `Unresolved reference 'IO'` (common) | `Dispatchers.IO` without its import | add `import kotlinx.coroutines.IO` |
| `Unresolved reference 'tooling'`, `Unresolved reference 'Preview'` | `@Preview` in `commonMain` | remove it, or move the preview to `androidMain` |
| `Unresolved reference 'java'` / `'android'` | JVM or Android API in `commonMain` | common API, or `expect`/`actual` with the platform code in `androidMain`/`iosMain` |

Other JVM-only things with the same effect: `synchronized {}`, `Thread`, `java.util.*` collections,
`androidx.compose.ui.res.*`, Android-only libraries. After a fix, rerun the iOS gate, not only the
Android one.

## Fails on every target

| Error | Cause | Fix |
|---|---|---|
| `Unresolved reference 'icons'` / `'Icons'` (measured) | Material icons are not a dependency of this template | vector drawables in `composeResources/drawable` with `painterResource(Res.drawable.key)`; Compass's `design/icons/` has ready ones |
| `Unresolved reference 'KoinViewModel'` (measured) | imported from `org.koin.core.annotation` | `import org.koin.android.annotation.KoinViewModel` |
| `This declaration needs opt-in` in `iosMain` | Apple API taking pointers | `@OptIn(ExperimentalForeignApi::class)` on the function |

## KSP and Koin

| Error | Cause | Fix |
|---|---|---|
| `e: [ksp] --> Unreachable definition '<param>:<Type>' in '<Class>'. Fix your modules and configuration.` (measured, task `kspCommonMainKotlinMetadata`) | a constructor parameter provided by another Gradle module | `@Provided` on that parameter, or include the providing module in `@Module(includes = [...])` |
| `Unresolved reference 'module'` or a module class import that does not resolve in `initKoin.kt` | the class lacks `@Module`, or `shared` does not depend on its Gradle module | add `@Module @ComponentScan(...)`; add `implementation(projects.<path>)` to `shared/build.gradle.kts` |
| `KoinGraphTest` fails with `<Class> needs <Type>` (task `testAndroidHostTest`, new template) | no module in `appModules()` defines `<Type>` | add the module that defines it (usually the feature's domain or data module) to `appModules()` in `initKoin.kt`; use `extraTypes` only when the type reaches the graph another way |
| `NoDefinitionFoundException` at runtime | wiring missing although the build is green | the order in `cmp-feature`, `references/koin.md` |

## Room

| Error | Cause | Fix |
|---|---|---|
| `Task ':core:database:kspKotlinIosSimulatorArm64' uses this output of task ':core:database:kspCommonMainKotlinMetadata' without declaring an explicit or implicit dependency` (measured) | Room's per-target KSP reads the common Koin KSP output | the `tasks.matching { ... }.configureEach { dependsOn("kspCommonMainKotlinMetadata") }` block from `cmp-feature`, `references/persistence.md` |
| missing `actual` for the database constructor | Room compiler not added for every target | `add("kspAndroid", ...)`, `add("kspIosArm64", ...)`, `add("kspIosSimulatorArm64", ...)`; never write the `actual` yourself |
| crash on open after a schema change | schema changed without a version bump on an installed build | before release: uninstall or clear data; after release: bump `version` and add a migration |

## Compose resources

- `Unresolved reference 'Res'`: import the module's own `Res`. Its package is the module's
  `compose.resources { packageOfResClass = "..." }` if set, otherwise
  `<root project name, lowercase>.<module path with dots>.generated.resources` (for example
  `cookbook.feature.recipes.presentation.generated.resources`). The generated class sits under
  `<module>/build/generated/compose/resourceGenerator/kotlin/commonResClass/`; its folder path is
  the package.
- `Unresolved reference '<key>'` on `Res.string.key` or `Res.drawable.key`: each key needs its own
  import from the same package, and the file or entry must exist in that module's
  `src/commonMain/composeResources/`. Build once after adding files so the accessors regenerate.
- Resources work on iOS but are missing on Android, gates green: the module does not enable Android
  resources, so its files are not in the APK (measured). Add `androidResources.enable = true`
  (`cmp-feature`, `references/screen.md`, "Resources").

## Navigation

- `Serializer for class '...' is not found` when navigating: the destination is missing
  `@Serializable`.
- `Navigation destination ... cannot be found in the navigation graph`: no provider registers that
  destination, or the provider's presentation module is not in `initKoin.kt`.
- Arguments that are not simple values need custom navigation types; pass an id instead.

## Dependencies and Gradle

- Duplicate classes or version conflicts: align the versions in `gradle/libs.versions.toml` and use
  the `libs.*` alias everywhere. Never change the Gradle wrapper, the Kotlin or AGP versions, or the
  `build-logic` plugin wiring.
- A new library does not resolve: check the alias spelling (`libs.androidx.room.runtime` for the
  key `androidx-room-runtime`) and that it was added to the right module.
- The daemon dies, the JDK is not found, out of memory: environment, not code. `./gradlew --stop`
  once and retry. `./gradlew build` is never the fix; it needs even more memory.
- Android packaging fails on file paths after the project folder moved: `./gradlew clean` once.
- `Daemon JVM criteria`, `requires JVM 21`, or Gradle ending in `Unsupported class file major version`:
  `JAVA_HOME` is older than 21. Install JDK 21, or let Gradle download it
  (`gradle/gradle-daemon-jvm.properties`).
- Release build fails with R8 `Missing class ...`, or only the release build throws
  `ClassNotFoundException` / `SerializationException`: minify removed a class. Add the lines from
  `androidApp/build/outputs/mapping/release/missing_rules.txt`, or the narrowest `-keep` rule, to
  `androidApp/proguard-rules.pro`, with a comment saying why.

## Gates that are red for other reasons

- detekt findings: `cmp-detekt`.
- A failing test, or zero tests counted: `cmp-testing`.
