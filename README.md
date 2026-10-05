# skills

AI-optimized, modular **agent skills** for [Claude Code](https://code.claude.com),
following the open Agent Skills format — each skill is a folder with a `SKILL.md`
that the agent loads on demand.

Inspired by the structure of [`android/skills`](https://github.com/android/skills).

## What's a skill?

A skill is a directory containing a `SKILL.md` (instructions + YAML frontmatter)
plus any supporting `scripts/` and `reference/` files. Claude Code auto-loads a
skill when your request matches its `description`, or you can invoke it explicitly
with `/<skill-name>`.

## Available skills

| Skill | What it does |
|---|---|
| [`cmp-new-project`](./cmp-new-project) | Generate a Compose Multiplatform (Kotlin Multiplatform) project from the terminal via the [cmpose.dev](https://cmpose.dev) API — the chat equivalent of the cmpose.dev web wizard. |
| [`cmp-feature`](./cmp-feature) | Add a screen, feature module or data source to a generated app — the contract, domain, data and presentation layers, ViewModel, navigation destination and Koin wiring. |
| [`cmp-design-to-code`](./cmp-design-to-code) | Build or adjust UI from a provided design (exported boards, mockup or screenshot) by measuring it, mapping every value to a theme token and checking the result against the design. |
| [`cmp-code-rules`](./cmp-code-rules) | Rules for every Kotlin change in a generated project — layering, visibility, Multiplatform limits, Compose state, Koin annotations, resources, accessibility — plus a self-review checklist. |
| [`cmp-testing`](./cmp-testing) | Add or fix unit tests for ViewModels, use cases, repositories and mappers, and repair a test gate that is red, counts zero tests or hangs. |
| [`cmp-maestro`](./cmp-maestro) | Write or repair Maestro flows, including the walkthrough used to record the demo video on Android and iOS, and add the test tags they select by. |
| [`cmp-detekt`](./cmp-detekt) | Run detekt in projects that have the detekt gate, auto-correct formatting first, then fix the remaining findings at their cause without suppressions, baselines or config changes. |
| [`cmp-verify`](./cmp-verify) | Run the finish gates (Android build, iOS simulator compile, detekt, tests) in order and fix the common Kotlin Multiplatform, KSP, Koin and Compose resources failures. |
| [`cmp-commit`](./cmp-commit) | On explicit request, split the work into atomic commits, run the finish gates and write Conventional Commits messages — committing only, never pushing unless asked. |
| [`cmp-matrix-test`](./cmp-matrix-test) | Run the cmpose.dev generator's release matrix (every variant built and launched as a release build on an Android emulator and an iOS simulator) through the backend's smoke gate, and report with screenshots. Requires a cmpose.dev backend checkout. |
| [`account-delegate`](./account-delegate) | Offer to hand a self-contained job to a second Claude Code account on the same machine (headless, live in a side cmux pane) and bring its report — or a worktree branch to merge — back to your main session. |

[`compass-kit`](./compass-kit) is not a skill but a kit that Compass installs into every project
it generates. Its `kit.json` lists the skills it ships — `cmp-code-rules`, `cmp-feature`,
`cmp-design-to-code`, `cmp-maestro`, `cmp-testing`, `cmp-verify`, `cmp-commit` and, for projects
with detekt, `cmp-detekt` — together with the finish gates those skills run. `cmp-matrix-test` also
runs detekt with the kit's `detekt.yml`. See [compass-kit](#compass-kit) below for its contents.

## Install

Skills live in `~/.claude/skills/` (personal) or `<project>/.claude/skills/`
(project-scoped). Clone this repo, then install a skill by **symlink** (recommended —
you keep getting updates with `git pull`) or by **copy**:

```bash
git clone https://github.com/Keremturker/skills.git
cd skills

# symlink (recommended)
ln -s "$PWD/cmp-new-project" ~/.claude/skills/cmp-new-project

# …or copy
cp -R cmp-new-project ~/.claude/skills/
```

Start a new Claude Code session and run `/cmp-new-project`. Each skill's own
`README.md` lists its requirements and usage.

## Repository layout & conventions

- **One directory per skill** at the repo root, named in `kebab-case` matching the
  skill's `name:` field.
- Each skill dir contains `SKILL.md` (required), an optional `README.md`, and any
  `scripts/` / `reference/` it needs.
- As the collection grows, skills may be grouped into domain folders
  (e.g. `compose/`, `android/`), following the `android/skills` convention.

```
skills/
├── README.md
├── LICENSE
└── cmp-new-project/
    ├── SKILL.md
    ├── README.md
    ├── defaults.json
    ├── reference/
    └── scripts/
```

## Contributing

1. Create `<skill-name>/SKILL.md` with at least `name` and `description` frontmatter.
2. Add a `README.md` documenting the skill's requirements and usage.
3. Keep heavy / deterministic work in `scripts/`; keep `SKILL.md` focused on
   orchestration so it stays small and cheap to run.

## Disclaimer

These skills are AI-optimized instructions. Review what a skill does before running
it — some execute shell commands and call external APIs.

## License

[MIT](./LICENSE) © 2026 Kerem Turker

## compass-kit

`compass-kit/` is what Compass installs into every project it generates: the skills listed in
`kit.json`, `CLAUDE.md` (Compass fills in the `<!-- compass:gates -->` line), a project
`settings.json` that registers `hooks/secrets-guard.py` and turns commit/PR attribution off, and
the detekt configuration.
The gates in `kit.json` are both what the coding agent is told to run and what Compass runs
itself before it calls the app ready.

Hook test: `sh compass-kit/hooks/test_secrets_guard.sh`
