---
name: cmp-design-to-code
description: Use when building or adjusting UI from a provided design in this Compose Multiplatform app — the exported design boards under design/ (dc.html files and canvas.json), the fonts and icons Compass prepared, a mockup or a screenshot — or when a screen must match its design more closely. Measure first, map every value to a theme token, build exactly what is shown, then check each value against the design.
---

# Design to code

The design is the specification. Read values from it; never eyeball them. Code rules are in
`cmp-code-rules`, screen structure in `cmp-feature`.

## 1. What is in `design/`

Search `design/` recursively; the boards may sit in a subfolder such as `design/project/`.

| File | What it is |
|---|---|
| `*.dc.html` | One board per screen and state. Inline `style` attributes hold exact values: px sizes, hex colours, font family, weight, line height, letter spacing, radius, gaps. |
| `canvas.json` | The board list: file name, title (usually `Screen · state`) and frame size. Use it to pair screens with their states. A board that shows the flow between screens tells you the navigation. |
| a style-guide board | Colour tokens and the type scale, when the design has one. Read it first. |
| `fonts/<family>_<weight>.ttf` | The design's fonts, already downloaded (for example `figtree_600.ttf`). |
| `icons/<id>.xml` | Android vector drawables, drawn black; tint them. License in `icons/LICENSE-icons.txt`. |
| `sounds/` | Sound effects, when the app has them. |
| `artifact-url.txt` | Where the design was published. Do not open it: it needs a login. |

The `<link>` to Google Fonts and `support.js` in the HTML are for the browser; ignore them.

## 2. Extract

- Read every board of the screen you are building, all states included, before writing code.
- Machine-readable values (HTML, CSS, SVG, token files) are exact. Values taken from an image
  (a screenshot, a mockup) are estimates.
- Write a value table in your working notes, not in a file:
  `element → value → source (read or estimated) → token or component`. The code must follow the
  table; the table is what you check against at the end.

CSS to Compose. The board frame (for example 390 × 844) is a phone in dp, so 1 CSS px = 1 dp and
font px = sp.

| CSS | Compose |
|---|---|
| `width: 390px; height: 844px` on the board root | the frame, never code it: `fillMaxSize()` |
| `padding: 52px 20px 14px` (top, right/left, bottom) | `padding(start = 20.dp, top = 52.dp, end = 20.dp, bottom = 14.dp)` |
| `display: flex; flex-direction: column; gap: 8px` | `Column(verticalArrangement = Arrangement.spacedBy(8.dp))` |
| `display: flex` (row), `gap: 12px` | `Row(horizontalArrangement = Arrangement.spacedBy(12.dp))` |
| `justify-content: space-between` | `Arrangement.SpaceBetween` |
| `align-items: center` | `verticalAlignment = Alignment.CenterVertically` (Row), `horizontalAlignment = Alignment.CenterHorizontally` (Column) |
| `flex: 1` | `Modifier.weight(1f)` |
| `width: 100%` | `fillMaxWidth()` |
| `font-size: 15px; line-height: 22px; letter-spacing: 0.4px` | `fontSize = 15.sp, lineHeight = 22.sp, letterSpacing = 0.4.sp` |
| `font-weight: 400 / 500 / 600 / 700` | `FontWeight.Normal / Medium / SemiBold / Bold` |
| `color: #9E2F45` | `Color(0xFF9E2F45)`, defined in the theme |
| `rgba(255,255,255,0.16)` | `Color.White.copy(alpha = 0.16f)` |
| `border-radius: 20px` / `999px` | `RoundedCornerShape(20.dp)` / `CircleShape` |
| `border: 1px solid #E8DCD3` | `Modifier.border(1.dp, color, shape)` |
| `box-shadow: ...` | `Modifier.shadow(elevation, shape)`; an estimate, mark it |
| `opacity: 0.6` | `Modifier.alpha(0.6f)` |
| `aria-hidden="true"` | decorative: `contentDescription = null` |

## 3. Clarify

- The board titles name the states (content, empty, loading, error, dialog). Each board becomes a
  UI state; `cmp-code-rules` requires loading, empty and error even when the design leaves one out.
- Interactive session: ask about what the design does not show (a missing state, overflow of long
  text, what a tap does).
- Headless run: derive a missing state from the boards that exist (same header, spacing and
  colours) and list it under `Assumptions`. Never fill a gap with your own "improvement".
