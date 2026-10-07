# account-delegate

Lets your main Claude Code session offer to hand a self-contained job to a **second Claude
Code account** on the same machine — for example to use that account's quota. The second
account runs headless (`claude -p`) under its own settings and policy, you watch it live in
its own cmux workspace, and the report comes back into your main session. Nothing is delegated
without your explicit yes. Write jobs run in the second account's `auto` permission mode:
edits are allowed and its own classifier approves safe shell commands, denying risky ones
(`DELEGATE_PERMISSION_MODE=acceptEdits` allows edits only). Ro jobs get the read tools only.
Nothing is run with a mode that skips permission checks. Shell commands run as your OS user, so they are
not confined to the worktree: only the second account's classifier and its own settings
limit them.

Two modes:
- **ro** — read-only analysis/research/review (Read, Grep, Glob, WebSearch, WebFetch). In a
  git repo it also uses a throwaway detached worktree of the base, removed (without `--force`)
  after the run; outside a git repo it runs directly in `--cwd`.
- **write** — a code change on branch `delegate/<id>` in its own git worktree; you decide
  whether to merge. The worktree starts from the `--base` ref (uncommitted changes are not
  visible), and `--cwd` must be the repo root or a directory that exists on the base. Changes are committed
  for you after the run, as you, with signing and git hooks disabled for that commit (the
  agent could have edited a tracked hooks dir such as `.husky/`; your hooks run normally when
  you merge). That commit uses the git dir recorded before the run, never the worktree's
  `.git` file; if the agent changed that file, nothing is committed (`commit_failed: true`,
  explained in `stderr.log`) and the worktree is left as is. Clean/smudge filters your own git
  config defines (e.g. git-lfs) still run on the agent's files, as in any `git add`. Git never
  runs inside nested repos: a gitlink already in the index (a submodule of the base, a nested
  repo an earlier plan job committed) is left out of the collection while its path still holds
  a nested repo, so changes inside it are not collected; if the nested repo is gone (deleted,
  or replaced by a file) that change is collected like any other. A new nested repo is
  committed as a gitlink.

## Plan mode

`delegate.sh --mode write --plan <plan dir> --cwd <dir> --brief <file> [--base <ref>] [--title <t>] [--resume <session id>]`

Runs the tasks of one implementation plan in a single worktree, `<plan dir>/worktree`, on branch
`delegate/<plan id>` (`<plan id>` = basename of `<plan dir>`, `[A-Za-z0-9._-]`). The first call
needs `--base` and writes `<plan dir>/plan.json` (base, base commit, cwd, branch, and the pinned
git dir and `.git` file); later calls refuse `--base` and must use the same `--cwd`. Every call
gets `<plan dir>/jobs/<n>/` (a normal job dir) and adds at most one commit,
`delegate(<plan id>): <title>`. Before a later job starts, the script checks that the `.git`
file is unchanged, that the worktree is on the plan branch and that it has no uncommitted
changes; otherwise it exits 2. `--resume` continues the second account's session of an earlier
job of the same plan (any other session id: exit 2). `<plan dir>/lock` allows one job at a time;
a lock whose process is gone is taken over. A lock dir with no or an invalid pid (the process was
killed between creating it and writing the pid) is never taken over: check that no job is running,
then `rm -rf <plan dir>/lock`. If `delegate.sh` was SIGKILLed, its `claude` child may still be
running; check for it before taking over. The plan worktree is never removed by the script. A
plan dir without `plan.json` may hold other files (e.g. `progress.md`, the jobs of a first call
that failed) and is refused only if it has a `worktree` or `plan.json.tmp`.
`meta.json` gains `plan_id`, `plan_dir`, `job_n`, `title`, `resumed_from` and `parent_commit`
(the branch tip before the job), null outside plan mode. `--plan` is write mode only and cannot
be combined with `--id`; `--title` and `--resume` need `--plan`.

## Base ref

`delegate.sh --mode ro|write --cwd <dir> --brief <file> --base <ref> [--id <id>]`. `--base`
(branch, tag or commit) is **required** when `--cwd` is inside a git repo (missing or
unresolvable: exit 2, no job dir) and **refused** otherwise (a non-git `--cwd` is ro only and
runs in place). Anything not committed on the base is invisible to the job. Your checked-out
branch, working tree and index are never touched. The merge target is the base branch; a tag
or sha base has no automatic merge target (you are asked where to merge). A name that is both a
branch and a tag is refused (exit 2). Your own git hooks do not run when the worktree is created
(`core.hooksPath=/dev/null` for `git worktree add`).

