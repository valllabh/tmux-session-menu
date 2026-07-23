# tmux-session-menu
# Interactive tmux session picker for your shell login, with zombie garbage
# collection. Source this file from ~/.bashrc.
#
# Provides:
#   tmux-gc [-v]   garbage collect zombie clients and abandoned empty sessions
#   tm             open the session menu on demand
#   _tmux_menu     the menu itself (used at login and by tm)
#
# Auto launch: when sourced by an interactive shell that is not already inside
# tmux, the menu opens automatically. Set TMUX_MENU_AUTOLAUNCH=0 to disable.
#
# Tunables:
#   TMUX_GC_CLIENT_IDLE    seconds before an idle client is reaped   (default 300)
#   TMUX_GC_SESSION_IDLE   seconds before an empty session is killed (default 3600)

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
  # 2) abandoned sessions: detached, running only a bare shell, idle past threshold
  while read -r name att cmd act; do
    [ -n "$name" ] || continue
    [ "$att" = "0" ] && [ $(( now - act )) -ge "$idle_s" ] || continue
    case "$cmd" in
      bash|-bash|zsh|sh|fish) tmux kill-session -t "$name" 2>/dev/null && { killed=$((killed+1)); [ "${1:-}" = "-v" ] && echo "gc: killed idle empty session '$name'"; } ;;
    esac
  done < <(tmux ls -F '#{session_name} #{session_attached} #{pane_current_command} #{session_activity}' 2>/dev/null)
  [ "${1:-}" = "-v" ] && echo "tmux-gc: reaped $reaped client(s), killed $killed session(s)"
  return 0
}

# Build one display label per session. The pane title is appended when it says
# something the command name does not: Claude Code, vim and friends set it to
# the task in hand, so "claude" becomes "claude · ✳ Fix the parser". Titles that
# are just the host, the session name or the command are dropped as noise.
# Labels are truncated to the terminal width so every entry stays one line, which
# the menu redraw math depends on.
_tmux_menu_labels() {
  local t=$'\t' width host max name w att cmd title label
  # COLUMNS is unset in a non interactive shell and 0 with no tty, so neither
  # value can be trusted on its own. Fall back to tput, then to 80.
  width=${COLUMNS:-0}
  case "$width" in ''|*[!0-9]*) width=0 ;; esac
  [ "$width" -gt 0 ] || width=$(tput cols 2>/dev/null)
  case "$width" in ''|*[!0-9]*|0) width=80 ;; esac
  host=${HOSTNAME:-$(hostname 2>/dev/null)}; host=${host:-$'\x01'}
  max=$((width-8)); (( max < 20 )) && max=20
  while IFS="$t" read -r name w att cmd title; do
    [ -n "$name" ] || continue
    # A real title says more than the command name does, so it replaces it.
    case "$title" in
      ''|"$name"|"$cmd"|*"$host"*) label="$name  (${w}w, $att, $cmd)" ;;
      *)                           label="$name  (${w}w, $att) · $title" ;;
    esac
    label=${label//[$'\t\r\n']/ }
    (( ${#label} > max )) && label="${label:0:$((max-1))}…"
    printf '%s\n' "$label"
  done < <(tmux ls -F "#{session_name}$t#{session_windows}$t#{?session_attached,attached,detached}$t#{pane_current_command}$t#{pane_title}" 2>/dev/null)
}

# Interactive tmux session menu. Owns the whole loop: lists sessions, lets you
# navigate (Up/Down + Enter), jump by letter, kill a session (k, with confirm),
# pick "New session", or drop to a plain shell (q). Redraws in place.
_tmux_menu() {
  local -a sess labels letters=({a..z})
  local n sel=0 i key rest ans drawn=0
  while :; do
    mapfile -t sess < <(tmux ls -F '#{session_name}' 2>/dev/null)
    if [ ${#sess[@]} -eq 0 ]; then
      (( drawn > 0 )) && printf '\e[%dA\e[J' "$drawn"    # clear leftover menu
      printf '\e[?25h'; tmux new-session; return
    fi
    mapfile -t labels < <(_tmux_menu_labels)
    labels+=("New session"); n=${#labels[@]}
    (( sel >= n )) && sel=$((n-1)); (( sel < 0 )) && sel=0
    (( drawn > 0 )) && printf '\e[%dA\e[J' "$drawn"       # erase previous render
    printf '\e[?25l'
    printf 'Session  —  ↑/↓+Enter attach · letter jump · k kill · q shell\n'
    for ((i=0; i<n; i++)); do
      if ((i==sel)); then printf '\e[7m  %s) %s  \e[0m\n' "${letters[i]}" "${labels[i]}"
      else            printf '  %s) %s\n' "${letters[i]}" "${labels[i]}"; fi
    done
    drawn=$((n+1))
    IFS= read -rsn1 key
    case "$key" in
      $'\e') # arrow key: CSI (ESC [ A/B) or SS3 (ESC O A/B). Read the two trailing
             # bytes one at a time, tolerating latency between them.
             read -rsn2 -t 0.4 rest
             case "$rest" in
               '[A'|'OA') ((sel=(sel-1+n)%n)) ;;
               '[B'|'OB') ((sel=(sel+1)%n)) ;;
             esac ;;
      '')    printf '\e[?25h'
             if (( sel >= ${#sess[@]} )); then tmux new-session; else tmux attach -t "${sess[sel]}"; fi
             return ;;
      q|Q)   printf '\e[?25h'; return ;;                  # plain shell
      k|K)                                                # kill highlighted session
             if (( sel < ${#sess[@]} )); then
               printf '\e[?25h'; printf 'Kill session "%s"? [y/N] ' "${sess[sel]}"
               IFS= read -rsn1 ans; printf '\n'
               case "$ans" in y|Y) tmux kill-session -t "${sess[sel]}" 2>/dev/null;; esac
               drawn=$((n+2))                             # erase menu + confirm line, redraw in place
             fi ;;
      [a-z]) for ((i=0;i<n;i++)); do [ "${letters[i]}" = "$key" ] && sel=$i; done
             printf '\e[?25h'
             if (( sel >= ${#sess[@]} )); then tmux new-session; else tmux attach -t "${sess[sel]}"; fi
             return ;;
    esac
  done
}

# Re-open the session menu on demand (after quitting to a shell, or after detach).
tm() {
  if [ -n "$TMUX" ]; then echo "Already inside tmux — detach first with Ctrl-b d, then run tm"; return 1; fi
  tmux-gc; _tmux_menu
}

# Auto launch at interactive login when not already inside tmux.
if [ "${TMUX_MENU_AUTOLAUNCH:-1}" = "1" ] && command -v tmux >/dev/null 2>&1 \
   && [ -z "$TMUX" ] && [ -n "$PS1" ]; then
  tmux-gc
  _tmux_menu
fi
