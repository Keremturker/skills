---
name: account-delegate
description: >-
  Offer to hand a self-contained job (analysis, research, review, or a code change in an
  isolated git worktree) to a second Claude Code account configured on this machine, run it
  headless in a side cmux pane, and bring the report back into this session. Use when the
  user wants to spend the second account's quota, says "şirket hesabına pasla", "ikinci hesaba pasla", "bunu diğer
  hesaba yaptır", "delegate this to the other account", "planı şirket hesabıyla yürüt", "execute this plan on the other account", or when you are about to start a
  sizeable, self-contained job and the second account is configured. Also offers to execute a written implementation plan task by task on the second account while this session reviews every task. Never delegates
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
cmux new-split right --focus false --command "~/.claude/skills/account-delegate/scripts/watch.sh '<JOB_DIR>' && { printf '\nClosing in 5s'; sleep 5; } || { printf '\nPress Enter to close'; read _; }"
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
  tell the user it was left and where. If `stderr.log` says its `.git` was changed or removed,
  run NO git command in it (its `.git` may point at a git dir whose config runs commands) and
  tell the user to delete it with plain tools (`rm -rf <JOB_DIR>/worktree`) and then run
  `git -C <repo> worktree prune`; otherwise `git -C <repo> worktree remove <JOB_DIR>/worktree`
  (never `--force`) is theirs to run.
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
    - Otherwise also show the status, but never with plain `git` inside the worktree (a nested
      repo's own config could run): use the git dir pinned in `meta.gitdir`,
      `git --git-dir=<meta.gitdir> --work-tree=<JOB_DIR>/worktree -c core.hooksPath=/dev/null -c core.fsmonitor=false status --ignore-submodules=all`.
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

## 6. Plan mode (execute an implementation plan)

The second account writes the code task by task; this session reviews every task itself (no
review subagents: that keeps this account's quota low).

### When to offer

An implementation plan is written (e.g. by `superpowers:writing-plans`), the second account is
configured, the repo is a git repo, and the tasks meet section 1's criteria. This replaces the
usual execution-method question: ask once, e.g.

> Bu planı şirket hesabıyla yürüteyim mi? — kod şirket hesabında, kontrol bende; `develop`
> dalından, 5 görev, görev başına en fazla 3 düzeltme turu. Commit'lenmemiş değişiklikler işe
> görünmez.

Yes covers every task and fix round of this plan. No → `superpowers:subagent-driven-development`.

**Split the plan before offering.** Mark each task in the plan as *second account* (code and
docs edits) or *this session*: anything needing an emulator/simulator, network, package
installs, push or publishing (smoke runs, UI tests such as Maestro, releases) always stays here.
Only *second account* tasks are counted in the offer and delegated; run the others here in plan
order. If those tasks span several repos, use one `PLAN_DIR` per repo (each with its own
`--cwd`/`--base`) and name every repo and base in the offer.

### Setup

`PLAN_DIR="${DELEGATE_CACHE_DIR:-$HOME/.cache/claude-delegate}/plans/<YYYYMMDD-HHMMSS>-<slug>"`
(slug: `[a-z0-9-]`). Create `PLAN_DIR/progress.md` yourself (the script never touches it):
plan file path, base, and one line per task — status (`pending` / `running` / `done` /
`stopped`), job numbers, session id, fix rounds, cost. Update it after every job.

**Git in the plan worktree.** The worktree is a tree the second account controlled: never run
plain `git` (not even `git status`) inside `<PLAN_DIR>/worktree`, and never `git -C` it. Use the
git dir pinned in `PLAN_DIR/plan.json` (`gitdir`), called `<pgit>` below:
`git --git-dir=<plan.json gitdir> --work-tree=<PLAN_DIR>/worktree -c core.hooksPath=/dev/null -c core.fsmonitor=false`.
Safe status: `<pgit> status --ignore-submodules=all` (diff the same way, with
`--ignore-submodules=all`). Section 5's `<JOB_DIR>/worktree` does not exist in plan mode; the
worktree is always `<PLAN_DIR>/worktree`.

### Per task

1. **Brief** (scratchpad file, user's language): the task's text copied **verbatim** from the
   plan (the plan file may not be committed on the base, so never just point at it); short
   project context (repo, decisions, things not to touch); the rules from the project's rule
   files (CLAUDE.md, AGENTS.md, style/convention docs) that apply to this task, copied in, since
   the second account may not load them; one line per finished task; "if you cannot run a build
   or test command, list it under Blocked".
2. **Run** with `run_in_background: true`, then open the side pane as in section 4:

   ```bash
   ~/.claude/skills/account-delegate/scripts/delegate.sh --mode write --plan "<PLAN_DIR>" \
     --cwd "<repo dir>" --brief "<brief file>" --title "Task <n>: <name>" [--base "<base ref>"]
   ```

   `--base` only for the first job of the plan (it creates `PLAN_DIR/plan.json`, the worktree
   `PLAN_DIR/worktree` and branch `delegate/<plan id>`, plan id = basename of `PLAN_DIR`); every
   later job must omit it and pass the same `--cwd`. Exit 2 with no `JOB_DIR=` is a refusal
   (bad flags, held lock, tampered `.git`, worktree not on the plan branch, uncommitted changes
   in the plan worktree): show the message, do not retry blindly. For uncommitted changes, show
   `<pgit> status --ignore-submodules=all` (see Setup).
3. **Review** (this session):
   - Read `<JOB_DIR>/meta.json`; errors and denials → *Stop and ask* below.
   - `git -C <repo> diff --stat <parent_commit>..<commit>`, then read only the relevant hunks
     (`git -C <repo> diff <parent_commit>..<commit> -- <paths>`). Use the main repo, never
     `-C <PLAN_DIR>/worktree`: git must not find its git dir through the agent's `.git` file.
     `commit` null with `commit_failed` false means the job changed nothing.
   - Spec compliance first (everything the task asked, nothing more), then code quality.
   - **Safety gate:** if the task's diff touches build, hook, CI or script files
     (`build.gradle*`, `settings.gradle*`, `gradle/`, `package.json`, `Makefile`, `*.sh`,
     `.githooks/`, `.husky/`, `.hooks/`, the `core.hooksPath` dir, `.github/workflows/`,
     `.gitlab-ci.yml`, ...), show those hunks in full and get the user's yes **before** running
     any build or test there. The plan-level yes does not cover this.
   - Run the task's test/verification commands inside `<PLAN_DIR>/worktree`.
   - Then check the worktree is clean (`<pgit> status --ignore-submodules=all`); otherwise the
     next job refuses with "uncommitted changes". If this session changed files on purpose (a fix
     made here, or "you finish it here" / "you do the task here"), show
     `<pgit> diff --ignore-submodules=all` and commit them: first confirm
     `<PLAN_DIR>/worktree/.git` is unchanged (`od -An -tx1 < <PLAN_DIR>/worktree/.git | tr -d ' \n'`
     equals `plan.json.gitfile_hex`; if not, stop as for a changed `.git`), then from inside
     `<PLAN_DIR>/worktree` run `<pgit> add -- <the paths you changed>` (not `add -A`: it runs git
     inside nested repos) and `<pgit> commit --no-verify -m "delegate(<plan id>): Task <n> (main session)"`.
     Build/test output nobody wants: remove it only with the user's yes.
4. **Fix round** if anything is wrong: write the findings as a brief and run the same command
   with `--resume <session_id of this task's last job>` and `--title "Task <n> fix <k>"` (no
   `--base`). Then review again. At most 3 fix rounds per task.
5. **Done:** update `progress.md`, tell the user one line (task, rounds, cost), next task.

Section 5's per-job cleanup (worktree remove, `branch -d` when `commit` is null) does not apply
in plan mode: never remove the plan worktree or branch before the end of the plan.

### Stop and ask

- Still wrong after 3 fix rounds → show the remaining findings; options: you finish it here /
  one more round with a fresh brief and no `--resume` / stop the plan.
- `permission_denials` or a "Blocked" section → list the commands, ask which to run here, run
  only those.
- Job failure (`is_error`, `error_max_turns`, empty `result.md`) → last ~20 formatted events and
  the end of `stderr.log`; options: retry / you do the task here / stop the plan. A failed or
  killed job may already have committed partial work (`meta.commit` non-null, or the branch tip
  moved past `parent_commit`): review that commit before retrying. Retry: if `PLAN_DIR/plan.json`
  exists, omit `--base`, even for task 1; if it does not (the first job failed before the plan
  was created, e.g. branch `delegate/<plan id>` already exists — see `result.md`), fix the cause
  and retry with `--base` on the same `PLAN_DIR`.
- `.git` changed or removed (exit 2 naming `.git`, or `stderr.log` says so) → stop the plan, run
  no git command inside the worktree, leave cleanup to the user as in section 5.
- `commit_failed` true → the worktree holds the only copy; touch nothing, show the end of
  `stderr.log` and `<pgit> status --ignore-submodules=all` (never plain `git status` there), ask.
  The next plan job refuses to start until the worktree is clean.
- Safety gate (above).

### End of plan

Summarise: tasks, total cost, total fix rounds. Then follow section 5's write-mode merge rules
with `delegate/<plan id>` as the branch, `plan.json.base` as `base`, `plan.json.base_commit` as
`base_commit` and `<PLAN_DIR>/worktree` as the worktree: `git -C <repo> diff --stat
<base_commit>...delegate/<plan id>`, hook/CI/build hunks in full, "birleştireyim mi?",
`--no-ff`, never switch branches, never `-D` or `--force` unprompted.

### Resuming

After an interruption or `/clear`, read `PLAN_DIR/progress.md` and continue from the first task
that is not `done`. A handoff note names `PLAN_DIR` and `progress.md`.
