#!/usr/bin/env bash
#
# grove E2E test suite
#
# Runs grove through all major scenarios in a throwaway git repo.
# No test framework — each test prints PASS/FAIL. Exit 1 if any fail.

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# ─── State ────────────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()
TEST_DIR=""
GROVE_BIN=""

# ─── Assertions ───────────────────────────────────────────────────────────

pass() {
    local name="$1"
    echo -e "  ${GREEN}PASS${NC} $name"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    local name="$1"
    shift
    echo -e "  ${RED}FAIL${NC} $name"
    for line in "$@"; do
        echo "       $line"
    done
    FAILURES+=("$name")
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_exit() {
    local expected="$1" actual="$2" name="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name" "expected exit $expected, got $actual"
    fi
}

assert_contains() {
    local output="$1" substring="$2" name="$3"
    if echo "$output" | grep -qF "$substring"; then
        pass "$name"
    else
        fail "$name" "expected to contain: $substring" \
            "output: $(echo "$output" | head -5)"
    fi
}

assert_not_contains() {
    local output="$1" substring="$2" name="$3"
    if ! echo "$output" | grep -qF "$substring"; then
        pass "$name"
    else
        fail "$name" "expected NOT to contain: $substring"
    fi
}

# ─── Setup / Cleanup ─────────────────────────────────────────────────────

setup_test_repo() {
    # Use a dot-free dir name — tmux silently replaces dots with underscores
    # in session names, which breaks session lookups if the project name has dots.
    TEST_DIR="/tmp/grove-e2e-$$-${RANDOM}"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email "test@grove.wtf"
    git config user.name "Grove Test"
    git commit --allow-empty -m "initial commit" >/dev/null 2>&1

    cp "$GROVE_BIN" "$TEST_DIR/grove"
    chmod +x "$TEST_DIR/grove"
}

cleanup() {
    # Kill grove tmux sessions from this test repo
    if [[ -n "${TEST_DIR:-}" ]]; then
        local project
        project="$(basename "${TEST_DIR}")"
        tmux list-sessions -F '#{session_name}' 2>/dev/null \
            | grep "^grove-${project}-" \
            | while read -r s; do tmux kill-session -t "$s" 2>/dev/null || true; done
    fi

    if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR:-}" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
    TEST_DIR=""
}

trap cleanup EXIT

# ─── Tests ────────────────────────────────────────────────────────────────

test_basic_create() {
    echo -e "${BOLD}1. basic create${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Worktree created" "prints worktree created"
    assert_contains "$output" "Session started" "prints session started"

    [[ -d "$TEST_DIR/.worktrees/feat-auth" ]] \
        && pass "worktree directory exists" \
        || fail "worktree directory exists"

    local project session
    project="$(basename "$TEST_DIR")"
    session="grove-${project}-feat-auth"
    tmux has-session -t "$session" 2>/dev/null \
        && pass "tmux session exists" \
        || fail "tmux session exists"

    cleanup
}

test_idempotency() {
    echo -e "${BOLD}2. idempotency${NC}"
    setup_test_repo

    ./grove feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Session already running" "reports existing session"

    cleanup
}

test_ls() {
    echo -e "${BOLD}3. grove ls${NC}"
    setup_test_repo

    ./grove feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove ls 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "BRANCH" "has header"
    assert_contains "$output" "feat/auth" "shows branch"
    assert_contains "$output" "detached" "shows session status"

    cleanup
}

test_dots_in_branch_names() {
    echo -e "${BOLD}4. dots in branch names${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove v1.2.3-hotfix 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "v1-2-3-hotfix" "slug replaces dots with dashes"
    assert_contains "$output" "Session started" "session started"

    local ls_output
    ls_output=$(./grove ls 2>&1)
    assert_contains "$ls_output" "detached" "ls shows detached (not dash)"

    cleanup
}

