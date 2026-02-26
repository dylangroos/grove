# Grove — Architecture

Simple plan. Build incrementally. Each phase ships something useful.

---

## What exists today (v0.2.0)

A 720-line bash script that manages git worktrees + tmux sessions.

```
grove <branch>          →  worktree + tmux session
grove attach <branch>   →  attach to session
grove ls                →  list worktrees + session status
grove rm <branch>       →  kill session + remove worktree
grove init              →  generate Grovefile
```

Worktrees live in `.worktrees/`. Sessions named `grove-{project}-{slug}`.
Grovefile defines `grove_setup()` and `grove_windows()`. It works.

---

## Target architecture

```
                ┌──────────────────────────────────┐
                │           grove CLI              │
                │         (bash script)            │
                │                                  │
                │  grove checkout feat/auth        │
                │  grove branch                    │
                │  grove status                    │
                │  grove diff feat/auth            │
                │  grove log feat/auth             │
                │  grove attach feat/auth          │
                │  grove approve feat/auth         │
                └────────────┬─────────────────────┘
                             │
                     reads / writes
                             │
                             ▼
                ┌──────────────────────────────────┐
                │         .grove/ state            │
                │                                  │
                │  sessions.json   ← registry      │
                │  log/            ← output logs   │
                │    feat-auth.log                 │
                │    fix-bug.log                   │
                └──────────────────────────────────┘
                             │
                      manages / monitors
                             │
                ┌────────────┴─────────────────────┐
                │                                  │
         ┌──────▼──────┐                    ┌──────▼──────┐
         │    tmux     │                    │    tmux     │
         │   session   │         ...        │   session   │
         │  feat-auth  │                    │  fix-bug    │
         └──────┬──────┘                    └──────┬──────┘
                │                                  │
         ┌──────▼──────┐                    ┌──────▼──────┐
         │  .worktrees │                    │  .worktrees │
         │  /feat-auth │                    │  /fix-bug   │
         └─────────────┘                    └─────────────┘
```

No daemon. No socket API. No separate binary. Just the bash script,
a state directory, and tmux. The engine is the script + the state files.

A daemon / TUI / web UI can come later by reading the same state files
and talking to the same tmux sessions. But v1 is just the CLI.

---

## State: `.grove/`

Lives at repo root next to `.worktrees/`.

### `sessions.json`

```json
{
  "feat-auth": {
    "branch": "feat/auth",
    "worktree": ".worktrees/feat-auth",
    "tmux_session": "grove-myapp-feat-auth",
    "agent": "claude --dangerously-skip-permissions",
    "status": "active",
    "started": 1708956000,
    "last_output": 1708956300,
    "pid": 12345
  },
  "fix-bug": {
    "branch": "fix/bug",
    "worktree": ".worktrees/fix-bug",
    "tmux_session": "grove-myapp-fix-bug",
    "agent": "claude --dangerously-skip-permissions",
    "status": "idle",
    "started": 1708955000,
    "last_output": 1708955060,
    "pid": 12346
  }
}
```

Written by the CLI on every state change. Read by the CLI (and future
TUI/web) to display status.

### `log/<slug>.log`

Raw output captured from each session. Append-only. Used by `grove log`.

Captured via `tmux pipe-pane` — tmux writes all pane output to a file.
Zero overhead, built into tmux, no polling.

```bash
# When creating a session:
tmux pipe-pane -t "$session:agent" -o "cat >> .grove/log/${slug}.log"
```

---

## Commands

### Phase 1: rename existing commands to git-style

| new command                   | maps to current           | change needed       |
|-------------------------------|---------------------------|---------------------|
| `grove checkout <branch>`    | `grove <branch>`          | rename              |
| `grove checkout -b <branch>` | `grove <branch>` (new)    | add -b flag         |
| `grove branch`               | `grove ls`                | rename              |
| `grove attach <branch>`      | `grove attach <branch>`   | no change           |
| `grove rm <branch>`          | `grove rm <branch>`       | no change           |
| `grove init`                 | `grove init`              | no change           |

Keep `grove <branch>` as a shorthand alias for `grove checkout <branch>`.
Keep `grove ls` as an alias for `grove branch`. No breaking changes.

### Phase 2: new commands (need `.grove/` state)

| command                       | what it does                                      |
|-------------------------------|---------------------------------------------------|
| `grove status`                | list sessions with status (active/idle/waiting)   |
| `grove diff <branch>`        | `git diff main...<branch>` in the worktree        |
| `grove log <branch>`         | tail `.grove/log/<slug>.log`                      |
| `grove send <branch> <text>` | `tmux send-keys` to the agent pane                |
| `grove approve <branch>`     | `grove send <branch> y Enter`                     |
| `grove kill <branch>`        | kill tmux session, keep worktree for review        |

