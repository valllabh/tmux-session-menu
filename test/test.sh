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
rows()  { tmux ls -F "$(_tmux_menu_format)" 2>/dev/null; }

# A pane reports no command for the first instant of its life, which is long
# enough to make gc see a session as busy and the test flake. Wait for the
# session named in $1 to actually be running something.
settle() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$(tmux display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null)" ] && return 0
    sleep 0.2
  done
}

# tmux-gc removes an empty detached session but keeps one running a real command
new_sock gc
tmux new-session -d -s empty
tmux new-session -d -s busy 'sleep 300'
settle empty; settle busy
TMUX_GC_SESSION_IDLE=0 TMUX_GC_CLIENT_IDLE=0 tmux-gc >/dev/null
assert_eq "gc removes empty, keeps busy" "busy " "$(names)"
end_sock

# tmux-gc reaps a detached scratch holder at once, regardless of idle, but leaves
# an ordinary detached session alone until it is actually idle
new_sock scratch
tmux new-session -d -s _tsm_scratch
tmux new-session -d -s ordinary
settle ordinary
tmux-gc >/dev/null    # default idle threshold of an hour: only the holder should go
assert_eq "gc reaps the scratch holder immediately, keeps the rest" "ordinary " "$(names)"
end_sock

# the chooser format: a meaningful pane title is shown, a shell style host title
# gives way to the command name
new_sock format
tmux new-session -d -s work 'sleep 300'
tmux select-pane -t work -T '✳ Fix the parser'
row=$(rows)
case "$row" in *"✳ Fix the parser"*) echo "ok   - pane title shown in the row" ;;
               *) echo "FAIL - pane title missing (got [$row])"; fail=1 ;; esac
tmux select-pane -t work -T "${HOSTNAME:-$(hostname)}: ~/work"
row=$(rows)
case "$row" in *"~/work"*) echo "FAIL - host title not dropped (got [$row])"; fail=1 ;;
               *sleep*)    echo "ok   - host style title gives way to the command" ;;
               *)          echo "FAIL - no command in the row (got [$row])"; fail=1 ;; esac
tmux select-pane -t work -T 'work'
row=$(rows)
case "$row" in *sleep*) echo "ok   - session name as title gives way to the command" ;;
               *) echo "FAIL - session name title not dropped (got [$row])"; fail=1 ;; esac
end_sock

# the chooser format: the project directory is shown when it says something the
# session name does not, and dropped when it only repeats it
new_sock project
tmux new-session -d -s work -c "$ROOT" 'sleep 300'
case "$(rows)" in *"tmux-session-menu"*) echo "ok   - project directory shown" ;;
                  *) echo "FAIL - project directory missing (got [$(rows)])"; fail=1 ;; esac
end_sock
new_sock samedir
tmux new-session -d -s tmux-session-menu -c "$ROOT" 'sleep 300'
_tmux_menu_items
# The label is the session name plus the format, so the name should appear once,
# not twice over.
assert_eq "directory dropped when it repeats the session name" "1" \
  "$(printf '%s' "${_TMUX_MENU_ITEMS[0]}" | awk -v RS='tmux-session-menu' 'END{print NR-1}')"
end_sock

# the chooser format: a talkative pane title is capped so it cannot stretch the
# menu past the terminal
new_sock cap
tmux new-session -d -s work 'sleep 300'
tmux select-pane -t work -T "$(printf 'x%.0s' {1..100})"
xs=$(rows); xs=${xs##*[!x]}
assert_eq "long pane title capped" "40" "${#xs}"
end_sock

# the chooser format: one line per session, window count included, no tmux error
new_sock shape
for s in alpha beta; do tmux new-session -d -s "$s" 'sleep 300'; done
assert_eq "one row per session" "2" "$(rows | wc -l)"
case "$(rows)" in *"1w"*) echo "ok   - window count in the row" ;;
                  *) echo "FAIL - window count missing"; fail=1 ;; esac
case "$(rows)" in *'#{'*) echo "FAIL - format left unexpanded (got [$(rows)])"; fail=1 ;;
                  *) echo "ok   - format fully expanded by tmux" ;; esac
end_sock

# TMUX_MENU_FORMAT overrides the default row format
new_sock override
tmux new-session -d -s only 'sleep 300'
assert_eq "TMUX_MENU_FORMAT is honoured" "only!" "$(TMUX_MENU_FORMAT='#{session_name}!' rows)"
end_sock

