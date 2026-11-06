# Third-party notices

Rewarp's own code is under the [MIT license](LICENSE). Dependencies keep their
own licenses. Copies of the notices below are in [LICENSES](LICENSES) and are
included in `Rewarp.app/Contents/Resources` by `make app`.

## libghostty-vt

Source: <https://github.com/ghostty-org/ghostty>, commit
`86aef72a2c8e67c780867de2378b2fc4d6dcd9ca`.

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors. MIT license;
see [Ghostty-MIT.txt](LICENSES/Ghostty-MIT.txt).

The pinned upstream [dependency inventory](LICENSES/libghostty-vt-third-party.json)
identifies the following linked code. It covers multiple upstream build targets
and may include more than a particular Rewarp build uses. These copies come from
the exact dependency archives referenced by the pinned Ghostty manifest, except
simdutf, whose license comes from Ghostty's vendored source.

| Component | Upstream license | Included notices |
| --- | --- | --- |
| Highway 1.2.0 | Apache-2.0 OR BSD-3-Clause | [Highway](LICENSES/highway/) |
| simdutf 9.0.0 | Apache-2.0 OR MIT | [MIT](LICENSES/simdutf/LICENSE-MIT) |
| translate-c 2.0.0 | MIT | [MIT](LICENSES/translate_c/LICENSE) |
| uucode 0.2.0 | MIT AND Unicode-3.0, with additional UTF-8 code attribution | [MIT](LICENSES/uucode/LICENSE.md), [Unicode](LICENSES/uucode/LICENSE_unicode), [UTF-8 decoder](LICENSES/uucode/LICENSE_Bjoern_Hoehrmann) |
| Wuffs 0.4.0-alpha.10 | Apache-2.0 OR MIT | [Wuffs](LICENSES/wuffs/) |

For dual-licensed components the permissive MIT or BSD alternative is used.
The inventory also lists packages used only at build time. Those packages are
downloaded by Zig and are not bundled as source in this repository.

When updating Ghostty, refresh the inventory and notices from that revision and
review the linked packages again; do not assume this list stays complete.

## JetBrains Mono Nerd Font

The app bundles `JetBrainsMonoNerdFont-Regular.ttf` unchanged from the same
Ghostty revision. JetBrains Mono: Copyright 2020 The JetBrains Mono Project
Authors (<https://github.com/JetBrains/JetBrainsMono>). Nerd Fonts: Copyright
2014 Ryan L McIntyre and contributors. The patched font is under the SIL Open
Font License 1.1. See [OFL](LICENSES/JetBrainsMono-OFL.txt) and the upstream
[Nerd Fonts notices](LICENSES/NerdFonts-LICENSE.txt), which include the
licensing breakdown for the font project.

## Project independence

Rewarp is an independent project and is not affiliated with or endorsed by Warp,
Ghostty, or JetBrains. Product names belong to their respective owners. Warp's
implementation is not a dependency; the parity checklist describes behavior
observed in public documentation. Contributions must not copy code or assets
without a compatible license and the required attribution.
