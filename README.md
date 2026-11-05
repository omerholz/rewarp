# Rewarp

A native macOS terminal with Warp's ergonomics and Ghostty's speed, and no AI.
Built on [libghostty-vt](https://github.com/ghostty-org/ghostty) with a hand-written
Metal renderer. See [docs/design.md](docs/design.md) for how it works and why.

## Build

You need Zig and the Xcode Command Line Tools. Full Xcode isn't required.

```bash
brew install zig
```

Build the app and open it:

```bash
make run
```

Run `make` on its own to list every command. The main ones:

| Command | What it does |
| --- | --- |
| `make build` | Debug binary |
| `make release` | Optimized binary |
| `make app` | `dist/Rewarp.app` |
| `make install` | Copies the app to `/Applications` |
| `make zip` | `dist/Rewarp-<version>.zip` |
| `make dmg` | `dist/Rewarp-<version>.dmg` |
| `make package` | Both the zip and the disk image |
| `make clean` | Removes build output, keeping libghostty-vt |
| `make distclean` | Removes everything that can be rebuilt |

The version is set in `Sources/RewarpCore/Version.swift`. Packages are signed ad
hoc, so they run on the machine that built them. On another Mac, Gatekeeper will
block them until they're signed with a Developer ID and notarized.

## Test

Unit tests, including ones that run a real zsh:

```bash
make test
```

End-to-end tests drive the real app with synthesized input, invisibly. They use a
private pasteboard and a throwaway `HOME`, so they don't touch your clipboard or
dotfiles.

```bash
make e2e
```

`make check` runs both, and `FILTER=name` narrows either one.

## Parity with Warp

[docs/warp-parity.md](docs/warp-parity.md) lists every non-AI Warp behaviour found
in Warp's public docs. A box is ticked only by a passing end-to-end test whose name
carries the item's ID, such as `test_blk_032_click_selects_block`.

Benchmark against the installed Ghostty with `make bench`, or with
`make bench MB=256 KIND=repaint` for full-screen repaints.

Warp's client is AGPL-3.0, so this project is written from scratch. Behaviour and
shortcuts are matched from public docs and by using the app. Please don't copy from
its source.