# the menu items: three display-menu arguments per session, distinct keys, a
# label carrying both the session name and the row format, and a command that
# switches to the session and disposes of the holder
new_sock items
tmux new-session -d -s alpha 'sleep 300'
tmux new-session -d -s beta  'sleep 300'
settle alpha; settle beta
_tmux_menu_items
assert_eq "three menu arguments per session" "6" "${#_TMUX_MENU_ITEMS[@]}"
assert_eq "first label names its session" "alpha" "${_TMUX_MENU_ITEMS[0]%% *}"
assert_eq "keys are handed out in order" "a" "${_TMUX_MENU_ITEMS[1]}"
assert_eq "second session gets the next key" "b" "${_TMUX_MENU_ITEMS[4]}"
case "${_TMUX_MENU_ITEMS[0]}" in *sleep*) echo "ok   - label carries the row format" ;;
                                 *) echo "FAIL - label missing the row format (got [${_TMUX_MENU_ITEMS[0]}])"; fail=1 ;; esac
case "${_TMUX_MENU_ITEMS[2]}" in
  "switch-client -t \"alpha\" ; kill-session -t "*) echo "ok   - choosing switches and disposes the holder" ;;
  *) echo "FAIL - item command not switch+dispose (got [${_TMUX_MENU_ITEMS[2]}])"; fail=1 ;; esac
end_sock

# session shortcut keys never collide with the fixed items. display-menu binds a
# key to the first item that claims it, and session items come first, so a
# session landing on d, n, q or x would shadow Detach, New or a habit key.
new_sock keypool
for s in s1 s2 s3 s4 s5 s6 s7; do tmux new-session -d -s "$s" 'sleep 300'; done
_tmux_menu_items
bad=""; i=1
while [ "$i" -lt "${#_TMUX_MENU_ITEMS[@]}" ]; do
  case "${_TMUX_MENU_ITEMS[$i]}" in d|n|q|x) bad="$bad ${_TMUX_MENU_ITEMS[$i]}" ;; esac
  i=$((i+3))
done
assert_eq "session keys avoid the fixed keys d n q x" "" "$bad"
end_sock

# the scratch holder is never offered as a session to pick
new_sock exclude
tmux new-session -d -s real 'sleep 300'
tmux new-session -d -s _tsm_scratch
settle real
_tmux_menu_items
assert_eq "holder excluded: only the real session is listed" "3" "${#_TMUX_MENU_ITEMS[@]}"
assert_eq "the one listed item is the real session" "real" "${_TMUX_MENU_ITEMS[0]%% *}"
end_sock

# a session name with a hash and a quote survives both format expansion and the
# tmux parse of the command the item runs. source-file parses a command string
# exactly as display-menu does, so it stands in for choosing the item.
new_sock quoting
tmux new-session -d -s 'we#ird "one"' 'sleep 300'
settle 'we#ird "one"'
_tmux_menu_items
case "${_TMUX_MENU_ITEMS[0]}" in 'we##ird "one"'*) echo "ok   - hash doubled so tmux shows it" ;;
                                 *) echo "FAIL - hash not doubled (got [${_TMUX_MENU_ITEMS[0]}])"; fail=1 ;; esac
sw=${_TMUX_MENU_ITEMS[2]%% ; *}   # the switch-client half of the command
cmd="display-message -p -F '#{session_name}' ${sw#switch-client }"
assert_eq "menu command targets the right session" 'we#ird "one"' \
  "$(printf '%s\n' "$cmd" | tmux source-file - 2>&1)"
end_sock

# the menu is floated over a blank holder and dispatched behind a run-shell delay.
# Two things this guards, neither catchable without a real terminal: tmux silently
# drops a display-menu queued directly behind attach-session, so the menu must be
# deferred; and the holder must exist with its status bar off so the popup sits on
# a clean screen. The attach-session call is stubbed to capture its arguments; the
# rest run for real on the socket, so the holder it builds can be inspected.
new_sock dispatch
tmux new-session -d -s solo 'sleep 300'
settle solo
line=$(
  tmux() { case "$1" in attach-session) printf '%s' "$*" ;; *) command tmux -L "$sock" "$@" ;; esac; }
  _tmux_menu
)
case "$line" in
  "attach-session -t _tsm_scratch ; run-shell -d "*" ; display-menu"*) echo "ok   - menu deferred behind a run-shell delay over the holder" ;;
  *) echo "FAIL - menu not deferred over the holder (got [${line:0:80}])"; fail=1 ;;
esac
assert_eq "holder created with its status bar off" "off" \
  "$(tmux show-options -t _tsm_scratch status 2>/dev/null | awk '{print $2}')"
case "$line" in *"new-session ; kill-session -t "*) echo "ok   - the new session item disposes the holder too" ;;
                *) echo "FAIL - new session item does not dispose the holder"; fail=1 ;; esac
end_sock

# no real sessions: skip the menu and just start one, rather than show an empty
# popup over a holder
new_sock none
n=$(
  tmux() { case "$1" in new-session) printf 'new-session\n' ;; *) command tmux -L "$sock" "$@" ;; esac; }
  _tmux_menu
)
assert_eq "empty server starts a session directly" "new-session" "$n"
end_sock

[ "$fail" -eq 0 ] && echo "all tests passed"
exit "$fail"
