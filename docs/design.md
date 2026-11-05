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
  Ghostty.app and Warp.app installed on this machine.
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

`libghostty-vt` provides what Rewarp needs:

| Need | API |
| --- | --- |
| Parse the stream, hold screen state | `ghostty_terminal_*` |
| Hear from the shell | `GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE` (a private OSC) |
| Split the stream on exact boundaries | `ghostty_terminal_vt_write_until` |
| Draw efficiently | `render.h`: dirty rows, stable row ids, overscan, split begin/end update |
| Avoid half-drawn TUI frames | `GHOSTTY_TERMINAL_OPT_RENDER_HOLD` (mode 2026) |
| Encode input | `key.h`, `mouse.h`, `paste.h`, `focus.h` |
| Selection, find | `selection.h`, `search.h` |
| Keep memory down | `ghostty_terminal_compress` |
| Session restore | `snapshot.h` |
| Inline images | `kitty_graphics.h` |

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
the shell reports that a command started, later bytes go to a new block terminal. On command end they return to the shell terminal. The split is exact
even when one read holds the end of a command and the next prompt.

### Shell integration

Rewarp starts the shell with its own bootstrap, which sources the user's config and
then installs hooks. Only zsh is done, through `ZDOTDIR`. Bash and fish will use
`--rcfile` and `XDG_DATA_DIRS`. Hooks report prompts, command text, exit codes and
the working directory.

Those reports don't use OSC 133 and OSC 7, the standard way to send them, because
anything printed to the terminal could send those too: a file being read, a
background job at the prompt, or a remote shell with its own integration. They go
on a private OSC 7701 channel instead, each quoting a token made fresh for each
shell. The token reaches the shell through the environment, and the script moves it
to a shell variable straight away, so commands never inherit it.

Readiness comes from wrapping `zle-line-init`, not from a marker in `PS1`, because
prompt themes rewrite `PS1` and oh-my-posh runs the whole line edit inside its own
widget. If a shell at a prompt still doesn't report ready within a second, the app
assumes it is, so no prompt setup can wedge the input.

Startup output stays hidden, since it's mostly noise. But a shell that has printed
something and still has no prompt after two seconds may be asking a question, as
oh-my-zsh's update check does, so the pane then shows the shell terminal and sends
it keys until the prompt arrives. Commands submitted meanwhile wait for the prompt,
because a shell that's still starting can swallow what's written to it.

The prompt is hidden and the editor submits commands to the shell with bracketed
paste plus CR. Commands sent before the shell is ready are held until it reports
input start.

Fallback: without integration events the pane stays a plain terminal drawn from
the shell terminal, with keys sent straight to the PTY. This also covers shells
that are not supported yet. Inside a running command such as ssh or a nested
shell, the block acts as a plain terminal, as Warp's does.

### Rendering

A hand-written Metal renderer, one `CAMetalLayer` per pane:

- Glyphs are rasterised with Core Text into grayscale and colour atlases and cached
  per font, glyph and style, with one set per display scale. Fallback fonts come
  from Core Text.
- Instanced quads for backgrounds and glyphs. Instance data is cached per row and
  rebuilt only for dirty rows, keyed by the render state's stable row ids.
- Block chrome is drawn in the same pass, with AppKit overlays only for hover
  actions.
- Shaders are compiled from source at startup, which needs no Xcode. Startup cost
  is to be measured, and can be replaced with a precompiled library later.

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
- Output arriving faster than the display refreshes is simply coalesced.

### Panes

A tab's layout is `PaneTree`, a plain value holding splits, ratios and pane ids.
Views are positioned from it and stay flat children of one container, so a split
never reparents a running pane, and the tree can be tested without any views and
saved for session restore. Maximizing hides the other panes, which therefore can't
hold keyboard focus.

### Input editor

An `NSTextView` subclass, which brings IME, undo, selection and accessibility.
Rewarp adds shell syntax highlighting, ghost-text autosuggestions, a completion
menu, multi-line editing and Warp's Emacs-style bindings. Multi-cursor editing is
still to come.

