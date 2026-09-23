#!/usr/bin/env bash
# Smoke tests for root Claude component hook routing and PR safeguards.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
HOOK="${REPO_ROOT}/.claude/hooks/component-pre-tool-use.sh"
TEST_ROOT=$(mktemp -d)
BIN="${TEST_ROOT}/bin"
LOG="${TEST_ROOT}/commands.log"
mkdir -p "$BIN"
touch "$LOG"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

[[ -f "$HOOK" ]] || fail "missing $HOOK"
command -v git >/dev/null 2>&1 || fail "git not on PATH"
command -v jq >/dev/null 2>&1 || fail "jq not on PATH"

cat >"${BIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'make|%s\n' "$*" >>"$HOOK_COMMAND_LOG"
if [[ -n "${OPERATOR_TEST_GENERATE:-}" && "${!#}" == test \
  && "${2:-}" == "${OPERATOR_TEST_DIR:-}" ]]; then
  mkdir -p "$(dirname "$OPERATOR_TEST_GENERATE")"
  printf 'generated: true\n' >"$OPERATOR_TEST_GENERATE"
fi
EOF

cat >"${BIN}/gofmt" <<'EOF'
#!/usr/bin/env bash
printf 'gofmt|%s\n' "$*" >>"$HOOK_COMMAND_LOG"
EOF

cat >"${BIN}/ginkgo" <<'EOF'
#!/usr/bin/env bash
printf 'ginkgo|%s\n' "$*" >>"$HOOK_COMMAND_LOG"
EOF

cat >"${BIN}/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${GH_FAIL:-0}" == 1 ]]; then
  exit 1
fi
printf 'osac-project/osac\tmain\n'
EOF

chmod +x "${BIN}/make" "${BIN}/gofmt" "${BIN}/ginkgo" "${BIN}/gh"
export PATH="${BIN}:${PATH}"
export HOOK_COMMAND_LOG="$LOG"

# Clear the stub command log before each independent scenario.
clear_log() { : >"$LOG"; }

# Create a fixture repository with an upstream base ref for PR path resolution.
init_repo() {
  local repo=$1
  mkdir -p "$repo/proto/private" "$repo/fulfillment-service/internal" "$repo/osac-operator"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email hooks-test@example.invalid
  git -C "$repo" config user.name hooks-test
  printf 'syntax = "proto3";\n' >"$repo/proto/private/base.proto"
  printf 'package service\n' >"$repo/fulfillment-service/main.go"
  printf 'package internal\n' >"$repo/fulfillment-service/internal/main.go"
  printf 'package operator\n' >"$repo/osac-operator/main.go"
  git -C "$repo" add proto fulfillment-service osac-operator
  git -C "$repo" commit -q -m seed
  git -C "$repo" remote add origin https://github.com/osac-project/osac.git
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" checkout -q -b feature
}

# Send a serialized Bash PreToolUse event to the component hook.
run_hook() {
  local repo=$1 command=$2
  jq -nc --arg cwd "$repo" --arg command "$command" \
    '{cwd:$cwd,tool_input:{command:$command}}' \
    | bash "$HOOK"
}

# Require a specific stub command to have been invoked.
assert_log_contains() {
  local expected=$1
  [[ "$(cat "$LOG")" == *"$expected"* ]] || fail "expected command log to contain: $expected"
}

# Assert the hook blocks the tool action with the expected validation message.
expect_hook_failure() {
  local repo=$1 command=$2 expected=$3 output rc=0
  output=$(run_hook "$repo" "$command" 2>&1) || rc=$?
  [[ "$rc" == 2 ]] || fail "expected hook exit 2, got $rc: $output"
  [[ "$output" == *"$expected"* ]] || fail "expected '$expected' in output: $output"
}

# Cover proto lint detection before a new proto file is added and committed.
test_untracked_proto_commit() {
  local repo="${TEST_ROOT}/untracked-proto"
  init_repo "$repo"
  printf 'message New {}\n' >"$repo/proto/private/new.proto"
  clear_log
  run_hook "$repo" "git add proto/private/new.proto && git commit -m schema"
  assert_log_contains "make|-C $repo/proto lint"
  pass "commit checks include new untracked proto files"
}

# Ensure a chained commit and PR command runs both pre-command validations.
test_chained_commit_and_pr() {
  local repo="${TEST_ROOT}/chained"
  init_repo "$repo"
  printf '\n// changed\n' >>"$repo/proto/private/base.proto"
  printf '\n// changed\n' >>"$repo/fulfillment-service/main.go"
  printf '\n// changed\n' >>"$repo/osac-operator/main.go"
  clear_log
  run_hook "$repo" "git add . && git commit -m changes && git push && gh pr create --repo osac-project/osac"
  assert_log_contains "make|-C $repo/proto lint"
  assert_log_contains "ginkgo|run -r internal"
  assert_log_contains "make|-C $repo/osac-operator test"
  pass "chained commit and PR commands run both validations"
}

# Ensure failed base resolution still formats tracked and untracked service Go files.
test_fallback_formats_service_files() {
  local repo="${TEST_ROOT}/fallback"
  init_repo "$repo"
  printf '\n// changed\n' >>"$repo/fulfillment-service/main.go"
  printf 'package untracked\n' >"$repo/fulfillment-service/untracked.go"
  clear_log
  GH_FAIL=1 run_hook "$repo" "gh pr create --repo osac-project/osac"
  assert_log_contains "gofmt|-s -w $repo/fulfillment-service/main.go"
  assert_log_contains "gofmt|-s -w $repo/fulfillment-service/internal/main.go"
  assert_log_contains "gofmt|-s -w $repo/fulfillment-service/untracked.go"
  pass "base-resolution fallback formats tracked service files"
}

# Ensure generated operator changes after make test block PR creation.
test_operator_generation_drift_fails() {
  local repo="${TEST_ROOT}/operator-drift"
  init_repo "$repo"
  printf '\n// changed\n' >>"$repo/osac-operator/main.go"
  clear_log
  OPERATOR_TEST_GENERATE="$repo/osac-operator/generated-crd.yaml" \
    OPERATOR_TEST_DIR="$repo/osac-operator" \
    expect_hook_failure "$repo" "gh pr create --repo osac-project/osac" \
      "make test modified or generated osac-operator files"
  pass "untracked operator manifest generation during make test blocks PR creation"
}

test_untracked_proto_commit
test_chained_commit_and_pr
test_fallback_formats_service_files
test_operator_generation_drift_fails
