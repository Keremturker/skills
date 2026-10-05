# account-delegate

Lets your main Claude Code session offer to hand a self-contained job to a **second Claude
Code account** on the same machine — for example to use that account's quota. The second
account runs headless (`claude -p`) under its own settings and policy, you watch it live in
a side cmux pane, and the report comes back into your main session. Nothing is delegated
without your explicit yes, and nothing the second account asks permission for is
auto-approved.

Two modes:
- **ro** — read-only analysis/research/review (Read, Grep, Glob, WebSearch, WebFetch).
- **write** — a code change on branch `delegate/<id>` in its own git worktree; you decide
  whether to merge. The worktree starts from `HEAD` (uncommitted changes are not visible),
  and `--cwd` must be the repo root or a directory tracked in `HEAD`. Changes are committed
  for you after the run (signing is disabled for that commit; repo git hooks still run).

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

The child process does not inherit your main session's identity: every `CLAUDE_CODE_*`
variable plus `CLAUDECODE`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`,
`ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` are dropped, so the second account always uses
its own login.

`delegate.sh` exits 0 on success, 1 if the job failed, and 2 on a usage error (message on
stderr, no job dir created).

Each job dir holds `brief.md`, `events.jsonl` (stream-json), `stderr.log`, `result.md`
(final report) and `meta.json` (mode, exit code, error flag, turns, cost, denials, branch,
commit).

## Tests

```bash
bash account-delegate/tests/test_watch.sh
bash account-delegate/tests/test_delegate.sh
bash account-delegate/tests/test_delegate_write.sh
```

They use a fake `claude` and never touch a real account.
