#!/usr/bin/env bash
# Install tmux-session-menu: copy the script and add a source line to the shell rc.
set -euo pipefail

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
DEST_DIR=${PREFIX:-$HOME/.local/share/tmux-session-menu}
RC=${BASHRC:-$HOME/.bashrc}
BEGIN='# >>> tmux-session-menu >>>'
END='# <<< tmux-session-menu <<<'

mkdir -p "$DEST_DIR"
cp "$SRC_DIR/tmux-session-menu.sh" "$DEST_DIR/tmux-session-menu.sh"
echo "installed script -> $DEST_DIR/tmux-session-menu.sh"

if grep -qF "$BEGIN" "$RC" 2>/dev/null; then
  echo "source block already present in $RC, leaving it alone"
else
  {
    printf '\n%s\n' "$BEGIN"
    printf 'source "%s/tmux-session-menu.sh"\n' "$DEST_DIR"
    printf '%s\n' "$END"
  } >> "$RC"
  echo "added source block to $RC"
fi

echo "done. open a new shell to use it."
