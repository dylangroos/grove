# grove

<p align="center">
  <img src="docs/tree.svg" alt="grove" width="500">
</p>

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
gr init
```

That's it. `gr init` walks you through picking your agent and setting up per-repo config. Run it again anytime to change settings.

Works with Claude, Codex, Aider, or any CLI agent. Requires bash 4+, git, [dtach](https://github.com/cripty2001/dtach).

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
