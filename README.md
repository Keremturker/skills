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
