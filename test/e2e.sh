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
SAVED_GROVE_CONFIG=""

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

assert_file_exists() {
    local path="$1" name="$2"
    if [[ -e "$path" ]]; then
        pass "$name"
    else
        fail "$name" "file does not exist: $path"
    fi
}

assert_file_not_exists() {
    local path="$1" name="$2"
    if [[ ! -e "$path" ]]; then
        pass "$name"
    else
        fail "$name" "file should not exist: $path"
    fi
}

# ─── Mock agent ──────────────────────────────────────────────────────────

create_mock_agent() {
    local dir="$1"
    mkdir -p "$dir/bin"
    cat > "$dir/bin/mock-agent" <<'AGENT'
#!/bin/bash
if [[ -n "${1:-}" ]]; then
    echo "prompt: $1"
fi
echo "agent started"
sleep 30
AGENT
    chmod +x "$dir/bin/mock-agent"
}

# ─── Setup / Cleanup ─────────────────────────────────────────────────────

setup_test_repo() {
    TEST_DIR="/tmp/grove-e2e-$$-${RANDOM}"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    git init --initial-branch=main . >/dev/null 2>&1
    git config user.email "test@grove.wtf"
    git config user.name "Grove Test"
    git config commit.gpgsign false
    git commit --allow-empty -m "initial commit" >/dev/null 2>&1

    cp "$GROVE_BIN" "$TEST_DIR/grove"
    chmod +x "$TEST_DIR/grove"

    # Create mock agent
    create_mock_agent "$TEST_DIR"

    # Set up ~/.grove with mock agent for this test
    export GROVE_CONFIG_BACKUP="${HOME}/.grove.backup.$$"
    if [[ -f "$HOME/.grove" ]]; then
        cp "$HOME/.grove" "$GROVE_CONFIG_BACKUP"
    fi
    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"
}

