# Grove — Architecture Brainstorm

A grove of agents. Easy to check in on any of them. Human in the loop when you
want to be, autonomous when you don't.

Core engine first. Attach a TUI if you want. Attach a web UI if you want.
The engine is the product.

---

## What Grove is

Grove manages a **grove of agents** — each running in its own isolated
worktree, each in its own detached session. You can:

- Spin up agents on branches
- See what they're all doing at a glance
- Drop into any one of them to steer, approve, or course-correct
- Leave them running while you do something else
- Review what they've produced (diffs, not vibes)

It's a process supervisor for coding agents. Like pm2 or supervisord, but
purpose-built for the agent-per-branch workflow.

---

## CLI: git-style commands

Commands mirror git so they're already in your muscle memory.

```
grove init                        # init grove in this repo
grove checkout feat/auth          # worktree + agent session on existing branch
grove checkout -b feat/new        # create branch + worktree + session
grove branch                      # list active sessions (like git branch)
grove status                      # status of all sessions w/ activity
grove attach feat/auth            # drop into a session's terminal
grove diff feat/auth              # what has the agent changed vs base
grove log feat/auth               # recent output from session
grove send feat/auth "y"          # send raw input to a session
grove approve feat/auth           # shorthand: approve pending prompt
grove kill feat/auth              # stop agent, keep worktree
grove rm feat/auth                # kill + remove worktree + branch cleanup
grove ui                          # launch TUI client
```

### Why these verbs

| grove command    | git parallel        | what it does                          |
|------------------|---------------------|---------------------------------------|
| `checkout`       | `git checkout`      | switch to / create a branch context   |
| `checkout -b`    | `git checkout -b`   | create new branch + context           |
| `branch`         | `git branch`        | list branches (that have sessions)    |
| `status`         | `git status`        | show state of working sessions        |
| `diff`           | `git diff`          | show what changed                     |
| `log`            | `git log`           | show history (of agent output)        |
| `rm`             | `git branch -D`     | delete branch context                 |
| `init`           | `git init`          | initialize grove in a repo            |

New verbs (no git parallel, but natural):
- `attach` — enter a session (like ssh/tmux attach)
- `send` — pipe input to a session
- `approve` — approve a waiting prompt (sugar for `send <id> "y"`)
- `kill` — stop agent but keep the worktree around for review
- `ui` — launch the TUI client

### Agent adapters

Generic byte-stream monitoring works for any agent, but agents like Claude Code
and Codex expose structured output that's far richer than raw terminal bytes.
Agent adapters parse this structured output so the engine knows more:

```
generic adapter (any agent):
  "bytes are flowing"        → status: active
  "no output for 60s"        → status: idle
  "output matches prompt"    → status: waiting_input

claude adapter:
  "reading src/auth.ts"      → activity: reading file
  "editing src/routes.ts"    → activity: editing file
  "tool use: Bash"           → activity: running command
  "Allow / Deny"             → status: waiting_input (permission prompt)
  "45k tokens used"          → metrics: token usage

codex adapter:
  structured output parsing  → same enriched status + activity
```

The engine ships a generic adapter. Agent-specific adapters are optional
plugins. You get basic status for any agent out of the box, and rich
status for agents that support it.

### Triage workflow (lazy-grove)

The real workflow isn't watching agents work — it's reviewing what they
produced. Like lazygit for agent output:

```
grove — myproject                                    4 sessions

  feat/auth        ● active    +87 -12  3 files
  feat/payments    ⚠ waiting   +245 -31  8 files
  fix/login-bug    ◐ thinking  +12 -4   1 file
  refactor/db      ■ done      +156 -89  6 files

─────────────────────────────────────────────────────────────
  refactor/db — diff vs main

  src/db/connection.ts                    +34 -22
  src/db/migrations/004_indexes.ts        +45 (new)
  src/db/queries.ts                       +77 -67

  @@ -15,7 +15,20 @@
   import { Pool } from 'pg';
  -const pool = new Pool(config);
  +const pool = new Pool({
  +  ...config,
  +  max: 20,
  +  idleTimeoutMillis: 30000,

  [enter] expand  [a]pprove  [r]eject  [j/k] files  [q] back
```

You don't tend a grove by staring at each tree. You walk through, check
the ones that need attention, and move on.

---

## Architecture: engine + clients

