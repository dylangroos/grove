# grove

Run coding agents in parallel across git worktrees.

```bash
gr feat/auth "add JWT auth"     # branch + worktree + background agent
gr fix/bug "fix redirect loop"  # another one, in parallel
gr status                       # see all agents at a glance
gr attach feat/auth             # snap into a running session
gr rm feat/auth                 # kill agent + clean up
```

## Install

```bash
curl -fsSL grove.wtf/install.sh | bash
```

Requires bash 4+, git, [dtach](https://github.com/cripty2001/dtach). The install script handles dtach for you.

## Configuration

```bash
gr init   # interactive setup — creates both files
```

**`~/.grove`** (global) — which agent to use:
```bash
GROVE_AGENT="claude"
# GROVE_AGENT_FLAGS="--dangerously-skip-permissions"  # override default flags
```

**`Grovefile`** (per-repo, optional) — project setup:
```bash
GROVE_PROJECT="myapp"
setup() { npm install; }
```

Claude gets `--dangerously-skip-permissions` by default (background agents can't prompt). Set `GROVE_AGENT_FLAGS` to override. Works with Claude, Codex, Aider, or any CLI agent.

## Commands

```
gr <branch> "prompt"       Start agent in background on a new worktree
gr <branch>                Start agent interactively (or attach if running)
gr status                  All worktrees, agents, last activity
gr attach <branch>         Snap into a running agent (Ctrl+\ to detach)
gr log/diff <branch>       What the agent committed
gr rm <branch>             Kill agent + remove worktree
gr rm --all                Remove everything
```

## License

MIT
