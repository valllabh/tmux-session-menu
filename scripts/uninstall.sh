#!/usr/bin/env bash
# Uninstall tmux-session-menu: remove the source block and the installed script.
set -euo pipefail

DEST_DIR=${PREFIX:-$HOME/.local/share/tmux-session-menu}
RC=${BASHRC:-$HOME/.bashrc}
BEGIN='# >>> tmux-session-menu >>>'
END='# <<< tmux-session-menu <<<'

if grep -qF "$BEGIN" "$RC" 2>/dev/null; then
  tmp=$(mktemp)
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1}
    skip==0 {print}
    $0==e {skip=0}
  ' "$RC" > "$tmp"
  cat "$tmp" > "$RC"
  rm -f "$tmp"
  echo "removed source block from $RC"
else
  echo "no source block found in $RC"
fi

rm -rf "$DEST_DIR"
echo "removed $DEST_DIR"
echo "done. open a new shell for the change to take effect."
