# Grove TUI — Interface Brainstorm

Grove already solves the plumbing: git worktrees + tmux sessions, configured
via a Grovefile. Everybody in the multi-agent space (Claude Squad, Multiclaude,
Superset, Orchestra, Conduit) converges on the same architecture. What nobody
has nailed yet is the interface layer.

This doc explores what a Grove TUI could look like.

---

## The landscape (as of Feb 2026)

Every tool in this space uses **tmux + git worktrees**. The differentiators are:

| Tool          | Lang | Session  | TUI?    | Differentiator                         |
|---------------|------|----------|---------|----------------------------------------|
| Claude Squad  | Go   | tmux     | Yes     | Most popular, agent-agnostic           |
| Multiclaude   | Go   | tmux     | No      | "Brownian ratchet" — chaos + CI        |
| Superset      | ?    | tmux     | Desktop | Desktop app, diff viewer               |
| Orchestra     | Rust | tmux     | Yes     | Fast, minimal                          |
| Conduit       | ?    | ?        | Yes     | Tab-based, token tracking              |
| Agent Deck    | ?    | tmux     | Yes     | MCP socket pooling                     |
| **Grove**     | Bash | tmux     | **No**  | Grovefile convention, zero-dep plumbing|

Grove's current advantage: it's the simplest, most Unix-y option. A single
bash script. No runtime, no build step, no framework. The question is whether
to keep that purity or build a proper TUI on top.

---

## Core question: what layer is the TUI?

Two options:

### Option A: TUI as a separate binary, grove stays as-is

```
grove                    # the bash script (plumbing)
grove-tui / grove ui     # the TUI (porcelain)
```

`grove` remains the workhorse. The TUI is a thin layer that calls `grove`
commands and reads state from the filesystem (worktree dirs, tmux/dtach
sessions). Users who don't want the TUI lose nothing.

Pros: grove stays simple, TUI is optional, clean separation
Cons: two binaries, coordination between them

### Option B: TUI built into grove

`grove` gains a `grove ui` subcommand (or `grove` with no args becomes the
TUI). Everything in one binary.

Pros: single install, single tool
Cons: forces a language change (bash can't do a real TUI), the binary gets big

**Recommendation: Option A.** Keep grove as bash plumbing. Build the TUI as a
separate thing that consumes grove's conventions (worktree dirs, session
naming, Grovefile).

---

## dtach vs tmux

### Why consider dtach?

tmux does way more than multi-agent orchestration needs. For agent sessions you
typically need three things:

1. **Detach/reattach** — run an agent in the background, come back later
2. **Screen capture** — peek at what an agent is doing without attaching
3. **Keystroke injection** — send `y\n` to accept a prompt, nudge an idle agent

tmux gives you all three out of the box. dtach gives you (1) and nothing else.

But tmux pays a tax: it interposes a terminal emulator between the app and
your real terminal. This means:
- `TERM` changes to `tmux-256color`
- Escape sequences get translated (lossy)
- Features like kitty keyboard protocol, OSC sequences, etc. break
- Memory overhead per session

dtach forwards raw bytes over a Unix socket. No terminal emulation. No
overhead. The app talks directly to your terminal.

### The missing pieces with dtach

**Screen capture:** dtach doesn't maintain a screen buffer. You can't
`capture-pane`. But you could:
- Run a lightweight VT parser in the TUI process that taps the dtach socket
  and maintains a virtual screen buffer per session
- Use this for previews/status without attaching
- Libraries: vterm (C), vt100 (Rust), node-pty + xterm.js, etc.

**Keystroke injection:** dtach doesn't have `send-keys`. But the Unix socket
is bidirectional. You can:
- Open the dtach socket and write bytes directly
- This is actually simpler than tmux's `send-keys` — no escaping, no
  target specifiers, just raw terminal input

### Architecture with dtach

```
                     ┌──────────────────────────────────┐
                     │           grove-tui              │
                     │                                  │
                     │  ┌──────────┐  ┌──────────────┐  │
                     │  │ session  │  │  VT parser   │  │
                     │  │ list     │  │  (per agent) │  │
                     │  │          │  │              │  │
                     │  │ > agent1 │  │  captures    │  │
                     │  │   agent2 │  │  screen for  │  │
                     │  │   agent3 │  │  preview     │  │
                     │  └──────────┘  └──────────────┘  │
                     │         │              │         │
                     │         │    attach    │  read   │
                     │         ▼              ▼         │
                     └─────────┬──────────────┬────────┘
                               │              │
               ┌───────────────┼──────────────┼───────────┐
               │               │              │           │
        ┌──────▼──────┐ ┌──────▼──────┐ ┌────▼────────┐  │
        │  dtach sock │ │  dtach sock │ │  dtach sock │  │
        │  /tmp/grove │ │  /tmp/grove │ │  /tmp/grove │  │
        │  /agent1    │ │  /agent2    │ │  /agent3    │  │
        └──────┬──────┘ └──────┬──────┘ └─────┬───────┘  │
               │               │              │           │
        ┌──────▼──────┐ ┌──────▼──────┐ ┌────▼────────┐  │
        │   claude    │ │   claude    │ │   aider     │  │
        │   (agent)   │ │   (agent)   │ │   (agent)   │  │
        └─────────────┘ └─────────────┘ └─────────────┘  │
               │               │              │           │
        ┌──────▼──────┐ ┌──────▼──────┐ ┌────▼────────┐  │
        │  worktree/  │ │  worktree/  │ │  worktree/  │  │
        │  agent1     │ │  agent2     │ │  agent3     │  │
        └─────────────┘ └─────────────┘ └─────────────┘  │
               git worktrees (.worktrees/)                │
               ───────────────────────────────────────────┘
```

