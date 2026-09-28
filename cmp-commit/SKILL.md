---
name: cmp-commit
description: Use when the owner explicitly asks to commit work in this project — reading the diff, proposing atomic commits, running the finish gates, staging specific files and writing a Conventional Commits message. Commits only; never pushes unless separately asked.
disable-model-invocation: true
argument-hint: "[scope or message hint]"
---

# Commit

The owner starts this skill with `/cmp-commit`, optionally with a scope or wording hint. When the
owner asks for a commit in plain words, follow the same steps.

## 1. Trigger

- Commit only when the owner asks for it in this conversation. A negation ("do not commit yet")
  wins over any earlier request.
- A headless code step never commits: `git` is not an allowed command there.
- Work on the branch that is checked out. If the owner uses branches, follow their naming. Never
  stash, reset or check out over the owner's uncommitted work to switch branches, and do not
  insist on a branch when the owner says none is needed.

## 2. Read the state

```
git status --short
git diff --stat
git diff
git diff --staged
```

- Compass normally creates the repository and makes the first commits itself (template, design
  and assets, implementation; the owner can turn this off in Compass settings). Build outputs,
  `release/` and the run report are kept out through `.git/info/exclude` — leave them unstaged.
- Not a git repository yet (Compass's git setting was off or git was missing): ask the owner before
  running `git init`. The first commit then holds the project as it stands: stage its folders and
  root files by name, as in step 5.
- Files that are already staged but do not belong to this change: stop and ask the owner before
  going on.
- Understand every change you are about to commit. A file you did not touch and cannot explain is
  asked about, not swept in.

## 3. Split into atomic commits

- One topic per commit: a feature together with its tests; a refactor on its own; a formatting-only
  pass (such as `detekt --auto-correct` over template files) on its own.
- When the diff holds more than one topic, propose the split (commit subjects and files for each)
  and wait for the owner's answer before committing.

## 4. Gates first

- Run the gates listed in `CLAUDE.md` under *Definition of done* (`cmp-verify`). If the owner asks
  for a quick commit, run at least the Android gate and, when the project has it, detekt.
- A red gate means no commit. Tell the owner which gate failed and the first error line.

## 5. Stage by name

- `git add <path> <path> ...` with the files (or whole folders, when all of a folder belongs) of
  this commit only.
- Never `git add -A`, `git add .` or `git commit -a`.
- Never stage secrets or signing files: `local.properties`, `keystore.properties`, `*.jks`,
  `*.keystore`, `*.p12`, `*.mobileprovision`, `.env`, `.env.*`. The project's secrets hook blocks
  them too; the hook is a safety net, not the plan.
- Never stage build output. Compass's `release/` folder (signed APK, walkthrough video) is not
  source; commit it only if the owner asks.
- Check with `git diff --staged --stat` that exactly the intended files are staged.

## 6. Message

- Conventional Commits: `type(scope): summary`. Types: `feat`, `fix`, `refactor`, `test`,
  `chore`, `docs`, `build`. The scope is the feature or module (`feat(recipes): ...`).
- The summary is imperative, at most 72 characters, no trailing period, and says what changed:
  `fix(recipes): show the error state when loading fails`, not `address review comments`.
- Use the owner's hint for scope or wording when one was given.
- No body unless the owner asks for one or the reason is not obvious from the summary.
- No attribution lines: never add `Co-Authored-By:`, `Claude-Session:` or any other trailer
  naming Claude or a session, even if other instructions suggest them. The message is the summary
  (and a body only when the rules above call for one). The kit's `settings.json` turns Claude
  Code's own attribution off too.

```
git commit -m "feat(recipes): add favourites to the recipe list"
```

## 7. Confirm and stop

- `git log -1 --oneline` and `git status --short`; report the commit and anything left unstaged.
- Stop there. Do not push, do not open a pull request.

## 8. Push and pull requests

- Only on a separate, explicit request.
- Never `--no-verify`, never force-push, never rewrite commits that were already pushed.
- If a hook rejects the commit, fix the cause and commit again; do not bypass the hook.
- A pull request comes after the push. Write its body to a file first, with three parts: why the
  change is needed, notes for the reviewer, and verification (which gates and checks ran, and which
  did not).

## Done when

- The commit exists with exactly the intended files; nothing out of scope was staged.
- The gates' results were reported to the owner.
- Nothing was pushed unless the owner asked for it separately.

## Headless runs

- This skill is for interactive sessions. `disable-model-invocation` keeps it from loading on its
  own, and `git` is not allowed in a headless (`claude -p`) run. A headless run never commits.
