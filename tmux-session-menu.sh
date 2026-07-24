# tmux-session-menu
# At shell login, pop a tmux session menu over a blank screen: pick a running
# session or start a new one, with zombie garbage collection. Source from ~/.bashrc.
#
# Provides:
#   tmux-gc [-v]   garbage collect zombie clients and abandoned empty sessions
#   tm             open the menu on demand
#
# Auto launch: when sourced by an interactive shell that is not already inside
# tmux, the menu opens automatically. Set TMUX_MENU_AUTOLAUNCH=0 to disable.
#
# Tunables:
#   TMUX_GC_CLIENT_IDLE    seconds before an idle client is reaped   (default 300)
#   TMUX_GC_SESSION_IDLE   seconds before an empty session is killed (default 3600)
#   TMUX_MENU_FORMAT       tmux format for one menu row

# The disposable session the menu floats over, so the popup is the only thing on
# screen instead of your last session's live output. Created blank with its
# status bar off, killed the instant you pick or create, and reaped by tmux-gc
# if you dismiss onto it. The name is prefixed so it does not collide with a real
# session and reads as ours if it is ever seen.
_TSM_SCRATCH=_tsm_scratch

# Garbage-collect tmux zombies: detach dead clients, kill abandoned empty sessions.
#   tmux-gc        run once (silent)
#   tmux-gc -v     run and print what was cleaned
tmux-gc() {
  command -v tmux >/dev/null 2>&1 || return 0
  local now idle_c idle_s tty act name att cmd reaped=0 killed=0
  now=$(date +%s)
  idle_c=${TMUX_GC_CLIENT_IDLE:-300}
  idle_s=${TMUX_GC_SESSION_IDLE:-3600}
  # 1) zombie clients: dead or idle connections still holding a session "attached"
  while read -r tty act; do
    [ -n "$tty" ] || continue
    [ $(( now - act )) -ge "$idle_c" ] && tmux detach-client -t "$tty" 2>/dev/null && reaped=$((reaped+1))
  done < <(tmux list-clients -F '#{client_tty} #{client_activity}' 2>/dev/null)
  # 2) abandoned sessions: detached, running only a bare shell, idle past threshold.
  #    Our own scratch holder, left detached by a dismiss, is disposable at once.
  while read -r name att cmd act; do
    [ -n "$name" ] || continue
    if [ "$name" = "$_TSM_SCRATCH" ] && [ "$att" = "0" ]; then
      tmux kill-session -t "$name" 2>/dev/null && killed=$((killed+1)); continue
    fi
    [ "$att" = "0" ] && [ $(( now - act )) -ge "$idle_s" ] || continue
    case "$cmd" in
      bash|-bash|zsh|sh|fish) tmux kill-session -t "$name" 2>/dev/null && { killed=$((killed+1)); [ "${1:-}" = "-v" ] && echo "gc: killed idle empty session '$name'"; } ;;
    esac
  done < <(tmux ls -F '#{session_name} #{session_attached} #{pane_current_command} #{session_activity}' 2>/dev/null)
  [ "${1:-}" = "-v" ] && echo "tmux-gc: reaped $reaped client(s), killed $killed session(s)"
  return 0
}

# One row per session: how big it is, which project it sits in, and what it is
# doing. tmux resolves the pane formats against the session active pane, so a
# session running Claude Code shows the task in hand rather than a bare number.
# Two things only earn their place when they say something new: the directory is
# dropped when it matches the session name, and the pane title gives way to the
# command name when it is only the host name or the session name. The title is
# capped so one talkative session cannot stretch the menu past the terminal.
_TMUX_MENU_FORMAT_DEFAULT='#{session_windows}w#{?session_attached, · attached,}  #{?#{==:#{b:pane_current_path},#{session_name}},,#{b:pane_current_path}  }#{?#{||:#{m:*#{host_short}*,#{pane_title}},#{==:#{pane_title},#{session_name}}},#{pane_current_command},#{=40:pane_title}}'

_tmux_menu_format() {
  printf '%s' "${TMUX_MENU_FORMAT:-$_TMUX_MENU_FORMAT_DEFAULT}"
}

