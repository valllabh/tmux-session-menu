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

# menu: SS3 arrows (ESC O B) also navigate, not just CSI (ESC [ B)
new_sock ss3
for s in alpha beta gamma; do tmux new-session -d -s "$s" 'sleep 300'; done
printf '\eOBkyq' | _tmux_menu >/dev/null 2>&1   # SS3 Down to beta, k, y, q
assert_eq "SS3 down + k kills beta" "alpha gamma " "$(names)"
end_sock

# menu: a no answer at the confirm leaves the session alone
new_sock decline
for s in one two; do tmux new-session -d -s "$s" 'sleep 300'; done
printf 'knq' | _tmux_menu >/dev/null 2>&1        # k on one, answer n, q
assert_eq "kill declined keeps sessions" "one two " "$(names)"
end_sock

# labels: a meaningful pane title is shown, a shell style host title is dropped
new_sock title
tmux new-session -d -s work 'sleep 300'
tmux select-pane -t work -T '✳ Fix the parser'
label=$(COLUMNS=120 _tmux_menu_labels)
case "$label" in *"✳ Fix the parser"*) echo "ok   - pane title shown in label" ;;
                 *) echo "FAIL - pane title missing (got [$label])"; fail=1 ;; esac
tmux select-pane -t work -T "${HOSTNAME:-$(hostname)}: ~/work"
label=$(COLUMNS=120 _tmux_menu_labels)
case "$label" in *"~/work"*) echo "FAIL - host title not dropped (got [$label])"; fail=1 ;;
                 *) echo "ok   - host style title dropped" ;; esac
end_sock

# labels: long titles are truncated so each entry stays a single line
new_sock trunc
tmux new-session -d -s work 'sleep 300'
tmux select-pane -t work -T "$(printf 'x%.0s' {1..200})"
label=$(COLUMNS=60 _tmux_menu_labels)
assert_eq "label truncated to width" "52" "${#label}"
# COLUMNS is 0 with no tty: fall back to tput, do not clamp to the 20 char floor
label=$(COLUMNS=0 _tmux_menu_labels)
if [ "${#label}" -gt 40 ]; then echo "ok   - zero COLUMNS falls back to tput width"
else echo "FAIL - zero COLUMNS clamped the label (got ${#label} chars)"; fail=1; fi
end_sock

[ "$fail" -eq 0 ] && echo "all tests passed"
exit "$fail"
