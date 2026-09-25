# Compose reference

Details behind section 8 of `cmp-code-rules`. Everything here compiles for Android and iOS from
`commonMain`.

## Stability and recomposition

- This Kotlin version compiles Compose with strong skipping on: a composable skips when every
  argument is equal to last time. Stable types are compared with `equals`, unstable ones by
  instance (`===`).
- So the cost of instability is a new instance on every recomposition. Do not build lists,
  objects or formatters inside a composable body and pass them down; build them in the ViewModel,
  or `remember(key) { ... }` them.
- UiState is an `@Immutable` data class with `val`s only. Never expose `MutableList`, `var` or a
  mutable collection through state.
- Pass a leaf composable the fields it needs, not the whole UiState.
- Sorting, filtering and mapping for display belong in the ViewModel. If one must happen in
  composition, wrap it in `remember(input) { ... }`.

## Which state primitive

| Need | Use |
|---|---|
| Screen state from the ViewModel | `viewModel.uiState.collectAsStateWithLifecycle()` in the Route |
| Local UI state (expanded, selected tab) | `remember { mutableStateOf(...) }` |
| Local UI state that must survive rotation | `rememberSaveable { mutableStateOf(...) }` with a primitive or `String` |
| Int, Long or Float state | `mutableIntStateOf`, `mutableLongStateOf`, `mutableFloatStateOf` |
| A value derived from state that changes more often than the result | `remember { derivedStateOf { ... } }` (for example "show the scroll-to-top button" from the scroll position) |
| A local list edited in place | `remember { mutableStateListOf<T>() }` (local UI only; ViewModel state stays immutable) |
| Text the user types that the ViewModel needs | keep it in UiState and update it with an action on every change |

## Which effect

| Need | Use |
|---|---|
| Suspend work tied to a key (animate when `selectedId` changes) | `LaunchedEffect(selectedId) { ... }` |
| Loading data for a screen | not an effect: the ViewModel starts it in `init` or on an action |
| Register and release a listener or observer | `DisposableEffect(key) { ...; onDispose { ... } }` |
| Start a coroutine from a click (scroll to top, show a snackbar) | `val scope = rememberCoroutineScope()` then `scope.launch { }` in the callback |
| Call the latest lambda from a long-lived effect | `val latestOnTimeout by rememberUpdatedState(onTimeout)` |
| Turn Compose state into a Flow | `snapshotFlow { state.value }` inside `LaunchedEffect` |
| Push a value to non-Compose code after every successful recomposition | `SideEffect { ... }` |

- Keys are the inputs the effect reads. `LaunchedEffect(Unit)` or `LaunchedEffect(true)` is for
  work that truly runs once per entry into composition, which is rare.
- Never start work directly in a composable body (no `viewModel.load()` or `launch` there).

## Modifier order

Modifiers apply from the outside in; order changes behaviour.

```kotlin
Modifier
    .fillMaxWidth()
    .clip(MaterialTheme.shapes.medium) // clip before background, or the corners stay square
    .background(MaterialTheme.colorScheme.surfaceVariant)
    .clickable(onClick = onClick) // before padding, so the padding is tappable too
    .padding(16.dp)
```

- `padding` then `clickable`: the padding is not part of the touch target.
- `testTag` and semantics go on the node that is actually clicked (see `cmp-maestro`).
- The `modifier` parameter comes first in the chain of the outermost element:
  `modifier.fillMaxWidth()...`, not `Modifier.fillMaxWidth().then(modifier)` on an inner child.

## Lazy lists

- `items(items = list, key = { it.id }) { item -> ... }`. The key is a stable id, never the index.
  Two items with the same key crash the list.
- Add `contentType` when a list mixes different item layouts.
- Never put a `LazyColumn` inside a `Column` with `verticalScroll`; the inner list gets an infinite
  height and crashes. Use one `LazyColumn` with several `item { }` / `items()` blocks.
- Do not compute inside item lambdas; prepare the display model in the ViewModel.

## Crash patterns

| Symptom at runtime | Cause |
|---|---|
| `Key ... was already used` | duplicate `key` in a lazy list |
| `Vertically scrollable component was measured with an infinity maximum height constraints` | lazy list nested in a vertically scrolling parent |
| `NoDefinitionFoundException` when a screen opens | ViewModel or dependency not wired; see `cmp-feature`, `references/koin.md` |
| `Serializer for class ... is not found` on navigation | destination is missing `@Serializable` |
| crash when the app goes to the background | a `rememberSaveable` value of a type that cannot be saved |
| navigation loop or repeated events | calling `navigate` or `onAction` from a composable body instead of a callback |

## Accessibility

- Touch targets are at least 48dp; small icons get `Modifier.minimumInteractiveComponentSize()` or
  a padded clickable parent.
- Icon-only buttons have a `contentDescription` from resources; decorative images use `null`.
- Section titles get `Modifier.semantics { heading() }`.
- A custom clickable says what it is: `clickable(role = Role.Button, onClick = ...)`.
- Colour is never the only carrier of meaning (add text or an icon).
- Text sizes come from the theme's typography in `sp`; containers of text use `heightIn(min = ...)`.

## Composable API shape

- A composable either emits UI (PascalCase noun, returns `Unit`) or returns a value (camelCase,
  usually `remember...`), never both.
- Parameter order: required parameters, `modifier: Modifier = Modifier`, optional parameters, then
  a trailing `content` lambda if any.
- Exactly one `modifier` parameter, applied to the root element only.
- Hoist state: a stateless component takes `value` and `onValueChange`.
- Event parameters are `onX` in present tense: `onClick`, `onValueChange`, `onItemSelect`.
- Below the Route no composable receives a ViewModel or a `NavController`.
- `CompositionLocal` is for values the whole tree needs (theme, the template's palette), not for
  handing data to one child.
