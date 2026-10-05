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
  if git history matters, collect it yourself and paste it into the brief. In a git repo it
  runs in a throwaway detached worktree of the base (removed automatically afterwards); outside
  a git repo it runs directly in `--cwd` and `--base` must not be passed.
- **write** (code change in a worktree): only inside a git repo with at least one commit. The
  job works on branch `delegate/<id>` in its own worktree created from the base; the user's
  working tree and branch are not touched. `--cwd` must be the repo root or a directory that
  exists on the base; otherwise the script exits 2.

### Choose the base (git repos)

Every job in a git repo needs `--base <ref>` (branch, tag or commit); without it the script
exits 2 and creates no job dir. Choose it like this:
- Default: the user's currently checked-out branch (`git -C <repo> branch --show-current`).
  If HEAD is detached (empty output), propose the default branch (`main`/`develop`) or ask.
- For an independent job (e.g. a new feature unrelated to the current work) you may propose
  `main` / the default branch instead; always say why.
- The user can name any other ref. For a branch base pass the plain local branch name (`develop`,
  not `origin/develop` or `refs/heads/develop`); a name that is both a branch and a tag is
  refused by the script (exit 2).

Anything not committed on `<base>` is invisible to the job, in both modes. Say so in the offer
when the working tree is dirty or when `<base>` differs from the current branch.

If it does not qualify, say nothing about delegation and do the job yourself.

## 2. Offer

Ask one question, e.g. (Turkish user):

> Bu işi ikinci hesaba paslayabiliriz — **mod: worktree'de kod değişikliği, `develop` dalından** —
> kapsam: `core/` modülündeki ağ katmanını yeniden düzenlemek. Yapalım mı?

For read-only say **mod: salt-okur analiz, `develop` dalından** instead (in a git repo; outside
one, just **mod: salt-okur analiz**). The offer always names the base, and the repo for write
mode; if the base is not the current branch, or the tree is dirty, add that uncommitted work is
not visible to the job. Wait for the answer.

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
~/.claude/skills/account-delegate/scripts/delegate.sh --mode <ro|write> --cwd "<project dir>" --brief "<brief file>" --base "<base ref>"
```

Always pass `--base` in a git repo; omit it only for a `--cwd` outside any git repo (ro only).

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
missing brief, missing or unresolvable `--base`, `--base` for a non-git `--cwd`, write mode
outside a git repo, a `--cwd` that does not exist on the base, missing config dir or binary). No job was
created: show the stderr message to the user and fix the call; do not treat it as a job
failure.

## 5. When it finishes

Read `<JOB_DIR>/meta.json` and `<JOB_DIR>/result.md`.

- **Success** (`is_error: false`): summarise the report for the user. Mention the cost
  (`total_cost_usd`) and turns in one line. In ro mode inside a git repo the worktree is
  removed automatically; if `meta.worktree` is non-null it was left behind (see `stderr.log`):
  tell the user it was left and where (`worktree remove` without `--force` is theirs to run).
- **Blocked or needed commands** (report section, or `permission_denials` in meta): list them
  and ask the user whether you should run them here. Run only the ones they approve.
- **Write mode:** delegate.sh committed the changes for the job with git hooks disabled and
  with the git dir it pinned before the run, so nothing the job edited (a tracked hooks dir,
  the worktree's `.git` file) ran on this machine. The user's own hooks run normally when you
  merge in their tree.
  - If `commit` is null and `commit_failed` is false, there were no changes: remove the
    worktree (`git -C <repo> worktree remove <JOB_DIR>/worktree`), delete the branch
    (`git -C <repo> branch -d delegate/<id>`) and say so. The branch still points at
    `base_commit`, so `-d` accepts it while that commit is in the history of the user's current
    branch; if `-d` refuses (e.g. the base differs from the current branch and is not in its
    history), say so and leave the branch for the user; never use `-D` unprompted.
  - If `commit_failed` is true, the worktree holds the only copy of the work: do NOT remove it
    unless the user says so. Show the end of `stderr.log` and ask how to proceed.
    - If `stderr.log` says the worktree's `.git` was changed or removed, the job tampered with
      git metadata. Run NO git command inside `<JOB_DIR>/worktree` (not even `git status`): its
      `.git` may point at a git dir whose config runs commands. Tell the user plainly, list the
      files with plain tools (`ls -la`), and leave the cleanup to them.
    - Otherwise also show `git -C <JOB_DIR>/worktree status`.
  - Otherwise (a commit on `delegate/<id>`):
    1. The merge target is `meta.base`, but only when it is a local branch
       (`git -C <repo> show-ref -q --verify refs/heads/<base>`). For anything else (`origin/x`,
       `HEAD`, a tag, a sha) ask where to merge. Check the user's current branch
       (`git -C <repo> branch --show-current`; empty when detached). If it is not `base`, tell
       the user and offer explicitly: (a) they switch to `base` themselves and you merge,
       (b) you merge into their current branch instead, (c) leave the branch as is. Never switch
       branches yourself, and never merge into a branch the user did not confirm.
       (`start_branch` is informational only.)
    2. Show `git -C <repo> diff --stat <base_commit>...delegate/<id>` and offer the full diff
       (`git -C <repo> diff <base_commit>...delegate/<id>`); if it is small (roughly under 200 lines),
       show it directly. Explicitly point out every change to git hooks (`.githooks/`,
       `.husky/`, `.hooks/`, the dir in `core.hooksPath`), CI config (`.github/workflows/`,
       `.gitlab-ci.yml`, ...), and build or package scripts (`build.gradle*`, `package.json`
       scripts, `Makefile`, shell scripts) and show those hunks in full: they run code on the
       user's machine or CI once merged, and hooks in a tracked hooks dir already run during
       the merge commit.
    3. Ask "birleştireyim mi?". On yes (ask first if the user's working tree has uncommitted
       changes that could conflict), run `git -C <repo> merge --no-ff --no-edit delegate/<id>`;
       on conflict run `git -C <repo> merge --abort` and ask the user. After a successful
       merge remove the worktree and delete the branch with `git branch -d` (never `-D`). On
       no, leave the branch and remove only the worktree; use `-D` only if the user explicitly
       says to discard it.
  - Never use `--force` when removing a worktree; if removal is refused, tell the user.
- **Failure** (`is_error: true`, non-zero `exit_code`, or empty `result.md`): also check
  `meta.worktree` for a failed ro git run and tell the user if a worktree was left (and where).
  Show the last
  ~20 lines of `watch.sh`-formatted events
  (`jq -R -r -f ~/.claude/skills/account-delegate/scripts/format-events.jq < <JOB_DIR>/events.jsonl | tail -n 20`)
  and the end of `stderr.log`, and offer to do the job in this session instead.
  `subtype: error_max_turns` means it hit the turn limit (`DELEGATE_MAX_TURNS`, default 40).
  In write mode a failed job can leave branch `delegate/<id>` (possibly with a commit) and
  `<JOB_DIR>/worktree`: tell the user what was left and ask before removing anything.

Job dirs live in `DELEGATE_CACHE_DIR` (default `~/.cache/claude-delegate`) and are kept for
reference; nothing cleans them automatically.