- The design's sample data (names, counts, prices) is sample data. Show real or fake data from
  the data layer, not the design's numbers hard-coded in the UI.

## 4. Ground in the theme

- Use the theme the project already has: `core/designsystem`'s palette when the project was
  generated with it, or a `theme` package that already exists. Otherwise create one in
  `core/presentation` under a `theme` package: colours, typography and a theme composable that
  wraps `MaterialTheme`, applied once in `shared/.../MainScreen.kt` around the `Scaffold` (add
  `implementation(projects.core.presentation)` to `shared/build.gradle.kts` if it is missing).
  Name each file after the one type it declares.
- Colours: every measured colour becomes a named token in the theme. Map it to a
  `MaterialTheme.colorScheme` role when one fits (primary, background, surface, onSurface, error,
  outline). Colours with no role go into a small `@Immutable` data class provided through a
  `CompositionLocal`. Composables read tokens; no bare `Color(0x...)` under `ui/`. detekt's
  `MagicNumber` exempts the `theme` package, not `ui/` (hex colours in a `when` under `ui/` were
  reported in a measured run).
- One colour mode shown in the design: use it and list that under `Assumptions`. Do not invent a
  dark palette.
- Fonts: copy the needed files from `design/fonts/` into
  `src/commonMain/composeResources/font/` of the theme module. That module needs
  `androidResources.enable = true` (`cmp-feature`, `references/screen.md`, "Resources"), or the
  Android app falls back to the system font while every gate stays green. Build the family in a
  `@Composable` function, because `org.jetbrains.compose.resources.Font` is composable:

```kotlin
@Composable
fun figtreeFamily(): FontFamily = FontFamily(
    Font(Res.font.figtree_400, FontWeight.Normal),
    Font(Res.font.figtree_600, FontWeight.SemiBold)
)
```

  Put the design's type scale into `Typography(...)`: size, line height, weight and letter
  spacing per role. Components use `MaterialTheme.typography.x`, not ad-hoc `TextStyle`s.
- Icons: copy the ones the screen uses from `design/icons/` into `composeResources/drawable/` of
  the module that shows them, and draw them with
  `Icon(painterResource(Res.drawable.<id>), contentDescription = ..., tint = ...)`. Material icons
  are not on the classpath.
- Texts shown in the design become string resources in every UI language (`cmp-code-rules`,
  section 11).
- Reuse components the project already has before writing new ones.

## 5. Build one to one

- Apply the table's values exactly. Add nothing the design does not show: no extra animation,
  shadow, gradient, divider or "nicer" spacing.
- Do not hard-code the board frame. Express proportions with `weight`, `fillMaxWidth(fraction)`
  and `Arrangement.spacedBy`; fixed sizes only for things that are fixed by nature (icons, avatars,
  button heights). The app runs on phones of many sizes on Android and iOS.
- Boards usually draw no status bar, but their first element often has a large top padding
  (around 44 to 60 px) that stands in for it. The generated `MainScreen` passes its `Scaffold`
  padding to the `NavHost`, so every screen already starts below the status bar. Do not add that
  space a second time: keep only the part that is real spacing and mark it as estimated.
- Spacing written once inside a composable may stay inline (`20.dp`); values repeated across
  screens become theme tokens.

## 6. Verify

- Headless run: go through the table and find each value in the code (Grep for the hex value or
  the token). Every row is used, or its absence is listed. Then run the gates (`cmp-verify`). The
  visual comparison happens on the walkthrough video Compass records afterwards.
- Interactive session: run the app, take a screenshot of each state and compare it with its board
  row by row. List what still differs.

## Done when

- Every size, colour and font in the diff traces to a table row, read or marked estimated.
- Nothing appears that the design does not show; every state board has a matching UI state.
- The design's fonts and icons are used; no system font where the design names a family.
- Modules that received fonts or drawables enable Android resources.
- The final summary lists remaining differences, estimates and assumptions.

## Headless runs

- No pixel measurement with scripts. Open images with the Read tool and mark every value taken
  from an image as estimated.
- Do not open the design URL; it needs a login this session does not have. Everything needed is
  under `design/`.
- There is no internet: if a font family is not in `design/fonts/`, use the theme's default and
  say so under `Assumptions`.
- Do not ask questions. Choose the closest reading of the design and list it under `Assumptions`.