### Hybrid option: support both

Start with tmux (grove already uses it). Add dtach as an alternative backend
behind a config flag. Let the TUI abstract over both:

```bash
# Grovefile
GROVE_SESSION_BACKEND="dtach"  # or "tmux" (default)
```

The TUI talks to whichever backend is configured. This lets people who already
have tmux workflows keep them, while making dtach available for people who want
lighter sessions or better terminal fidelity.

---

## TUI interface design

### Main screen: session list

```
 grove — myproject                                           3 agents running

 ┌─ Sessions ──────────────────────┬─ Preview ──────────────────────────────┐
 │                                 │                                        │
 │  ● feat/auth          3m ago   │  $ claude                              │
 │    feat/payments      idle     │                                        │
 │    fix/login-bug      12m ago  │  I'll implement the JWT refresh token  │
 │                                 │  logic. Let me start by reading the    │
 │                                 │  existing auth middleware...           │
 │                                 │                                        │
 │                                 │  Read src/middleware/auth.ts           │
 │                                 │                                        │
 │                                 │  Now I'll update the token refresh     │
 │                                 │  endpoint:                             │
 │                                 │                                        │
 │                                 │  Edit src/routes/auth.ts               │
 │                                 │  ████████████░░░░░░░░ writing...       │
 │                                 │                                        │
 │                                 │                                        │
 │                                 │                                        │
 ├─────────────────────────────────┴────────────────────────────────────────┤
 │ [n]ew  [a]ttach  [k]ill  [d]iff  [enter] fullscreen  [q]uit            │
 └──────────────────────────────────────────────────────────────────────────┘
```

### Key interactions

