---
name: cmp-testing
description: Use when adding or fixing unit tests in this Compose Multiplatform project — tests for a ViewModel, use case, repository or mapper, locking down a bug, adding commonTest dependencies to a module of an older project that has none — or when the test gate is red, counts zero tests, or a test fails or hangs.
---

# Unit tests

## 1. Where tests run (measured on apps generated from this template)

First tell which generation the project is: the new template has `shared/src/androidHostTest` and
its `build-logic/.../convention/configureKotlinMultiplatform.kt` mentions `commonTest`. A project
generated before the template had tests has neither.

- New template: every KMP module has Android host tests (source set `androidHostTest`, task
  `testAndroidHostTest`) and `commonTest` dependencies `kotlin-test`, `kotlinx-coroutines-test` and
  Turbine, all from the convention. `./gradlew allTests` runs the `commonTest` code on the JVM
  (`testAndroidHostTest`) and on the iOS simulator (`iosSimulatorArm64Test`).
- Older project: `allTests` runs `iosSimulatorArm64Test` only. Android host tests are not enabled,
  so tests exist only in `src/commonTest/` and run as Kotlin/Native on the iOS simulator. The build
  log warns that "android host tests are not enabled"; that is expected there. Do not enable them.
- Test code follows the `commonMain` rules in both, because it runs on iOS: no `java.*`, no
  `Thread.sleep`, no JUnit, MockK or Mockito. Use `kotlin.test` (`@Test`, `@BeforeTest`,
  `@AfterTest`, `assertEquals`, `assertIs`, `assertTrue`, `assertFailsWith`).
- Results: `<module>/build/test-results/testAndroidHostTest/` (new template only) and
  `<module>/build/test-results/iosSimulatorArm64Test/`, `TEST-*.xml`, with `tests="N"`, `failures`
  and `errors` on the `testsuite` element. The gate counts `tests="N"` across the
  `iosSimulatorArm64Test` files; **zero tests is a red gate**, even though `allTests` itself
  succeeds. Host-only tests such as `KoinGraphTest` (`shared/src/androidHostTest`) do not count
  toward it.
- `KoinGraphTest` fails when a class in the Koin graph needs a type no module in `appModules()`
  defines, printing `<Class> needs <Type>`. Fix: add the module that defines the type to
  `appModules()` in `initKoin.kt`. Do not add the type to its `extraTypes` unless it reaches the
  graph another way.

## 2. Setup

New template: nothing to set up. Write tests in `src/commonTest/`; the dependencies come from the
convention. Never add `turbine`, `kotlinx-coroutines-test` or `kotlin-test` to
`gradle/libs.versions.toml` again (a duplicate key makes Gradle reject the catalog) and no per-module
`commonTest.dependencies` is needed.

### Projects generated before the template had tests

Once per module that gets tests. Dependencies go into the build file of the module that has the
tests, never into `build-logic`.

`gradle/libs.versions.toml` (reuse the coroutines version key the catalog already has; in this
template it is `kotlinxCoroutinesCore`):

```toml
[versions]
turbine = "1.2.1"

[libraries]
kotlinx-coroutines-test = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-test", version.ref = "kotlinxCoroutinesCore" }
turbine = { module = "app.cash.turbine:turbine", version.ref = "turbine" }
```

The module's `build.gradle.kts`, merged into its existing `kotlin { sourceSets { } }` block:

```kotlin
kotlin {
    sourceSets {
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.turbine)      // only where flows are tested
        }
    }
}
```

This exact setup compiled and ran on the iOS simulator in a generated app. For Ktor repository
tests add `ktor-client-mock` with the catalog's existing Ktor version key (both generations).

## 3. Fakes, not mocks

- Write fakes of the domain interfaces in the module's `commonTest`: a repository backed by a
  `MutableStateFlow`, with a constructor switch that makes it fail.
- Use cases are concrete classes. A ViewModel test builds the real use case around a fake
  repository.