test_rm_from_inside_worktree() {
    echo -e "${BOLD}5. rm from inside worktree${NC}"
    setup_test_repo

    ./grove feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(cd "$TEST_DIR/.worktrees/feat-auth" && "$TEST_DIR/grove" rm feat/auth 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Cannot remove worktree while inside it" "error message"

    cleanup
}

test_failed_grove_setup() {
    echo -e "${BOLD}6. failed grove_setup${NC}"
    setup_test_repo

    cat > "$TEST_DIR/Grovefile" <<'GROVEFILE'
grove_setup() { false; }
GROVEFILE

    local output rc=0
    output=$(./grove feat/fail-setup 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code (continues despite failure)"
    assert_contains "$output" "grove_setup failed" "warning printed"
    assert_contains "$output" "Session started" "session still created"

    cleanup
}

test_git_ref_conflict() {
    echo -e "${BOLD}7. git ref conflict${NC}"
    setup_test_repo

    ./grove feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove feat/auth/deep/nested 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Failed to create worktree" "grove-level error message"

    cleanup
}

test_rm_basic() {
    echo -e "${BOLD}8. rm basic${NC}"
    setup_test_repo

    ./grove feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove rm feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Session killed" "session killed"
    assert_contains "$output" "Removed: feat-auth" "worktree removed"

    [[ ! -d "$TEST_DIR/.worktrees/feat-auth" ]] \
        && pass "worktree directory gone" \
        || fail "worktree directory gone"

    cleanup
}

test_help() {
    echo -e "${BOLD}9a. help${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove help 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "worktree + tmux environment manager" "description"
    assert_contains "$output" "USAGE:" "usage section"

    cleanup
}

test_version() {
    echo -e "${BOLD}9b. version${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove version 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "grove v" "version string"

    cleanup
}

test_not_in_git_repo() {
    echo -e "${BOLD}10. not in git repo${NC}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    local output rc=0
    output=$(cd "$tmpdir" && "$GROVE_BIN" ls 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Not in a git repository" "error message"

    rm -rf "$tmpdir"
}

test_attach_nonexistent() {
    echo -e "${BOLD}11. attach nonexistent${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove attach nonexistent 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No session for" "error message"

    cleanup
}

test_rm_nonexistent() {
    echo -e "${BOLD}12. rm nonexistent${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove rm nonexistent 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Worktree not found" "error message"

    cleanup
}

test_grovefile_with_windows() {
    echo -e "${BOLD}13. Grovefile with windows${NC}"
    setup_test_repo

    cat > "$TEST_DIR/Grovefile" <<'GROVEFILE'
grove_setup() { echo "setup ran"; }
grove_windows() {
    grove_window "server" "echo running"
    grove_window "logs" "echo logging"
}
GROVEFILE

    local output rc=0
    output=$(./grove feat/windowed 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Running setup" "setup hook ran"
    assert_contains "$output" "Session started" "session started"

    local project session windows
    project="$(basename "$TEST_DIR")"
    session="grove-${project}-feat-windowed"
    windows=$(tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null)

    assert_contains "$windows" "server" "server window exists"
    assert_contains "$windows" "logs" "logs window exists"
    assert_contains "$windows" "shell" "shell window exists"

    cleanup
}

test_no_args() {
    echo -e "${BOLD}14. grove with no args${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "No worktrees" "runs ls"

    cleanup
}

# ─── Init: unit tests ─────────────────────────────────────────────────

test_detect_node_npm() {
    echo -e "${BOLD}15. detect — node (npm)${NC}"
    setup_test_repo
    echo '{"scripts":{"dev":"node server.js"}}' > "$TEST_DIR/package.json"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "node (npm)" "detects node (npm)"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "npm install" "npm install default"
    assert_contains "$grovefile" "npm run dev" "npm run dev default"

    cleanup
}

test_detect_node_pnpm() {
    echo -e "${BOLD}16. detect — node (pnpm)${NC}"
    setup_test_repo
    echo '{"scripts":{"dev":"vite"}}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/pnpm-lock.yaml"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "node (pnpm)" "detects pnpm"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "pnpm install" "pnpm install default"
    assert_contains "$grovefile" "pnpm run dev" "pnpm run dev default"

    cleanup
}

test_detect_node_yarn() {
    echo -e "${BOLD}17. detect — node (yarn)${NC}"
    setup_test_repo
    echo '{"scripts":{"start":"node index.js"}}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/yarn.lock"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "node (yarn)" "detects yarn"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "yarn install" "yarn install default"
    assert_contains "$grovefile" "yarn start" "yarn start default (no dev script)"

    cleanup
}

test_detect_node_bun() {
    echo -e "${BOLD}18. detect — node (bun)${NC}"
    setup_test_repo
    echo '{"scripts":{"dev":"bun run src/index.ts"}}' > "$TEST_DIR/package.json"
    touch "$TEST_DIR/bun.lockb"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "node (bun)" "detects bun"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "bun install" "bun install default"
    assert_contains "$grovefile" "bun run dev" "bun run dev default"

    cleanup
}

test_detect_rust() {
    echo -e "${BOLD}19. detect — rust${NC}"
    setup_test_repo
    echo '[package]' > "$TEST_DIR/Cargo.toml"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Detected: " "shows detected"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "cargo build" "cargo build default"
    assert_contains "$grovefile" "cargo run" "cargo run default"

    cleanup
}

test_detect_go() {
    echo -e "${BOLD}20. detect — go${NC}"
    setup_test_repo
    echo 'module example.com/test' > "$TEST_DIR/go.mod"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "go build ./..." "go build default"
    assert_contains "$grovefile" "go run ." "go run default"

    cleanup
}

test_detect_python_uv() {
    echo -e "${BOLD}21. detect — python (uv)${NC}"
    setup_test_repo
    echo '[project]' > "$TEST_DIR/pyproject.toml"
    touch "$TEST_DIR/uv.lock"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "python (uv)" "detects uv"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "uv sync" "uv sync default"

    cleanup
}

test_detect_python_pip() {
    echo -e "${BOLD}22. detect — python (pip)${NC}"
    setup_test_repo
    echo '[project]' > "$TEST_DIR/pyproject.toml"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Detected: " "shows detected"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "pip install -e ." "pip install -e . default"

    cleanup
}

test_detect_python_requirements() {
    echo -e "${BOLD}23. detect — python (requirements.txt)${NC}"
    setup_test_repo
    echo 'flask' > "$TEST_DIR/requirements.txt"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "pip install -r requirements.txt" "pip install -r default"

    cleanup
}

test_detect_ruby_rails() {
    echo -e "${BOLD}24. detect — ruby (rails)${NC}"
    setup_test_repo
    echo 'source "https://rubygems.org"' > "$TEST_DIR/Gemfile"
    mkdir -p "$TEST_DIR/bin"
    touch "$TEST_DIR/bin/rails"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "bundle install" "bundle install default"
    assert_contains "$grovefile" "bin/rails server" "rails server default"

    cleanup
}

test_detect_php_laravel() {
    echo -e "${BOLD}25. detect — php (laravel)${NC}"
    setup_test_repo
    echo '{}' > "$TEST_DIR/composer.json"
    touch "$TEST_DIR/artisan"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "composer install" "composer install default"
    assert_contains "$grovefile" "php artisan serve" "artisan serve default"

    cleanup
}

test_detect_unknown() {
    echo -e "${BOLD}26. detect — unknown project${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_not_contains "$output" "Detected:" "no detection message"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "GROVE_PROJECT=" "project name still set"
    assert_not_contains "$grovefile" "grove_setup" "no setup (nothing detected)"
    assert_not_contains "$grovefile" "grove_windows" "no windows (nothing detected)"

    cleanup
}

# ─── Init: window naming ─────────────────────────────────────────────

test_window_name_run() {
    echo -e "${BOLD}27. window name — run <name>${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\nnpm run dev\n\n' | ./grove init 2>&1) || rc=$?

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" 'grove_window "dev"' "names window from run command"

    cleanup
}

test_window_name_start() {
    echo -e "${BOLD}28. window name — start${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\nnpm start\n\n' | ./grove init 2>&1) || rc=$?

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" 'grove_window "start"' "names window 'start'"

    cleanup
}

test_window_name_cd() {
    echo -e "${BOLD}29. window name — cd <dir>${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\ncd frontend && npm run dev\n\n' | ./grove init 2>&1) || rc=$?

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" 'grove_window "frontend"' "names window from cd dir"

    cleanup
}

test_window_name_fallback() {
    echo -e "${BOLD}30. window name — fallback${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\npython app.py\n\n' | ./grove init 2>&1) || rc=$?

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" 'grove_window "window-1"' "falls back to window-N"

    cleanup
}

# ─── Init: multi-command + skip ──────────────────────────────────────

test_init_multiple_setup_commands() {
    echo -e "${BOLD}31. init — multiple setup commands${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf 'npm install\nnpm run build\n\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "npm install" "first setup command"
    assert_contains "$grovefile" "npm run build" "second setup command"

    cleanup
}

test_init_skip_all() {
    echo -e "${BOLD}32. init — skip all (unknown project)${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "GROVE_PROJECT=" "only project name"
    assert_not_contains "$grovefile" "grove_setup" "no setup section"
    assert_not_contains "$grovefile" "grove_windows" "no windows section"

    cleanup
}

# ─── Init: E2E ───────────────────────────────────────────────────────

test_init_custom_commands() {
    echo -e "${BOLD}33. init — custom commands${NC}"
    setup_test_repo

    local output rc=0
    output=$(printf 'make build\n\nmake run\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Created Grovefile" "created message"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "make build" "custom setup command"
    assert_contains "$grovefile" "make run" "custom window command"

    cleanup
}

test_init_already_exists() {
    echo -e "${BOLD}34. init — already exists${NC}"
    setup_test_repo

    echo "# existing" > "$TEST_DIR/Grovefile"

    local output rc=0
    output=$(./grove init 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "already exists" "error message"

    cleanup
}

test_init_not_in_git_repo() {
    echo -e "${BOLD}35. init — not in git repo${NC}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    local output rc=0
    output=$(cd "$tmpdir" && "$GROVE_BIN" init 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Not in a git repository" "error message"

    rm -rf "$tmpdir"
}

test_unknown_flag() {
    echo -e "${BOLD}36. unknown flag${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove feat/test --bogus 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Unknown option" "error message"

    cleanup
}

# ─── Main ─────────────────────────────────────────────────────────────────

main() {
    GROVE_BIN="$(cd "$(dirname "$0")/.." && pwd)/grove"

    if [[ ! -f "$GROVE_BIN" ]]; then
        echo "Error: grove not found at $GROVE_BIN" >&2
        exit 1
    fi

    echo -e "${BOLD}grove E2E tests${NC}"
    echo "binary: $GROVE_BIN"
    echo

    test_basic_create
    test_idempotency
    test_ls
    test_dots_in_branch_names
    test_rm_from_inside_worktree
    test_failed_grove_setup
    test_git_ref_conflict
    test_rm_basic
    test_help
    test_version
    test_not_in_git_repo
    test_attach_nonexistent
    test_rm_nonexistent
    test_grovefile_with_windows
    test_no_args
    # Init: detection per project type
    test_detect_node_npm
    test_detect_node_pnpm
    test_detect_node_yarn
    test_detect_node_bun
    test_detect_rust
    test_detect_go
    test_detect_python_uv
    test_detect_python_pip
    test_detect_python_requirements
    test_detect_ruby_rails
    test_detect_php_laravel
    test_detect_unknown
    # Init: window naming
    test_window_name_run
    test_window_name_start
    test_window_name_cd
    test_window_name_fallback
    # Init: multi-command + skip
    test_init_multiple_setup_commands
    test_init_skip_all
    # Init: E2E
    test_init_custom_commands
    test_init_already_exists
    test_init_not_in_git_repo
    test_unknown_flag

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Failed: $FAIL_COUNT${NC}"
        for f in "${FAILURES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi
    echo "All tests passed."
}

main
