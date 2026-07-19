#!/usr/bin/env bash
# Tests run against isolated tmux server sockets, never your real sessions.
# Each scenario uses its own socket so there is no cross test interference.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export TMUX_TMPDIR=${TMPDIR:-/tmp}
export TMUX_MENU_AUTOLAUNCH=0
fail=0
sock=""

# shellcheck disable=SC1091
source "$ROOT/tmux-session-menu.sh"
# route every tmux call inside the sourced functions to the current test socket
tmux() { command tmux -L "$sock" "$@"; }

new_sock() { sock="tsm-test-$1"; command tmux -L "$sock" kill-server 2>/dev/null || true; }
end_sock() { command tmux -L "$sock" kill-server 2>/dev/null || true; }
trap 'end_sock' EXIT

assert_eq() { # message expected actual
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1 (expected [$2] got [$3])"; fail=1; fi
}

names() { tmux ls -F '#{session_name}' 2>/dev/null | sort | tr '\n' ' '; }

# tmux-gc removes an empty detached session but keeps one running a real command
new_sock gc
tmux new-session -d -s empty
tmux new-session -d -s busy 'sleep 300'
TMUX_GC_SESSION_IDLE=0 TMUX_GC_CLIENT_IDLE=0 tmux-gc >/dev/null
assert_eq "gc removes empty, keeps busy" "busy " "$(names)"
end_sock

# menu: k kills the highlighted session after a yes confirm
new_sock kill
for s in alpha beta gamma; do tmux new-session -d -s "$s" 'sleep 300'; done
printf '\e[Bkyq' | _tmux_menu >/dev/null 2>&1   # Down to beta, k, y, q
assert_eq "k kills highlighted beta" "alpha gamma " "$(names)"
end_sock

# menu: a no answer at the confirm leaves the session alone
new_sock decline
for s in one two; do tmux new-session -d -s "$s" 'sleep 300'; done
printf 'knq' | _tmux_menu >/dev/null 2>&1        # k on one, answer n, q
assert_eq "kill declined keeps sessions" "one two " "$(names)"
end_sock

[ "$fail" -eq 0 ] && echo "all tests passed"
exit "$fail"
