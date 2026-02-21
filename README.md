# grove

Multi-agent worktree manager. Run coding agents in parallel across git worktrees — one command to spawn, monitor, and attach.

```bash
gr checkout feat/auth "add auth"   # worktree + background agent
gr status                          # all worktrees, agents, activity
gr attach feat/auth                # snap into the running agent
gr rm feat/auth                    # kill agent + remove worktree
```

## Install

```bash
curl -fsSL grove.wtf/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/dylangroos/grove.git
cd grove && bash install.sh
```

**Dependencies:** bash 4+, git, [dtach](https://github.com/cripty2001/dtach) (`apt install dtach` / `brew install dtach`)

## Usage

```
gr checkout <branch> "prompt"    Create worktree + run agent in background
gr checkout <branch>             Create worktree + run agent interactively
gr <branch> "prompt"             Shorthand for checkout
gr status                        Show all worktrees, agents, activity
gr attach <branch>               Snap into a running agent session
gr log <branch>                  Agent's commits on this branch
gr diff <branch>                 What the agent changed vs base
gr rm <branch>                   Kill agent + remove worktree
gr rm --all                      Remove everything (with confirmation)
gr init                          Set up ~/.grove + Grovefile
gr help                          Help
```

`gr` with no args runs `gr status`. Detach from a foreground agent with `Ctrl+\`.

### How `gr checkout` works

Idempotent — safe to run multiple times:

1. **No worktree?** Create it, run `setup`, start agent.
2. **Worktree exists, no agent?** Start agent (resumes conversation if prior session).
3. **Agent idle?** Auto-attach (no prompt) or restart with new prompt.
4. **Agent busy?** Auto-attach (no prompt) or warn and suggest `gr attach`.

With a prompt → agent runs in background (`dtach -n`). Without → interactive foreground (`dtach -c`).

### `gr status` output

```
BRANCH                  AGENT     STATUS     LAST ACTIVITY
feat/auth               claude    running    3m ago · "add JWT middleware"
fix/login               claude    waiting    "fix login redirect"
refactor/db             claude    done       1h ago · "normalize schema"
```

## Configuration

### `~/.grove` (global)

Set your coding agent. Created by `gr init` or write manually:

```bash
GROVE_AGENT="claude"     # or codex, aider, etc.
# GROVE_AGENT_FLAGS="--dangerously-skip-permissions"  # override default agent flags
```

**Agent flags:** Background agents can't ask for permission, so grove passes `--dangerously-skip-permissions` to Claude by default. Set `GROVE_AGENT_FLAGS` to override this — even `GROVE_AGENT_FLAGS=""` to run with no extra flags. When unset, smart defaults apply.

### `Grovefile` (per-repo, optional)

```bash
GROVE_PROJECT="myapp"        # defaults to repo dirname

setup() {              # runs once after worktree creation
    npm install
}
```

Run `gr init` to generate both interactively. Grove works with zero config on any git repo.

### Supported agents

| Agent | With prompt | Without prompt |
|-------|------------|----------------|
| claude | `claude "prompt"` | `claude` |
| codex | `codex "prompt"` | `codex` |
| aider | `aider --message "prompt"` | `aider` |
| other | `agent "prompt"` | `agent` |

### Shell completions

```bash
eval "$(gr completions)"
```

## Why grove?

Most tools give you worktree isolation. Grove gives you worktree **orchestration**:

- **Any agent** — Claude, Codex, Aider, or your own. Swap per-project or globally.
- **One dashboard** — `gr status` shows every branch, agent, and state at a glance.
- **Smart checkout** — auto-attaches, detects idle/busy, resumes prior sessions.
- **Setup hooks** — `setup()` runs automatically so worktrees come up ready.
- **Full lifecycle** — `gr rm`, `gr log`, `gr diff` per branch. One command to spawn, monitor, or tear down.

## License

MIT
