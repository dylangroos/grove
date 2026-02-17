# grove

Parallel dev environment manager using git worktrees + tmux. Configured per-repo via a `Grovefile`.

## What it does

Grove manages multiple isolated development environments on a single machine. Each environment gets its own git worktree, tmux session with service windows, and isolated ports — so you can work on multiple branches simultaneously without conflicts.

```bash
grove feat/auth-flow     # Create worktree + install deps + start services
grove ls                 # List all worktrees with health status
grove logs 0             # Attach to tmux session
grove rm feat/auth-flow  # Stop services + remove worktree
```

## Install

```bash
# Clone into your project (or add as a submodule)
# Then symlink to PATH:
./install.sh

# Or manually:
ln -sf "$(pwd)/grove" ~/.local/bin/grove
```

## Usage

```
grove <branch>             Create worktree + start instance
grove ls                   List all worktrees with branch, instance, health
grove rm <branch>          Stop instance + remove worktree

grove start [N]            Start instance N (auto-detects from .grove-instance)
grove stop [N]             Stop instance N
grove status               Show all instances + shared services
grove logs [N]             Attach to tmux session for instance N
grove ports                Show port assignments for running instances

grove start-all [N]        Start N instances (default: 3)
grove stop-all             Stop all running instances
```

## Configuration

Create a `Grovefile` at your repo root. It's a bash script that defines project-specific hooks:

```bash
# Grovefile
GROVE_PROJECT="myapp"
GROVE_MAX_INSTANCES=4

grove_ports() {
    local n="$1"
    APP_PORT=$((3000 + n * 100))
    DB_PORT=$((5432 + n))
}

grove_setup() {
    npm install
}

grove_windows() {
    local n="$1"
    grove_window "server" "PORT=${APP_PORT} npm run dev"
    grove_window "worker" "npm run worker"
}

grove_health() {
    curl -sf "http://localhost:${APP_PORT}/health" > /dev/null
}

grove_shared() {
    grove_ensure_service "postgres" \
        "pg_isready -q" \
        "docker run -d --name myapp-pg -p 5432:5432 -e POSTGRES_PASSWORD=dev postgres:16-alpine"

    grove_ensure_service "redis" \
        "docker ps -f name=myapp-redis --format '{{.Names}}' | grep -q myapp-redis" \
        "docker run -d --name myapp-redis -p 6379:6379 redis:7-alpine"
}

grove_post_start() {
    echo "Instance $1 is ready at http://localhost:${APP_PORT}"
}
```

### Grovefile hooks

| Hook | Called when | Purpose |
|------|-----------|---------|
| `grove_ports <N>` | Before starting | Set port variables for instance N |
| `grove_setup` | Creating a worktree | Install dependencies (cwd = new worktree) |
| `grove_windows <N>` | Starting an instance | Define tmux windows via `grove_window` |
| `grove_shared` | Starting an instance | Start shared services via `grove_ensure_service` |
| `grove_health` | After start + in status | Return 0 if healthy |
| `grove_post_start <N>` | After health passes | Run post-startup tasks |

### Helper functions

- **`grove_window <name> <cmd>`** — Register a tmux window with a command
- **`grove_ensure_service <name> <check_cmd> <start_cmd>`** — Idempotently start a shared service

## How it works

1. `grove` walks up directories to find the nearest `Grovefile` (like `git` finds `.git/`)
2. Sources the `Grovefile` to load config and hook functions
3. Manages worktrees in `.worktrees/`, instance markers in `.grove-instance`, tmux sessions named `grove-<project>-N`

### Instance isolation

Each instance gets:
- Its own git worktree: `.worktrees/<branch-slug>/`
- An instance marker: `.grove-instance` (enables auto-detection)
- A tmux session: `grove-<project>-N`
- Isolated ports: defined by `grove_ports()` in the Grovefile

When you run grove commands from inside a worktree, the instance number is auto-detected — so `grove stop` just works without specifying N.

## Requirements

- bash 4+
- git
- tmux

## License

MIT
