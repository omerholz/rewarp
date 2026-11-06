# Rewarp design

A native macOS terminal with Warp's ergonomics and Ghostty's speed, and no AI.

## Why

Warp has the best terminal ergonomics, but LLM agents and streaming CLIs now
push huge amounts of output through the terminal, so raw terminal speed matters
more than it used to. Ghostty is much faster. Rewarp aims for both.

It is also an experiment in how far Claude Code can take this on its own, so
decisions below are made by Claude unless marked otherwise. See "Calls made
without asking".

## Goals

- Warp's core experience: command blocks, an IDE-style input editor, command
  palette, tabs and splits, with Warp's default keyboard shortcuts.
- Speed is a feature with a number on it. Throughput is benchmarked against the
  installed Ghostty.app. Warp is the other comparison, and hasn't been measured yet.
- Well-behaved under agent workloads: heavy streaming, and full-redraw TUIs
  running on the primary screen.
- Anything that works in a normal terminal still works here, including vim,
  htop, ssh and tmux.

## Non-goals

- AI, agents and anything that calls a model.
- Warp Drive, accounts, cloud sync, teams, block sharing, telemetry. The EXC section
  of the parity file lists what this excludes.
- Non-macOS platforms.

## Anti-goals

These would count as failure even if everything else worked:

- Slower than a plain terminal because of the block machinery.
- A shell or TUI that misbehaves because of the Warp-style features. If shell
  integration fails, the pane must fall back to a working plain terminal.
- Copying Warp code. Warp's client is AGPL-3.0, so Rewarp is written from
  scratch. Matching behaviour and default shortcuts is fine. Reading or porting
  its source is not.

## Foundation: libghostty-vt, not `ghostty.h`

The request named both libraries. Rewarp uses only `libghostty-vt`.

`ghostty.h`'s own header calls it an internal API whose only consumer is
Ghostty's macOS app, and tells external embedders to use `libghostty-vt`. It
also rules itself out on the merits: a surface owns its PTY and renderer, and
exposes no way to feed it bytes or read its grid. Warp's input editor needs the
host to own the PTY. Blocks need the host to own the stream and the layout.

`libghostty-vt` provides what Rewarp needs. In use today:

| Need | API |
| --- | --- |
| Parse the stream, hold screen state | `ghostty_terminal_*` |
| Hear from the shell | `GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE` (a private OSC) |
| Split the stream on exact boundaries | `ghostty_terminal_vt_write_until` |
| Draw efficiently | `render.h`: dirty rows, stable row ids, overscan, split begin/end update |
| Avoid half-drawn TUI frames | `GHOSTTY_TERMINAL_OPT_RENDER_HOLD` (mode 2026) |
| Encode input | `key.h`, `mouse.h`, `paste.h` |
| Select text | `selection.h` |
| Measure characters | `unicode.h` |

Available for what's still to come:

| Need | API |
| --- | --- |
| Keep memory down | `ghostty_terminal_compress` |
| Session restore | `snapshot.h` |
| Inline images | `kitty_graphics.h` |
| Tell programs about focus | `focus.h` |

The cost is that Rewarp writes its own renderer and does not inherit Ghostty's.
libghostty-vt has no tagged release and its C API is still moving, so Rewarp pins
an exact Ghostty commit (`86aef72` at the time of writing).

## Architecture

```
keyboard ──> input editor ─────────────┐ (idle: command submitted on Enter)
         └─> key encoder ──────────────┤ (command running: raw keys)
                                       v
                              PTY ──> shell
                                       │
                              I/O thread per pane
                                       │
                                  stream router  (vt_write_until, stop at OSC end)
                                   │         │
                         shell terminal    block terminal N
                     (prompt, line echo)   (one per command)
                                   │         │
                                 render state per visible block
                                       │
                              Metal renderer, on display link
```

### One terminal per block

Each command gets its own `GhosttyTerminal`. A separate long-lived shell terminal
takes everything between commands.

The obvious alternative is one terminal per pane with block boundaries tracked as
grid references. It is simpler and is what makes reflow and search easy, but it
fails the agent workload: macOS `clear` emits `CSI 3 J`, and primary-screen TUIs
also clear scrollback when they redraw. In a single terminal that erases every
earlier block. Per-block grids contain the damage, and also stop a misbehaving
command from leaving mouse or keyboard modes on for the next one.

