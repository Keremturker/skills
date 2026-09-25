# Domain and data layers

Examples use a `recipes` feature. `RestResult` (`Success`, `Error`, `Loading`) and the flow helpers
come from the template's `core/domain`.

## Model (domain)

```kotlin
// domain/model/Recipe.kt
data class Recipe(
    val id: String,
    val title: String,
    val imageUrl: String?,
    val isFavorite: Boolean = false,
)
```

## Repository interface (domain)

```kotlin
// domain/repository/RecipesRepository.kt
interface RecipesRepository {
    suspend fun getRecipes(): RestResult<List<Recipe>>    // one-shot read, for example from the network
    fun observeFavorites(): Flow<List<Recipe>>            // observed read, for example from Room
    suspend fun setFavorite(id: String, favorite: Boolean)
}
```

- Only domain models cross this interface; never a DTO or an entity.
- One-shot reads are `suspend`, observed data is `Flow<T>`.
- Failures are typed: `RestResult` for network reads. `RestResult.Error` carries no detail; if the
  UI must show different messages for different failures (and only then), add a sealed error type
  in `domain` and map to it in `data`.

## Use cases (domain)

```kotlin
// domain/usecase/GetRecipesUseCase.kt
@Factory
class GetRecipesUseCase(@Provided private val repository: RecipesRepository) {
    operator fun invoke(): Flow<RestResult<List<Recipe>>> = flow {
        emit(repository.getRecipes())
    }.buildDefaultFlow(Dispatchers.IO)
}

// domain/usecase/ObserveFavoritesUseCase.kt
@Factory
class ObserveFavoritesUseCase(@Provided private val repository: RecipesRepository) {
    operator fun invoke(): Flow<List<Recipe>> = repository.observeFavorites()
}
```

- One operation per class, exposed as `operator fun invoke`. Business rules (sorting, validation,
  combining sources) live here, not in the ViewModel.
- `buildDefaultFlow` (from `core/domain`) emits `Loading(true)` first and `Loading(false)` last, and
  turns an exception into `Error`. `Dispatchers.IO` needs `import kotlinx.coroutines.IO`.
- `@Provided` because the implementation is bound in the `data` module, not in `domain`.
- Use cases are `public`: the presentation module uses them.

## Repository implementation (data)

```kotlin
// data/repository/RecipesRepositoryImpl.kt
@Single(binds = [RecipesRepository::class])
internal class RecipesRepositoryImpl(
    @Provided private val dao: RecipeDao,          // from core/database
) : RecipesRepository {

    override fun observeFavorites(): Flow<List<Recipe>> =
        dao.observeFavorites().map { entities -> entities.map { it.toDomain() } }

    override suspend fun setFavorite(id: String, favorite: Boolean) {
        dao.setFavorite(id = id, favorite = favorite)
    }

    // getRecipes(): see references/network.md
}
```

- The `data` module declares what it uses: `implementation(dependencyNotation = projects.core.database)`
  for local storage. The network module comes with the `data` convention plugin.
- Room and Ktor are main-safe. Use `withContext(Dispatchers.IO)` only around blocking work you
  write yourself.

## Mappers

```kotlin
// data/mapper/RecipeMapper.kt
internal fun RecipeEntity.toDomain(): Recipe =
    Recipe(id = id, title = title, imageUrl = imageUrl, isFavorite = isFavorite)
```

- Extension functions, no Koin annotation, no changes to the input.
- Decide missing values on purpose. An optional text may become empty; a missing id or price makes
  the item invalid, so drop it deliberately (`mapNotNull`) instead of inventing `0` or `""`.

## No silent fallbacks

- A failure reaches the ViewModel as an error: no `catch { emit(emptyList()) }`, no
  `getOrNull() ?: emptyList()`, no stale cache presented as fresh data.
- Do not wrap the template's `BaseRepository.request` in try/catch; its result is already typed.
- Errors from a Room `Flow` travel to the ViewModel, whose `.catch { }` sets the error state.

## Fake data

When no key-free public API fits the app, write `Fake<Name>Repository` in `data`, bound with the
same `@Single(binds = [...])`, returning realistic sample data. Keep the interface unchanged so a
real implementation can replace it later, and say in your summary that the data is fake.

## Where stored data lives

The app has one Room database and one DataStore, both in `core/database`. Entities and DAOs are
defined there; each feature's `data` module maps them to its own domain models.