```
┌─────────────────────────────────────────────────────────────────┐
│                          clients                                │
│                                                                 │
│   grove cli        grove tui        grove web        your app   │
│   (bash)           (Go/Rust)        (future)         (API)      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                       grove engine                              │
│                                                                 │
│   ┌─────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│   │  session    │  │  worktree    │  │  event stream         │ │
│   │  manager    │  │  manager     │  │                       │ │
│   │             │  │              │  │  agent.started         │ │
│   │  create     │  │  create      │  │  agent.output          │ │
│   │  attach     │  │  setup       │  │  agent.idle            │ │
│   │  detach     │  │  teardown    │  │  agent.stopped         │ │
│   │  send keys  │  │  diff        │  │  agent.waiting_input   │ │
│   │  capture    │  │              │  │                       │ │
│   │  status     │  │              │  │  (any client can       │ │
│   │             │  │              │  │   subscribe)           │ │
│   └──────┬──────┘  └──────────────┘  └───────────────────────┘ │
│          │                                                      │
│   ┌──────▼──────────────────────────────────────┐              │
│   │  session backend (pluggable)                │              │
│   │                                              │              │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────────┐ │              │
│   │  │  dtach   │  │  tmux   │  │  direct pty │ │              │
│   │  └─────────┘  └─────────┘  └─────────────┘ │              │
│   └─────────────────────────────────────────────┘              │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐  │
│   │  agent 1  │  │  agent 2  │  │  agent 3  │  │  agent N  │  │
│   │  claude   │  │  claude   │  │  aider    │  │  codex    │  │
│   │           │  │           │  │           │  │           │  │
│   │  feat/auth│  │  feat/pay │  │  fix/bug  │  │  refactor │  │
│   └───────────┘  └───────────┘  └───────────┘  └───────────┘  │
│        git worktrees (.worktrees/)                              │
└─────────────────────────────────────────────────────────────────┘
```

The engine is a **daemon** that:
1. Manages agent sessions (create, monitor, attach, kill)
2. Manages worktrees (create, setup via Grovefile, teardown)
3. Emits an event stream that any client can subscribe to
4. Exposes a Unix socket API

Clients are thin. They consume the API and render it however they want.

---

## The engine

### What it manages

Each agent in the grove is a **session**:

```
session {
    id:        "feat-auth"
    branch:    "feat/auth"
    worktree:  ".worktrees/feat-auth"
    agent:     "claude --dangerously-skip-permissions"
    status:    active | thinking | idle | waiting_input | stopped
    started:   1708956000
    last_output: 1708956300
    socket:    "/tmp/grove/myproject/feat-auth.sock"
}
```

### Session lifecycle

```
grove checkout feat/auth
  │
  ├── create worktree (if needed)
  ├── run grove_setup() (if defined)
  ├── start session backend (dtach/tmux)
  ├── launch agent command in session
  ├── register in session registry
  └── start monitoring output
        │
        ├── bytes flowing → status: active
        ├── no bytes, process alive → status: thinking
        ├── no bytes for 60s+ → status: idle
        ├── prompt pattern detected → status: waiting_input
        └── process exited → status: stopped
```

### Status detection

Status comes from watching the byte stream. No agent-specific APIs needed.

```
active          bytes received in last 5s
thinking        process alive, no bytes in 5-60s
idle            no bytes for 60s+
waiting_input   output matches known prompt patterns:
                  - "Allow" / "Deny" (claude)
                  - "(Y)es / (N)o" (aider)
                  - "?" at end of line
                  - configurable in Grovefile
stopped         process exited
```

The `waiting_input` status is the key one for human-in-the-loop. The engine
detects when an agent is asking for permission and surfaces it. A client can
then show a notification, and the human can jump in or auto-approve.

### API (Unix socket, JSON)

```
grove.sessions.list        → [session, session, ...]
grove.sessions.get <id>    → session
grove.sessions.create      → { branch, agent?, attach? }
grove.sessions.kill <id>   → ok
grove.sessions.attach <id> → hands off PTY to client
grove.sessions.send <id>   → send bytes to session stdin
grove.sessions.capture <id> → last N lines of output
grove.sessions.diff <id>   → git diff vs base branch

grove.events.subscribe     → event stream (SSE / newline-delimited JSON)
```

This is the interface contract. Any client that speaks JSON over a Unix socket
can drive Grove. The CLI, the TUI, a web UI, a Slack bot, a CI system — all
equal citizens.

