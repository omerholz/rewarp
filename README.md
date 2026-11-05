# Rewarp

A native macOS terminal with Warp's ergonomics and Ghostty's speed, and no AI.
Built on [libghostty-vt](https://github.com/ghostty-org/ghostty) with a hand-written
Metal renderer. See [docs/design.md](docs/design.md) for how it works and why.

## Build

You need Zig and the Xcode Command Line Tools. Full Xcode isn't required.

```bash
brew install zig
```

```bash
scripts/build-ghostty-vt.sh
```

```bash
scripts/bundle.sh
```

```bash
open dist/Rewarp.app
```

## Test

Unit tests, including ones that run a real zsh:

```bash
scripts/test.sh
```

End-to-end tests drive the real app with synthesized input, invisibly. They use a
private pasteboard and a throwaway `HOME`, so they don't touch your clipboard or
dotfiles. Build first with `swift build --product Rewarp`.

```bash
python3 tests-e2e/run.py
```

## Parity with Warp

[docs/warp-parity.md](docs/warp-parity.md) lists every non-AI Warp behaviour found
in Warp's public docs. A box is ticked only by a passing end-to-end test whose name
carries the item's ID, such as `test_blk_032_click_selects_block`.

Benchmark against the installed Ghostty with `scripts/bench.sh 512 scroll` or
`scripts/bench.sh 256 repaint`.

Warp's client is AGPL-3.0, so this project is written from scratch. Behaviour and
shortcuts are matched from public docs and by using the app. Please don't copy from
its source.