### Phase 3: status detection

Status is derived from the log file. No daemon needed — just check the
file on each `grove status` call:

```bash
grove_detect_status() {
    local log=".grove/log/${slug}.log"
    local tmux_session="$1"

    # Is the tmux session alive?
    if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
        echo "stopped"
        return
    fi

    # When was the last output?
    local last_mod
    last_mod=$(stat -c %Y "$log" 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local age=$(( now - last_mod ))

    # Check last line for prompt patterns
    local last_line
    last_line=$(tail -1 "$log" 2>/dev/null)
    if echo "$last_line" | grep -qE '(Allow|Deny|Y/n|\? )'; then
        echo "waiting"
        return
    fi

    if [ "$age" -lt 5 ]; then
        echo "active"
    elif [ "$age" -lt 60 ]; then
        echo "thinking"
    else
        echo "idle"
    fi
}
```

That's it. Status detection in ~20 lines of bash. No daemon, no VT
parser, no event stream. Just file timestamps and pattern matching.

---

## Status display

### `grove branch`

```
  feat/auth          3 min ago
  fix/login-bug      12 min ago
  refactor/db        idle
```

### `grove status`

```
  ● feat/auth        active     +87 -12   3 files   3m ago
  ⚠ feat/payments    waiting    +245 -31  8 files   1m ago
  ◐ fix/login-bug    thinking   +12 -4    1 file    12m ago
  ○ refactor/db      idle       +156 -89  6 files   45m ago
```

The diff stats come from:
```bash
git diff --stat main...$(git -C ".worktrees/${slug}" rev-parse HEAD)
```

### `grove log feat/auth`

```
  I'll implement the JWT refresh token logic. Let me start by
  reading the existing auth middleware...

  Read src/middleware/auth.ts

  Now I'll update the token refresh endpoint:

  Edit src/routes/auth.ts
```

Just `tail -n 50 .grove/log/feat-auth.log` with some cleanup.

---

## Agent adapters (future, not phase 1)

For now, all agents are treated the same: a command that runs in tmux.
Status comes from byte flow + pattern matching on the log.

Later, agent-specific adapters can parse the log for richer info:

```bash
# In Grovefile
GROVE_AGENT_ADAPTER="claude"   # or "codex", "aider", "generic"
```

The adapter would define:
- Custom prompt patterns for `waiting_input` detection
- Output parsing for structured activity (which file is being edited)
- Token usage extraction

But this is not needed for v1. The generic approach works for everything.

---

## Implementation phases

### Phase 1: git-style commands + state dir

**Changes to `grove` bash script:**

1. Add `checkout` subcommand (calls existing worktree+session creation)
2. Add `branch` subcommand (calls existing `ls` logic)
3. Keep old names as aliases (`grove <branch>` still works)
4. Create `.grove/` and `.grove/log/` on first use
5. Write `sessions.json` on session create/destroy
6. Enable `tmux pipe-pane` to capture output to `.grove/log/`

**Result:** Same tool, new names, session state is now tracked on disk.

### Phase 2: new read commands

1. `grove status` — reads `sessions.json` + log files, shows status table
2. `grove diff <branch>` — runs git diff against main for that worktree
3. `grove log <branch>` — tails the log file for that session

**Result:** You can now see what all your agents are doing and have done
without attaching to each one.

### Phase 3: new write commands

1. `grove send <branch> <text>` — `tmux send-keys` to agent pane
2. `grove approve <branch>` — sugar for `grove send <branch> y Enter`
3. `grove kill <branch>` — kill session, keep worktree

**Result:** Human-in-the-loop from the CLI. Approve prompts without
attaching.

### Phase 4: TUI (separate binary, consumes same state)

A Go/Rust binary that:
1. Reads `.grove/sessions.json` for session list
2. Tails `.grove/log/*.log` for preview + status
3. Calls `grove` commands (or tmux directly) for actions
4. Renders the triage view

The TUI is a **consumer** of the state that the CLI produces. No new
backend needed.

---

## File changes summary

```
grove                     ← modify: add new subcommands
.grove/                   ← new: state directory
  sessions.json           ← new: session registry
  log/                    ← new: output logs directory
    feat-auth.log
    fix-bug.log
.worktrees/               ← existing: no changes
Grovefile                 ← existing: add grove_prompts() hook (optional)
```

That's the whole architecture. A bash script, a JSON file, and some log
files. Everything else is built on top of that.