### Session backends

The engine abstracts over how sessions are actually run:

**dtach** (recommended)
- Lightest weight. Raw PTY forwarding over Unix socket.
- Engine taps the socket for output monitoring + VT parsing.
- Attach = connect client terminal to dtach socket.
- Send keys = write bytes to socket.
- Capture = engine maintains a ring buffer of recent output per session.

**tmux** (fallback / compatibility)
- Heavier but battle-tested. Everybody has it.
- Capture = `tmux capture-pane`.
- Send keys = `tmux send-keys`.
- Attach = `tmux attach-session`.

**direct PTY** (simplest)
- Engine owns the PTY directly. No external tool.
- Maximum control, but must implement detach/reattach.
- Most work to build, cleanest result.

The engine starts with one backend. Abstracts it behind an interface so the
others can be added later.

---

## The clients

### CLI (`grove` — bash, already exists)

The current bash script with git-style commands:

```bash
grove checkout feat/auth    # worktree + session
grove checkout -b feat/new  # new branch + worktree + session
grove branch                # list sessions
grove status                # session status with activity
grove attach feat/auth      # drop into session
grove diff feat/auth        # what the agent changed
grove log feat/auth         # recent agent output
grove approve feat/auth     # approve pending prompt
grove rm feat/auth          # kill + cleanup
```

For simple workflows this is all you need. No daemon, no engine — just the
bash script calling tmux/dtach directly. The engine is optional.

When the engine IS running, the CLI talks to it instead of managing
tmux/dtach directly. Same commands, richer output (agent adapter data,
status indicators, event awareness).

### TUI (`grove ui`)

A terminal dashboard. Shows the grove at a glance.

```
 grove — myproject                                 4 sessions  2 waiting

 ┌─ Sessions ──────────────────────┬─ Preview ──────────────────────────────┐
 │                                 │                                        │
 │  ● feat/auth          3m ago   │  I'll implement the JWT refresh token  │
 │  ⚠ feat/payments      waiting  │  logic. Let me start by reading the    │
 │  ◐ fix/login-bug      thinking │  existing auth middleware...           │
 │  ○ refactor/db        idle     │                                        │
 │                                 │  Read src/middleware/auth.ts           │
 │                                 │                                        │
 │                                 │  Now I'll update the token refresh     │
 │                                 │  endpoint:                             │
 │                                 │                                        │
 │                                 │  Edit src/routes/auth.ts               │
 │                                 │                                        │
 ├─────────────────────────────────┴────────────────────────────────────────┤
 │ [enter] attach  [n]ew  [d]iff  [y] approve  [K]ill  [q]uit             │
 └──────────────────────────────────────────────────────────────────────────┘
```

The TUI is a client. It subscribes to the engine's event stream, renders
sessions, and sends commands back. It doesn't manage anything itself.

Key features:
- **Preview pane** — last N lines from the selected session's output
- **Status indicators** — derived from engine events, not polled
- **`y` to approve** — when an agent is `waiting_input`, one keystroke approves
- **`enter` to attach** — drops into the agent's terminal fullscreen
- **`d` for diff** — shows what the agent has changed vs base branch

### Web UI (future)

Same engine API, different renderer. The event stream maps naturally to
WebSocket or SSE. A web dashboard could show:

- All sessions with live status
- Preview/output streaming
- Diff viewer (rendered HTML, not terminal)
- Approve/reject from a browser (phone, iPad, etc.)

Not a priority. But the engine makes it possible without any backend work.

---

## What makes this different

### 1. Engine-first, UI-second

Everyone else builds a TUI that IS the tool. Claude Squad is a Go TUI.
Orchestra is a Rust TUI. You close the TUI, you lose your management layer.

Grove's engine runs independently. The TUI is optional. The web UI is optional.
The CLI works without either. You can manage your grove from a phone browser,
a tmux split, or a cron job. Same API, same events.

### 2. Grovefile

Per-repo, declarative, travels with the code:

```bash
GROVE_PROJECT="myapp"

grove_setup() {
    npm install
}

grove_windows() {
    grove_window "server" "npm run dev"
    grove_window "agent" "claude --dangerously-skip-permissions"
}

# NEW: prompt patterns for waiting_input detection
grove_prompts() {
    grove_prompt "Allow"          # claude permission prompt
    grove_prompt "(Y)es"          # aider confirmation
    grove_prompt "Continue?"      # generic
}
```