| Key       | Action                                                    |
|-----------|-----------------------------------------------------------|
| `j/k`     | Navigate session list                                     |
| `Enter`   | Attach to session (fullscreen, detach with `ctrl-\`)      |
| `n`       | New session — prompts for branch name, runs `grove open`  |
| `k`       | Kill session + worktree (`grove rm`)                      |
| `d`       | Show `git diff` for this worktree vs main                 |
| `p`       | Toggle preview pane (or cycle: off / small / large)       |
| `s`       | Send a message/prompt to the agent                        |
| `y`       | Send `y\n` to accept a pending prompt                     |
| `q`       | Quit TUI (sessions keep running)                          |
| `?`       | Help                                                      |

### Status indicators

```
● active    — agent is producing output (bytes flowing in last 5s)
◐ thinking  — agent is running but no output (waiting for API response)
○ idle      — no output for 60s+ (might be done or stuck)
■ stopped   — session exited
```

Status is derived from monitoring the dtach socket / tmux pane for byte flow.
No need for agent-specific APIs — just watch the terminal output.

### Preview pane

The preview shows the last N lines of the agent's terminal output. With tmux,
this uses `capture-pane`. With dtach, the TUI maintains a VT parser per session
that taps the socket and keeps a virtual screen buffer.

The preview is read-only. To interact, press Enter to attach fullscreen.

### New session flow

```
 ┌─ New Session ────────────────────────────────────────────┐
 │                                                          │
 │  Branch: feat/█                                          │
 │                                                          │
 │  Recent branches:                                        │
 │    feat/auth                                             │
 │    feat/payments                                         │
 │    fix/login-bug                                         │
 │                                                          │
 │  [enter] create  [tab] autocomplete  [esc] cancel        │
 └──────────────────────────────────────────────────────────┘
```

Tab-completes from local + remote branches. Creating a new branch forks from
current HEAD (same as `grove <branch>` today).

### Diff view

```
 grove — myproject > feat/auth (diff vs main)

 ┌──────────────────────────────────────────────────────────────────────────┐
 │  src/middleware/auth.ts                              +24 -3             │
 │  src/routes/auth.ts                                 +87 -12            │
 │  src/models/token.ts                                +45 (new)          │
 │  tests/auth.test.ts                                 +62 (new)          │
 ├──────────────────────────────────────────────────────────────────────────┤
 │  src/middleware/auth.ts                                                  │
 │                                                                          │
 │  @@ -15,7 +15,20 @@                                                     │
 │   import { verifyToken } from '../lib/jwt';                              │
 │                                                                          │
 │  -export function authMiddleware(req, res, next) {                       │
 │  +export function authMiddleware(options = {}) {                         │
 │  +  const { refreshOnExpiry = true } = options;                          │
 │  +  return (req, res, next) => {                                         │
 │  +    const token = req.headers.authorization?.split(' ')[1];            │
 │                                                                          │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ [j/k] files  [enter] expand  [q] back                                   │
 └──────────────────────────────────────────────────────────────────────────┘
```

This is the killer feature most tools lack. When you have 5 agents running, the
question isn't "what are they doing right now" — it's "what have they done."
The diff view answers that instantly.

---

## Language / framework options

| Option        | Pros                                     | Cons                              |
|---------------|------------------------------------------|-----------------------------------|
| **Go + bubbletea** | Fast, single binary, great TUI ecosystem (Claude Squad uses this) | Another language in the project |
| **Rust + ratatui** | Fast, single binary, great TUI ecosystem (Orchestra uses this) | Slower to iterate, steep learning curve |
| **Bash + dialog/whiptail** | Stays in bash, zero new deps | Extremely limited, bad UX |
| **Python + textual** | Quick to prototype, rich widgets | Runtime dep, slower |
| **Zig** | Small binary, no runtime, C interop for vterm | Immature ecosystem |

**Recommendation: Go + bubbletea.** It's the proven choice in this exact
space (Claude Squad shipped with it). Single binary, cross-platform, fast
iteration. The TUI is a separate binary from `grove` (bash), so there's no
language conflict.

Alternative worth considering: **Rust + ratatui** if you want the smallest
possible binary and care about the VT parser performance (parsing 10+ agent
output streams simultaneously).

---

## What makes Grove different?

Looking at the landscape, every tool is building roughly the same thing. The
differentiators that could matter:

### 1. The Grovefile convention

Nobody else has a declarative per-repo config that defines the environment.
Claude Squad makes you configure everything through the TUI. Multiclaude uses a
config file but it's tool-specific. The Grovefile is project-level and
agent-agnostic:

```bash
GROVE_PROJECT="myapp"
grove_setup()   { npm install; }
grove_windows() {
    grove_window "server" "npm run dev"
    grove_window "agent" "claude --dangerously-skip-permissions"
}
```

This means: clone a repo with a Grovefile, run `grove feat/whatever`, and
you have a fully configured environment. No manual setup. The Grovefile
travels with the repo.

### 2. Plumbing/porcelain split

`grove` (bash) = plumbing. Always works, no dependencies beyond bash+git+tmux.
`grove-tui` = porcelain. Optional, nice-to-have.

This means grove is composable. You can script it, pipe it, use it in CI, call
it from other tools. The TUI doesn't eat the CLI.

### 3. dtach backend (if pursued)

Nobody in the space uses dtach. Everyone copies the tmux approach. A dtach
backend with in-process VT parsing would be genuinely novel and deliver better
terminal fidelity + lower overhead.

### 4. Staying small

Claude Squad is already 5k+ lines of Go. Multiclaude has daemons and polling
loops. Grove could win by staying radically simple — do session management
extremely well and nothing else.

Don't build: coordination protocols, message passing between agents, CI
integration, merge automation. Those are separate concerns. Grove manages
environments. Other tools can handle orchestration strategy.

---

## Open questions

1. **dtach availability** — dtach isn't installed by default anywhere. Is it
   worth requiring an extra dependency? Or should grove vendor/bundle it? (It's
   tiny — ~500 lines of C.)

2. **VT parser complexity** — maintaining a virtual terminal buffer per session
   is non-trivial. Is the preview pane valuable enough to justify this? Or is
   "attach to see, detach to go back" good enough?

3. **Agent awareness** — should the TUI understand agent-specific output
   (Claude's tool use markers, Aider's edit blocks) and display structured
   status? Or stay terminal-agnostic and just show raw output?

4. **Scope creep** — the temptation is to build coordination features (agent
   messaging, task assignment, merge automation). Should Grove stay in the
   session management lane? Or is the orchestration layer where the real value
   is?

5. **Single binary distribution** — if the TUI is Go/Rust, should `grove`
   (bash) be bundled inside it? Or keep them separate? Separate is cleaner
   but harder to install.

---

## Minimum viable TUI

If we build the smallest possible thing that's useful:

1. **Session list** with status indicators (active/idle/stopped)
2. **Attach/detach** (Enter to go in, ctrl-\ to come back)
3. **New session** (type branch name, grove handles the rest)
4. **Kill session** (grove rm)
5. **Preview pane** showing last N lines of selected session

That's it. No diff view, no agent awareness, no dtach backend. Just a
navigable list of grove sessions with quick attach. Build on tmux since grove
already uses it. Add dtach and fancy features later.

Ship it as `grove ui`.
