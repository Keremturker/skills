# account-delegate

Lets your main Claude Code session offer to hand a self-contained job to a **second Claude
Code account** on the same machine — for example to use that account's quota. The second
account runs headless (`claude -p`) under its own settings and policy, you watch it live in
a side cmux pane, and the report comes back into your main session. Nothing is delegated
without your explicit yes. Edits (write mode, `acceptEdits`) and the read tools (ro mode)
are pre-allowed; permission prompts for anything else are never auto-approved.

Two modes:
- **ro** — read-only analysis/research/review (Read, Grep, Glob, WebSearch, WebFetch).
- **write** — a code change on branch `delegate/<id>` in its own git worktree; you decide
  whether to merge. The worktree starts from `HEAD` (uncommitted changes are not visible),
  and `--cwd` must be the repo root or a directory tracked in `HEAD`. Changes are committed
  for you after the run, as you, with signing and git hooks disabled for that commit (the
  agent could have edited a tracked hooks dir such as `.husky/`; your hooks run normally when
  you merge). That commit uses the git dir recorded before the run, never the worktree's
  `.git` file; if the agent changed that file, nothing is committed (`commit_failed: true`,
  explained in `stderr.log`) and the worktree is left as is. Clean/smudge filters your own git
  config defines (e.g. git-lfs) still run on the agent's files, as in any `git add`.

## Requirements

- Claude Code CLI, `jq`, `git`; macOS or Linux. `cmux` is optional (live side pane).
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

The child process does not inherit your main session's identity: every `CLAUDE_CODE_*` and
every `ANTHROPIC_*` variable (API key, auth token, base URL, models, custom headers, ...)
plus `CLAUDECODE` are dropped, so the second account always uses its own login.

`delegate.sh` exits 0 on success, 1 if the job failed, and 2 on a usage error (message on
stderr, no job dir created).

Each job dir (created private, `umask 077`) holds `brief.md`, `pid` (delegate.sh's process
id), `events.jsonl` (stream-json), `stderr.log`, `result.md` (final report), `meta.json`
(mode, exit code, error flag, turns, cost, denials; in write mode also `branch`, `commit`,
`commit_failed` and `start_branch`, the branch you were on when the job started, null if
detached) and, in write mode, `worktree/`. If jq cannot build the full `meta.json`, a minimal
one (`id`, `mode`, `exit_code`, `is_error: true`, ...) is written instead.

`watch.sh <job dir>` exits 0 once `meta.json` appears, and exits 1 with "job process is gone
without meta.json" if the process in `pid` dies first (e.g. it was SIGKILLed).

## Tests

```bash
bash account-delegate/tests/test_watch.sh
bash account-delegate/tests/test_delegate.sh
bash account-delegate/tests/test_delegate_write.sh
```

They use a fake `claude` and never touch a real account.
