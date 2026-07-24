# tmux-session-menu

Pop a tmux session menu over a blank screen at shell login: pick a running
session or start a new one, with garbage collection for zombie clients and
abandoned sessions.

When you SSH into a box (for example from Termius over Tailscale), each new tab
greets you with a menu floating on an otherwise empty screen. One key per
session, plus new session, the full `choose-tree` chooser, and a way out.

## Why

The common `tmux attach || tmux new` login snippet forces every tab into one
shared session, so two tabs mirror the same screen. Dropped SSH connections also
leave dead clients that keep sessions marked attached, which hides your running
work behind zombies. This tool fixes both.

Both widgets are tmux own, `display-menu` and `choose-tree`. An earlier version
drew its own menu and later shelled out to sesh and fzf; both could fail to
render at login and leave you staring at a bare prompt. tmux draws inside its own
client, so there is nothing left in the way. All this repo adds is a blank screen
to float the menu on, a readable row format, and the garbage collection.

A tmux menu needs a client attached to something before it can draw, so the menu
opens over a disposable blank session rather than over your last one. That
session is killed the instant you pick or create, so it is never in your way; if
you dismiss the menu with Escape you are left sitting in it as a fresh shell, and
`tmux-gc` clears it away later.

The menu is the entry point rather than `choose-tree` alone because `choose-tree`
has no key for starting a session, and starting one is half of what you want at
login. It is one key away when you need its filtering, killing and previews.

## Features

- Session menu on login, floated over a blank screen, one row per session with
  its window count, project directory and either the running command or a
  meaningful pane title
- One keystroke per session, assigned in list order so they stay put between
  logins
- New session, named or not, which `choose-tree` cannot do
- The full `choose-tree` chooser one key away, for filtering, killing and pane
  previews
- `tmux-gc` reaps zombie clients and abandoned empty sessions, and runs
  automatically before the menu so the list is always accurate
- `tm` reopens the menu any time, after you detach
- Each tab lands in its own session, no mirroring
- No dependencies beyond tmux and a shell

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

Open a shell. If tmux sessions exist, a menu opens on an otherwise blank screen.

```
┌─ tmux sessions ─────────────────────────────────────┐
│ api  1w  tax-project  sleep                     (a) │
│ claude  1w  news-room  ✳ Build the news aggregator (b) │
│ tmux-session-menu  1w  sleep                    (c) │
├─────────────────────────────────────────────────────┤
│ New session                                     (n) │
│ New session, named                              (N) │
├─────────────────────────────────────────────────────┤
│ Chooser: filter, kill, preview                  (/) │
│ Detach to a plain shell                         (d) │
└─────────────────────────────────────────────────────┘
```

Press a session key to switch, or move with Up and Down and press Enter. `n`
starts a session, `N` starts one you name. Escape dismisses the menu and drops
you into a fresh blank shell, which `tmux-gc` clears away on the next login.

A row is the session name, its size, the project it sits in, and what it is
doing, so you can tell which one you want without opening it:

- The project is the basename of the session working directory. It is left out
  when it only repeats the session name, as in `tmux-session-menu` above.
- What it is doing is the pane title when the running program sets a useful one,
  and the command name otherwise. Claude Code puts the task it is working on in
  the title, so several `claude` sessions stay tellable apart instead of all
  reading as "claude". Titles that carry nothing new, the host name or the
  session name, give way to the command. Long ones are capped at 40 characters.

For more than a row can hold, `/` opens the chooser, which previews the live
content of whatever is highlighted.

Sessions are listed in the order `tmux ls` gives them, which is by name, so a
session keeps the same key from one login to the next. The keys `d`, `n`, `q` and
`x` are never handed out to a session, so they stay free for Detach, New and the
chooser's own habits.

`/` opens tmux `choose-tree`, which is the same list with more to do to it:

| Key      | Action                             |
|----------|------------------------------------|
| Enter    | Switch to the highlighted session  |
| x, X     | Kill it, or kill everything tagged |
| t        | Tag an item, `:` runs a command on every tagged one |
| f        | Filter by a tmux format            |
| C-s, n   | Search by name, repeat the search  |
| O, r     | Change the sort field, reverse it  |
| v        | Toggle the pane preview            |
| q        | Leave the chooser                  |

The full key list is in `man tmux` under `choose-tree`.

Commands available in the shell:

- `tm` opens the menu on demand
- `tmux-gc` cleans zombies now, add `-v` to see what was cleaned

Inside tmux the chooser is always a `Ctrl-b s` away, which is what `tm` tells you
if you run it there.

## Configuration

| Variable               | Default | Meaning                                          |
|------------------------|---------|--------------------------------------------------|
| `TMUX_MENU_AUTOLAUNCH` | `1`     | Set to `0` to stop the menu opening at login     |
| `TMUX_MENU_FORMAT`     | see below | tmux format string for one row, in both the menu and the chooser |
| `TMUX_GC_CLIENT_IDLE`  | `300`   | Seconds before an idle client is reaped          |
| `TMUX_GC_SESSION_IDLE` | `3600`  | Seconds before an empty detached session is killed. Set to `0` to purge empty sessions immediately |

The default row format, which drops a directory or a pane title that says nothing
the session name does not, and caps the title at 40 characters:

```
#{session_windows}w#{?session_attached, · attached,}  #{?#{==:#{b:pane_current_path},#{session_name}},,#{b:pane_current_path}  }#{?#{||:#{m:*#{host_short}*,#{pane_title}},#{==:#{pane_title},#{session_name}}},#{pane_current_command},#{=40:pane_title}}
```

It does not include the session name. `choose-tree` prints the name itself, and
the menu prepends it, so putting it in the format would show it twice.

Garbage collection only ever kills sessions that are detached and running just a
bare shell. Anything running a real program, or attached, is left alone.

## Requirements

- tmux 3.0 or newer, for `display-menu` and the format conditionals
- bash 4 or newer, or zsh 5

Nothing else. There is no build step and no optional tooling.

## Uninstall

```sh
make uninstall
```

## License

MIT. See [LICENSE](LICENSE).