# One display-menu triple per session: label, shortcut key, command. Fills the
# global _TMUX_MENU_ITEMS because a function cannot return an array. The scratch
# holder is skipped so a lingering one never shows as a choice.
#
# display-menu expands both the label and the command as formats, so a literal
# hash in a pane title has to be doubled or tmux swallows it, and the command is
# re-parsed by tmux, so a quote or backslash in a session name has to be escaped
# or it ends the argument early. Choosing a session switches to it and disposes
# of the holder in one command, the two separated by a bare " ; " inside the
# single command string.
_tmux_menu_items() {
  local keys='abcefghijklmoprstuvwyz' i=0 name label esc tab
  tab=$(printf '\t')
  _TMUX_MENU_ITEMS=()
  while IFS="$tab" read -r name label; do
    [ -n "$name" ] || continue
    [ "$name" = "$_TSM_SCRATCH" ] && continue
    [ "$i" -lt "${#keys}" ] || break
    esc=${name//\\/\\\\}; esc=${esc//\"/\\\"}
    _TMUX_MENU_ITEMS+=("${label//#/##}" "${keys:$i:1}" "switch-client -t \"$esc\" ; kill-session -t $_TSM_SCRATCH")
    i=$((i+1))
  done < <(tmux ls -F "#{session_name}$tab#{session_name}  $(_tmux_menu_format)" 2>/dev/null)
}

# The picker is tmux own. Attach to a blank throwaway session, then open a
# display-menu over it: one key per running session, plus the two things
# choose-tree cannot do, which are starting a session and getting out of the way.
# The full chooser is one key further in, for filtering, killing and previews.
# Nothing of ours draws the screen, which is the whole point: it cannot fail to
# render at login.
#
# The `run-shell -d` is not a cosmetic pause and must not be removed. A
# display-menu queued directly behind attach-session is silently dropped,
# because the client has not finished attaching and has no screen to draw an
# overlay on, and you land in a bare session with no menu at all. run-shell
# blocks the command queue, so the menu is dispatched a beat later, once the
# client is up. Any non zero delay works, 0 does not, and the margin here is
# generous because the cost of it being too short is no menu.
#
# Every path that commits to a session disposes of the holder inline; the one
# path that does not is dismissing the menu with Escape, which leaves you sitting
# in the blank holder. tmux exposes no event for a menu closing, so this cannot
# be cleaned on the spot: tmux-gc reaps the holder on the next run instead.
_tmux_menu() {
  _tmux_menu_items
  # Nothing to choose between. An empty menu at login is a dead end, so skip
  # straight to the one useful thing.
  if [ ${#_TMUX_MENU_ITEMS[@]} -eq 0 ]; then tmux new-session; return; fi
  tmux kill-session -t "$_TSM_SCRATCH" 2>/dev/null
  tmux new-session -d -s "$_TSM_SCRATCH"
  tmux set-option -t "$_TSM_SCRATCH" status off
  tmux attach-session -t "$_TSM_SCRATCH" \; run-shell -d 0.3 \; display-menu -T ' tmux sessions ' -x C -y C \
    "${_TMUX_MENU_ITEMS[@]}" \
    '' \
    'New session'         n "new-session ; kill-session -t $_TSM_SCRATCH" \
    'New session, named'  N "command-prompt -p 'new session name:' 'new-session -s \"%%\" ; kill-session -t $_TSM_SCRATCH'" \
    '' \
    'Chooser: filter, kill, preview' / "choose-tree -Zs -F \"$(_tmux_menu_format)\" \"switch-client -t '%%' ; kill-session -t $_TSM_SCRATCH\"" \
    'Detach to a plain shell'        d 'detach-client'
}

# Re-open the menu on demand (after detaching, or after quitting to a shell).
tm() {
  if [ -n "$TMUX" ]; then echo "Already inside tmux. Press Ctrl-b s for the chooser, or detach with Ctrl-b d first."; return 1; fi
  tmux-gc
  _tmux_menu
}

# Auto launch at interactive login when not already inside tmux.
if [ "${TMUX_MENU_AUTOLAUNCH:-1}" = "1" ] && command -v tmux >/dev/null 2>&1 \
   && [ -z "$TMUX" ] && [ -n "$PS1" ]; then
  tmux-gc
  _tmux_menu
fi
