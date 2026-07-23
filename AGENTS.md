# AGENTS.md

Project instructions for agents working in this repo.

## What this is

An interactive tmux session menu at login, with zombie garbage collection.
Shipped for two shells: `tmux-session-menu.sh` for bash and
`tmux-session-menu.plugin.zsh` for zsh and oh-my-zsh. Everything else supports
installing and testing it.

## Layout

- `tmux-session-menu.sh`         bash implementation
- `tmux-session-menu.plugin.zsh` zsh / oh-my-zsh implementation
- `scripts/install.sh`           copy the bash script, add a source block to the rc
- `scripts/uninstall.sh`         reverse the install
- `test/test.sh`                 bash tests against an isolated tmux socket
- `test/test.zsh`                zsh tests against an isolated tmux socket
- `Makefile`                     install, uninstall, test, lint targets
- `README.md`                    user facing docs

## Two implementations, keep them in sync

The bash and zsh files must stay behaviourally identical. When you change one,
change the other and run both test suites. Known shell differences already
handled:

- bash uses `mapfile` and `read -rsn`; zsh uses `${(@f)...}` and `read -rsk`.
- zsh `read -k` reads the terminal by default, so the zsh port passes `-u0` to
  read from fd 0, which is both the terminal interactively and the pipe in tests.
- zsh arrays are 1 indexed; the zsh port sets `ksh_arrays` to match the bash 0
  indexed logic.
- bash `read -n1` returns empty on Enter; zsh `read -k1` returns a newline, so the
  zsh port matches `$'\n'` and `$'\r'` for Enter and guards read failure to avoid
  an EOF loop.

## Conventions

- Keep the tool a single sourceable bash file with no runtime dependencies
  beyond bash 4 and tmux.
- Public functions: `tmux-gc`, `tm`. Internal: `_tmux_menu`, `_tmux_menu_labels`.
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
