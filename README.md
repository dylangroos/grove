# grove

Agent-first worktree manager. Spawn coding agents in git worktrees — snap in, snap out, let them work.

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

1. **No worktree?** Create it, run `grove_setup`, start agent.
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
```

### `Grovefile` (per-repo, optional)

```bash
GROVE_PROJECT="myapp"        # defaults to repo dirname

grove_setup() {              # runs once after worktree creation
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

## License

MIT
