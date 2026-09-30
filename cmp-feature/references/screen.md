# Presentation layer

The shapes below use a `recipes` feature in `com.example.cookbook`. Rename, keep the structure.
When the module already has its own style (for example the template's `XActions` interface
implemented by the ViewModel), follow that instead of mixing the two.

## Imports that break builds when guessed

| Symbol | Import |
|---|---|
| `@KoinViewModel` | `org.koin.android.annotation.KoinViewModel` |
| `@Provided` | `org.koin.core.annotation.Provided` |
| `koinViewModel()` | `org.koin.compose.viewmodel.koinViewModel` |
| `collectAsStateWithLifecycle()` | `androidx.lifecycle.compose.collectAsStateWithLifecycle` |
| `viewModelScope` | `androidx.lifecycle.viewModelScope` |
| `SavedStateHandle`, `toRoute()` | `androidx.lifecycle.SavedStateHandle`, `androidx.navigation.toRoute` |
| `LocalColorsPalette` (with Theming) | `<rootPackage>.core.designsystem.theme.LocalColorsPalette`; `shared/.../AppTheme.kt` exists: the project was generated from the release that added it or later (projects without it: `.core.designsystem.darkmode.`) |
| `LocalStringResources` (with `core/multilang`) | `<rootPackage>.core.designsystem.language.LocalStringResources` |
| `LanguageManager`, `AppLanguage` | `<rootPackage>.core.multilang.language.*` |
| `stringResource`, `painterResource` | `org.jetbrains.compose.resources.stringResource`, `...painterResource` |
| `Res` and each key (`Res.string.title` needs `...generated.resources.title` too) | the module's `Res` package; see `cmp-verify`, `references/failures.md` |
| `Dispatchers.IO` | `kotlinx.coroutines.Dispatchers` and `kotlinx.coroutines.IO` |
| `Modifier.testTag` | `androidx.compose.ui.platform.testTag` |
| `@Immutable` | `androidx.compose.runtime.Immutable` |
| `items(list, key = ...)` in a `LazyColumn` | `androidx.compose.foundation.lazy.items` |
| `onLoading`, `onSuccess`, `onError`, `buildDefaultFlow` | `<rootPackage>.core.domain.*` |
| `DataError` | `<rootPackage>.core.domain.DataError` |

The code on this page was compiled for Android and iOS in an app generated from this template,
with these imports and the small `ErrorState`, `EmptyState` and `RecipeRow` composables filled in.

## UiState and actions

```kotlin
// ui/RecipesUiState.kt
@Immutable
internal data class RecipesUiState(
    val isLoading: Boolean = false,
    val error: DataError? = null,
    val recipes: List<Recipe> = emptyList()
)

// ui/RecipesAction.kt
internal sealed interface RecipesAction {
    data object Retry : RecipesAction
    data class OpenRecipe(val id: String) : RecipesAction
}
```

Generated modules use the other shape: `ui/<Name>Actions.kt` is an `internal interface` with one
function per action (`fun onNavigateUp()`), implemented by the ViewModel and passed to the screen.

Use a sealed interface for the state instead when the states cannot overlap (a form that is
editing, saving or saved).

## ViewModel

`getRecipes` comes from the domain module and `navigationManager` from `core/navigation`, hence
`@Provided`. Extend `ViewModel()` instead when the project has no `CoreViewModel`.

```kotlin
@KoinViewModel
internal class RecipesViewModel(
    @Provided private val getRecipes: GetRecipesUseCase,
    @Provided private val navigationManager: NavigationManager
) : CoreViewModel() {

    private val _uiState = MutableStateFlow(RecipesUiState())
    val uiState: StateFlow<RecipesUiState> = _uiState.asStateFlow()

    private var loadJob: Job? = null

    init {
        load()
    }

    fun onAction(action: RecipesAction) {
        when (action) {
            RecipesAction.Retry -> load()

            is RecipesAction.OpenRecipe ->
                navigationManager.navigate(NavigationCommand.NavigateTo(RecipeDetailDestination(action.id)))
        }
    }

    private fun load() {
        loadJob?.cancel()
        _uiState.update { it.copy(error = null) }
        loadJob = getRecipes()
            .onLoading { loading -> _uiState.update { it.copy(isLoading = loading) } }
            .onSuccess { recipes -> _uiState.update { it.copy(recipes = recipes) } }
            .onError { error -> _uiState.update { it.copy(error = error) } }
            .launchIn(viewModelScope)
    }
}
```

`onLoading`, `onSuccess` and `onError` are the template's `Flow<RestResult<T>>` helpers in
`core/domain`. For a use case that returns a plain `Flow<List<Recipe>>` (local database), collect
it in `viewModelScope` and use `.catch { }` to set the error state.