Costs of this choice, and how they are handled:

- Memory per block. Measured in M0. Compressing finished blocks and evicting old
  ones to snapshots would reduce it, and neither is built yet.
- Resize touches every terminal, on the main thread. That should move to the
  background, with estimated heights until it finishes, and hasn't yet.
- Selection across blocks is ours to implement, by joining per-block selections.
  Today a selection stays inside the block it started in.
- Session-level state such as OSC 4 palette changes has to be copied forward to
  the next block's terminal, which isn't done yet.

### Stream routing

The router feeds PTY bytes with `vt_write_until`, stopping at each OSC end. When
the shell reports that a command started, later bytes go to a new block terminal.
When the command ends they return to the shell terminal. The split is exact even
when one read holds the end of a command and the next prompt.

With an `ESC \` terminator the library stops at the `ESC`, so the `\` still has to go
to the old terminal, even if it arrives in a later read. Otherwise it prints as a
stray character in the next block.

### Shell integration

Rewarp starts the shell with its own bootstrap, which sources the user's config and
then installs hooks. Only zsh is done, through `ZDOTDIR`. Bash and fish will use
`--rcfile` and `XDG_DATA_DIRS`. Hooks report prompts, command text, exit codes and
the working directory.

Those reports don't use OSC 133 and OSC 7, the standard way to send them, because
anything printed to the terminal could send those too: a file being read, a
background job at the prompt, or a remote shell with its own integration. They go
on a private OSC 7701 channel instead, each quoting a token made fresh for each
shell.

The token never goes through the environment. Removing it there straight away isn't
enough, because a command can read a shell's starting environment through `ps -E` on
any zsh without Apple's hardening, such as Homebrew's. So the shell asks the app for
it over a Unix socket as it starts, and keeps it in a shell variable, where commands
can't inherit it. The kernel tells the app which process connected (`LOCAL_PEERPID`),
and it answers only the pane's own process. A command has a pid of its own, so it
gets no answer, even one that goes looking.

A shell with no token sends no reports, so the pane ends up a plain terminal, as it
does for a shell with no integration. That's why the socket falls back from `TMPDIR`
to the system's temporary directory and then to `/tmp`: a `TMPDIR` inherited from
wherever the app was launched can be gone, or too long for a socket path.

`exec zsh`, which `omz reload` runs, starts a new shell in the same process, and that
shell needs both the hooks and the token again. `exec` keeps the pid, so it asks for
the token the same way. The hooks are harder. They're found through `ZDOTDIR`, and
leaving that exported would send installers that write to `${ZDOTDIR:-$HOME}/.zshrc`
into the app. zsh runs no hook before `exec`, so `exec` is an alias that sets
`ZDOTDIR` and the socket's path for the one process it starts. A function wouldn't do:
one called `exec` would undo `exec 3>&1` when it returned, and one called `zsh` would
lose the `-l` of `exec -l zsh`. The alias is defined before the user's startup files,
because an alias only reaches functions parsed after it, and `omz reload` is one. The
token can't go in the alias, because `exec` could be starting anything.

Readiness comes from wrapping `zle-line-init`, not from a marker in `PS1`, because
prompt themes rewrite `PS1` and oh-my-posh runs the whole line edit inside its own
widget. If a shell at a prompt still doesn't report ready within a second, the app
assumes it is, so no prompt setup can wedge the input.

Startup output stays hidden, since it's mostly noise. But a shell that has printed
something and still has no prompt after two seconds may be asking a question, as
oh-my-zsh's update check does, so the pane then shows the shell terminal and sends
it keys until the prompt arrives. Commands submitted meanwhile wait for the prompt,
because a shell that's still starting can swallow what's written to it.

The prompt is hidden. The editor submits commands through the library's paste
encoder, so control characters the input can't show never reach the line editor as
keys. Anything still holding a newline or a tab goes in as a bracketed paste.
Commands submitted before the shell is ready wait in order, and each is sent at its
own prompt. A command also holds back the next one until the shell reacts to it, but
for a second at most. A line can get no report at all, when zsh waits for a closing
quote or asks `[nyae]?` about a typo, and only the next submission can answer it.

Fallback: a shell that never reports stays a plain terminal drawn from the shell
terminal, with keys sent straight to the PTY. That covers every shell except zsh for
now. Inside a running command such as ssh or a nested shell, the block acts as a
plain terminal.

### Rendering

A hand-written Metal renderer, one `CAMetalLayer` per pane:

- Glyphs are rasterised with Core Text into grayscale and colour atlases and cached
  per font, glyph and style, with one set per display scale. Fallback fonts come
  from Core Text.
- Instanced quads for backgrounds and glyphs. Instance data is cached per row and
  rebuilt only for dirty rows, keyed by the render state's stable row ids.
- Block chrome, hover buttons, find highlights, the scrollbar and the sticky header
  are drawn in the same pass. AppKit handles what's around the terminal: the input,
  tab bar, find and filter bars, palettes and menus.
- Instance positions are 16-bit, so anything that can reach beyond that, such as a
  tall block's edges, is clipped to the view first.
- A program using synchronized output (mode 2026) can hold drawing back for up to a
  second, so a half-drawn frame is never shown.
- The display link pauses when nothing is changing, so an idle pane costs nothing.
- Shaders are compiled from source at startup, which needs no Xcode. That takes 44
  to 112 ms, and a precompiled library could replace it later.

Ligatures are out of scope at first: cell-by-cell drawing is fast and simple, and
shaping can be added afterwards.

### Threading

The rule is that rendering never slows parsing, and parsing never blocks the main
thread.

- One I/O thread per pane reads the PTY and writes to terminals under a per-pane
  lock. Terminals are not thread safe.
- The display link takes that lock only for `render_state_begin_update`, then does
  `end_update` and draws outside it.
- The app can only reach shared state through `PaneSession.withState`, which holds
  the lock. Everything the read thread writes is internal to `RewarpCore`, so
  forgetting the lock is a compile error. The lock isn't recursive, and Swift can't
  stop a terminal being kept past the closure, so those two rules are on the caller.
- PTY writes have their own queue, because a full PTY buffer blocks. Replies the
  terminal makes during parsing are queued, and written after the lock is released.
- Output arriving faster than the display refreshes is simply coalesced.

### Tabs and panes

A tab's layout is `PaneTree`, a plain value holding splits, ratios and pane ids.
Views are positioned from it and stay flat children of one container, so a split
never reparents a running pane, and the tree can be tested without any views and
saved for session restore. Maximizing hides the other panes, which therefore can't
hold keyboard focus.

The tab bar sits on the top, left or right, and the choice is saved. Dragging a tab
reorders live: the tab follows the pointer, and the order changes as it passes each
slot, so letting go only settles it. Dragging a tab out into a new window isn't
built yet.

The tab bar overlaps the title bar, which drags the window on its own, in the window
server, whatever a view says through `mouseDownCanMoveWindow` or `isOpaque`. So the
bar overrides the private `_opaqueRectForWindowMoveWhenInTitlebar`, the one thing that
takes a view out of that drag area, and moves the window itself from empty space with
`performDrag`. If a future macOS stops asking, tabs go back to moving the window.

### Input editor

An `NSTextView` subclass, which brings IME, undo, selection and accessibility.
Rewarp adds shell syntax highlighting, ghost-text autosuggestions, a completion
menu, multi-line editing and Warp's Emacs-style bindings. Multi-cursor editing is
still to come.

Completions run natively in Swift, never in-band in the user's shell: `$PATH`
commands, files, git refs, ssh hosts, package scripts and make targets. Aliases and
functions are reported by the shell integration at the first prompt, and again when
`PATH` changes. Everything inserted is shell-quoted by default, because these names
come from places an attacker can control, such as a cloned repository.

### Find and filter

Find takes each block's text and runs a regular expression over it in Swift, rather
than using `search.h`. Matches map back to cells through the library's width table,
and drawing looks them up by visible row, so a frame's cost follows what's on screen
and not the number of matches. Find and filter both follow a running command,
refreshing four times a second.

A filter never touches a block's output. It builds a second terminal from the rows
it keeps, with their styling, and the block draws from that until the filter is
cleared.

### Untrusted output

Anything printed to the terminal can come from an attacker: a file, a build log, a
remote host. So printed bytes can't:

- End a block or fake a command. Those need the token described under shell
  integration, and OSC 133 is ignored altogether.
- Move the working directory, in a shell with integration. A plain terminal has only
  OSC 7 to go on, so it does believe that.
- Reach the clipboard or open anything. OSC 52 has no effect, and nothing in the app
  opens a link yet.
- Feed text back to the shell. The terminal's replies never echo what was printed.

### Stack

Swift 5 language mode, AppKit, SwiftPM. Zig and the Command Line Tools are enough,
with no Xcode, because the XCFramework and `metal` steps of Ghostty's build aren't
needed here. `scripts/` builds the pinned libghostty-vt as a static library and
assembles an ad-hoc-signed `.app`, and the `Makefile` is the front door to all of it.

The version is set in `Sources/RewarpCore/Version.swift`, and it stays at 0.0.1 until
the project's owner asks for a change.

### Testing

Unit tests use Swift Testing and cover `RewarpCore`, including ones that run a real
zsh against the real integration scripts.

End-to-end tests drive the real app through a control FIFO (`REWARP_CONTROL`). Input
arrives as synthesized `NSEvent`s sent through the window, so it takes the same path
as a user's inside the app but skips the window server, and each reply is a JSON
snapshot of what a user would see. Windows stay invisible, and each run gets a
private pasteboard. `REWARP_SHELL` picks another shell, to reach the plain terminal.

Three rules came from getting these wrong:

- Scripted runs always use a throwaway `HOME`. A real shell can stop at a question,
  as oh-my-zsh's update check does, and a script might answer it. That doesn't cover
  app settings, though: only `REWARP_CONTROL` keeps a run out of the real ones.
- A regression test has to fail without its fix, so that gets checked by taking the
  fix out. Several tests here passed either way until they were rewritten.
- Anything the window server decides needs a real mouse, or a test of what AppKit
  computed, not of what a view reports. Tab dragging passed every test while most of
  each tab moved the window. Its test now reads the window's actual drag area.

## Milestones

[warp-parity.md](warp-parity.md) is the definition of done: 1,647 behaviours from
Warp's public docs, each with an ID. The milestones below are an order for working
through it, and every parity section belongs to exactly one.

A box in the parity file is ticked only by a passing end-to-end test named for its
ID, which `tests-e2e/run.py` does on a full run. Progress is the count of ticked
boxes, nothing else, so behaviour that works but has no such test doesn't count. At
the time of writing that's 103 of 1,647.

| Milestone | Parity sections | State |
| --- | --- | --- |
| M0, proof | The bets below | Done |
| M1, plain terminal | Part of EMU and PAN, TXT basics | Done |
| M2, blocks | COR, BLK except find and filter, MOU for blocks, scrollbars, hover and alt-screen | Started |
| M3, input editor | INP, MOU for the prompt and input, CMP, AUT, HIS, CSR, FIX, ALS, XRY, HLT | Started |
| M4, find and palettes | BLK find and filter, PAL, NAV, FND | Started |
| M5, windows | TAB, VTB, PAN, WIN, TBR, HKY, and their MOU sections | Started |
| M6, sessions | RST, CWD, LCF, TCF, WFL, SYN | Not started |
| M7, settings and keys | SET, KEY, KBE | Not started |
| M8, appearance | THM, TXT, WAP, PRM, POS | Not started |
| M9, shells | EMU, ALT, TMX, SHL, WFY, SSH, VIM | Not started |
| M10, the rest | LNK, MKD, NTF, SEC, QUT, A11, URI, SLS, BAN, STU, IMP, UPD | Not started |
| M11, code features | EDT, FRP, FTR, LSP, REV, WTR | Not started |

Items marked `(verify in app)` are checked by observing Warp.app, not by reading
its code. `CNF` lists places where the docs disagree with each other.

## Known limits

- The integration only survives an `exec` that its alias can see. `builtin exec zsh`,
  `exec -c zsh`, `exec zsh -f` and an `exec` parsed before the alias existed all leave
  a shell with no hooks. The pane keeps working, but as one block that never finishes,
  the same as any nested shell.
- The alias can't see what `exec` is starting, so a program other than zsh inherits
  the app's `ZDOTDIR`. Any zsh started under it puts that back. A bare `exec`, which
  does nothing, leaves the alias's variables set in the shell.
- A zsh built without the `zsh/net/socket` module can't ask for its token, so its
  panes are plain terminals. `/bin/zsh` and Homebrew's zsh both have it.
- A pane's socket stays in the temporary directory if the app quits with the pane
  open. It's empty, and macOS clears that directory by itself.
- A pane closes when the PTY reaches end of file, so a background job holding the
  terminal keeps a pane open after its shell exits.
- Find and filter do their work on the main thread under the session lock, so they
  can stall the parser on very long blocks.
- Tabs that don't fit in the tab bar can't be reached with the mouse, because it
  doesn't scroll yet. Shortcuts and the navigation palette still reach them.
- Programs aren't told about focus changes, inline images aren't drawn, and there
  are no ligatures.

## Default shortcuts

Warp's documented macOS defaults, listed under KEY in the parity file.

## Bets

Results from M0, measured on this Mac with libghostty-vt `86aef72` in ReleaseFast.

| Bet | Result | Status |
| --- | --- | --- |
| Builds with Zig and CLT, no Xcode | About 2 minutes, 12.6 MB static library | Proven |
| Swift links it through SwiftPM | Works, via a C target and the `.a` | Proven |
| A terminal per block is cheap | 10 us and 56 KB for 20 lines, 157 us and 800 KB for 1,000 lines | Proven |
| Compression recovers memory | About half on large blocks, nothing on small ones | Proven |
| `vt_write_until` keeps up | 703 vs 706 MB/s, 477 MB/s with an OSC on every line | Proven |
| The stream splits exactly | The callback fires before the call returns | Proven |

Since then, with Ghostty 1.4.0 on its default config, and `make bench` at 256 MB in a
throwaway `HOME`:

| Bet | Result | Status |
| --- | --- | --- |
| Runtime shader compile is acceptable | 44 to 112 ms, launch about 100 to 160 ms | Proven |
| Scrolling output keeps up, keeping 50,000 rows | Rewarp 183 to 196 MB/s, Ghostty 160 to 181 MB/s | Proven |
| Full-screen repaint keeps up, keeping 50,000 rows | Rewarp 176 to 187 MB/s, Ghostty 142 to 155 MB/s | Proven |
| A full block is affordable | 152 MB resident for one 50,000-row block, before any compression | Measured |

Frames under load, inside a block, on a 120 Hz display with a window of about 39
rows: 116 to 121 fps through both a `yes` flood and a full-screen repaint, with 0.10
to 0.15 ms to build each frame.

Those numbers measure drain speed and frame rate. Not yet measured: keypress
latency, and Warp itself, which can't be scripted without writing into `~/.warp`.

## Calls made without asking

- libghostty-vt only, not `ghostty.h` (departs from the request; reasons above).
- One terminal per block.
- Own Metal renderer, AppKit, SwiftPM, no Xcode project.
- App name is Rewarp, from the repo name. Public distribution may want a name
  that doesn't lean on Warp's trademark.
- zsh first, then bash and fish.
- macOS 14 or later as the minimum, for the modern display link APIs.
- A private channel with a token for shell reports, not the standard OSC 133 and
  OSC 7.
- An alias on `exec`, which shows up in the user's `alias` list, because nothing else
  keeps the hooks through `exec zsh` without leaving `ZDOTDIR` exported.
- Startup output stays hidden unless the shell seems to be waiting for an answer.
- `-Ounchecked` in release builds, because bounds checks are the wrong trade in a
  per-cell render loop.
- GNU Make as the front door, since it ships with the Command Line Tools.
- One private AppKit method overridden so tabs can be dragged. Rewarp only defines it,
  so losing it brings back a bug, not a crash. App Store review might object to it.

## Going beyond Warp

Asked for by the user, and not in Warp:

- Tabs in a right sidebar. Warp offers the top and a left sidebar.
