# tmux-session-menu

An interactive tmux session picker for your shell login, with built in garbage
collection for zombie clients and abandoned sessions.

When you SSH into a box (for example from Termius over Tailscale), each new tab
greets you with a menu of existing tmux sessions. Pick one to attach, jump to it
by letter, kill one you no longer need, start a fresh session, or drop to a plain
shell. Every tab gets its own session, so tabs never mirror each other.

## Why

The common `tmux attach || tmux new` login snippet forces every tab into one
shared session, so two tabs mirror the same screen. Dropped SSH connections also
leave dead clients that keep sessions marked attached, which hides your running
work behind zombies. This tool fixes both.

## Features

- Menu on login listing every session with its window count, attach state, and
  running command
- Navigate with Up and Down then Enter, or press a letter to jump straight to a
  session
- Kill the highlighted session with `k`, guarded by a yes or no confirm so you
  never drop a running job by accident
- New session and plain shell options always available
- `tmux-gc` reaps zombie clients and abandoned empty sessions, and runs
  automatically before the menu so the list is always accurate
- `tm` reopens the menu any time, after you quit to a shell or detach
- Each tab lands in its own session, no mirroring

## Install

```sh
git clone https://github.com/valllabh/tmux-session-menu.git
cd tmux-session-menu
make install
```

`make install` copies the script to `~/.local/share/tmux-session-menu/` and adds a
single source line to your `~/.bashrc`. Open a new shell to use it.

Manual install: source the script from your `~/.bashrc`.

```sh
source /path/to/tmux-session-menu.sh
```

### zsh and oh-my-zsh

A zsh port ships as `tmux-session-menu.plugin.zsh`.

oh-my-zsh:

```sh
git clone https://github.com/valllabh/tmux-session-menu.git \
  "$ZSH_CUSTOM/plugins/tmux-session-menu"
```

Then add it to your plugin list in `~/.zshrc`:

```sh
plugins=(... tmux-session-menu)
```

Other zsh plugin managers point at the repo and load the `.plugin.zsh` file, for
example with sheldon or zinit `zinit load valllabh/tmux-session-menu`. Manual
install: `source /path/to/tmux-session-menu.plugin.zsh` from your `~/.zshrc`.

## Usage

Open a shell. If tmux sessions exist you get the menu.

```
Session  —  ↑/↓+Enter attach · letter jump · k kill · q shell
  a) main   (1w, detached, claude)
> b) work   (2w, detached, vim)
  c) New session
```

| Key            | Action                                         |
|----------------|------------------------------------------------|
| Up, Down       | Move the highlight                             |
| Enter          | Attach the highlighted session                 |
| a, b, c, ...   | Jump straight to that session                  |
| k              | Kill the highlighted session, asks to confirm  |
| q              | Drop to a plain shell, no tmux                  |
| New session    | Start a fresh session                          |

Commands available in the shell:

- `tm` opens the menu on demand
- `tmux-gc` cleans zombies now, add `-v` to see what was cleaned

## Configuration

| Variable               | Default | Meaning                                          |
|------------------------|---------|--------------------------------------------------|
| `TMUX_MENU_AUTOLAUNCH` | `1`     | Set to `0` to stop the menu opening at login     |
| `TMUX_GC_CLIENT_IDLE`  | `300`   | Seconds before an idle client is reaped          |
| `TMUX_GC_SESSION_IDLE` | `3600`  | Seconds before an empty detached session is killed. Set to `0` to purge empty sessions immediately |

Garbage collection only ever kills sessions that are detached and running just a
bare shell. Anything running a real program, or attached, is left alone.

## Requirements

- bash 4 or newer, or zsh 5, for the arrow key reader and arrays
- tmux

## Uninstall

```sh
make uninstall
```

## License

MIT. See [LICENSE](LICENSE).
