---
name: account-delegate
description: >-
  Offer to hand a self-contained job (analysis, research, review, or a code change in an
  isolated git worktree) to a second Claude Code account configured on this machine, run it
  headless in a side cmux pane, and bring the report back into this session. Use when the
  user wants to spend the second account's quota, says "şirket hesabına pasla", "ikinci hesaba pasla", "bunu diğer
  hesaba yaptır", "delegate this to the other account", or when you are about to start a
  sizeable, self-contained job and the second account is configured. Never delegates
  without the user's explicit yes.
---

# account-delegate

Runs a job on a second Claude Code account (its config dir is `DELEGATE_CLAUDE_CONFIG_DIR`,
default `~/.claude-work`) and returns the result. Skill dir: `~/.claude/skills/account-delegate/`.
Talk to the user in their language.

## Rules

- **Never delegate without asking.** Offer, then wait for an explicit yes. A no means: do not re-offer that same
  job this session; similar future jobs may still be offered.
- The second account runs under its own policy. Never add MCP servers, plugin dirs, agents,
  permission-bypass flags or approval hooks to its run, and never try to get around a denial
  it reports — bring blocked commands back to the user instead.
- Never put secrets, tokens, or private credentials in the brief.
- If `DELEGATE_CLAUDE_CONFIG_DIR` (or `~/.claude-work`) does not exist, this skill does not
  apply; do the work yourself.

## 1. Decide whether to offer

Offer only if ALL hold:
- The job is self-contained: the brief can carry everything needed.
- It is big enough to be worth a fresh session's fixed start-up cost (roughly $0.2 of the
  second account's quota per job) — e.g. a multi-file analysis, a research question, a
  review, a feature or refactor in one repo. Not a one-line answer or a single small edit.
- It needs none of this session's MCP servers, plugins or private files outside the project.
- It does not need back-and-forth with the user while it runs.
- It does not hinge on something the second account will be refused: `git push`, package
  installs, raw network calls (`curl`, `wget`), or files under `~/.ssh`, `~/.aws`, `.env`.

Pick the mode:
- **ro** (read-only analysis): reads files and the web, writes nothing. Bash is disabled, so
  if git history matters, collect it yourself and paste it into the brief.
- **write** (code change in a worktree): only inside a git repo with at least one commit. The
  job works on branch `delegate/<id>` in its own worktree from `HEAD`; the user's working tree
  is not touched. Uncommitted changes are NOT visible to it — mention this if the tree is dirty.
  `--cwd` must be the repo root or a directory tracked in `HEAD`; an untracked or ignored
  subdirectory makes the script exit 2, so pick a tracked directory (or the repo root).

If it does not qualify, say nothing about delegation and do the job yourself.

## 2. Offer

Ask one question, e.g. (Turkish user):

> Bu işi ikinci hesaba paslayabiliriz — **mod: salt-okur analiz** — kapsam: `core/` modülündeki
> ağ katmanını inceleyip riskleri raporlamak. Yapalım mı?

For write mode say **mod: worktree'de kod değişikliği** and name the repo. Wait for the answer.

## 3. Write the brief

Write it to a temp file (e.g. in your scratchpad). It must stand alone — the other session
has none of this conversation. Include:
- **Goal** and what "done" means.
- **Context:** repo/dir, the relevant file paths, decisions already made, constraints
  (style, versions, things not to touch).
- **For write mode:** which tests or checks to run and that they must pass.
- **Report:** anything specific you need in the final report (it always ends with the
  sections Done / Findings / Blocked or needed commands / Open questions).

Write the brief in the user's language.

## 4. Start the job and the watcher

Start it with the Bash tool and `run_in_background: true`:

```bash
~/.claude/skills/account-delegate/scripts/delegate.sh --mode <ro|write> --cwd "<project dir>" --brief "<brief file>"
```

Read the background output until the first line `JOB_DIR=<path>` appears, then open the
live view next to this session (skip this step if `cmux` is not available or
`CMUX_SURFACE_ID` is unset):

```bash
cmux new-split right --focus false --command "~/.claude/skills/account-delegate/scripts/watch.sh '<JOB_DIR>'; printf '\nPress Enter to close'; read _"
```

Tell the user in one line that the job is running in the side pane. Do not poll; you are
notified when the background command exits. Meanwhile you may continue other work that does
not touch the same files.

If the command exits with code 2 and no `JOB_DIR=` line, it was a usage error (bad flag,
missing brief, non-git or untracked `--cwd`, missing config dir or binary). No job was
created: show the stderr message to the user and fix the call; do not treat it as a job
failure.

## 5. When it finishes

Read `<JOB_DIR>/meta.json` and `<JOB_DIR>/result.md`.

- **Success** (`is_error: false`): summarise the report for the user. Mention the cost
  (`total_cost_usd`) and turns in one line.
- **Blocked or needed commands** (report section, or `permission_denials` in meta): list them
  and ask the user whether you should run them here. Run only the ones they approve.
- **Write mode:**
  - If `commit` is null and `commit_failed` is false, there were no changes: remove the
    worktree (`git -C <repo> worktree remove <JOB_DIR>/worktree`), delete the branch
    (`git -C <repo> branch -d delegate/<id>`; it equals HEAD's ancestor) and say so.
  - If `commit_failed` is true (e.g. a repo git hook rejected the commit), the worktree holds
    the only copy of the work: do NOT remove it unless the user says so. Show the end of
    `stderr.log` and the worktree's `git status`, and ask how to proceed.
  - Otherwise show `git -C <repo> diff --stat HEAD...delegate/<id>` and ask "birleştireyim mi?".
    On yes (ask first if the user's working tree has uncommitted changes that could conflict),
    run `git -C <repo> merge --no-ff --no-edit delegate/<id>`; on conflict run
    `git -C <repo> merge --abort` and ask the user. After a successful merge remove the
    worktree and delete the branch with `git branch -d` (never `-D`). On no, leave the branch
    and remove only the worktree; use `-D` only if the user explicitly says to discard it.
  - Never use `--force` when removing a worktree; if removal is refused, tell the user.
- **Failure** (`is_error: true`, non-zero `exit_code`, or empty `result.md`): show the last
  ~20 lines of `watch.sh`-formatted events
  (`jq -R -r -f ~/.claude/skills/account-delegate/scripts/format-events.jq < <JOB_DIR>/events.jsonl | tail -n 20`)
  and the end of `stderr.log`, and offer to do the job in this session instead.
  `subtype: error_max_turns` means it hit the turn limit (`DELEGATE_MAX_TURNS`, default 40).
  In write mode a failed job can leave branch `delegate/<id>` (possibly with a commit) and
  `<JOB_DIR>/worktree`: tell the user what was left and ask before removing anything.

Job dirs live in `DELEGATE_CACHE_DIR` (default `~/.cache/claude-delegate`) and are kept for
reference; nothing cleans them automatically.
