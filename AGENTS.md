# AGENTS.md

Project instructions for agents working in this repo.

## What this is

At shell login, pop a tmux `display-menu` of sessions over a blank screen, with
`choose-tree` one key further in, plus zombie garbage collection. Shipped for two
shells: `tmux-session-menu.sh` for bash and `tmux-session-menu.plugin.zsh` for
zsh and oh-my-zsh. Everything else supports installing and testing it.

The widgets are not ours and must not become ours again. Two earlier versions
drew their own screen, a hand rolled menu and then a sesh plus fzf picker with a
node preview pane, and both could fail to render at login and leave the user at a
bare prompt with no way in. tmux draws inside its own client, so there is nothing
of ours between the user and the list. What this repo still owns is small and
deliberate: the blank holder the menu floats on, the format of a row, the menu
item list, and the garbage collection. Prefer deleting code here to adding it.
Anything tmux already does is not ours to reimplement, and any change that puts
our own drawing back in front of the user at login is the wrong direction.

`choose-tree` alone was tried first and is not enough on its own: its key table
is fixed and has no way to start a session, which is half of what login is for.
`display-menu` takes arbitrary items, so the menu is the entry point and the
chooser is what `/` opens for filtering, killing and previews. If a future tmux
gives `choose-tree` a create key, the menu layer should go.

## The blank holder

A tmux overlay needs a client attached to a session before it can draw, and at
login there is none. So `_tmux_menu` creates a throwaway session, `_TSM_SCRATCH`
(`_tsm_scratch`), attaches to it with its status bar off, and floats the menu on
that blank screen. This is the whole answer to "why is a session sitting behind
the popup": the menu cannot exist without one, and a blank disposable session is
the least surprising thing to put there.

Rules that keep the holder invisible:

- It is created right before attaching and after `_tmux_menu_items` has already
  read the session list, so it is never itself a menu entry. `_tmux_menu_items`
  also skips it by name as a belt.
- Every menu path that commits to a session disposes of it inline: session items
  and the chooser template run `switch-client ... ; kill-session -t _tsm_scratch`,
  and the two new session items run `new-session ; kill-session -t _tsm_scratch`.
- The one path that cannot dispose of it is Escape. tmux fires no event when a
  menu closes and exposes no "menu is open" state (checked: no hook, no client
  flag), so nothing can run on dismiss. The user is left in the holder as a blank
  shell, and `tmux-gc` reaps it: gc kills a detached `_tsm_scratch` at once,
  regardless of the idle threshold that guards ordinary sessions.

Do not try to restore the status bar or rename the holder on Escape. It was
investigated and there is no signal to hang it on; the gc sweep is the design.

## Layout

- `tmux-session-menu.sh`         bash implementation
- `tmux-session-menu.plugin.zsh` zsh / oh-my-zsh implementation
- `scripts/install.sh`           copy the bash script, add a source block
- `scripts/uninstall.sh`         reverse the install
- `test/test.sh`                 bash tests against an isolated tmux socket
- `test/test.zsh`                zsh tests against an isolated tmux socket
- `Makefile`                     install, uninstall, test, lint targets
- `README.md`                    user facing docs

## The row format

`_TMUX_MENU_FORMAT_DEFAULT` is a tmux format string, used both as `choose-tree
-F` and as the tail of every menu label, and it is where the display rule lives.
A row has to answer "which one do I want" without being opened, so it carries the
size, the project directory and what the session is doing. Two parts earn their
place only when they say something new: the directory is dropped when it matches
the session name, and the pane title gives way to `pane_current_command` when it
is only the host name or the session name. The title is capped with `#{=40:}`
because `display-menu` sizes itself to its widest label and one talkative Claude
Code session would otherwise push the menu past the terminal. That rule used to
be duplicated in a shell `case` and in TypeScript; it is now one string in each
of the two shell files. Change one and change the other. `TMUX_MENU_FORMAT`
overrides it.

It deliberately omits `session_name`: `choose-tree` prints the name itself and
`_tmux_menu_items` prepends it, so a name in the format shows up twice.

Test format changes by feeding the string to `tmux ls -F`, which expands it the
same way both widgets do, and assert on the output. Do not assert on a
screenshot.

## The run-shell delay, do not remove it

