# tmux-session-menu (zsh / oh-my-zsh plugin)
# zsh port of tmux-session-menu.sh. Same behaviour, zsh native reader and arrays.
#
# oh-my-zsh: clone into $ZSH_CUSTOM/plugins/tmux-session-menu and add
#   plugins=(... tmux-session-menu)
# Other managers: source this file.
#
# Provides: tmux-gc [-v], tm, _tmux_menu
# Tunables: TMUX_MENU_AUTOLAUNCH (default 1), TMUX_GC_CLIENT_IDLE (300),
#           TMUX_GC_SESSION_IDLE (3600)

tmux-gc() {
  emulate -L zsh
  command -v tmux >/dev/null 2>&1 || return 0
  local now idle_c idle_s tty act name att cmd reaped=0 killed=0
  now=$(date +%s)
  idle_c=${TMUX_GC_CLIENT_IDLE:-300}
  idle_s=${TMUX_GC_SESSION_IDLE:-3600}
  # zombie clients: dead or idle connections still holding a session "attached"
  while read -r tty act; do
    [ -n "$tty" ] || continue
    [ $(( now - act )) -ge "$idle_c" ] && tmux detach-client -t "$tty" 2>/dev/null && reaped=$((reaped+1))
  done < <(tmux list-clients -F '#{client_tty} #{client_activity}' 2>/dev/null)
  # abandoned sessions: detached, running only a bare shell, idle past threshold
  while read -r name att cmd act; do
    [ -n "$name" ] || continue
    [ "$att" = "0" ] && [ $(( now - act )) -ge "$idle_s" ] || continue
    case "$cmd" in
      bash|-bash|zsh|-zsh|sh|fish) tmux kill-session -t "$name" 2>/dev/null && { killed=$((killed+1)); [ "${1:-}" = "-v" ] && echo "gc: killed idle empty session '$name'"; } ;;
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
  emulate -L zsh
  local t=$'\t' width=${COLUMNS:-80} host max name w att cmd title label
  host=${HOST:-$(hostname 2>/dev/null)}; host=${host:-$'\x01'}
  max=$((width-8)); (( max < 20 )) && max=20
  while IFS="$t" read -r name w att cmd title; do
    [ -n "$name" ] || continue
    label="$name  (${w}w, $att, $cmd)"
    case "$title" in
      ''|"$name"|"$cmd"|*"$host"*) ;;
      *) label="$label · $title" ;;
    esac
    label=${label//[$'\t\r\n']/ }
    (( ${#label} > max )) && label="${label:0:$((max-1))}…"
    printf '%s\n' "$label"
  done < <(tmux ls -F "#{session_name}$t#{session_windows}$t#{?session_attached,attached,detached}$t#{pane_current_command}$t#{pane_title}" 2>/dev/null)
}

# Interactive tmux session menu: navigate (Up/Down + Enter), jump by letter,
# kill a session (k, with confirm), pick "New session", or quit to a shell (q).
_tmux_menu() {
  emulate -L zsh
  setopt local_options ksh_arrays          # 0-indexed arrays, like the bash port
  local -a sess labels
  local letters=({a..z})
  local n sel=0 i key rest ans drawn=0 out _sv=""
  # bash read -n sets raw mode automatically; zsh read -k -u0 does not, so
  # enable raw mode here for live single keypresses. Restored in always below.
  [ -t 0 ] && { _sv=$(stty -g 2>/dev/null); stty -icanon -echo min 1 time 0 2>/dev/null; }
  {
  while :; do
    out=$(tmux ls -F '#{session_name}' 2>/dev/null)
    if [ -z "$out" ]; then
      (( drawn > 0 )) && printf '\e[%dA\e[J' "$drawn"
      printf '\e[?25h'; tmux new-session; return
    fi
    sess=("${(@f)out}")
    labels=("${(@f)$(_tmux_menu_labels)}")
    labels+=("New session"); n=${#labels[@]}
    (( sel >= n )) && sel=$((n-1)); (( sel < 0 )) && sel=0
    (( drawn > 0 )) && printf '\e[%dA\e[J' "$drawn"
    printf '\e[?25l'
    printf 'Session  —  ↑/↓+Enter attach · letter jump · k kill · q shell\n'
    for (( i=0; i<n; i++ )); do
      if (( i == sel )); then printf '\e[7m  %s) %s  \e[0m\n' "${letters[i]}" "${labels[i]}"
      else                    printf '  %s) %s\n' "${letters[i]}" "${labels[i]}"; fi
    done
    drawn=$((n+1))
    read -rsk1 -u0 key || { printf '\e[?25h'; return; }
    case "$key" in
      $'\e') # arrow key: CSI (ESC [ A/B) or SS3 (ESC O A/B). Read the two trailing
             # bytes one at a time, tolerating latency between them.
             read -rsk2 -u0 -t 0.4 rest 2>/dev/null
             case "$rest" in
               '[A'|'OA') ((sel=(sel-1+n)%n)) ;;
               '[B'|'OB') ((sel=(sel+1)%n)) ;;
             esac ;;
      $'\n'|$'\r')
             printf '\e[?25h'
             if (( sel >= ${#sess[@]} )); then tmux new-session; else tmux attach -t "${sess[sel]}"; fi
             return ;;
      q|Q)   printf '\e[?25h'; return ;;
      k|K)   if (( sel < ${#sess[@]} )); then
               printf '\e[?25h'; printf 'Kill session "%s"? [y/N] ' "${sess[sel]}"
               read -rsk1 -u0 ans; printf '\n'
               case "$ans" in y|Y) tmux kill-session -t "${sess[sel]}" 2>/dev/null;; esac
               drawn=$((n+2))
             fi ;;
      [a-z]) for (( i=0; i<n; i++ )); do [ "${letters[i]}" = "$key" ] && sel=$i; done
             printf '\e[?25h'
             if (( sel >= ${#sess[@]} )); then tmux new-session; else tmux attach -t "${sess[sel]}"; fi
             return ;;
    esac
  done
  } always {
    [[ -n "$_sv" ]] && stty "$_sv" 2>/dev/null
  }
}

tm() {
  if [ -n "$TMUX" ]; then echo "Already inside tmux — detach first with Ctrl-b d, then run tm"; return 1; fi
  tmux-gc; _tmux_menu
}

# Auto launch at interactive login when not already inside tmux.
if [ "${TMUX_MENU_AUTOLAUNCH:-1}" = "1" ] && command -v tmux >/dev/null 2>&1 \
   && [ -z "$TMUX" ] && [[ -o interactive ]]; then
  tmux-gc
  _tmux_menu
fi