- `NavigationManager` is an interface; its fake records the commands it receives.
- One module's `commonTest` is invisible to another module. A small fake copied into both is fine.
- A fake behaves like the real thing: a fake that returns data for any id hides the bug a real
  lookup would show.

For the `RecipesRepository` of `cmp-feature`, `references/data.md`:

```kotlin
internal class FakeRecipesRepository(
    private val recipes: List<Recipe> = emptyList(),
    private val fail: Boolean = false
) : RecipesRepository {
    private val favorites = MutableStateFlow(recipes.filter { it.isFavorite })

    override suspend fun getRecipes(): RestResult<List<Recipe>> =
        if (fail) RestResult.Error(DataError.Network) else RestResult.Success(recipes)

    override fun observeFavorites(): Flow<List<Recipe>> = favorites

    override suspend fun setFavorite(
        id: String,
        favorite: Boolean
    ) {
        val recipe = recipes.first { it.id == id }.copy(isFavorite = favorite)
        favorites.update { list -> list.filterNot { it.id == id } + listOfNotNull(recipe.takeIf { favorite }) }
    }
}
```

## 4. What to test

- The minimum the gate expects: for every ViewModel and every use case you write, one test of the
  success path and one of the failure path.
- ViewModel: the state after each action, and the navigation command it sends.
- Use case: the business rule and its failure path.
- Mapper: only when it has branches (a missing id dropped, a default chosen).
- Repository: error mapping, with Ktor's `MockEngine`, only when it adds logic beyond the
  template's `BaseRepository`.