A screen with arguments takes `private val savedStateHandle: SavedStateHandle` (Koin supplies it,
no `@Provided`) and reads the argument by its name,
`checkNotNull(savedStateHandle[RecipeDetailDestination::id.name])` (`toRoute()` works in the app too,
but fails the JVM test run; `cmp-testing`).

## Route and Content

```kotlin
// ui/RecipesScreen.kt
@Composable
internal fun RecipesRoute(viewModel: RecipesViewModel = koinViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    RecipesContent(uiState = uiState, onAction = viewModel::onAction)
}

@Composable
private fun RecipesContent(
    uiState: RecipesUiState,
    onAction: (RecipesAction) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxSize().testTag(RecipesTestTags.ROOT)) {
        when {
            uiState.isLoading && uiState.recipes.isEmpty() -> CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center).testTag(RecipesTestTags.LOADING)
            )

            uiState.error != null -> ErrorState(
                error = uiState.error,
                onRetry = { onAction(RecipesAction.Retry) },
                modifier = Modifier.align(Alignment.Center)
            )

            uiState.recipes.isEmpty() -> EmptyState(modifier = Modifier.align(Alignment.Center))

            else -> LazyColumn(modifier = Modifier.fillMaxSize().testTag(RecipesTestTags.LIST)) {
                items(items = uiState.recipes, key = { it.id }) { recipe ->
                    RecipeRow(
                        recipe = recipe,
                        onClick = { onAction(RecipesAction.OpenRecipe(recipe.id)) },
                        modifier = Modifier.testTag(RecipesTestTags.ITEM)
                    )
                }
            }
        }
    }
}
```

`ErrorState` shows the message for its `DataError` (with `core/multilang`, a `StringResourcesUiModel`
function like the showcase's `errorMessage(error)`) and a retry button tagged
`RecipesTestTags.RETRY`; `EmptyState`
shows a message and, if the screen can create items, the action that does. Texts come from
`LocalStringResources.current` when the project has `core/multilang`, otherwise from
`stringResource` (`cmp-code-rules`, section 11).

The provider (generated under `navigation/`) calls the Route:

```kotlin
composable<RecipesDestination> { RecipesRoute() }
```

Use the destination declared in the module's `contract/Screens.kt`: `<Name>Destination` in new
projects, `<Name>ScreenDestination` in projects generated before the blank guide screen release.

## Test tags

```kotlin
// ui/RecipesTestTags.kt
internal object RecipesTestTags {
    const val ROOT = "recipes_root"
    const val LOADING = "recipes_loading"
    const val LIST = "recipes_list"
    const val ITEM = "recipes_item"
    const val RETRY = "recipes_retry"
}
```

- Every screen root has a `ROOT` tag; every button, field and list item the walkthrough touches
  has one.
- Tags go on the node that is clicked, not on a wrapper around it.
- `cmp-maestro` explains how the flow uses these ids and where `testTagsAsResourceId` is turned on.

## Resources

- Drawables and fonts go under `src/commonMain/composeResources/` of the module that uses them:
  `drawable/`, `font/`. Strings go there too (`values/strings.xml`) only when the project has no
  `core/multilang`; with it they are `StringResourcesUiModel` properties (`cmp-code-rules`,
  section 11). Icons Compass prepared are in `design/icons/` as vector drawables; copy the ones
  the screen needs into `drawable/`.
- The module's build file must enable Android resources, or the files never reach the APK. Both
  gates stay green without it; the app then fails on Android when it loads the resource (measured
  on an app generated from this template: 30 resource files in the APK with the setting, 0
  without):

```kotlin
import com.android.build.api.dsl.KotlinMultiplatformAndroidLibraryExtension

plugins {
    alias(libs.plugins.feature.presentation.plugin)
}

kotlin {
    extensions.configure<KotlinMultiplatformAndroidLibraryExtension> {
        androidResources.enable = true
    }
    // sourceSets { ... } as before
}

// Optional: a readable package for the generated Res class.
compose.resources {
    packageOfResClass = "com.example.cookbook.recipes.presentation.resources"
}
```

- Use them with `painterResource(Res.drawable.key)`, and `stringResource(Res.string.key)` in a
  project without `core/multilang` (with it, `LocalStringResources.current.<property>`). Each key
  is its own import from the `Res` package (`...resources.Res` and `...resources.key`).

## Previews

- Headless runs write no previews: nobody opens them, and `@Preview` in `commonMain` breaks the
  iOS gate (the preview tooling is only on the Android classpath in this template).
- In an interactive session, if the owner wants previews, put them in
  `src/androidMain/kotlin/<same package>/` of the presentation module, one per reachable state
  (loading, empty, error, content). The previewed Content must then be `internal` instead of
  `private`, because `androidMain` is a different source set.