Clone a repo with a Grovefile. Run `grove checkout feat/whatever`. Done. The
environment configures itself.

### 3. Human-in-the-loop as a first-class feature

The `waiting_input` status detection + event stream means you know the moment
any agent needs you. You get a notification (terminal bell, desktop
notification, webhook — whatever the client supports). You jump in, approve or
redirect, jump out. The rest of the grove keeps running.

This is the actual workflow: not staring at agents, not fully autonomous.
Tending your grove. Checking in when needed.

### 4. Actually open source, actually an idea

Not a Cursor marketing video. Not a demo that falls apart. A real tool that
solves a real problem: managing parallel coding agents with human oversight.

The core engine is < 1000 lines. The CLI is 720 lines of bash. The whole thing
should be understandable by reading the source.

---

## Implementation plan

### Phase 1: engine core

The engine as a standalone daemon, with the CLI as the first client.

1. **Session registry** — in-memory, backed by a JSON file in `.grove/`
2. **Session backend: tmux** — start with what grove already uses
3. **Output monitoring** — tail tmux panes, detect status from byte flow
4. **Unix socket API** — JSON protocol, the interface contract
5. **CLI integration** — `grove` talks to the engine when it's running,
   falls back to direct tmux when it's not

Ship this. It's useful standalone — `grove branch` and `grove status` show
richer info, the CLI gains `grove approve` and `grove log` commands.

### Phase 2: TUI

A terminal client that subscribes to the engine.

1. **Session list** with live status from event stream
2. **Preview pane** using `grove.sessions.capture`
3. **Attach/detach** flow
4. **Diff view** using `grove.sessions.diff`
5. **Approve shortcut** — `y` sends approval to `waiting_input` sessions

### Phase 3: dtach backend

Replace tmux with dtach for lighter sessions.

1. **dtach session management** — create/attach/detach
2. **VT parser** — maintain screen buffer per session for capture
3. **Output monitoring** — tap dtach sockets for status detection
4. **Backend config** — `GROVE_SESSION_BACKEND` in Grovefile

### Phase 4: web UI

A browser client consuming the same engine API.

1. **WebSocket bridge** — proxy engine events to the browser
2. **Dashboard** — session list, status, preview
3. **Diff viewer** — rendered HTML diffs
4. **Approve from anywhere** — phone, iPad, remote

---

## Language choice

The engine needs to:
- Run as a daemon
- Manage PTYs / subprocesses
- Serve a Unix socket API
- Parse terminal output (VT sequences)
- Be distributable as a single binary

| Option             | Verdict                                               |
|--------------------|-------------------------------------------------------|
| **Go**             | Best ecosystem for this exact problem. bubbletea for  |
|                    | TUI, goroutines for concurrent session monitoring,    |
|                    | single binary. Claude Squad proves the stack works.   |
| **Rust**           | Better perf, harder to iterate. Worth it if VT        |
|                    | parsing performance matters (10+ concurrent streams). |
| **Bash (engine)**  | No. Can't do daemon, socket API, or VT parsing.       |
| **Bash (CLI)**     | Yes. Keep the existing CLI as the lightweight client.  |

**Recommendation: Go for engine + TUI. Bash stays for the CLI.**

The existing `grove` bash script remains as the zero-dependency entry point.
When the engine is running, it becomes a thin client. When it's not, it works
exactly as it does today.

---

## Open questions

1. **Daemon lifecycle** — who starts the engine? `grove init --daemon`?
   Auto-start on first `grove checkout`? Systemd/launchd service? Should it
   even be a long-running daemon, or a short-lived process that starts on demand?

2. **Multi-repo** — should one engine manage multiple repos? Or one engine
   per repo? Per-repo is simpler and matches the Grovefile convention.

3. **Agent lifecycle** — should grove restart crashed agents? Auto-retry?
   Or just report the status and let the human decide? (Leaning toward the
   latter — opinionated minimalism.)

4. **Auth for web UI** — if the web UI exists, how do you secure it?
   Local-only? Token-based? This is a future problem but worth noting.

5. **Config location** — engine state lives where? `.grove/` in the repo root
   (next to `.worktrees/`)? XDG dirs? Repo-local is simpler and more portable.

6. **Name** — is the engine also called `grove`? Or `groved` (grove daemon)?
   `grove-engine`? Single binary with subcommands (`grove engine start`)?