- Not tested: getters, branchless mappers, Koin wiring (the new template's `KoinGraphTest` covers it), composables.

## 5. Behaviour, not implementation

- Assert what can be observed: the state, the return value, the stored data. Never "X was called
  twice".
- The test name says which regression it prevents: `a failing repository shows the error state`.
- Edge cases first: empty list, one item, duplicate id, failure, cancellation.
- A fixture describes a state the app can really reach. Check: break the behaviour the test is
  named after; the test must turn red. If it stays green, suspect the fixture.

## 6. Coroutines and ViewModels

- `runTest` for every suspending test; it uses virtual time, so `delay` costs nothing.
- ViewModel tests set the main dispatcher, because `viewModelScope` runs on it:

```kotlin
private val pasta = Recipe(id = "1", title = "Pasta", imageUrl = null)

@OptIn(ExperimentalCoroutinesApi::class)
class RecipesViewModelTest {

    private val createdViewModels = mutableListOf<RecipesViewModel>()

    @BeforeTest
    fun setUp() = Dispatchers.setMain(StandardTestDispatcher())

    @AfterTest
    fun tearDown() = runTest {
        createdViewModels.forEach { it.viewModelScope.coroutineContext.job.cancelAndJoin() }
        createdViewModels.clear()
        Dispatchers.resetMain()
    }

    private fun viewModel(repository: FakeRecipesRepository) =
        RecipesViewModel(GetRecipesUseCase(repository), FakeNavigationManager()).also { createdViewModels += it }

    @Test
    fun `loaded recipes reach the screen state`() = runTest {
        val state = viewModel(FakeRecipesRepository(listOf(pasta))).uiState.first { it.recipes.isNotEmpty() }

        assertEquals(listOf(pasta), state.recipes)
    }

    @Test
    fun `a failed load shows the error state instead of an empty list`() = runTest {
        val state = viewModel(FakeRecipesRepository(fail = true)).uiState.first { it.error != null }

        assertEquals(DataError.Network, state.error)
        assertTrue(state.recipes.isEmpty())
    }
}
```

- Teardown: cancel and join every view model's `viewModelScope` job inside `runTest`, before
  `Dispatchers.resetMain()`. A load that finishes on IO resumes its parent on `Dispatchers.Main`; after
  `resetMain` that hits the real Main, and the Android host run fails at random with "Dispatchers.Main
  was accessed". Keep the view models a test creates in a list (`createdViewModels += it`) and cancel them
  in `@AfterTest`, as above.
- Imports, each by name (the generator re-sorts them in ktlint order, lexicographic with `kotlin.*`
  last, so an unsorted file shows as a diff): `androidx.lifecycle.viewModelScope`,
  `app.cash.turbine.test`, `<rootPackage>.core.domain.DataError`, `kotlinx.coroutines.*`
  (`ExperimentalCoroutinesApi`, `Dispatchers`, `cancelAndJoin`, `job`), `kotlinx.coroutines.flow.first`,
  `kotlinx.coroutines.test.*` (`runTest`, `setMain`, `resetMain`, ...), `kotlin.test.*` names. The
  examples on this page ran green on the iOS simulator.
- Measured without `setMain`: a flow that emits at once still loads, but one that suspends never
  reaches the test and it fails with `UncompletedCoroutinesError` ("the test body did not run to
  completion").
- `GetRecipesUseCase` runs its flow on `Dispatchers.IO` (`buildDefaultFlow`), on real threads that
  virtual time does not control, and the `StateFlow` may skip intermediate states. So wait for the
  property you assert with `first { }`; never `advanceUntilIdle()` followed by reading `.value`.
- Turbine checks a sequence where every step matters, typically a flow a use case returns:

```kotlin
@Test
fun `a recipe marked as favourite appears in the favourites`() = runTest {
    val repository = FakeRecipesRepository(listOf(pasta))

    ObserveFavoritesUseCase(repository)().test {
        assertEquals(emptyList(), awaitItem())
        repository.setFavorite(pasta.id, favorite = true)
        assertEquals(listOf(pasta.copy(isFavorite = true)), awaitItem())
    }
}
```

- A ViewModel that reads its route with `savedStateHandle.toRoute<...>()` cannot be built in the
  JVM run: `toRoute` decodes through an Android `Bundle`, which host tests stub
  (`Method ... not mocked`). Read the argument by its name instead, with a declared type:
  `private val id: String = checkNotNull(savedStateHandle[RecipeDetailDestination::id.name]) { "id missing" }`
  (primitive and `String` arguments; a custom `NavType` keeps `toRoute`), and build the test's
  handle with `SavedStateHandle(mapOf("id" to "1"))`.
- Projects generated before `template-2026.09.30.1` (projects without `core/domain/.../DataError.kt`): `RestResult.Error` is an
  object without a reason (`RestResult.Error`, `onError { }`).
- An endless loop started in `init` (a ticker) never lets `runTest` finish. Bound it by a state, or
  start it from an action.

## 7. Layout and names

- Same package as the class under test, under `src/commonTest/kotlin/<package path>/`, file
  `<Class>Test.kt`. `internal` classes are visible to their own module's tests.
- Backticked names use letters, digits and spaces only. A `,` or `()` fails the iOS test compile
  (measured: `Name contains illegal characters: ","`).
- Body in three blocks separated by blank lines: given, when, then. No comments needed.

## 8. Run and read

- The gate: `./gradlew allTests` (new template: JVM and iOS run; older: iOS only). One module while iterating: `./gradlew :feature:<name>:<layer>:allTests`.
- A failing test prints `<package>.<Class>.<test name>[iosSimulatorArm64] FAILED` (the JVM run
  prints its own line) and the file and line; the assertion message (`Expected <2>, actual <3>.`) is in the `<failure message=...>` of the
  XML.
- Report the count from the XML files, not from "BUILD SUCCESSFUL".
- A red test means the implementation is wrong, or the test misreads the requirement. Fix the one
  that is wrong. Never loosen an assertion, add `@Ignore` or delete a test to get green.

## Done when

- Every ViewModel and use case you wrote has at least one success and one failure test.
- `./gradlew allTests` ran green in this session after the last change.
- The summary names the command and the test count read from the XML files, above zero.
- A bug the tests found is fixed, or reported if fixing it is out of scope.

## Headless runs

- There is no Grep tool: read the XML files with Read or `grep`.
- The first test run compiles and links a Kotlin/Native test binary per module; give the Bash call
  a long timeout (up to ten minutes).
- Do not ask which tests to write. Cover the minimum above, then the riskiest logic, and list what
  you left out under `Assumptions`.
