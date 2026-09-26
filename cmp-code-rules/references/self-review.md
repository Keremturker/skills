# Self-review before finishing

Run this pass over the files you created or changed, before the final gates. Use Grep on those
files; do not review the whole project.

## What to search for

| Search for | Why it is wrong | Fix |
|---|---|---|
| `collectAsState(` in code you wrote | not lifecycle-aware; keeps collecting in the background | `collectAsStateWithLifecycle()` |
| a `MutableStateFlow` that is not `private` | the UI can write state | private `_uiState`, public `asStateFlow()` |
| `items(` without `key =` | wrong item reused after changes, lost scroll position | `key = { it.id }` |
| `LaunchedEffect(true)` or `LaunchedEffect(Unit)` that loads data | reloads on every entry, races the ViewModel | start loading in the ViewModel |
| `import androidx.compose.material.` (not `material3`) | Material 2 is not a dependency; icons are not on the classpath | Material3 components, drawables from `composeResources` |
| `map {`, `filter {`, `sortedBy {` in a composable body without `remember` | recomputed on every recomposition | move to the ViewModel or `remember(input)` |
| `java.`, `android.`, `System.`, `String.format` under `src/commonMain` | breaks the iOS gate | common API or `expect`/`actual` |
| `@Preview` under `src/commonMain` | breaks the iOS gate | remove, or move to `androidMain` (see `cmp-feature`) |
| `println(` | debug output left behind; forbidden here, but detekt does not catch it (see `cmp-detekt`) | remove |
| `!!` | crash instead of a handled case | `?:`, `requireNotNull` with a message, typed error |
| a user-visible string literal in a composable | not translatable | a `StringResourcesUiModel` property (`core/multilang`), else `stringResource(Res.string.key)` |
| a language object with empty strings, or a `StringResourcesUiModel` default that is not the English text | blank UI in that language | fill it; default = English text |
| `catch (e: Exception)` or `runCatching` without rethrowing `CancellationException` | swallows cancellation; coroutines keep running | rethrow `CancellationException` first |
| `.catch { emit(emptyList()) }` or any `emit(empty...)` in a catch | the error becomes "no data" | emit or return an error; the UI shows the error state |
| `getOrNull()` or `?: emptyList()` on a result that can fail | the failure is silently dropped | handle the error branch |
| a `when` over a result that sends `Error` and `Success` to the same branch | the error is shown as success | separate branches |
| `org.koin.core.annotation.KoinViewModel` | does not resolve here | `org.koin.android.annotation.KoinViewModel` |
| a new `@Module` class that is not in `initKoin.kt` | runtime crash | add it to `initKoin.kt` |
| `@Suppress`, a baseline file, a disabled rule | hides a problem instead of fixing it | fix the cause |

## False-positive filter

Before you report or change something, drop it if:

- the line is not part of your change (template code such as `MainScreen.kt`'s `collectAsState`
  is out of scope);
- detekt or the compiler already reports it (the gates will catch it; fix it there). This never
  applies to `println(` or `!!`: detekt does not catch them in this project;
- it is a matter of taste where both versions are defensible.

What remains is fixed now, or, if fixing it is out of scope, listed in your final summary with
the reason.