Completions run natively in Swift, never in-band in the user's shell: `$PATH`
commands, files, git refs, ssh hosts, package scripts and make targets. Aliases and
functions are reported by the shell integration at startup. Everything inserted is
shell-quoted by default, because these names come from places an attacker can
control, such as a cloned repository.

### Stack

Swift 5 language mode, AppKit, SwiftPM. `scripts/` builds the pinned libghostty-vt
as a static library and assembles an ad-hoc-signed `.app`, and the `Makefile` is the
front door to all of it. Tests use Swift Testing.

No Xcode should be needed: Zig plus the Command Line Tools should be enough, as
the XCFramework and `metal` steps of Ghostty's build are avoidable here. To be
proven in M0.

## Milestones

[warp-parity.md](warp-parity.md) is the definition of done: 1,647 behaviours from
Warp's public docs, each with an ID. The milestones below are an order for working
through it, and every parity section belongs to exactly one.

A box in the parity file is ticked only when a test or the running app has shown
that the behaviour works. Progress is the count of ticked boxes, nothing else.

| Milestone | Parity sections |
| --- | --- |
| M0, proof. Done. | The bets below |
| M1, plain terminal. Done. | Part of EMU and PAN, TXT basics |
| M2, blocks | COR, BLK except find and filter, MOU for blocks, scrollbars, hover and alt-screen |
| M3, input editor | INP, MOU for the prompt and input, CMP, AUT, HIS, CSR, FIX, ALS, XRY, HLT |
| M4, find and palettes | BLK find and filter, PAL, NAV, FND |
| M5, windows | TAB, VTB, PAN, WIN, TBR, HKY, and their MOU sections |
| M6, sessions | RST, CWD, LCF, TCF, WFL, SYN |
| M7, settings and keys | SET, KEY, KBE |
| M8, appearance | THM, TXT, WAP, PRM, POS |
| M9, shells | EMU, ALT, TMX, SHL, WFY, SSH, VIM |
| M10, the rest | LNK, MKD, NTF, SEC, QUT, A11, URI, SLS, BAN, STU, IMP, UPD |
| M11, code features | EDT, FRP, FTR, LSP, REV, WTR |

Items marked `(verify in app)` are checked by observing Warp.app, not by reading
its code. `CNF` lists places where the docs disagree with each other.

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

From M1, with Ghostty 1.4.0 on default config and `scripts/bench.sh`:

| Bet | Result | Status |
| --- | --- | --- |
| Runtime shader compile is acceptable | 44 to 112 ms, launch about 100 to 160 ms | Proven |
| Scrolling output keeps up, keeping 50,000 rows | Rewarp 190 MB/s, Ghostty 175 MB/s | Proven |
| Full-screen repaint keeps up, keeping 50,000 rows | Rewarp 180 MB/s, Ghostty 147 MB/s | Proven |
| A full block is affordable | 152 MB resident for one 50,000-row block, before any compression | Measured |

Frames under load, on a 120 Hz display with a window of about 39 rows: a steady
117 to 120 fps through both a `yes` flood and a full-screen repaint, with 0.11 to
0.17 ms to build each frame.

Those numbers measure drain speed and frame rate. Not yet measured: keypress
latency, and Warp itself, which can't be scripted without writing into `~/.warp`.

Router note: with an `ESC \\` terminator the callback fires on the `ESC`, so the
`\\` still has to go to the old terminal, even if it arrives in a later read.
Otherwise it prints as a stray character in the next block.

## Calls made without asking

- libghostty-vt only, not `ghostty.h` (departs from the request; reasons above).
- One terminal per block.
- Own Metal renderer, AppKit, SwiftPM, no Xcode project.
- App name is Rewarp, from the repo name. Public distribution may want a name
  that doesn't lean on Warp's trademark.
- zsh first, then bash and fish.
- macOS 14 or later as the minimum, for the modern display link APIs.

## Going beyond Warp

Asked for by the user, and not in Warp:

- Tabs in a right sidebar. Warp offers the top and a left sidebar.