## Requirements

- Claude Code CLI, `jq`, `git`; macOS or Linux. `cmux` is optional (live view in its own workspace).
- A second account logged in under its own config dir, e.g.:

  ```bash
  alias clt='CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude'   # then run `clt` once and log in
  ```

## Install

```bash
ln -s "$PWD/account-delegate" ~/.claude/skills/account-delegate
```

Link it into your **main** account's skills only — not into the second account's.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DELEGATE_CLAUDE_CONFIG_DIR` | `~/.claude-work` | Second account's config dir |
| `DELEGATE_CLAUDE_BIN` | `~/.local/bin/claude`, else `claude` on `PATH` | CLI to run (bypasses shell wrappers) |
| `DELEGATE_CACHE_DIR` | `~/.cache/claude-delegate` | Where job dirs are kept |
| `DELEGATE_MAX_TURNS` | `40` | Turn limit per job |
| `DELEGATE_PERMISSION_MODE` | `auto` | Write-mode permission mode: `auto` or `acceptEdits` (anything else: exit 2) |

- `--model <alias|id>` / `DELEGATE_MODEL` — model for the second account's run (flag wins; unset =
  that account's default). A plan keeps its first job's model: a different `--model` on a later job
  is refused, `DELEGATE_MODEL` is ignored there. Recorded as `model` in `meta.json`.

The child process does not inherit your main session's identity: every `CLAUDE_CODE_*` and
every `ANTHROPIC_*` variable (API key, auth token, base URL, models, custom headers, ...)
plus `CLAUDECODE` are dropped, so the second account always uses its own login.

`delegate.sh` exits 0 on success, 1 if the job failed, and 2 on a usage error (message on
stderr, no job dir created).

Each job dir (created private, `umask 077`) holds `brief.md`, `pid` (delegate.sh's process
id), `events.jsonl` (stream-json), `stderr.log`, `result.md` (final report), `meta.json`
(mode, exit code, error flag, turns, cost, denials; `base`, the ref as given, and `base_commit`,
the sha it resolved to, both null outside git; `start_branch`, the branch you were on when the
job started, null if detached or outside git; in write mode also `permission_mode` (the mode the run reported), `gitdir` (the worktree's git dir, pinned before the run), `branch`, `commit`,
`commit_failed`) and `worktree/` (git repos only; in ro mode normally removed again after the
run). `meta.worktree` is the worktree path while it still exists: always in write mode, and in ro
mode only if the automatic removal failed (the reason is in `stderr.log`); otherwise null. The
minimal fallback meta carries `base`, `base_commit` and `worktree` too. If jq cannot build the full `meta.json`, a minimal
one (`id`, `mode`, `exit_code`, `is_error: true`, ...) is written instead.

`watch.sh <job dir>` returns once `meta.json` appears: exit 0 if the job finished cleanly (no
error, no denied tool call, no failed commit), exit 2 if it finished but needs a look. It exits 1
with "job process is gone without meta.json" if the process in `pid` dies first (e.g. it was
SIGKILLed). The workspace the skill opens closes itself 5 seconds after exit 0 and otherwise
waits for Enter.

## Usage report

`scripts/usage.sh [--since YYYY-MM-DD]` (default: the last 7 days, UTC days) prints two tables:
the second account's delegated jobs per plan (jobs, cost as the CLI reported it, output and
cache tokens; read from the job dirs in `DELEGATE_CACHE_DIR`), and the main account's tokens per
project from its session transcripts (`USAGE_MAIN_PROJECTS_DIR`, default `~/.claude/projects`;
tokens only, the transcripts carry no cost). For plan limits use `/usage` in each account.

## Tests

```bash
bash account-delegate/tests/test_watch.sh
bash account-delegate/tests/test_usage.sh
bash account-delegate/tests/test_delegate.sh
bash account-delegate/tests/test_delegate_write.sh
bash account-delegate/tests/test_delegate_plan.sh
```

They use a fake `claude` and never touch a real account.
