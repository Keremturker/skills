---
name: cmp-testing
description: Use when adding or fixing unit tests in this Compose Multiplatform project — tests for a ViewModel, use case, repository or mapper, locking down a bug, adding commonTest dependencies to a module that has none — or when the test gate is red, counts zero tests, or a test fails or hangs.
---

# Unit tests

## 1. Where tests run (measured on apps generated from this template)

- `./gradlew allTests` runs `iosSimulatorArm64Test` in every module. Android host tests are not
  enabled, so tests exist only in `src/commonTest/` and run as Kotlin/Native on the iOS simulator.
  The build log warns that "android host tests are not enabled"; that is expected. Do not enable
  them; the iOS run is what the gate counts.
- Test code therefore follows the `commonMain` rules: no `java.*`, no `Thread.sleep`, no JUnit,
  MockK or Mockito. Use `kotlin.test` (`@Test`, `@BeforeTest`, `@AfterTest`, `assertEquals`,
  `assertIs`, `assertTrue`, `assertFailsWith`).
- Results: `<module>/build/test-results/iosSimulatorArm64Test/TEST-*.xml`, with `tests="N"`,
  `failures` and `errors` on the `testsuite` element. The gate counts `tests="N"` across these files;
  **zero tests is a red gate**, even though `allTests` itself succeeds.

## 2. Setup, once per module that gets tests

Dependencies go into the build file of the module that has the tests, never into `build-logic`.

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
tests add `ktor-client-mock` with the catalog's existing Ktor version key.

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
        if (fail) RestResult.Error else RestResult.Success(recipes)

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
- Not tested: getters, branchless mappers, Koin wiring, composables.

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

    @BeforeTest
    fun setUp() = Dispatchers.setMain(StandardTestDispatcher())

    @AfterTest
    fun tearDown() = Dispatchers.resetMain()

    private fun viewModel(repository: FakeRecipesRepository) =
        RecipesViewModel(GetRecipesUseCase(repository), FakeNavigationManager())

    @Test
    fun `loaded recipes reach the screen state`() = runTest {
        val state = viewModel(FakeRecipesRepository(listOf(pasta))).uiState.first { it.recipes.isNotEmpty() }

        assertEquals(listOf(pasta), state.recipes)
    }

    @Test
    fun `a failed load shows the error state instead of an empty list`() = runTest {
        val state = viewModel(FakeRecipesRepository(fail = true)).uiState.first { it.hasError }

        assertTrue(state.recipes.isEmpty())
    }
}
```

- Imports: `kotlin.test.*` names, `kotlinx.coroutines.test.*` (`runTest`, `setMain`, ...),
  `kotlinx.coroutines.ExperimentalCoroutinesApi`, `kotlinx.coroutines.flow.first`,
  `app.cash.turbine.test`, each imported by name. The examples on this page ran green on the iOS
  simulator.
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

- An endless loop started in `init` (a ticker) never lets `runTest` finish. Bound it by a state, or
  start it from an action.

## 7. Layout and names

- Same package as the class under test, under `src/commonTest/kotlin/<package path>/`, file
  `<Class>Test.kt`. `internal` classes are visible to their own module's tests.
- Backticked names use letters, digits and spaces only. A `,` or `()` fails the iOS test compile
  (measured: `Name contains illegal characters: ","`).
- Body in three blocks separated by blank lines: given, when, then. No comments needed.

## 8. Run and read

- The gate: `./gradlew allTests`. One module while iterating: `./gradlew :feature:<name>:<layer>:allTests`.
- A failing test prints `<package>.<Class>.<test name>[iosSimulatorArm64] FAILED` and the file and
  line; the assertion message (`Expected <2>, actual <3>.`) is in the `<failure message=...>` of the
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

- Only `./gradlew` runs. Read the XML files with the Grep or Read tool.
- The first test run compiles and links a Kotlin/Native test binary per module; give the Bash call
  a long timeout (up to ten minutes).
- Do not ask which tests to write. Cover the minimum above, then the riskiest logic, and list what
  you left out under `Assumptions`.
