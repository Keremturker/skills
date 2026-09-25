# Network (`core/network`)

Only for projects that have `core/network`. Without it, do not add a network stack unless the app
cannot work without one.

## What the template provides

- `core/network/.../di/NetworkModule.kt` provides one `HttpClient` through Koin. It uses the
  platform engine from `getPlatformEngine()` (`expect`/`actual`: Android engine, Darwin on iOS),
  `expectSuccess = true` (a status outside 2xx throws), a request timeout, JSON with
  `ignoreUnknownKeys = true`, and `defaultRequest { url(...) }` for the base URL. Leave the client
  configuration as it is.
- `BaseRepository.request<T> { httpClient.get(...) }` returns `RestResult<T>`: `Success(body)`, or
  `Error` for any failure (status, connection, parsing). It already runs on `Dispatchers.IO`.
- `RestResult<T>.mapOnSuccess { value -> ... }` maps the success value (`value` is nullable).
- The feature `data` convention plugin already adds `:core:network` and the Ktor client.

## Base URL

- Set once, in `NetworkModule`: `defaultRequest { url("https://api.example.com/v1/") }`. A blank
  project may have it empty; fill it in.
- Keep the trailing `/` and write request paths without a leading one: `httpClient.get("recipes")`.
  A leading `/` replaces the base path (`/recipes` would drop `/v1`).
- A second host gets an absolute URL in that request, not a second client.

## Repository

```kotlin
private const val PAGE_SIZE = 50

@Single(binds = [RecipesRepository::class])
internal class RecipesRepositoryImpl(
    @Provided private val httpClient: HttpClient,          // provided by core/network
) : BaseRepository(), RecipesRepository {

    override suspend fun getRecipes(): RestResult<List<Recipe>> =
        request<List<RecipeResponse>> {
            httpClient.get("recipes") {
                parameter("limit", PAGE_SIZE)
            }
        }.mapOnSuccess { list -> list.orEmpty().mapNotNull { it.toDomain() } }
}
```

- `HttpClient` needs `@Provided`, or `@Module(includes = [NetworkModule::class])` on
  `<Name>DataModule`. Use one of the two, not both.
- Imports: `io.ktor.client.HttpClient`, `io.ktor.client.request.get`, `io.ktor.client.request.parameter`.

## DTOs

```kotlin
// data/model/RecipeResponse.kt
@Serializable
internal data class RecipeResponse(
    @SerialName("id") val id: String? = null,
    @SerialName("title") val title: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
)

// data/mapper/RecipeResponseMapper.kt
internal fun RecipeResponse.toDomain(): Recipe? {
    val id = id ?: return null
    return Recipe(id = id, title = title.orEmpty(), imageUrl = imageUrl)
}
```

- Every field the API may leave out is nullable with a default. `@SerialName` holds the wire
  name; Kotlin names stay camelCase.
- DTOs are `internal` to `data` and never appear in `domain` or `presentation`.

## Errors

- `request` already turns every failure into `RestResult.Error`; do not add try/catch around it.
- Only if the UI shows different messages for "offline" and "server error", add a sealed error in
  `domain` and map to it in `data`.

## Keys

- An API that needs a key is never written into source; the project's secrets hook blocks common
  key formats anyway. Prefer a key-free public API.
- If none fits, use a fake repository (`references/data.md`) and say so in your summary.
- Headless runs cannot reach the API from your tools; the code is checked by the gates, and the
  real response is seen when the app runs.
