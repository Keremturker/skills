# Persistence (`core/database`)

## Choose

- DataStore (Preferences) for settings, flags and a few small values.
- Room for records the user creates, lists, queries or sorts.
- When `core/database` exists it already has DataStore and a `DatabaseModule`
  (`@Module @ComponentScan`) registered in `initKoin.kt`. Room is not in the template.

## DataStore

The template provides one `DataStore<Preferences>` through Koin (`provideDataStore()` in
`core/database`, file path from the platform `actual`). Wrap it in a repository in the feature's
`data` module:

```kotlin
@Single(binds = [SettingsRepository::class])
internal class SettingsRepositoryImpl(@Provided private val dataStore: DataStore<Preferences>) : SettingsRepository {

    override fun observeSoundOn(): Flow<Boolean> = dataStore.data.map { it[SOUND_ON] ?: true }

    override suspend fun setSoundOn(on: Boolean) {
        dataStore.edit { it[SOUND_ON] = on }
    }

    private companion object {
        val SOUND_ON = booleanPreferencesKey("sound_on")
    }
}
```

- Reuse that single instance. A second DataStore on the same file crashes at runtime.
- The feature's `data` module adds `implementation(dependencyNotation = projects.core.database)`;
  `core/database` exposes the DataStore types with `api`.

## Room (Kotlin Multiplatform)

This setup was measured in an app generated from this template: both gates green, the app ran on
Android. Versions used there: Room `2.8.4`, `androidx.sqlite` `2.6.2`.

1. `gradle/libs.versions.toml`:

```toml
[versions]
room = "2.8.4"
sqlite = "2.6.2"

[libraries]
androidx-room-runtime = { module = "androidx.room:room-runtime", version.ref = "room" }
androidx-room-compiler = { module = "androidx.room:room-compiler", version.ref = "room" }
androidx-sqlite-bundled = { module = "androidx.sqlite:sqlite-bundled", version.ref = "sqlite" }

[plugins]
room = { id = "androidx.room", version.ref = "room" }
```

2. `core/database/build.gradle.kts`, added to what is there:

```kotlin
plugins {
    alias(libs.plugins.kmp.library.plugin)
    alias(libs.plugins.room)
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(dependencyNotation = libs.androidx.room.runtime)
            implementation(dependencyNotation = libs.androidx.sqlite.bundled)
        }
    }
}

room {
    schemaDirectory("$projectDir/schemas")
}

dependencies {
    add("kspAndroid", libs.androidx.room.compiler)
    add("kspIosArm64", libs.androidx.room.compiler)
    add("kspIosSimulatorArm64", libs.androidx.room.compiler)
}

// Room runs KSP per target, and those tasks read the common KSP output (Koin), so they must run
// after it. Without this Gradle rejects the build for an undeclared task dependency.
tasks.matching { it.name.startsWith("ksp") && it.name != "kspCommonMainKotlinMetadata" }
    .configureEach { dependsOn("kspCommonMainKotlinMetadata") }
```

3. Database, in `core/database/src/commonMain/.../room/`:

```kotlin
@Database(entities = [RecipeEntity::class], version = 1)
@ConstructedBy(AppDatabaseConstructor::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun recipeDao(): RecipeDao
}

// The Room compiler generates the `actual` objects. Do not write them.
expect object AppDatabaseConstructor : RoomDatabaseConstructor<AppDatabase> {
    override fun initialize(): AppDatabase
}

internal const val APP_DATABASE_FILE = "app.db"

expect fun getAppDatabaseBuilder(): RoomDatabase.Builder<AppDatabase>

fun buildAppDatabase(builder: RoomDatabase.Builder<AppDatabase>): AppDatabase = builder
    .setDriver(BundledSQLiteDriver())
    .setQueryCoroutineContext(Dispatchers.IO)
    .build()
```

No `@Suppress` is needed on the `expect object`; it compiles on both targets with only a warning
that expect/actual classes are in Beta.

4. Builders per platform:

```kotlin
// androidMain
actual fun getAppDatabaseBuilder(): RoomDatabase.Builder<AppDatabase> {
    val context: Context = getKoin().get<Context>().applicationContext
    return Room.databaseBuilder<AppDatabase>(
        context = context,
        name = context.getDatabasePath(APP_DATABASE_FILE).absolutePath
    )
}

// iosMain
@OptIn(ExperimentalForeignApi::class)
actual fun getAppDatabaseBuilder(): RoomDatabase.Builder<AppDatabase> {
    val documents: NSURL? = NSFileManager.defaultManager.URLForDirectory(
        directory = NSDocumentDirectory,
        inDomain = NSUserDomainMask,
        appropriateForURL = null,
        create = false,
        error = null
    )
    return Room.databaseBuilder<AppDatabase>(name = requireNotNull(documents).path + "/$APP_DATABASE_FILE")
}
```

`getKoin()` is `org.koin.mp.KoinPlatform.getKoin`; the Android `Context` is there because the app
starts Koin with `androidContext`.

5. Koin, as top-level functions inside the `core/database` package (the `DatabaseModule` scan
   picks them up, like the template's `provideDataStore()`):

```kotlin
@Single
fun provideAppDatabase(): AppDatabase = buildAppDatabase(getAppDatabaseBuilder())

@Single
fun provideRecipeDao(database: AppDatabase): RecipeDao = database.recipeDao()
```

6. DAOs: reads return `Flow<List<T>>` (or `Flow<T?>`), writes are `suspend`. Entities stay in
   `core/database` and are mapped to domain models in the feature's `data` module.

## Schema changes

- Before the app's first release, version 1 may change. An installed debug build with the old
  schema then has to be uninstalled or have its data cleared; Room refuses to open a database
  whose schema changed without a version bump.
- After a release, every schema change bumps `version` and comes with a migration (the exported
  schema in `schemas/` makes auto-migrations possible). Never `fallbackToDestructiveMigration`.
