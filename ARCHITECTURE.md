# Grove — What's next

What already works (v0.3.0): worktrees, dtach sessions, agent auto-detect,
status, diff, log, output, attach, Grovefile. The plumbing is solid.

What's missing: **the human-in-the-loop layer.** You can spawn agents and
attach to them. You can't meaningfully oversee them without attaching.

---

## The gap

Right now, managing 5 agents looks like this:

```
gr status                    # see they're running... cool
gr attach feat/auth          # attach, see what's happening, detach
gr attach feat/payments      # attach, see what's happening, detach
gr attach fix/bug            # attach, oh it's waiting for approval
                             # type y, detach
gr attach refactor/db        # attach, it's idle... is it done? stuck?
                             # detach
```

That's the tmux/dtach tax. You have to enter each session to know what's
going on. The status command tells you running/waiting/done, but not:

- **What** it's waiting for (permission prompt? stuck? confused?)
- **What** it's actually done (diff stats, files changed)
- **How** to approve without attaching (send input from outside)

---

## What we're adding

### 1. `grove send` — the human-in-the-loop primitive

Write bytes directly to a dtach socket without attaching.

```bash
grove send feat/auth "y"              # approve a prompt
grove send feat/auth "/help"          # send a command
grove send fix/bug "try a different approach, the tests are in test/"
```

Implementation: open the dtach socket and write bytes + newline.

```bash
cmd_send() {
    local branch="$1" text="$2"
    local slug wt_dir socket
    slug="$(slugify_branch "$branch")"
    wt_dir="$GROVE_ROOT/$GROVE_WORKTREE_DIR/$slug"
    socket="$(grove_socket_path "$wt_dir")"

    # dtach sockets are Unix domain sockets — write raw bytes
    # Use dtach's -p flag to push characters to the session
    printf '%s\n' "$text" | dtach -p "$socket"
}
```

This is the single most important missing feature. Everything else builds
on it.

### 2. `grove approve` — one-command approval

```bash
grove approve feat/auth          # send "y" + enter
grove approve --all              # approve all waiting agents
```

Sugar for `grove send <branch> "y"`. The `--all` flag approves every
session with `waiting` status. That's your "check the grove, approve
the batch" workflow.

### 3. Smarter status — prompt detection, not just timers

Current status detection:

```
running     = output in last 10s
waiting     = no output for 10s+
done        = dtach socket gone
```

This is lossy. An agent thinking for 15s shows as "waiting" when it's
actually working. An agent stuck on a prompt for 5s shows as "running."

Better: scan the log tail for known prompt patterns.

```bash
get_agent_status() {
    local wt_dir="$1"
    if ! is_agent_running "$wt_dir"; then
        echo "done"; return
    fi

    local log_file
    log_file="$(grove_log_path "$wt_dir")"

    # Check last few lines for prompt patterns
    local tail
    tail="$(tail -5 "$log_file" 2>/dev/null | strip_ansi)"

    # Known prompt patterns
    if echo "$tail" | grep -qiE '(Allow|Deny|yes.*no|y/n|approve|reject|Continue\?)'; then
        echo "waiting"
        return
    fi

    # Fall back to time-based
    local age
    age=$(( $(date +%s) - $(file_mtime "$log_file") ))
    if [[ "$age" -le 10 ]]; then
        echo "running"
    elif [[ "$age" -le 120 ]]; then
        echo "thinking"
    else
        echo "idle"
    fi
}
```

New states:

```
● running    bytes in last 10s, no prompt detected
◐ thinking   no output 10-120s, process alive (API call, long operation)
⚠ waiting    prompt pattern detected in output tail
○ idle       no output 120s+, process alive (stuck? done thinking?)
■ done       process exited
```

The `thinking` state is the key addition. It means "the agent is alive
and working, just not producing output yet." This is normal for LLM
agents — they spend a lot of time waiting for API responses.

### 4. Diff stats in status

The `get_diff_stat()` function exists but isn't shown in `grove status`.
Add it:

```
BRANCH                   AGENT      STATUS    CHANGES           ACTIVITY
feat/auth                claude     running   +87 -12 (3)       editing src/auth.ts
feat/payments            claude     waiting   +245 -31 (8)      Allow edit? [Y/n]
fix/login-bug            claude     thinking                    reading test files...
refactor/db              claude     done      +156 -89 (6)      12m ago · "refactor db"
```

Now `grove status` (or just `gr`) is a real dashboard. You see at a
glance: what's running, what's waiting, what's done, and how much each
agent has produced.

### 5. `grove kill` — stop agent, keep worktree

```bash
grove kill feat/auth          # stop agent, keep worktree for review
grove rm feat/auth            # stop agent AND remove worktree + branch
```

Currently `rm` does both. But sometimes you want to stop a runaway agent
and review its work before deciding to keep or discard. `kill` gives you
that.

### 6. Notifications

When an agent hits `waiting` status, optionally notify:

```bash
# Terminal bell (works in most terminals)
printf '\a'

# macOS notification
osascript -e 'display notification "feat/auth needs approval" with title "grove"'

# Generic: configurable hook
if declare -f grove_notify >/dev/null 2>&1; then
    grove_notify "$branch" "$status"
fi
```

Configurable in Grovefile:

```bash
grove_notify() {
    local branch="$1" status="$2"
    # your notification logic
}
```

Or just the terminal bell by default. The bell rings, you glance at
`grove status`, approve what needs approving, move on.

---

## Implementation order

Each step ships independently. Each makes grove more useful.

### Step 1: `send` + `approve`
- `cmd_send()` — write to dtach socket
- `cmd_approve()` — sugar for send "y"
- `grove approve --all`
- Wire into main dispatch

**~30 lines of bash.** Biggest bang for least effort.

### Step 2: smarter status
- Prompt pattern detection in `get_agent_status()`
- Add `thinking` state (10-120s no output)
- Diff stats in `cmd_status()` output
- Better formatting: status indicators (● ◐ ⚠ ○ ■), aligned columns

**~50 lines changed.** Makes `grove status` a real dashboard.

### Step 3: `kill` command
- `cmd_kill()` — calls `kill_agent()` without removing worktree
- Update help text

**~15 lines.**

### Step 4: notifications
- Terminal bell on status change to `waiting`
- `grove_notify()` hook in Grovefile
- macOS native notification if available

**~20 lines.**

### Step 5 (future): TUI
- Separate binary (Go + bubbletea)
- Reads same state: worktree dirs, dtach sockets, log files
- Calls `grove` commands or dtach directly
- Live-updating dashboard with preview pane
- Inline diff view
- The lazy-grove triage workflow

This is the only step that requires a new binary. Everything before it
is pure bash additions to the existing script.

---

## What this gets you

Before (v0.3.0):
```
gr status                        # running / waiting / done
gr attach feat/auth              # only way to see what's happening
                                 # only way to approve
```

After:
```
gr                               # dashboard: status + diff stats + activity
gr approve --all                 # approve everything waiting, don't even attach
gr send feat/auth "try tests/"   # redirect an agent without attaching
gr kill feat/auth                # stop a runaway, review its work later
```

The difference: you manage your grove **from the outside**. Check in when
you want to. Approve, redirect, or kill from the command line. Only attach
when you actually need to take the wheel.

That's the product. Not a TUI. Not a web dashboard. A CLI that lets you
tend a grove of agents without context-switching into each one.