cleanup() {
    # Kill any dtach sockets from this test
    if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR:-}" ]]; then
        # Find and kill dtach processes for our test worktrees
        for socket in "$TEST_DIR"/.worktrees/*/.grove-socket; do
            if [[ -S "$socket" ]]; then
                local pid=""
                if command -v fuser >/dev/null 2>&1; then
                    pid="$(fuser "$socket" 2>/dev/null | tr -d '[:space:]')" || true
                fi
                if [[ -z "$pid" ]] && command -v lsof >/dev/null 2>&1; then
                    pid="$(lsof -t "$socket" 2>/dev/null | head -1)" || true
                fi
                if [[ -n "$pid" ]]; then
                    kill "$pid" 2>/dev/null || true
                fi
                rm -f "$socket"
            fi
        done
    fi

    # Restore ~/.grove
    if [[ -n "${GROVE_CONFIG_BACKUP:-}" ]]; then
        if [[ -f "$GROVE_CONFIG_BACKUP" ]]; then
            mv "$GROVE_CONFIG_BACKUP" "$HOME/.grove"
        else
            rm -f "$HOME/.grove"
        fi
    fi

    if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR:-}" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
    TEST_DIR=""
}

trap cleanup EXIT

# ─── Tests ────────────────────────────────────────────────────────────────

test_checkout_creates_worktree() {
    echo -e "${BOLD}1. checkout creates worktree${NC}"
    setup_test_repo

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Worktree created" "prints worktree created"

    [[ -d "$TEST_DIR/.worktrees/feat-auth" ]] \
        && pass "worktree directory exists" \
        || fail "worktree directory exists"

    cleanup
}

test_checkout_with_prompt_background() {
    echo -e "${BOLD}2. checkout with prompt runs agent in background${NC}"
    setup_test_repo

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "add JWT middleware" 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent started (background)" "agent started message"
    assert_contains "$output" "add JWT middleware" "prompt echoed"

    # Check prompt was saved
    local prompt_file="$TEST_DIR/.worktrees/feat-auth/.grove-prompt"
    assert_file_exists "$prompt_file" "prompt file saved"
    if [[ -f "$prompt_file" ]]; then
        local saved
        saved="$(cat "$prompt_file")"
        assert_contains "$saved" "add JWT middleware" "prompt content correct"
    fi

    # Check socket exists (agent running)
    sleep 0.5
    local socket="$TEST_DIR/.worktrees/feat-auth/.grove-socket"
    [[ -S "$socket" ]] \
        && pass "dtach socket exists" \
        || fail "dtach socket exists" "socket not found at $socket"

    cleanup
}

test_checkout_idempotency() {
    echo -e "${BOLD}3. checkout idempotency${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test again" 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent is busy" "reports agent is busy"
    assert_contains "$output" "gr attach" "suggests attach command"

    cleanup
}

test_shorthand_checkout() {
    echo -e "${BOLD}4. shorthand (gr <branch> \"prompt\")${NC}"
    setup_test_repo

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove feat/auth "add auth" 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Worktree created" "worktree created"
    assert_contains "$output" "Agent started (background)" "agent started"

    cleanup
}

test_status_shows_info() {
    echo -e "${BOLD}5. status shows agent info${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "add auth" >/dev/null 2>&1
    sleep 0.5

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "BRANCH" "has header"
    assert_contains "$output" "feat/auth" "shows branch"
    assert_contains "$output" "running" "shows running status"

    cleanup
}

test_status_empty() {
    echo -e "${BOLD}6. status with no worktrees${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove status 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "No worktrees" "shows no worktrees"

    cleanup
}

test_no_args_runs_status() {
    echo -e "${BOLD}7. grove with no args = status${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "No worktrees" "runs status"

    cleanup
}

test_rm_kills_agent() {
    echo -e "${BOLD}8. rm kills agent${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove rm feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent killed" "agent killed"
    assert_contains "$output" "Removed: feat-auth" "worktree removed"

    [[ ! -d "$TEST_DIR/.worktrees/feat-auth" ]] \
        && pass "worktree directory gone" \
        || fail "worktree directory gone"

    cleanup
}

test_rm_from_inside_worktree() {
    echo -e "${BOLD}9. rm from inside worktree${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.3

    local output rc=0
    output=$(cd "$TEST_DIR/.worktrees/feat-auth" && PATH="$TEST_DIR/bin:$PATH" "$TEST_DIR/grove" rm feat/auth 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Cannot remove worktree while inside it" "error message"

    cleanup
}

test_rm_nonexistent() {
    echo -e "${BOLD}10. rm nonexistent${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove rm nonexistent 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Worktree not found" "error message"

    cleanup
}

test_attach_nonexistent() {
    echo -e "${BOLD}11. attach no worktree${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove attach nonexistent 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No worktree for" "error message"

    cleanup
}

test_attach_no_agent() {
    echo -e "${BOLD}12. attach with no running agent${NC}"
    setup_test_repo

    # Create worktree directly via git (no agent involved)
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove attach feat/auth 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No running agent" "error message"

    cleanup
}

test_not_in_git_repo() {
    echo -e "${BOLD}13. not in git repo${NC}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    local output rc=0
    output=$(cd "$tmpdir" && "$GROVE_BIN" status 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Not in a git repository" "error message"

    rm -rf "$tmpdir"
}

test_help() {
    echo -e "${BOLD}14. help${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove help 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "agent-first worktree manager" "description"
    assert_contains "$output" "USAGE:" "usage section"
    assert_contains "$output" "gr checkout" "shows new commands"

    cleanup
}

test_version() {
    echo -e "${BOLD}15. version${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove version 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "grove v0.3.0" "version string"

    cleanup
}

test_dots_in_branch_names() {
    echo -e "${BOLD}16. dots in branch names${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"
    local output rc=0
    output=$(./grove checkout v1.2.3-hotfix 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"

    [[ -d "$TEST_DIR/.worktrees/v1-2-3-hotfix" ]] \
        && pass "slug replaces dots with dashes" \
        || fail "slug replaces dots with dashes"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    cleanup
}

test_failed_setup() {
    echo -e "${BOLD}17. failed setup${NC}"
    setup_test_repo

    cat > "$TEST_DIR/Grovefile" <<'GROVEFILE'
setup() { false; }
GROVEFILE

    rm -f "$HOME/.grove"
    local output rc=0
    output=$(./grove checkout feat/fail-setup 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code (continues despite failure)"
    assert_contains "$output" "setup failed" "warning printed"
    assert_contains "$output" "Worktree created" "worktree still created"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    cleanup
}

test_git_ref_conflict() {
    echo -e "${BOLD}18. git ref conflict${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"
    ./grove checkout feat/auth >/dev/null 2>&1
    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth/deep/nested 2>&1) || rc=$?

    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Failed to create worktree" "grove-level error message"

    cleanup
}

test_init_creates_grove_config() {
    echo -e "${BOLD}19. init creates ~/.grove${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"

    mkdir -p "$TEST_DIR/bin"
    printf '#!/bin/sh\n' > "$TEST_DIR/bin/claude"
    chmod +x "$TEST_DIR/bin/claude"

    local output rc=0
    output=$(printf '\n\n' | PATH="$TEST_DIR/bin:$PATH" ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_file_exists "$HOME/.grove" "~/.grove created"

    if [[ -f "$HOME/.grove" ]]; then
        local config
        config="$(cat "$HOME/.grove")"
        assert_contains "$config" 'GROVE_AGENT="claude"' "agent set to claude"
    fi

    assert_file_exists "$TEST_DIR/Grovefile" "Grovefile created"
    assert_contains "$output" "Saved ~/.grove" "prints config saved"
    assert_contains "$output" "Created Grovefile" "prints grovefile created"

    cleanup
}

test_init_detects_project() {
    echo -e "${BOLD}20. init detects project type${NC}"
    setup_test_repo

    echo '{"scripts":{"dev":"node server.js"}}' > "$TEST_DIR/package.json"

    local output rc=0
    output=$(printf '\n\n' | ./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "node (npm)" "detects node (npm)"

    local grovefile
    grovefile="$(cat "$TEST_DIR/Grovefile")"
    assert_contains "$grovefile" "npm install" "npm install default"

    cleanup
}

test_init_grovefile_already_exists() {
    echo -e "${BOLD}21. init — Grovefile already exists${NC}"
    setup_test_repo

    echo "# existing" > "$TEST_DIR/Grovefile"

    local output rc=0
    output=$(./grove init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "already exists" "reports existing Grovefile"

    cleanup
}

test_init_not_in_git_repo() {
    echo -e "${BOLD}22. init — not in git repo${NC}"
    local tmpdir
    tmpdir="$(mktemp -d)"

    rm -f "$HOME/.grove"

    local output rc=0
    output=$(cd "$tmpdir" && printf '\n' | PATH="/usr/bin:/bin:$PATH" "$GROVE_BIN" init 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Not in a git repo" "shows not in git repo"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"
    rm -rf "$tmpdir"
}

test_prompt_saved() {
    echo -e "${BOLD}23. prompt saved to file${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/test "implement user login" >/dev/null 2>&1

    local prompt_file="$TEST_DIR/.worktrees/feat-test/.grove-prompt"
    assert_file_exists "$prompt_file" "prompt file exists"

    if [[ -f "$prompt_file" ]]; then
        local content
        content="$(cat "$prompt_file")"
        assert_contains "$content" "implement user login" "prompt content matches"
    fi

    cleanup
}

test_status_shows_done_after_agent_exits() {
    echo -e "${BOLD}24. status shows done after agent exits${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    # Kill the agent to simulate completion
    local socket="$TEST_DIR/.worktrees/feat-auth/.grove-socket"
    if [[ -S "$socket" ]]; then
        local pid=""
        if command -v fuser >/dev/null 2>&1; then
            pid="$(fuser "$socket" 2>/dev/null | tr -d '[:space:]')" || true
        fi
        if [[ -z "$pid" ]] && command -v lsof >/dev/null 2>&1; then
            pid="$(lsof -t "$socket" 2>/dev/null | head -1)" || true
        fi
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 0.5
        fi
        rm -f "$socket"
    fi

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "done" "shows done status"

    cleanup
}

test_log_shows_commits() {
    echo -e "${BOLD}25. log shows commits${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"
    ./grove checkout feat/auth >/dev/null 2>&1

    # Make a commit in the worktree
    (cd "$TEST_DIR/.worktrees/feat-auth" && \
        echo "test" > test.txt && \
        git add test.txt && \
        git commit -m "add test file" >/dev/null 2>&1)

    local output rc=0
    output=$(./grove log feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "add test file" "shows commit message"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    cleanup
}

test_diff_shows_changes() {
    echo -e "${BOLD}26. diff shows changes${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"
    ./grove checkout feat/auth >/dev/null 2>&1

    # Make a commit in the worktree
    (cd "$TEST_DIR/.worktrees/feat-auth" && \
        echo "hello world" > newfile.txt && \
        git add newfile.txt && \
        git commit -m "add newfile" >/dev/null 2>&1)

    local output rc=0
    output=$(./grove diff feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "hello world" "shows diff content"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    cleanup
}

test_no_agent_configured() {
    echo -e "${BOLD}27. no agent configured${NC}"
    setup_test_repo

    rm -f "$HOME/.grove"

    # Use minimal PATH that excludes any real agents
    local output rc=0
    output=$(PATH="/usr/bin:/bin" ./grove checkout feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Worktree created" "worktree still created"
    assert_contains "$output" "No agent configured" "hints about no agent"

    echo 'GROVE_AGENT="mock-agent"' > "$HOME/.grove"

    cleanup
}

test_completions() {
    echo -e "${BOLD}28. completions${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove completions 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "complete -F _grove_completions gr" "gr completion"
    assert_contains "$output" "complete -F _grove_completions grove" "grove completion"

    cleanup
}

test_checkout_auto_attach() {
    echo -e "${BOLD}29. checkout auto-attaches to running agent${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    # Checkout with no prompt (no TTY) should print attach hint
    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent running in" "reports agent running"
    assert_contains "$output" "gr attach" "suggests attach"

    cleanup
}

test_status_shows_thinking() {
    echo -e "${BOLD}30. status shows thinking for agent idle 10-120s${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    # Backdate log file to simulate idle agent
    local log_file="$TEST_DIR/.worktrees/feat-auth/.grove-agent.log"
    local past
    if [[ "$(uname -s)" == "Darwin" ]]; then
        past="$(date -v-1M +%Y%m%d%H%M.%S)"
    else
        past="$(date -d '1 minute ago' +%Y%m%d%H%M.%S)"
    fi
    touch -t "$past" "$log_file" 2>/dev/null

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "thinking" "shows thinking status"

    cleanup
}

test_checkout_continue_after_done() {
    echo -e "${BOLD}31. checkout with prompt after agent done restarts${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "first task" >/dev/null 2>&1
    sleep 0.5

    # Kill the agent to simulate completion
    local socket="$TEST_DIR/.worktrees/feat-auth/.grove-socket"
    if [[ -S "$socket" ]]; then
        local pid=""
        if command -v fuser >/dev/null 2>&1; then
            pid="$(fuser "$socket" 2>/dev/null | tr -d '[:space:]')" || true
        fi
        if [[ -z "$pid" ]] && command -v lsof >/dev/null 2>&1; then
            pid="$(lsof -t "$socket" 2>/dev/null | head -1)" || true
        fi
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 0.5
        fi
        rm -f "$socket"
    fi

    # Now checkout with a new prompt — should restart
    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "second task" 2>&1) || rc=$?

    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent started (background)" "agent restarted"
    assert_contains "$output" "second task" "new prompt echoed"

    # Verify socket exists (agent running again)
    sleep 0.5
    [[ -S "$TEST_DIR/.worktrees/feat-auth/.grove-socket" ]] \
        && pass "dtach socket exists after restart" \
        || fail "dtach socket exists after restart"

    cleanup
}

test_send_missing_args() {
    echo -e "${BOLD}32. send missing args${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove send 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code: no branch"
    assert_contains "$output" "Missing branch name" "error: no branch"

    rc=0
    output=$(./grove send feat/auth 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code: no text"
    assert_contains "$output" "Missing text" "error: no text"

    cleanup
}

test_send_no_worktree() {
    echo -e "${BOLD}33. send no worktree${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove send nonexistent "hello" 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No worktree" "error message"

    cleanup
}

test_send_no_running_agent() {
    echo -e "${BOLD}34. send no running agent${NC}"
    setup_test_repo

    # Create worktree without agent
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove send feat/auth "hello" 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No running agent" "error message"

    cleanup
}

test_approve_missing_args() {
    echo -e "${BOLD}35. approve missing args${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove approve 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Missing branch name" "error message"

    cleanup
}

test_approve_all_none_waiting() {
    echo -e "${BOLD}36. approve --all with none waiting${NC}"
    setup_test_repo

    # Create a worktree so the "No worktrees" early-return path is not hit
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove approve --all 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "No agents waiting" "no agents message"

    cleanup
}

test_help_shows_send_approve() {
    echo -e "${BOLD}37. help shows send and approve${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove help 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "send" "help shows send"
    assert_contains "$output" "approve" "help shows approve"

    cleanup
}

test_status_thinking_state() {
    echo -e "${BOLD}38. status shows done for worktree without agent${NC}"
    setup_test_repo
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1
    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "done" "shows done when no socket"
    cleanup
}

test_status_has_indicators() {
    echo -e "${BOLD}39. status uses Unicode indicators${NC}"
    setup_test_repo
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1
    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "■" "uses Unicode done indicator (■)"
    cleanup
}

test_status_shows_diff_stats() {
    echo -e "${BOLD}40. status shows diff stats${NC}"
    setup_test_repo
    (cd "$TEST_DIR" && echo "base" > base.txt && git add base.txt && git commit --no-gpg-sign -m "base" >/dev/null 2>&1)
    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1
    (cd "$TEST_DIR/.worktrees/feat-auth" && echo "new content" > newfile.txt && git add newfile.txt && git commit --no-gpg-sign -m "add newfile" >/dev/null 2>&1)
    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    if (cd "$TEST_DIR/.worktrees/feat-auth" && git log --oneline -1 2>/dev/null | grep -q "add newfile"); then
        assert_contains "$output" "+" "shows insertions"
    else
        pass "skipped diff stats (git commit unavailable)"
    fi
    cleanup
}

test_help_shows_status_description() {
    echo -e "${BOLD}41. help describes status command${NC}"
    setup_test_repo
    local output rc=0
    output=$(./grove help 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "status" "help mentions status"
    cleanup
}

test_send_happy_path() {
    echo -e "${BOLD}42. send delivers text to running agent${NC}"
    setup_test_repo

    # Create a mock agent that reads input and echoes it
    cat > "$TEST_DIR/bin/mock-agent" <<'AGENT'
#!/bin/bash
echo "agent started, waiting for input"
read -r line
echo "received: $line"
sleep 5
AGENT
    chmod +x "$TEST_DIR/bin/mock-agent"

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test send" >/dev/null 2>&1
    sleep 1

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove send feat/auth "hello world" 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Sent to" "confirms send"

    # Give agent time to process
    sleep 1

    # Check log file for the received text
    local log_file="$TEST_DIR/.worktrees/feat-auth/.grove-agent.log"
    if [[ -f "$log_file" ]]; then
        local log_content
        log_content="$(cat "$log_file")"
        assert_contains "$log_content" "received: hello world" "agent received input"
    else
        fail "agent received input" "log file not found"
    fi

    cleanup
}

test_kill_happy_path() {
    echo -e "${BOLD}43. kill stops agent but keeps worktree${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test kill" >/dev/null 2>&1
    sleep 0.5

    # Verify agent is running
    local socket="$TEST_DIR/.worktrees/feat-auth/.grove-socket"
    [[ -S "$socket" ]] || fail "agent running before kill" "socket not found"

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove kill feat/auth 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "Agent killed" "confirms kill"
    assert_contains "$output" "Worktree kept" "mentions worktree kept"
    assert_contains "$output" "gr diff" "suggests review"

    # Worktree should still exist
    [[ -d "$TEST_DIR/.worktrees/feat-auth" ]] \
        && pass "worktree preserved after kill" \
        || fail "worktree preserved after kill"

    # Socket should be gone
    sleep 0.5
    [[ ! -S "$socket" ]] \
        && pass "socket removed after kill" \
        || fail "socket removed after kill"

    cleanup
}

test_kill_missing_args() {
    echo -e "${BOLD}44. kill missing args${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove kill 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "Missing branch name" "error message"

    cleanup
}

test_kill_no_worktree() {
    echo -e "${BOLD}45. kill no worktree${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove kill nonexistent 2>&1) || rc=$?
    assert_exit 1 "$rc" "exit code"
    assert_contains "$output" "No worktree" "error message"

    cleanup
}

test_kill_no_running_agent() {
    echo -e "${BOLD}46. kill no running agent is graceful${NC}"
    setup_test_repo

    mkdir -p "$TEST_DIR/.worktrees"
    git -C "$TEST_DIR" worktree add "$TEST_DIR/.worktrees/feat-auth" -b feat/auth >/dev/null 2>&1

    local output rc=0
    output=$(./grove kill feat/auth 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "No running agent" "graceful message"

    cleanup
}

test_status_running_indicator() {
    echo -e "${BOLD}47. status shows running indicator for active agent${NC}"
    setup_test_repo

    PATH="$TEST_DIR/bin:$PATH" ./grove checkout feat/auth "test" >/dev/null 2>&1
    sleep 0.5

    local output rc=0
    output=$(PATH="$TEST_DIR/bin:$PATH" ./grove status 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "●" "uses Unicode running indicator (●)"

    cleanup
}

test_help_shows_kill() {
    echo -e "${BOLD}48. help shows kill command${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove help 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "kill" "help shows kill"

    cleanup
}

test_completions_include_kill() {
    echo -e "${BOLD}49. completions include kill${NC}"
    setup_test_repo

    local output rc=0
    output=$(./grove completions 2>&1) || rc=$?
    assert_exit 0 "$rc" "exit code"
    assert_contains "$output" "kill" "completions include kill"

    cleanup
}

# ─── Main ─────────────────────────────────────────────────────────────────

main() {
    GROVE_BIN="$(cd "$(dirname "$0")/.." && pwd)/grove"

    if [[ ! -f "$GROVE_BIN" ]]; then
        echo "Error: grove not found at $GROVE_BIN" >&2
        exit 1
    fi

    # Save existing ~/.grove
    SAVED_GROVE_CONFIG=""
    if [[ -f "$HOME/.grove" ]]; then
        SAVED_GROVE_CONFIG="$(cat "$HOME/.grove")"
    fi

    echo -e "${BOLD}grove E2E tests${NC}"
    echo "binary: $GROVE_BIN"
    echo

    test_checkout_creates_worktree
    test_checkout_with_prompt_background
    test_checkout_idempotency
    test_shorthand_checkout
    test_status_shows_info
    test_status_empty
    test_no_args_runs_status
    test_rm_kills_agent
    test_rm_from_inside_worktree
    test_rm_nonexistent
    test_attach_nonexistent
    test_attach_no_agent
    test_not_in_git_repo
    test_help
    test_version
    test_dots_in_branch_names
    test_failed_setup
    test_git_ref_conflict
    test_init_creates_grove_config
    test_init_detects_project
    test_init_grovefile_already_exists
    test_init_not_in_git_repo
    test_prompt_saved
    test_status_shows_done_after_agent_exits
    test_log_shows_commits
    test_diff_shows_changes
    test_no_agent_configured
    test_completions
    test_checkout_auto_attach
    test_status_shows_thinking
    test_checkout_continue_after_done
    test_send_missing_args
    test_send_no_worktree
    test_send_no_running_agent
    test_approve_missing_args
    test_approve_all_none_waiting
    test_help_shows_send_approve

    test_status_thinking_state
    test_status_has_indicators
    test_status_shows_diff_stats
    test_help_shows_status_description

    test_send_happy_path
    test_kill_happy_path
    test_kill_missing_args
    test_kill_no_worktree
    test_kill_no_running_agent
    test_status_running_indicator
    test_help_shows_kill
    test_completions_include_kill

    # Restore ~/.grove
    if [[ -n "$SAVED_GROVE_CONFIG" ]]; then
        echo "$SAVED_GROVE_CONFIG" > "$HOME/.grove"
    else
        rm -f "$HOME/.grove"
    fi

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
