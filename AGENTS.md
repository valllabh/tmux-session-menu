# AGENTS.md

Project instructions for agents working in this repo.

## What this is

A single bash file, `tmux-session-menu.sh`, that you source from `~/.bashrc`. It
shows an interactive tmux session menu at login and provides zombie garbage
collection. Everything else in the repo supports installing and testing it.

## Layout

- `tmux-session-menu.sh`  the whole tool, source of truth
- `scripts/install.sh`    copy the script, add a source block to the shell rc
- `scripts/uninstall.sh`  reverse the install
- `test/test.sh`          tests against an isolated tmux socket
- `Makefile`              install, uninstall, test, lint targets
- `README.md`             user facing docs

## Conventions

- Keep the tool a single sourceable bash file with no runtime dependencies
  beyond bash 4 and tmux.
- Public functions: `tmux-gc`, `tm`. Internal: `_tmux_menu`.
- Behaviour is driven by env vars, documented in the README. Do not add new
  config surfaces without updating the README table.
- Tests must never touch the user real tmux server. Always use an isolated
  socket with `tmux -L`.
- No emojis anywhere.
- Use a Makefile for build, run, and test entry points.
- Do not create a CLAUDE.md file or a .claude directory. Put project
  instructions here in AGENTS.md at the repo root.

## Working on it

- Run `make test` after any change to the script.
- Run `make lint` if shellcheck is available.
- The menu redraw math depends on the number of printed lines. If you change
  what the menu prints, update the `drawn` accounting in `_tmux_menu`.