`_tmux_menu` runs `attach-session ; run-shell -d 0.3 ; display-menu`. The
`run-shell` looks like a pointless pause and is not. tmux silently drops a
`display-menu` queued directly behind `attach-session`: the client has not
finished attaching, has no screen to put an overlay on, and the menu is never
drawn at all. The user lands in the blank holder with no menu and no way out but
to detach, which is exactly the bug this project already shipped once.
`run-shell` blocks the command queue, so the menu is dispatched a beat later,
once the client is up. Measured: `-d 0` fails, `-d 0.05` and anything above it
works, and 0.3 is the margin. `test/test.sh` guards the command shape because
nothing else can catch this without a real terminal.

Note that this failure does not reproduce under `script(1)`, where the menu
appears fine. It reproduces under a real tmux client. Verify overlay changes by
running the login path inside a second tmux server and capturing the outer pane:

```sh
tmux -L outer new-session -d -x 110 -y 30 "env -u TMUX bash run-login.sh"
sleep 3; tmux -L outer capture-pane -p
```

## The menu items

`_tmux_menu_items` fills the global `_TMUX_MENU_ITEMS` with `display-menu`
triples, label then shortcut key then command, because a shell function cannot
return an array. Two escaping rules, both already bitten:

- The label is expanded as a tmux format, so a literal hash has to be doubled or
  tmux swallows it and whatever follows. Pane titles contain hashes.
- The command is a string tmux re-parses, so a double quote or backslash in a
  session name has to be escaped or the target argument ends early.

Session keys come from a fixed string that excludes `d`, `n`, `q` and `x`. `d`
and `n` would otherwise shadow the Detach and New items: display-menu resolves a
key to the first item bound to it, and the session items come first, so a fourth
session taking `d` would make Detach unreachable by key. `q` and `x` are kept
free out of habit. Order follows `tmux ls`, which is by name, so a session keeps
its key between logins. Do not sort by recency: a key that moves is worse than
one that is stale. `test/test.sh` asserts the pool never collides with a fixed
key.

An item command can be tested without a terminal by piping it to `tmux
source-file -`, which parses a command string exactly as `display-menu` does.
Swap `switch-client` for `display-message -p` to get an assertable answer. A
`no current client` error means the string parsed and only the runtime target was
missing, which is a pass for parse level tests.

## Two implementations, keep them in sync

The bash and zsh files must stay behaviourally identical. When you change one,
change the other and run both test suites. Known shell differences already
handled: every zsh function opens with `emulate -L zsh`, zsh wants `return`
without a trailing semicolon inside `{ ... }`, and `${var:offset:len}` needs the
offset written as `$i` rather than `i` or zsh reads it as a history modifier.
Note the test files diverge on one point that is not a bug: bash arrays index
from 0 and zsh arrays from 1, so the `_TMUX_MENU_ITEMS` assertions differ.

## Conventions

- Keep the tool a single sourceable file per shell, with no runtime dependency
  beyond the shell and tmux. No node, no build step, no optional binaries.
- Behaviour is driven by env vars, documented in the README. Do not add new
  config surfaces without updating the README table.
- Tests must never touch the user real tmux server. Always name the socket with
  `tmux -L`. This is not a style preference: tmux ignores `$TMUX` **only** when a
  socket is named on the command line, so `TMUX_TMPDIR` alone still resolves to
  the real server when the tests are run from inside a tmux session, and a
  `kill-server` there kills the user session. Every test routes tmux through a
  `tmux()` wrapper that passes `-L "$sock"`.
- A pane reports an empty `pane_current_command` for the first instant of its
  life, which is long enough to make garbage collection see a fresh session as
  busy. Tests wait for it with `settle`.
- An overlay change (the holder, its status bar, the run-shell defer) cannot be
  verified under `script(1)`, where it appears to work. Verify it under a real
  tmux client: run the login path inside a second tmux server and capture the
  outer pane. The command shape is unit tested by stubbing the `tmux()` wrapper
  to echo the `attach-session` arguments instead of running them.
- No emojis anywhere.
- Use a Makefile for build, run, and test entry points.
- Do not create a CLAUDE.md file or a .claude directory. Put project
  instructions here in AGENTS.md at the repo root.

## Working on it

- Run `make test` after any change.
- Run `make lint` if shellcheck is available.
