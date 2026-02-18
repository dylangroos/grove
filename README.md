# grove

The fastest way to branch off, work in isolation, and clean up. Git worktrees + tmux, nothing more.

```bash
grove feat/auth          # create worktree + tmux session
grove attach feat/auth   # get into the session
grove ls                 # list worktrees + session status
grove rm feat/auth       # kill session + remove worktree
```

## Install

```bash
curl -fsSL grove.wtf/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/dylangroos/grove.git
ln -sf "$(pwd)/grove/grove" ~/.local/bin/grove
```

## Usage

```
grove <branch>               Create worktree + tmux session (idempotent)
grove <branch> --attach      Create and attach to session
grove attach <branch>        Attach to existing session
grove ls                     List worktrees + session status
grove rm <branch>            Kill session + remove worktree
grove rm --all               Remove everything (with confirmation)
grove init                   Generate a Grovefile interactively
grove help                   Help
grove version                Version
```

`grove` with no args runs `grove ls`.

### How `grove <branch>` works

It's idempotent and non-blocking — always prints status and exits.

1. **No worktree?** Create it, run `grove_setup`, create tmux session. Print path + session name.
2. **Worktree exists, no session?** Create the session. Print session name.
3. **Session already running?** Print "already running" + session name.

To get into the session: `grove attach <branch>` or `grove <branch> --attach`.

## Configuration

Run `grove init` to generate a Grovefile interactively — it auto-detects your project type, installed coding agents (Claude, Codex, aider), and suggests defaults.

Or create a `Grovefile` at your repo root manually. It's entirely optional — grove works with zero config on any git repo.

```bash
# Grovefile
GROVE_PROJECT="myapp"        # defaults to repo dirname

grove_setup() {              # runs once after worktree creation
    npm install
}

grove_windows() {            # define tmux windows
    grove_window "server" "npm run dev"
    grove_window "ui" "cd frontend && npm run dev"
    grove_window "agent" "claude --dangerously-skip-permissions"
}
```

No Grovefile? `grove <branch>` still works — creates a worktree and opens a shell in tmux.

### Hooks

| Hook | Called when | Purpose |
|------|-----------|---------|
| `grove_setup` | After worktree creation | Install dependencies (cwd = new worktree) |
| `grove_windows` | Starting a tmux session | Define windows via `grove_window <name> <cmd>` |

### Shell completions

```bash
# Add to .bashrc or .zshrc:
eval "$(grove completions)"
```

## Requirements

- bash 4+
- git
- tmux

## License

MIT
