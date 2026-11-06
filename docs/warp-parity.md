# Warp parity spec

Exhaustive checklist of Warp's non-AI behaviour on macOS, for Rewarp. Read it with `docs/design.md`, which says how Rewarp is built. This file says what it must do.

Snapshot date: 2026-11-04. The docs and changelog move weekly, so items describe Warp as documented on that date.

## How to read this file

- A box is ticked only by a passing end-to-end test named for its ID, such as `test_blk_032_click_selects_block`. A full `make e2e` does that, so boxes are never ticked by hand.
- Each item is one behaviour with a stable ID. IDs never get reused. If an item is dropped, strike it through and keep the ID.
- `(verify in app)` means the sources imply the behaviour but don't state it precisely, or don't state it at all. Items worded "Undocumented:" are open questions, not claims. Run them against the real Warp.app and rewrite the item with what it does.
- Everything is paraphrased. Warp's menu labels and setting names are kept only because tests need them.
- macOS only. Windows and Linux behaviour was left out, except where a Linux doc is the only evidence for something on macOS.
- Warp-specific names (settings keys, file paths, URI schemes) describe Warp. Rewarp picks its own names, keeping the meaning and the default.

## Source references

| Form | Meaning |
| --- | --- |
| `terminal/blocks/block-basics` | Page path on docs.warp.dev |
| `changelog/2025.07.09` | Entry in the docs changelog, by release date |
| `blog/how-warp-works` | Post on warp.dev/blog |
| `privacy/events` | The telemetry event table in `support-and-community/privacy-and-security/privacy`. Event names are a useful record of which UI actions exist. |
| `3p/mvolkmann` | Third-party walkthrough, mvolkmann.github.io/blog/warp. Old, and always paired with `(verify in app)`. |

Sources used: the docs sitemap lists 410 pages, and 408 are in `llms-full.txt`. Every `terminal/` and `code/` page, the keyboard shortcuts page, and the shell, install and migration guides for iTerm2, Ghostty and Terminal.app were read in full. Other non-AI support pages were skimmed. AI, platform, factory and enterprise pages were only consulted to draw the line in [Excluded](#excluded). The 2021 to 2026 changelog was read with agent, cloud and Windows/Linux entries filtered out, and 18 blog posts were read or scanned. Demo videos and screenshots weren't available, so anything shown only on video is marked `(verify in app)`. Warp's source was not consulted. A few blog posts quote fragments of it, and nothing from those fragments is used here.

## Precedence when sources disagree

Reference pages (`all-settings`, `keyboard-shortcuts`) win over narrative pages for defaults and bindings. Newer changelog entries win over older ones. A changelog item records what shipped on that date and is assumed still true unless a later source says otherwise. Real conflicts are listed in [Source conflicts](#source-conflicts) and not silently resolved.

## Contents

1. [Core model and focus](#core-model-and-focus)
2. [Blocks](#blocks)
3. [Mouse interaction by surface](#mouse-interaction-by-surface)
4. [Input editor](#input-editor)
5. [Vim keybindings](#vim-keybindings)
6. [Completions, suggestions and history](#completions-suggestions-and-history)
7. [Palettes](#palettes)
8. [Tabs, panes and windows](#tabs-panes-and-windows)
9. [Sessions, restoration and reusable layouts](#sessions-restoration-and-reusable-layouts)
10. [Appearance](#appearance)
11. [Terminal emulation and shells](#terminal-emulation-and-shells)
12. [Other features](#other-features)
13. [Code features](#code-features)
14. [Settings and defaults](#settings-and-defaults)
15. [Default macOS keybindings](#default-macos-keybindings)
16. [Source conflicts](#source-conflicts)
17. [Top items to verify](#top-items-to-verify)
18. [Excluded](#excluded)

---

## Core model and focus

### Layout model

- [ ] COR-001 A window holds tabs, a tab holds panes, and each pane is its own terminal session with its own block list and input editor. (terminal/windows)
- [ ] COR-002 The viewport is an ordered, scrolling list of blocks rather than one character grid. (blog/block-model-behind-warps-agentic-development-environment)
- [ ] COR-003 The input editor and the prompt are separate UI elements from the terminal grid, so each can have its own hover behaviour and context menu. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [x] COR-004 Keystrokes typed at an idle prompt are held in the editor's own buffer and nothing reaches the shell until Enter sends the whole buffer. (blog/why-is-the-terminal-input-so-weird)
- [ ] COR-005 Warp reimplements completions, history search and soft wrap itself, which is why shell plugins that hook line editing conflict with it. (blog/why-is-the-terminal-input-so-weird)
- [ ] COR-006 Full-screen programs render on a separate alt-screen surface that sits beside the block list and swaps in on the standard mode change. (blog/block-model-behind-warps-agentic-development-environment)

### Pane states

- [ ] COR-007 A pane is in one of these states: bootstrapping, idle at the input, running a command on the primary screen, or running a full-screen program. Keyboard routing depends on the state. This four-state model is a summary, not Warp's wording. (blog/how-warp-works; blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs) (verify in app)
- [x] COR-008 While the shell bootstraps, the input editor already accepts typing and holds the command until the shell is ready. (changelog/2021.06.15)
- [ ] COR-009 `Ctrl+D` signals EOF while the shell is bootstrapping. (changelog/2024.10.11)
- [ ] COR-010 No prompt flash: the wrong prompt must not appear while bootstrap is in progress. (changelog/2022.10.20)
- [ ] COR-011 If startup takes longer than expected, a banner appears, not a popup. (changelog/2021.10.20)
- [ ] COR-012 Bootstrap commands don't appear in shell history. (changelog/2021.06.15; changelog/2023.06.08)
- [ ] COR-013 A slow bootstrap can reveal the bootstrap block's contents. The block is hidden by default. (privacy/events; terminal/settings/all-settings)

### Focus rules

- [x] COR-014 Selecting a block moves keyboard focus from the input editor to the block list by default. Setting `preserve_input_focus_on_block_selection` (default false) keeps focus in the input instead. (terminal/settings/all-settings; changelog/2026.06.10)
- [ ] COR-015 With focus on a selected block, the arrow keys move between blocks and must not drive any input dropdown. (changelog/2026.06.10)
- [ ] COR-016 Undocumented: what a printable keystroke does while a block is selected and focus is on the block list. Record it. (verify in app)
- [x] COR-017 `⌘L` focuses the terminal input from anywhere in the terminal view. (getting-started/keyboard-shortcuts)
- [x] COR-018 `⌘↓` on the most recent block (input at bottom) returns focus to the input and clears the block selection. (changelog/2021.12.22; changelog/2022.02.16)
- [ ] COR-019 Pressing `Esc` while a block is focused leaves the block and the up-arrow history still works afterwards. Exact effect of `Esc` on the selection isn't stated. (verify in app) (changelog/2022.05.04)
- [ ] COR-020 Running a command while blocks are selected returns focus to the input. (changelog/2026.06.24)
- [x] COR-021 A command finishing must not steal focus from anything, including the find bar. (changelog/2021.10.13; changelog/2022.02.23; changelog/2022.05.18)
- [ ] COR-022 Clicking a running long-lived block focuses the input and doesn't select the block. (changelog/2025.07.09)
- [ ] COR-023 Focus returns to the input editor after each of these: closing the share modal or a context menu, renaming a tab, clicking a hyperlink, pasting terminal content and running it. (changelog/2022.08.25; changelog/2022.06.27; changelog/2023.02.09; changelog/2023.12.07)
- [ ] COR-024 Closing a tab context menu restores the previous focus. (changelog/2026.09.30)
- [ ] COR-025 On app relaunch the input is focused and the last active window comes forward. (changelog/2022.01.12; changelog/2022.01.26)
- [ ] COR-026 Clicking into Warp from another app focuses the pane that was clicked. (changelog/2022.03.16; changelog/2023.06.20)
- [ ] COR-027 The input renders with a cursor after any temporary interaction such as a popover. (changelog/2026.08.13)
- [ ] COR-028 Leaving Command Search restores the cursor to its earlier position in the input. (changelog/2022.07.27)
- [ ] COR-029 Double character entry must not occur after the input loses and regains focus. (changelog/2021.10.27)
- [ ] COR-030 The input editor stays visible in inactive split panes. (changelog/2023.09.14)
- [ ] COR-031 Shortcut availability depends on state, for example `Ctrl+R` history search is only active when the input is visible. (blog/how-warp-works)

### Keyboard routing while a command runs

- [x] COR-032 While a command runs on the primary screen, keystrokes go to the program through the terminal's key encoder, not to the editor. (blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs; changelog/2026.08.13)
- [ ] COR-033 Characters typed during a long-running command that doesn't consume them appear in the input box when it completes (typeahead). (changelog/2021.08.09)
- [ ] COR-034 Keystrokes typed while a command runs are never dropped, even when the next prompt arrives right after Enter. (changelog/2022.10.06; changelog/2025.08.06; changelog/2026.04.29)
- [ ] COR-035 Typeahead text must not overlap the prompt. (changelog/2024.02.29)
- [ ] COR-036 Editing typeahead on bash older than 4.0 can be misread as background output. This is a known Warp limitation. Rewarp may do better. (terminal/blocks/background-blocks)
- [ ] COR-037 Typing into a running command scrolls its cursor into view. (changelog/2026.02.04)
- [ ] COR-038 `Page Up`, `Page Down`, `Home` and `End` go to the running program during long-running or full-screen commands. (terminal/blocks/block-basics; getting-started/keyboard-shortcuts)
- [ ] COR-039 `⌥←`, `⌥→`, `⌥⌫`, `⌘←`, `⌘→`, `⌘⌫` and `⌘fn⌫` have cursor-navigation bindings inside REPLs and subshells. They can be unset. (changelog/2023.03.30; changelog/2023.04.06)
- [x] COR-040 Single-line commands that finish in about 50 ms must not cause the input to jump up and down. (changelog/2022.05.04)
- [ ] COR-041 Executing a block must not flash the screen. (changelog/2022.06.27)
- [ ] COR-042 Undocumented: whether the input editor is hidden while a primary-screen command runs, and after how long. Changelog wording implies it hides past a short threshold. (verify in app)

## Blocks

### Creation

- [x] BLK-001 Running a command from the input creates a block holding that command and its output. (terminal/blocks/block-basics)
- [x] BLK-002 With input at the bottom, a new block lands directly above the input and older blocks move up. (terminal/blocks/block-basics)
- [ ] BLK-003 A multi-line buffer submitted with Enter runs its lines in sequence and each line produces its own block. (quickstart)
- [ ] BLK-004 Block boundaries come from shell hooks before and after each command, not from parsing output. (blog/how-warp-works)
- [ ] BLK-005 Each command gets isolated grids, so output with no trailing newline can't share a line with the next prompt and cursor movement can't overwrite an earlier block. (blog/how-warp-works)
- [ ] BLK-006 Internally a block has a left-prompt grid, an optional right-prompt grid, a command grid and an output grid. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] BLK-007 After the next block starts, a finished block is immutable apart from reflow on resize. (blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-008 Resizing rewrites visible grids to the pane's width, and no blank lines may be appended by it. (blog/the-data-structure-behind-terminals; changelog/2024.12.26)
- [ ] BLK-009 Resizing a pane while a command runs must keep the bottom reachable, must not lose scroll position and must not temporarily cut off output. (changelog/2022.02.16; changelog/2022.02.02; changelog/2023.06.01)
- [ ] BLK-010 Commands that print nothing still render fully, including multi-line ones. (changelog/2022.06.01)
- [ ] BLK-011 Rendering cost tracks visible rows only: blocks outside the viewport and rows outside the viewport aren't drawn. (blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-012 Undocumented: what Enter on an empty input does (no block, or an empty block). Record it. (verify in app)

### Anatomy

- [ ] BLK-013 A block shows its prompt, command, output and a runtime duration. (changelog/2022.02.16; terminal/blocks/block-actions)
- [ ] BLK-014 Duration is formatted in hours, minutes and seconds. (changelog/2022.08.25)
- [ ] BLK-015 Hovering the duration shows the start and end date and time. (changelog/2022.02.16)
- [ ] BLK-016 That timestamp tooltip stays visible with the input pinned to the top. (changelog/2023.09.07)
- [ ] BLK-017 Multi-line commands display in full, with no duplicated or missing leading characters, including with zsh themes and plugins. (changelog/2026.07.09; changelog/2026.06.03; changelog/2026.06.17)
- [ ] BLK-018 Bash older than 4.4 must not overlap the prompt, command and output for multi-line commands. (changelog/2024.05.16)
- [ ] BLK-019 Horizontal dividers separate blocks, on by default, also shown in compact mode. (terminal/appearance/blocks-behavior; changelog/2022.10.06)
- [ ] BLK-020 Compact mode reduces spacing between blocks, off by default, and persists across launches. (terminal/appearance/blocks-behavior)
- [ ] BLK-021 Compact mode also reduces the input editor's bottom padding. (changelog/2023.08.24)
- [ ] BLK-022 Toggling compact mode must keep padding and hover hit areas correct. (changelog/2021.09.22)

### States and appearance

- [x] BLK-023 A block that exits non-zero has a red background and a red sidebar. (terminal/blocks/block-basics)
- [x] BLK-024 A command like `xyz` that doesn't exist shows this failed style. (terminal/blocks/block-basics)
- [ ] BLK-025 Pagers and similar commands such as `git log` aren't shown as failed after normal use. (changelog/2021.10.20)
- [ ] BLK-026 A failed command also raises the error indicator on its tab when tab indicators are on. (terminal/appearance/tabs-behavior)
- [ ] BLK-027 Fish commands with syntax errors finish their block rather than leaving it open. (changelog/2024.07.18; changelog/2025.04.23)
- [ ] BLK-028 Undocumented: running-state appearance (spinner, border, live duration). Record it. (verify in app)
- [x] BLK-029 Undocumented: whether `Ctrl+C` on a running command renders as failed. (verify in app)
- [ ] BLK-030 A finished background block must not keep showing a cursor beside the input. (changelog/2026.08.27)
- [ ] BLK-031 The cursor is hidden when a program sends the hide-cursor sequence. (changelog/2022.08.25)

### Selecting blocks

- [x] BLK-032 Clicking a block selects it. (terminal/blocks/block-basics)
- [x] BLK-033 `⌘↑` with input at the bottom selects the most recent block, and `⌘↓` does this with the input pinned to the top. (terminal/blocks/block-basics)
- [x] BLK-034 Once a block is selected, `↑` and `↓` move to adjacent blocks. (terminal/blocks/block-basics)
- [x] BLK-035 `⌘+click` on another block toggles it in or out of the selection. (terminal/blocks/block-basics)
- [x] BLK-036 `Shift+click` selects the range between the active block and the clicked one. (terminal/blocks/block-basics)
- [x] BLK-037 `Shift+↑` and `Shift+↓` grow the selection up or down from the active block. (terminal/blocks/block-basics)
- [ ] BLK-038 The active block in a selection has a thicker border. (terminal/blocks/block-basics)
- [ ] BLK-039 Adjacent selected blocks render with one shared border, not one per block. (changelog/2024.03.14)
- [ ] BLK-040 `⌘A` selects all blocks when the block list has focus. In the input it selects the buffer. Both are bound to the same key, so the split by focus is implied. (verify in app) (getting-started/keyboard-shortcuts; terminal/editor)
- [ ] BLK-041 Right-clicking a block also focuses it. (changelog/2022.01.26)
- [ ] BLK-042 Multi-block selections support the block actions. (changelog/2022.03.16)
- [ ] BLK-043 Undocumented: whether a plain click on an already-selected block deselects it, and how to clear a selection with the mouse. (verify in app)
- [ ] BLK-044 Undocumented: whether selection survives a new block arriving. (verify in app)

### Navigating blocks

- [x] BLK-045 Scrolling works with mouse, trackpad and scrollbar. (terminal/blocks/block-basics)
- [ ] BLK-046 `Page Up` and `Page Down` scroll by a page at an idle prompt when the suggestion menu is closed. (terminal/blocks/block-basics; changelog/2026.05.06)
- [x] BLK-047 `Home` and `End` scroll to the top and bottom of terminal output. (terminal/blocks/block-basics)
- [ ] BLK-048 `⌘⇧↑` and `⌘⇧↓` scroll to the top and bottom of the selected block, also while the input has focus. (terminal/blocks/block-basics; changelog/2026.05.06)
- [ ] BLK-049 The palette offers scroll to top and bottom of the selected block. (terminal/blocks/block-basics; changelog/2023.08.31)
- [ ] BLK-050 Scroll up and down one line exist as actions with no default binding. (getting-started/keyboard-shortcuts; changelog/2023.09.14)
- [ ] BLK-051 On the last block, the down arrow scrolls to the bottom of that block. (changelog/2021.12.22)
- [ ] BLK-052 Up-arrow in block navigation moves one block, never more. (changelog/2022.02.23)
- [ ] BLK-053 Scroll position stays stable when a block hits its line limit. (changelog/2024.07.19)
- [ ] BLK-054 The block list returns to the correct scroll position after leaving the alt-screen. (changelog/2023.02.16)

### Text selection versus block selection

- [ ] BLK-055 Dragging over block text makes a text selection, a different thing from a block selection. (terminal/more-features/text-selection; terminal/blocks/block-basics)
- [ ] BLK-056 Selecting part of a URL by dragging doesn't open it. (changelog/2021.12.01)
- [ ] BLK-057 With a text selection in a block, `Shift+←`, `Shift+→`, `Shift+↑` and `Shift+↓` extend it. (changelog/2022.09.29)
- [ ] BLK-058 Copy prefers text selected in the input over a selected block when both exist. (changelog/2026.05.06)
- [ ] BLK-059 Text selection auto-scrolls when dragged past the viewport edge. (changelog/2026.05.06)
- [ ] BLK-060 Selecting during rapid output must not crash, and selection stays correct when a block reaches its line limit. (changelog/2026.03.05; changelog/2022.01.12)
- [ ] BLK-061 Find box prefill: opening find with text selected puts that text in the query. (changelog/2021.07.13)
- [ ] BLK-062 Undocumented: whether a text selection can span several blocks, and what it copies between them. (verify in app)
- [ ] BLK-063 Undocumented: whether a text selection and a block selection can coexist, and which `⌘C` prefers. (verify in app)

### Block actions

- [ ] BLK-064 Actions are reached from the kebab button on hover, by right-clicking the block, or with `Ctrl+M` on the selected block. (terminal/blocks/block-actions; changelog/2022.09.22)
- [x] BLK-065 Context menu lists: copy command, copy output, copy both, copy prompt, copy working directory, copy git branch, find within block, toggle block filter, toggle bookmark, reinput, split pane left, right, up and down, toggle maximize pane, close pane. Exact order and labels need checking. (verify in app) (terminal/blocks/block-actions; 3p/mvolkmann)
- [ ] BLK-066 The menu also has Paste. (changelog/2026.08.27)
- [ ] BLK-067 The menu also has Clear, which clears terminal output. (changelog/2026.05.18)
- [x] BLK-068 With text selected, the menu offers Copy and Insert into Input. (privacy/events; changelog/2023.12.21)
- [ ] BLK-069 Clicking outside dismisses the context menu, and menus in the block list are visually pronounced. (changelog/2021.07.28; changelog/2023.03.20)
- [ ] BLK-070 Context menus close when Settings opens. (changelog/2024.07.11)
- [ ] BLK-071 Find within Block on a running block works after clicking it. (changelog/2025.08.13)

### Copying

- [x] BLK-072 `⌘C` on a selected block copies its output. (quickstart; getting-started/keyboard-shortcuts)
- [x] BLK-073 `⇧⌘C` copies the selected commands. (getting-started/keyboard-shortcuts)
- [ ] BLK-074 `⌥⇧⌘C` copies the selected outputs. (getting-started/keyboard-shortcuts)
- [ ] BLK-075 Copy both copies command and output together, from the menu. (terminal/blocks/block-actions)
- [ ] BLK-076 Undocumented: separator and format when copying several blocks. (verify in app)
- [ ] BLK-077 Copying blocks includes custom PS1 prompt text. (changelog/2026.07.09)
- [ ] BLK-078 Copy Prompt respects PS1 when PS1 is on. (changelog/2023.03.23)
- [ ] BLK-079 With a same-line prompt, Copy Prompt and Copy Command still separate the two, including after resize moves the boundary. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] BLK-080 Copying a block with an OSC 8 link copies the visible text, not the URL or the escape sequence. (terminal/more-features/files-and-links)
- [ ] BLK-081 Copying output containing secrets gives asterisks unless revealed or copied from the secret's tooltip. (support-and-community/privacy-and-security/secret-redaction)
- [ ] BLK-082 Copying selected text creates one clipboard entry, not one per character. (changelog/2021.12.22)

### Bookmarks

- [x] BLK-083 `⌘B` toggles a bookmark on the selected block. So does Toggle bookmark in the menu. (terminal/blocks/block-actions)
- [ ] BLK-084 Several blocks can be bookmarked. (changelog/2022.07.07)
- [ ] BLK-085 Bookmarked blocks show indicators on the scrollbar, placed at their approximate position in history. (terminal/blocks/block-actions; changelog/2022.07.07)
- [ ] BLK-086 Clicking an indicator jumps to the block. (terminal/blocks/block-actions)
- [ ] BLK-087 Hovering an indicator shows a preview with prompt, command and the last two lines of output. (terminal/blocks/block-actions)
- [x] BLK-088 `⌥↑` and `⌥↓` jump to the nearest bookmark up or down. (terminal/blocks/block-actions; getting-started/keyboard-shortcuts)
- [ ] BLK-089 A bookmarked block shows a filled bookmark icon without needing hover. (changelog/2023.09.14)
- [ ] BLK-090 Bookmarks last only as long as the session is open. (terminal/blocks/block-actions)

### Filtering

- [x] BLK-091 Filtering shows only output lines that match, and deletes nothing, so clearing the filter restores all lines. (terminal/blocks/block-filtering)
- [ ] BLK-092 Open it with the filter icon at the block's top right, with `⌥⇧F` on the selected or latest block, or with Toggle Block Filter in the menu. (terminal/blocks/block-filtering)
- [ ] BLK-093 The filter editor has a large query field and a small numeric context-lines field. (terminal/blocks/block-filtering)
- [ ] BLK-094 Toggles: regex, case sensitive, invert. (terminal/blocks/block-filtering; changelog/2024.03.14)
- [ ] BLK-095 A number in the context field shows that many lines around each match. (terminal/blocks/block-filtering)
- [x] BLK-096 Toggling the filter on a block with no filter opens the editor. (terminal/blocks/block-filtering)
- [ ] BLK-097 Toggling it off and on again reapplies the same filter. (terminal/blocks/block-filtering)
- [x] BLK-098 The editor has a clear button. (changelog/2023.12.14)
- [ ] BLK-099 Regex supports `^` and `$` anchors. The changelog text lost the first character, read as `$`. (verify in app) (changelog/2024.03.14)
- [x] BLK-100 Results update as you type and you can keep adjusting the query. (blog/new-utilities-for-your-terminal-inspired-by-text-editors)
- [x] BLK-101 Filtering works on a command that's still running. (blog/new-utilities-for-your-terminal-inspired-by-text-editors)
- [ ] BLK-102 Triple-click line selection works on filtered output. (changelog/2023.12.14)
- [ ] BLK-103 Undocumented: how the block shows that a filter is active, and whether hidden-line gaps are marked. (verify in app)

### Find

Find in the alt-screen is covered in [Full-screen apps](#full-screen-apps).

- [x] BLK-104 `⌘F` opens a find view scoped to the current pane. (terminal/blocks/find)
- [x] BLK-105 Find searches all blocks from the bottom up. (terminal/blocks/find)
- [x] BLK-106 Find can be limited to the selected block, with the find-on-selected-block option or by pressing `⌘F` with a block selected. (terminal/blocks/find; terminal/blocks/block-actions)
- [ ] BLK-107 Toggles: regex and case sensitive. (terminal/blocks/find; changelog/2022.06.01; changelog/2022.03.16)
- [x] BLK-108 Input stays usable while find is open. (terminal/blocks/find)
- [ ] BLK-109 Undocumented: whether matches update on each keystroke or on Enter. (verify in app) (terminal/blocks/find)
- [x] BLK-110 No matches shows `0/0`. (changelog/2021.06.15)
- [ ] BLK-111 Navigating to a match on the same row doesn't scroll. (changelog/2021.06.15)
- [ ] BLK-112 Matches get a yellow rectangle drawn at the cell layer. (changelog/2021.06.15)
- [x] BLK-113 `⌘G` and `⇧⌘G` move to the next and previous match. (changelog/2022.05.26; getting-started/keyboard-shortcuts)
- [ ] BLK-114 Reopening the find bar selects the existing query. (changelog/2022.04.15; changelog/2022.08.03)
- [ ] BLK-115 Pasting several lines into find collapses them into one line. (changelog/2025.01.08)
- [ ] BLK-116 Find matches double-width text, including CJK and emoji. (changelog/2023.06.29)
- [ ] BLK-117 Find keeps highlighting matches after the screen is cleared during a running command. (changelog/2022.10.06)
- [ ] BLK-118 New output streaming into the active block must not move the current match. (changelog/2026.05.06)
- [ ] BLK-119 Find stays responsive on large outputs by searching asynchronously. (changelog/2026.05.27; changelog/2026.07.23)
- [ ] BLK-120 Find never returns partial results. (changelog/2022.09.01)
- [x] BLK-121 `Esc` closes find. (verify in app)

### Sticky command header

- [ ] BLK-122 When a block's output is cut off, its header stays pinned to the top of the pane, enabled by default. (terminal/blocks/sticky-command-header; terminal/blocks/block-basics)
- [ ] BLK-123 The header shows prompt and command. (changelog/2022.11.15)
- [ ] BLK-124 Clicking the header scrolls to the top of the block. (terminal/blocks/sticky-command-header)
- [ ] BLK-125 An up/down arrow in the middle of the header minimises it for the active pane. (terminal/blocks/sticky-command-header)
- [ ] BLK-126 `⌘⌃S` turns the feature off globally, as does the toggle in Settings or the palette. (terminal/blocks/sticky-command-header)
- [ ] BLK-127 `⌃S` toggles it in the active pane only. (terminal/blocks/sticky-command-header)
- [ ] BLK-128 For long-running commands that fill the screen, the header only appears after you start scrolling up, so it doesn't cover pseudo-full-screen output such as `git log`. (terminal/blocks/sticky-command-header)
- [ ] BLK-129 The header doesn't cut off or cover content for pagers. (changelog/2023.04.13; changelog/2023.06.01)

### Jump to bottom

- [ ] BLK-130 A jump-to-bottom button appears at the bottom left when a multi-line block starts scrolling out of reach. The changelog ties it to the hovered block, so its exact trigger needs checking. (verify in app) (blog/configure-input-at-the-top-in-warp; changelog/2023.04.06)
- [ ] BLK-131 Clicking it jumps to the latest line of that block. `⌘⇧↓` does the same. (blog/configure-input-at-the-top-in-warp)
- [ ] BLK-132 Setting `show_jump_to_bottom_of_block_button` hides it, default on. (terminal/settings/all-settings)
- [ ] BLK-133 With input pinned to the top, Lock scrolling at bottom of block keeps following output. (terminal/appearance/input-position)

### Re-input

- [x] BLK-134 `⌘I` puts the selected commands back in the input. (getting-started/keyboard-shortcuts)
- [ ] BLK-135 `⇧⌘I` does the same as root. (getting-started/keyboard-shortcuts; changelog/2021.08.18)
- [ ] BLK-136 Multi-line commands re-input correctly. (changelog/2021.08.18)
- [ ] BLK-137 Reinput is also in the context menu. (privacy/events)
- [ ] BLK-138 Undocumented: how several selected commands are joined in the input, and how the root form is written (`sudo` prefix or other). (verify in app)

### Clearing

- [x] BLK-139 `⌘K` clears the whole block list. (terminal/appearance/input-position)
- [ ] BLK-140 `⌃L` pushes blocks out of view past the scroll position while keeping them reachable. (terminal/appearance/input-position)
- [ ] BLK-141 With input starting at the top, `⌃L`, `⌘K` and `clear` return the input to the top, and `⌃L` and `clear` keep scroll history. (terminal/appearance/input-position; changelog/2023.04.06)
- [ ] BLK-142 Text input keeps working after `⌘K` inside a REPL. (changelog/2022.07.20)
- [ ] BLK-143 Clearing frees block memory at once. (changelog/2024.11.11)
- [ ] BLK-144 `⌘K` also removes those blocks from what restoration would bring back. (terminal/sessions/session-restoration)
- [ ] BLK-145 `clear` doesn't show up as a snackbar command at the top of the window. (changelog/2022.09.29)
- [ ] BLK-146 Clearing and then resizing must not crash, including when scrollback exists. (changelog/2026.06.10; changelog/2026.07.09)

### Huge output

- [x] BLK-147 A block holds up to 50,000 rows by default. (terminal/settings/all-settings; changelog/2025.05.21)
- [ ] BLK-148 The limit is user-set under Settings > Features > Session > Maximum rows in a block. (changelog/2025.07.30)
- [ ] BLK-149 Undocumented: what happens at the limit (oldest rows dropped or new rows dropped) and whether any notice is shown. Changelog wording suggests older rows go. (verify in app)
- [ ] BLK-150 Sessions with many blocks use reduced memory, with old rows in a compact representation. (changelog/2022.12.06; blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-151 File-path detection must stay bounded in long outputs. (changelog/2026.05.06)
- [ ] BLK-152 Very long runs of zero-width characters must not crash, including from restored sessions. (changelog/2026.04.27)
- [ ] BLK-153 Output must not stall or cut off for long-running tools such as Gradle, Maven or Bazel. (changelog/2022.08.03; changelog/2023.07.06; changelog/2022.05.11)

### Prompt on a block

- [ ] BLK-154 A finished block keeps the prompt as it looked when the command ran. (terminal/blocks/block-actions; blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] BLK-155 With a Warp prompt, right-clicking offers copying the whole prompt or a chip's value. (terminal/appearance/prompt)
- [ ] BLK-156 With a shell prompt, right-clicking offers copying the whole prompt, and part of it can be selected in a previously run block. (terminal/appearance/prompt)
- [ ] BLK-157 With a same-line prompt the prompt and command share one wrapped region. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] BLK-158 Prompt and input text must not overlap on narrow panes with a same-line Warp prompt. (changelog/2025.08.13)

### Full-screen commands

- [x] BLK-159 Full-screen programs take over the pane's view and the block list comes back on exit. (blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-160 Alt-screen programs expand to fill the window. (changelog/2022.03.16; changelog/2022.12.06)
- [ ] BLK-161 Selection from before must not reappear after leaving and reopening the alt-screen. (changelog/2021.08.18)
- [ ] BLK-162 Leaving the alt-screen after a find search must not hang. (changelog/2023.02.16)
- [ ] BLK-163 Exiting `info` is detected as process termination. (changelog/2023.02.28)
- [ ] BLK-164 Undocumented: what remains in the block list after a full-screen program exits. (verify in app)

### Interactive commands

- [ ] BLK-165 Commands that read input, like REPLs, run inside their block as a plain terminal and Warp doesn't change their environment. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] BLK-166 Arrow keys with Option or Command modifiers work in CLIs such as the Postgres client. (changelog/2021.08.09)
- [ ] BLK-167 Password prompts can trigger a desktop notification. (terminal/more-features/notifications)
- [ ] BLK-168 Long-running full-grid tools such as `k9s`, `less`, `mitmproxy` and `lazygit` render and don't hang. (changelog/2022.12.15; changelog/2022.12.06; changelog/2024.12.19)
- [ ] BLK-169 IME composition is positioned correctly in running blocks. (changelog/2023.02.16)

### Background output

- [ ] BLK-170 Output that arrives with no foreground command goes to a background block. (terminal/blocks/background-blocks)
- [ ] BLK-171 A background block acts like a regular block but has no command. (terminal/blocks/background-blocks)
- [ ] BLK-172 Background blocks appear automatically between regular blocks, and output from a process that keeps printing is split across several blocks interleaved with your commands. (terminal/blocks/background-blocks)
- [ ] BLK-173 If a background process prints during a foreground command, the output goes into the foreground block. (terminal/blocks/background-blocks)
- [ ] BLK-174 Output from several background processes may mix in one block. (terminal/blocks/background-blocks)
- [ ] BLK-175 Background blocks support block features such as bookmarking. (terminal/blocks/background-blocks)
- [ ] BLK-176 The hover toolbelt on a background block has a solid background. (changelog/2023.12.21)
- [ ] BLK-177 Restored background blocks don't create blank history entries. (changelog/2023.06.08)

### Commands that never finish

- [ ] BLK-178 A block stays open and keeps streaming until the shell reports the command finished. No timeout is documented. (verify in app) (blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-179 Scrolling up during streaming is possible and shows the sticky header. (terminal/blocks/sticky-command-header)
- [x] BLK-180 Filter and find work during streaming. (blog/new-utilities-for-your-terminal-inspired-by-text-editors; changelog/2026.05.06)
- [ ] BLK-181 Closing a pane, tab or window on a running command warns first, and quitting does too. (terminal/more-features/quit-warning; changelog/2024.10.11; changelog/2025.01.08)
- [ ] BLK-182 A command that runs longer than the threshold notifies on completion if Warp isn't frontmost. (terminal/more-features/notifications)
- [ ] BLK-183 System logout, shutdown and scheduled OS updates aren't blocked by a running process. (changelog/2026.07.03)
- [ ] BLK-184 Share is only offered on finished blocks. Noted as a signal that some actions depend on completion. (terminal/blocks/block-sharing)
- [ ] BLK-185 Undocumented: which other block actions are disabled while running. (verify in app)

### Hidden blocks

- [ ] BLK-186 Remote-session helper commands create blocks that are hidden by default. `Show background blocks` in the Blocks menu reveals them. (terminal/warpify/subshells; blog/block-model-behind-warps-agentic-development-environment)
- [ ] BLK-187 Hidden bootstrap and SSH-connection blocks have their own settings, both default off. (terminal/settings/all-settings)
- [ ] BLK-188 Undocumented: changelog says blocklist lines can be hidden, with no detail. (verify in app) (changelog/2025.01.08)

## Mouse interaction by surface

Coverage so far, from docs, changelog and blog. `D` means documented, `P` partly documented, `?` not documented at all. Every `P` and `?` needs a pass through the real app.

| Surface | Click | Dbl | Triple | Drag | Shift-click | ⌘-click | Right-click | Hover | Copy-on-select | Middle | Mouse reporting |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Block output text | D | D | D | D | P | P | D | P | D | D | n/a |
| Block command and header | P | ? | ? | P | P | P | D | D | ? | ? | n/a |
| Prompt | P | ? | ? | P | ? | ? | D | ? | ? | D | n/a |
| Typed text in input | D | D | D | D | ? | ? | D | D | n/a | D | n/a |
| Autosuggestion ghost text | ? | ? | ? | ? | ? | ? | ? | P | n/a | ? | n/a |
| Links and file paths | D | ? | ? | P | ? | D | D | D | ? | ? | P |
| Tab bar | D | D | n/a | D | D | D | D | D | n/a | D | n/a |
| Panes and dividers | D | D | n/a | D | ? | ? | D | P | n/a | ? | n/a |
| Scrollbars | D | n/a | n/a | P | n/a | n/a | n/a | D | n/a | n/a | n/a |
| Hover action buttons | D | ? | n/a | n/a | ? | ? | ? | D | n/a | n/a | n/a |
| Palettes and menus | D | ? | n/a | D | n/a | n/a | n/a | D | n/a | n/a | n/a |
| Alt-screen apps | P | ? | ? | D | D | ? | D | D | D | ? | D |

### Rules that apply everywhere

- [x] MOU-001 Copy on select is on by default. Selected text in blocks and in alt-screens goes to the clipboard automatically. (terminal/settings/all-settings; terminal/editor; changelog/2024.03.14)
- [ ] MOU-002 Copy on select persists across launches and updates. (changelog/2021.12.08; changelog/2022.01.05)
- [ ] MOU-003 Middle-click pastes from the clipboard on macOS, default on through `middle_click_paste_enabled`. (terminal/settings/all-settings; changelog/2024.10.11)
- [ ] MOU-004 Warp writes and reads a primary selection where the platform has one. On macOS, which doesn't, it uses the normal clipboard. (changelog/2024.03.14)
- [ ] MOU-005 Middle-click paste moves focus to the input editor. (changelog/2024.04.04)
- [ ] MOU-006 Middle-click paste only pastes into the pane it's aimed at. (verify in app) (changelog/2024.04.04)
- [ ] MOU-007 Setting `right_click_behavior` has two values. `context_menu` (default) opens a menu. `paste` pastes, and `Shift`+right-click then opens the menu. (terminal/settings/all-settings; changelog/2026.08.27)
- [ ] MOU-008 `Ctrl+click` is an alternative to right-click. (changelog/2022.06.08)
- [ ] MOU-009 Pointer cursor appears on clickable elements and on links. The I-beam appears over the input editor. (changelog/2022.06.29; changelog/2022.10.13; changelog/2024.12.19)
- [ ] MOU-010 Scroll wheel amount is `mouse_scroll_multiplier`, default 3.0, shown as Lines Scrolled by Mouse Wheel Interval. (terminal/settings/all-settings; changelog/2024.03.07)
- [ ] MOU-011 Scroll speed is the same across the whole app. (changelog/2023.11.16)
- [ ] MOU-012 Scrolling stays smooth on macOS Tahoe. (changelog/2025.09.17)
- [ ] MOU-013 Click targets inside scrolling views still register if the pointer is moving. (changelog/2025.04.02)
- [ ] MOU-014 Only one handler consumes a mouse-down, so a child that handles it stops a parent from also handling it. (changelog/2026.06.24)
- [ ] MOU-015 No touch input support. (support-and-community/troubleshooting-and-support/known-issues)

### Block output text

- [ ] MOU-016 Single click selects the block under the pointer. (terminal/blocks/block-basics)
- [x] MOU-017 Single click on a running long-lived block focuses the input and doesn't select it. (changelog/2025.07.09)
- [ ] MOU-018 Double-click runs smart selection when enabled (default), treating URLs, file paths, email addresses, IP addresses and floats including scientific notation as one unit. The setting's description also lists identifiers. (terminal/more-features/text-selection; terminal/settings/all-settings)
- [ ] MOU-019 With smart selection off, double-click selects a word, and the characters in `word_char_allowlist` (default `-.~/\`) count as word characters. (terminal/settings/all-settings)
- [ ] MOU-020 Double-click on a string with underscores selects the whole string, not one subword. (changelog/2022.01.12)
- [ ] MOU-021 Double-click selects the right range when non-ASCII characters are present. (changelog/2025.01.29)
- [ ] MOU-022 Smart-selecting right-to-left text must not crash. (changelog/2026.09.09)
- [ ] MOU-023 Double-click then drag extends by word, and must not run past word boundaries into the next word. (changelog/2026.07.03)
- [x] MOU-024 Triple-click selects a line. (changelog/2023.12.14)
- [x] MOU-025 Plain drag makes a text selection, and drag past the viewport edge auto-scrolls. (terminal/blocks/block-basics; changelog/2026.05.06)
- [ ] MOU-026 `⌘⌥`+drag makes a rectangular (column) selection. (terminal/more-features/text-selection; changelog/2025.01.22)
- [ ] MOU-027 Shift-click selects a block range when used on blocks. (terminal/blocks/block-basics)
- [ ] MOU-028 `⌘`-click toggles block selection. On a link it opens the link instead. (terminal/blocks/block-basics; terminal/more-features/files-and-links)
- [ ] MOU-029 Right-click opens the block context menu. With text selected it adds Copy and Insert into Input. (terminal/blocks/block-actions; privacy/events)
- [ ] MOU-030 Dragging a selection doesn't also start a block selection. (verify in app)
- [ ] MOU-031 Undocumented on this surface: whether shift-click after a text selection extends the text selection instead of making a block range. Record it. (verify in app)
- [ ] MOU-032 Undocumented on this surface: which hover state a block shows other than its action buttons. (verify in app)

### Block command and header text

- [ ] MOU-033 Text in the command and prompt areas of a block can be selected by dragging. (terminal/appearance/prompt)
- [ ] MOU-034 Clicking a block's command scrolls to the top of its output. (verify in app) (3p/mvolkmann)
- [ ] MOU-035 Clicking the sticky header scrolls to the top of the block. (terminal/blocks/sticky-command-header)
- [ ] MOU-036 Clicking the arrow in the sticky header minimises it. (terminal/blocks/sticky-command-header)
- [ ] MOU-037 Hovering the duration shows start and end time. (changelog/2022.02.16)
- [ ] MOU-038 Right-clicking anywhere in the block opens the same block menu. (verify in app) (3p/mvolkmann)
- [ ] MOU-039 Undocumented on this surface: triple-click, whether copy on select applies, and whether double-click runs smart selection in the command text. (verify in app)

### The prompt

- [ ] MOU-040 Right-clicking the Warp prompt opens the prompt menu, which copies the whole prompt or a single chip's value such as working directory or git branch. `Shift`+right-click does this when right-click is set to paste. (terminal/appearance/prompt)
- [ ] MOU-041 Right-clicking a shell prompt opens a menu that copies the whole prompt. (terminal/appearance/prompt)
- [ ] MOU-042 The prompt menu has Edit prompt, which opens the prompt editor. (getting-started/quickstart/customizing-warp)
- [ ] MOU-043 The prompt menu toggles the changed-file count on the git chip. (changelog/2022.11.03; privacy/events)
- [ ] MOU-044 The prompt menu can switch on the custom shell prompt. (changelog/2022.06.08)
- [ ] MOU-045 Prompt chips are clickable, including with the prompt pinned to the top. (changelog/2025.04.16)
- [ ] MOU-046 Clicking the git branch chip opens a searchable branch picker, which can create a branch. (changelog/2025.06.25; changelog/2026.05.14; changelog/2026.05.20)
- [ ] MOU-047 Clicking the directory chip opens a searchable directory list, and changing directory from it keeps the text in the input. (changelog/2025.06.25; changelog/2026.03.05)
- [ ] MOU-048 Clicking the Node version chip switches versions. (changelog/2025.09.10)
- [ ] MOU-049 Clicking the git diff chip opens the code review panel, and a menu on it switches the diff view. (code/code-review)
- [ ] MOU-050 Middle-click paste works with the pointer over the prompt. (changelog/2024.04.18)
- [ ] MOU-051 A shell prompt can be partly selected on a previously run block. (terminal/appearance/prompt)
- [ ] MOU-052 Undocumented on this surface: left click, double-click, triple-click and selection on the live prompt. (verify in app)

### Typed text in the input editor

- [ ] MOU-053 Single click places the cursor. (terminal/editor; quickstart)
- [ ] MOU-054 Clicking after scrolling a long input lands on the clicked line, not one above. (changelog/2026.03.25)
- [ ] MOU-055 Drag selects, and typing replaces the selection. (quickstart)
- [ ] MOU-056 Double-click runs smart selection, same patterns as block text. (terminal/more-features/text-selection)
- [ ] MOU-057 Double-click then drag selects by word. (changelog/2022.09.29)
- [ ] MOU-058 Triple-click selects the logical line, so a soft-wrapped line counts as one. (terminal/editor)
- [ ] MOU-059 Hovering a part of the command shows its Command Inspector tooltip. (terminal/editor/command-inspector)
- [ ] MOU-060 Hovering multi-byte text must not crash. (changelog/2022.12.01)
- [ ] MOU-061 Right-click opens the input menu with Cut, Copy, Paste, Select All, Command Search and split-pane actions. Exact list needs checking. (verify in app) (changelog/2023.04.27; privacy/events)
- [ ] MOU-062 Dropping a file or folder from Finder inserts its path with whitespace escaped, once. (changelog/2021.11.17; changelog/2021.11.24; changelog/2025.01.15)
- [ ] MOU-063 Copying from Finder and pasting into the input inserts the path. (changelog/2021.12.22)
- [ ] MOU-064 Undocumented on this surface: shift-click to extend selection, and the mouse gesture that adds a cursor. Linux and Windows use Alt for this, and the macOS modifier isn't stated. (verify in app) (changelog/2025.02.26)

### Autosuggestion ghost text

- [ ] MOU-065 Ghost text stays visible when the input loses focus, which stops height flicker when it wraps. (changelog/2025.02.26)
- [ ] MOU-066 The optional ignore button shows an X next to the suggestion, off by default. Clicking it hides that suggestion from then on. (terminal/settings/all-settings; changelog/2025.09.10)
- [ ] MOU-067 Undocumented on this surface: whether clicking in ghost text places the cursor or accepts anything, and whether it's selectable. (verify in app)

### Links and file paths in output

- [ ] MOU-068 Hovering a link underlines it and shows a pointer cursor. (changelog/2022.10.13; terminal/more-features/files-and-links)
- [ ] MOU-069 Links only react to hover when Warp is focused. (changelog/2023.02.16)
- [ ] MOU-070 A hover tooltip shows on links when `link_tooltip` is on (default). (terminal/settings/all-settings)
- [ ] MOU-071 `⌘`+click opens the link at once. (terminal/more-features/files-and-links)
- [ ] MOU-072 Plain click opens a clickable tooltip reading Open File, Open Folder or Open Link. (terminal/more-features/files-and-links)
- [ ] MOU-073 That tooltip also has Show in Finder for detected file links. (changelog/2026.05.06)
- [ ] MOU-074 File links can open with Open in Warp from the tooltip. (code/code-editor)
- [ ] MOU-075 Right-click opens a menu that copies the absolute path or URL. (terminal/more-features/files-and-links; changelog/2022.02.23)
- [ ] MOU-076 Right-click on a file path offers Show in Finder. (changelog/2023.06.08)
- [ ] MOU-077 OSC 8 links render only their visible text and open with `⌘`+click. (terminal/more-features/files-and-links)
- [ ] MOU-078 Dragging across a URL selects text and doesn't open anything. (changelog/2021.12.01)
- [ ] MOU-079 Link hover highlight clears when an alt-screen program changes the text beneath it. (changelog/2024.08.29)
- [ ] MOU-080 Undocumented on this surface: how a plain click interacts with block selection (does it also select the block), and double-click on a link beyond smart selection. (verify in app)

### Tab bar

- [ ] MOU-081 Click activates a tab. (terminal/windows/tabs)
- [x] MOU-082 Double-click renames a tab. (terminal/windows/tabs; changelog/2023.03.20)
- [ ] MOU-083 Double-clicking a tab or a button in the title bar doesn't resize the window. (changelog/2023.03.20)
- [ ] MOU-084 Double-clicking an empty part of the title area zooms the window. (changelog/2021.07.13; changelog/2022.02.02)
- [ ] MOU-085 Hovering a tab reveals its close `X`. (terminal/windows/tabs)
- [ ] MOU-086 Tabs don't change size while hovered, so several can be closed in a row. (changelog/2025.03.26)
- [ ] MOU-087 Middle-click closes a tab. (changelog/2022.08.10)
- [x] MOU-088 Drag reorders tabs. (changelog/2022.12.15; terminal/windows/tabs)
- [ ] MOU-089 Dragging a tab out to empty space opens it in a new window, keeping its session, panes and state. (terminal/windows/tabs)
- [ ] MOU-090 Dragging a tab onto another window's bar moves it there. (terminal/windows/tabs)
- [ ] MOU-091 Cross-window drag must not split tab groups, must work with pinned tabs, and must not crash when entering full screen. (changelog/2026.06.24; changelog/2026.07.09)
- [x] MOU-092 Tabs must never stick mid-drag. (changelog/2025.02.12)
- [ ] MOU-093 `⌘`-click adds or removes a tab from a multi-selection. (terminal/windows/tabs)
- [ ] MOU-094 `Shift`-click selects every tab between it and the active tab. (terminal/windows/tabs)
- [ ] MOU-095 The active tab is always part of a tab selection. (terminal/windows/tabs)
- [ ] MOU-096 Right-click on a tab opens the tab menu. See [Tabs](#tabs). (terminal/windows/tabs)
- [ ] MOU-097 Clicking `+` opens a new tab, right-clicking it opens a menu with new tab, restore closed tab and launch configurations. (terminal/windows/tabs; changelog/2023.06.01)
- [ ] MOU-098 Hovering `+` shows a tooltip. (changelog/2023.06.29)
- [ ] MOU-099 The new-tab button has hover and pressed states. (changelog/2021.06.15)
- [ ] MOU-100 A dropdown next to `+` picks a shell. (changelog/2024.12.13)
- [ ] MOU-101 When the tab bar is hidden, hovering near the top of the window reveals it. (terminal/appearance/tabs-behavior)
- [ ] MOU-102 Holding a modifier shows each tab's switch-to-tab shortcut on the tab. (changelog/2026.08.27)
- [ ] MOU-103 Tab tooltips don't show stray whitespace. (changelog/2025.09.01)

### Panes and dividers

- [ ] MOU-104 Clicking a pane activates it. (terminal/windows/split-panes)
- [ ] MOU-105 With `focus_pane_on_hover` on (default off), moving the pointer over a pane makes it active. (terminal/appearance/pane-dimming; terminal/settings/all-settings)
- [ ] MOU-106 Dragging a divider resizes panes. (verify in app) (3p/mvolkmann)
- [ ] MOU-107 Double-clicking a divider evens out the panes in that split. (changelog/2026.05.20)
- [ ] MOU-108 Dragging a pane header moves the pane within the tab. (terminal/windows/split-panes)
- [ ] MOU-109 Dragging a pane to the tab bar moves it to another tab or makes it a new tab. (terminal/windows/split-panes)
- [ ] MOU-110 Pane drags always show a drop target. (changelog/2024.04.11)
- [ ] MOU-111 Right-click on a pane offers splitting in any direction, maximize and close. (verify in app) (terminal/windows/split-panes; 3p/mvolkmann)
- [ ] MOU-112 Pane controls show on hover only. (changelog/2025.01.08)
- [ ] MOU-113 The active pane has a triangle in its top-left corner. (terminal/appearance/pane-dimming; changelog/2022.01.05)
- [ ] MOU-114 Pane header overflow menu shows Maximize or Minimize with its shortcut. (changelog/2026.06.24)
- [ ] MOU-115 Undocumented on this surface: shift-click, `⌘`-click, middle-click and right-click on the divider itself. (verify in app)

### Scrollbars

- [ ] MOU-116 Scrollbars show on hover only. (changelog/2025.01.08)
- [ ] MOU-117 Clicking in the scrollbar track jumps to that position. (changelog/2022.07.13)
- [ ] MOU-118 Clicking above the thumb doesn't produce a wrong position. (changelog/2023.02.16)
- [ ] MOU-119 Bookmark indicators sit on the scrollbar and can be clicked and hovered. (terminal/blocks/block-actions)
- [ ] MOU-120 Clicking the scrollbar of the input suggestions menu doesn't close that menu. (changelog/2021.06.15)
- [ ] MOU-121 Undocumented on this surface: thumb dragging details and overlay versus legacy scroller style. (verify in app)

### Hover action buttons

- [ ] MOU-122 Hovering a block reveals a toolbelt at its top right with the kebab button and the filter icon. (terminal/blocks/block-actions; terminal/blocks/block-filtering)
- [ ] MOU-123 Kebab opens the same menu as right-click. (terminal/blocks/block-actions)
- [ ] MOU-124 The toolbelt has a solid background when it overlaps the prompt. (changelog/2023.12.14)
- [ ] MOU-125 The bookmark icon is a toolbelt button, per the Linux tab of the docs. Check it exists on macOS. (verify in app) (terminal/blocks/block-actions)
- [ ] MOU-126 The workflow button was removed from the toolbelt. It's now in the menu only. (changelog/2023.11.09)
- [ ] MOU-127 Hovering hover icons must not glitch. (changelog/2022.10.27)
- [ ] MOU-128 Undocumented on this surface: tooltip text and delay, and what shows in the toolbelt on a selected block. (verify in app)

### Palettes and menus

- [ ] MOU-129 Items highlight under the pointer. (changelog/2022.08.18)
- [ ] MOU-130 Click runs an item. (terminal/sessions/session-navigation; terminal/command-palette)
- [ ] MOU-131 Filter buttons at the top of the palette can be clicked. (terminal/command-palette)
- [ ] MOU-132 Dragging the right edge of Command Search and the Workflows menu resizes them horizontally, and the width persists. (terminal/entry/command-search; changelog/2023.03.23)
- [ ] MOU-133 All inline menus can be resized. (changelog/2026.03.25)
- [ ] MOU-134 Clicking outside closes a context menu. (changelog/2021.07.28)
- [ ] MOU-135 Clicking an open dropdown closes it. (changelog/2022.08.18)
- [ ] MOU-136 Clicking a menu-bar item that has a sub-menu keeps the menu open. (changelog/2023.06.01)
- [ ] MOU-137 Keybinding chips show in menus and tooltips. (changelog/2026.08.27)
- [ ] MOU-138 Clicking the checkmark or X in the theme picker saves or reverts. (terminal/appearance/themes)
- [ ] MOU-139 Clickable tab completions: the menu can be used with the mouse. (terminal/command-completions/completions)

### Alt-screen apps and mouse reporting

- [ ] MOU-140 Mouse reporting is on by default and sends mouse events to the running app using escape sequences. (terminal/settings/all-settings; terminal/more-features/full-screen-apps)
- [ ] MOU-141 Scroll reporting is on by default and can only be enabled when mouse reporting is enabled. (terminal/settings/all-settings; terminal/more-features/full-screen-apps)
- [ ] MOU-142 Holding `Shift` sends a mouse event to Warp instead of the app without turning reporting off, for example to select text. (terminal/more-features/full-screen-apps)
- [ ] MOU-143 Shift-click selects text for apps in SGR mouse mode. (changelog/2024.07.11)
- [ ] MOU-144 With reporting off, or in an app that hasn't asked for mouse events, mouse actions go to Warp. (terminal/more-features/full-screen-apps)
- [ ] MOU-145 Reporting also applies to primary-screen apps that ask for it, such as Radare2. (changelog/2025.12.10)
- [ ] MOU-146 Toggle reporting from Settings > Features > Terminal, from the palette, or from View > Toggle Mouse Reporting. (terminal/more-features/full-screen-apps)
- [ ] MOU-147 The palette item reads Enable or Disable depending on state, with one entry only. (terminal/more-features/full-screen-apps; changelog/2026.06.03)
- [ ] MOU-148 Changing mouse or scroll reporting applies at once, and a banner confirms it. (changelog/2022.10.20; changelog/2023.03.09)
- [ ] MOU-149 Mouse reporting has no default key. (changelog/2023.03.09; getting-started/keyboard-shortcuts)
- [ ] MOU-150 Apps that request any-motion tracking (mode 1003) receive hover movement as motion events. (blog/making-ms-paint-work-in-the-terminal)
- [ ] MOU-151 Warp must not send synthetic motion events to the app. (blog/making-ms-paint-work-in-the-terminal)
- [ ] MOU-152 Drag in vim works. (changelog/2022.01.26)
- [ ] MOU-153 Right-click opens a context menu in the alt-screen unless the app takes mouse events. (changelog/2023.04.06)
- [ ] MOU-154 Single cells can be selected in the alt-screen. (changelog/2024.10.17)
- [ ] MOU-155 Selection in full-screen apps moves with the content when scrolled. (changelog/2024.06.27)
- [ ] MOU-156 Copy on select works in the alt-screen. (changelog/2024.03.14)
- [ ] MOU-157 Scrolling in an alt-screen app with scroll reporting behaves correctly. (changelog/2023.05.11)
- [ ] MOU-158 Undocumented on this surface: what scrolling does when scroll reporting is off (arrow keys sent, or nothing), and middle-click routing with reporting on. (verify in app)

## Input editor

Focus and keystroke routing are in [Focus rules](#focus-rules). Binding-only lists are in [Default macOS keybindings](#default-macos-keybindings). This section says what the actions do.

### General

- [ ] INP-001 The input behaves like an IDE text editor: click to place the cursor, multi-line editing, copy and paste, word selection, soft wrap. (terminal/editor)
- [ ] INP-002 The input works the same in Warpified SSH sessions. (terminal/editor)
- [x] INP-003 Text entered replaces any selection. (quickstart)
- [x] INP-004 `Enter` submits the buffer. (terminal/editor; quickstart)
- [x] INP-005 Input height grows with content up to half the pane height. (changelog/2022.02.16)
- [ ] INP-006 Past that height, the input scrolls and the cursor stays visible. (verify in app)
- [ ] INP-007 The bottom of the editor must not be clipped at any appearance setting. (changelog/2025.01.29)
- [ ] INP-008 Editor text follows the zoom level. (changelog/2021.08.25)
- [ ] INP-009 Editor line height follows the custom line height setting. (changelog/2023.08.24)
- [ ] INP-010 Hint text in the empty input is on by default via `show_hint_text`. (terminal/settings/all-settings)
- [ ] INP-011 `Backspace` works while `Shift` is held. (changelog/2021.06.15)
- [ ] INP-012 Tab stops in monospaced text use fixed widths. (changelog/2026.02.25)
- [ ] INP-013 Large pastes must not grow memory for the rest of the session. (changelog/2026.08.25)
- [ ] INP-014 Typing `#` at the start of the input opens Command Search, on by default, with the setting named for AI but the behaviour being search. (terminal/settings/all-settings)

### Character and word movement

- [ ] INP-015 `←` and `→` move by one character, as do `⌃B` and `⌃F`. `⌃F` accepts an autosuggestion instead when one is showing at the end of the buffer. (getting-started/keyboard-shortcuts; terminal/command-completions/autosuggestions)
- [ ] INP-016 `⌥←` and `⌥→` move to the start of the previous or next word. (terminal/editor)
- [ ] INP-017 Moving forward by word stops where expected and doesn't overshoot. (changelog/2022.07.20)
- [ ] INP-018 Word movement still works when Option is set as Meta. (changelog/2023.04.06)
- [ ] INP-019 `⌃⌥←` and `⌃⌥→` move by subword, for camelCase and snake_case parts. (terminal/editor; changelog/2023.04.13)
- [ ] INP-020 `Meta+B` and `Meta+F` move one word back or forward, and these can be rebound. (getting-started/keyboard-shortcuts; changelog/2022.12.01)

### Line and buffer movement

- [ ] INP-021 `⌘←`, `⌘→`, `⌃A` and `⌃E` go to the line start and end. (terminal/editor)
- [ ] INP-022 Whether `⌘←`, `⌘→`, `Home` and `End` stop at the visual (wrapped) line edge or the logical line edge changed recently. The changelog wording can be read either way. (verify in app) (changelog/2026.07.09)
- [ ] INP-023 `⌘↓` moves the cursor to the bottom of the buffer. (getting-started/keyboard-shortcuts)
- [ ] INP-024 `Meta+A` and `Meta+E` go to the start and end of the paragraph. (getting-started/keyboard-shortcuts)
- [ ] INP-025 `Shift+Meta+<` and `Shift+Meta+>` go to the start and end of the buffer. (getting-started/keyboard-shortcuts)
- [ ] INP-026 `⌃P` and `⌃N` move up and down a line. (getting-started/keyboard-shortcuts)
- [ ] INP-027 `↑` and `↓` move by visual line in a soft-wrapped or multi-line buffer. (terminal/editor)
- [ ] INP-028 Up-arrow moves within a multi-line command instead of leaving it, including one recalled from history. (changelog/2021.06.15; changelog/2021.07.21)

### Selection

- [ ] INP-029 `⇧←` and `⇧→` select by character. (terminal/editor)
- [ ] INP-030 `⌥⇧←` and `⌥⇧→` select by word. (terminal/editor)
- [ ] INP-031 `⌘⇧←` and `⌘⇧→` select to line start and end. (terminal/editor)
- [ ] INP-032 `⇧↑` and `⇧↓` select up and down by visual line. The docs table calls this selecting everything above or below the cursor, while the soft wrap paragraph treats it as visual lines. (verify in app) (terminal/editor)
- [ ] INP-033 `⌘⇧↑` and `⌘⇧↓` move and select to the top or bottom of the buffer. The same keys are documented as scrolling the selected block. (verify in app) (changelog/2025.04.02)
- [ ] INP-034 `⌘A` selects the whole buffer. (terminal/editor)
- [ ] INP-035 `⇧Home` and `⇧End` select to line start and end. (changelog/2022.08.18)
- [ ] INP-036 Emacs selection set: `⌃⇧A` to line start, `⌃⇧E` to line end, `⌃⇧B` left, `⌃⇧F` right, `⌃⇧P` up, `⌃⇧N` down, `Shift+Meta+B` word left, `Shift+Meta+F` word right. (getting-started/keyboard-shortcuts; changelog/2022.07.20)

### Deleting and clipboard

- [ ] INP-037 `⌃H` deletes the previous character. `⌃D` deletes forward. (terminal/editor; changelog/2021.11.10)
- [ ] INP-038 Undocumented: what `⌃D` does on an empty buffer. Shells treat it as EOF. (verify in app)
- [ ] INP-039 `⌥⌫` and `⌥⌦` delete the word left or right without touching the clipboard. (terminal/editor)
- [ ] INP-040 `⌃W` and `Meta+D` cut the word left or right. These go to an internal shell clipboard, not the system clipboard. (terminal/editor; changelog/2023.04.27)
- [ ] INP-041 `⌃K` cuts to the end of the line and copies it. (terminal/editor; changelog/2021.08.09)
- [ ] INP-042 `⌘⌦` deletes to the end without touching the clipboard. (terminal/editor)
- [ ] INP-043 `⌘⌫` deletes everything left of the cursor. (getting-started/keyboard-shortcuts)
- [ ] INP-044 `⌃U` copies and clears the current line or selected lines. (terminal/editor; getting-started/keyboard-shortcuts)
- [ ] INP-045 `⌘⇧K` clears the selected lines. (terminal/editor)
- [ ] INP-046 `⌃C` clears the whole buffer and doesn't copy. Also closes Command Search. (terminal/editor; changelog/2024.10.11)
- [ ] INP-047 `⌘C`, `⌘X` and `⌘V` copy, cut and paste. (terminal/editor)
- [ ] INP-048 Undocumented: whether `⌃Y` yanks from the internal clipboard. It isn't listed. (verify in app)

### Undo

- [ ] INP-049 `⌘Z` undoes and `⇧⌘Z` redoes, using the editor's own history rather than the shell. (changelog/2022.01.05; getting-started/keyboard-shortcuts)
- [ ] INP-050 Undocumented: undo grouping, and whether undo history survives submitting a command. (verify in app)

### Multi-line and soft wrap

- [ ] INP-051 `⇧Enter`, `⌃Enter`, `⌥Enter` and `⌃J` insert a newline without submitting. (terminal/editor; getting-started/keyboard-shortcuts)
- [ ] INP-052 The editor wraps long lines softly. (terminal/editor; changelog/2022.11.15)
- [ ] INP-053 Triple-click treats a soft-wrapped line as one logical line. (terminal/editor)
- [ ] INP-054 Arrow keys treat wrapped segments as separate visible lines. (terminal/editor)
- [x] INP-055 Autosuggestions soft-wrap as well. (changelog/2025.02.05)
- [ ] INP-056 If an autosuggestion runs past the visible width, the input scrolls horizontally to reveal it. (terminal/editor)
- [ ] INP-057 Long commands stay fully visible. (changelog/2022.11.15)
- [ ] INP-058 Multi-line buffers from history can be edited. (changelog/2021.07.21; changelog/2021.06.15)

### Multi-cursor

- [ ] INP-059 `⌃G` selects the next occurrence of the current selection and adds a cursor there. (getting-started/keyboard-shortcuts)
- [ ] INP-060 `⌃G` works with multi-byte characters. (changelog/2023.01.26)
- [ ] INP-061 `⌃⇧↑` and `⌃⇧↓` add a cursor above or below. (getting-started/keyboard-shortcuts; changelog/2022.02.16)
- [ ] INP-062 `⌃R` with several cursors must not crash. (changelog/2022.08.10)
- [ ] INP-063 Duplicate workflow arguments get one cursor each so they edit together. (knowledge-and-collaboration/warp-drive/workflows)
- [ ] INP-064 Undocumented: how typing, paste, undo and `Esc` behave across cursors, and how to return to one cursor. (verify in app)

### Folding

- [ ] INP-065 `⌥⌘F` folds the selected ranges. (getting-started/keyboard-shortcuts)
- [ ] INP-066 `⌥⌘[` folds and `⌥⌘]` unfolds. (getting-started/keyboard-shortcuts)
- [ ] INP-067 Folding is a display change that leaves the buffer text unchanged. (blog/how-warp-works)
- [ ] INP-068 Undocumented: what a fold looks like, what clicking it does, and what `⌥⌘[` folds with no selection. (verify in app)

### Auto-pairing and indentation

- [ ] INP-069 Quotes, parentheses and brackets auto-complete like in an IDE, on by default, with the toggle in Settings > Features > Text Editing or the palette. (terminal/editor; terminal/settings/all-settings)
- [ ] INP-070 Auto-closing still happens right after an alphanumeric character. (changelog/2022.02.16)
- [ ] INP-071 The setting is honoured when off. (changelog/2023.01.05)
- [ ] INP-072 `Tab` with a text selection opens completions and doesn't indent. (changelog/2022.03.24)
- [ ] INP-073 `Tab` must not insert a literal tab or spaces when the completion menu should open. (changelog/2023.06.29)
- [ ] INP-074 Unindenting several lines works. The binding isn't documented. (verify in app) (changelog/2024.05.02)

### Shell conveniences

- [ ] INP-075 `Meta+.` inserts the last word of the previous command. (changelog/2022.09.29)
- [ ] INP-076 `⌃L` clears the screen. (terminal/editor)
- [ ] INP-077 `⌃R` opens Command Search. (terminal/editor)
- [ ] INP-078 `Esc` closes the suggestions or history menu. (terminal/editor)
- [ ] INP-079 `Esc` also clears the visible autosuggestion. (changelog/2025.04.16)
- [ ] INP-080 Option-as-Meta is set separately for left and right Alt via `extra_meta_keys`, both off by default. (terminal/settings/all-settings; changelog/2022.03.09)
- [ ] INP-081 `⌘D` splits the pane from the input, and pane navigation works from it. (terminal/editor)
- [ ] INP-082 Pane navigation still works with Option as Meta. (changelog/2021.10.06)

### Keys when a menu is open

What `↑`, `↓`, `→`, `Tab`, `Enter` and `Esc` do depends on what's on screen. This is the order to test. Details are in [Completions, suggestions and history](#completions-suggestions-and-history).

- [x] INP-083 No menu, ghost text showing: `→` and `⌃F` accept it, `⌃E` and `⌘→` accept it at the end of the buffer, `Esc` clears it. (terminal/command-completions/autosuggestions; changelog/2022.02.16; changelog/2025.04.16)
- [ ] INP-084 No menu, ghost text showing, `Tab` default: opens completions. With `Tab key behavior` changed: accepts the suggestion. (terminal/command-completions/autosuggestions)
- [ ] INP-085 No menu, single-line buffer: `↑` opens the history menu with a prefix filter. (terminal/entry/command-history)
- [ ] INP-086 No menu, multi-line buffer: `↑` moves the cursor. The point where it hands over to history isn't documented. (changelog/2021.07.21) (verify in app)
- [x] INP-087 No menu: `Enter` submits, even with ghost text showing. The ghost text isn't accepted. (verify in app)
- [ ] INP-088 Completions menu open: `↑` and `↓` move through items and don't fall through to history or cursor movement. (terminal/command-completions/completions)
- [ ] INP-089 Completions menu open, nothing selected: `Enter` runs the input. (changelog/2026.01.07)
- [ ] INP-090 Completions menu open, item selected: the item is already written into the input. `⌘Enter` runs it. What plain `Enter` and `Tab` do is unclear. (changelog/2026.01.07; changelog/2022.09.22) (verify in app)
- [ ] INP-091 Completions menu open: `Esc` closes it. Whether the input text reverts isn't stated. (terminal/editor) (verify in app)
- [ ] INP-092 Completions menu open: typing keeps filtering, and stale results clear. (changelog/2026.07.23; changelog/2021.12.15)
- [ ] INP-093 History menu open: `↑` and `↓` move through items, and `⌘Enter` runs one. (changelog/2022.02.23; changelog/2022.09.22)
- [ ] INP-094 Page keys go to the suggestion menu when it's open, otherwise they scroll the terminal. (changelog/2026.05.06)
- [ ] INP-095 `⌃R` with the completions menu open closes it, as the two can't show together. (changelog/2022.12.01) (verify in app)
- [ ] INP-096 Vim mode: `Esc` in insert mode changes mode first and leaves any menu or ghost text alone. (changelog/2024.07.11; changelog/2025.05.07; changelog/2026.02.18)

### Same-line prompt

- [ ] INP-097 Same-line prompt puts the editor on the same row as the last line of the prompt, like a classic shell. Warp's own prompt defaults to a new line. (changelog/2024.07.11; blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] INP-098 With a shell prompt, same-line is the default. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] INP-099 The first line is indented by the prompt's width, with later lines wrapping at full width. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] INP-100 The prompt scrolls together with the input text. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] INP-101 Text selection maps correctly despite the offset first line. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text)
- [ ] INP-102 Changing prompt or same-line setting applies inside open sessions without opening a new tab. (blog/why-it-took-us-11-months-to-move-a-single-line-of-text; changelog/2022.11.10)

### IME and international text

- [ ] INP-103 IME input works in the editor, including non-English keyboards. (changelog/2021.10.20)
- [ ] INP-104 Marked text renders in place during composition. (changelog/2025.04.09)
- [ ] INP-105 The IME candidate window follows the caret, in the input, in the alt-screen and in running blocks. (changelog/2023.02.09; changelog/2023.02.16; changelog/2026.06.10)
- [ ] INP-106 Third-party IMEs advance candidates by one per arrow press, not two. (changelog/2026.05.14)
- [ ] INP-107 Japanese input keeps the last character of a phrase before punctuation. (changelog/2026.05.06)
- [ ] INP-108 The emoji picker inserts correctly and Unicode Hex Input doesn't crash. (changelog/2022.12.01)
- [ ] INP-109 Characters from dead keys or unhandled keystrokes aren't typed as text in the alt-screen. (changelog/2024.12.19)

### Known conflicts with shell line-editing

- [ ] INP-110 Users with `bindkey '^j' ...` or `bindkey 'tab' ...` hit trouble, since Warp owns the line editor. Rewarp should detect and tolerate this rather than copy the limitation. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] INP-111 `zle-line-init`, `zsh-autosuggestions`, `zsh-autocomplete` and similar plugins are listed as incompatible. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] INP-112 Warp won't work with shell-based completion plugins, such as `compinit`-driven ones, inside its input. (support-and-community/troubleshooting-and-support/known-issues)

## Vim keybindings

- [ ] VIM-001 Vim keybindings are off by default, and enabled from Settings > Features > Text Editing or the palette. (terminal/editor/vim; terminal/settings/all-settings)
- [ ] VIM-002 In bash and zsh, Warp detects a shell vi mode and offers the feature with a banner. (terminal/editor/vim; privacy/events)
- [ ] VIM-003 The input editor starts in insert mode. (terminal/editor/vim)
- [ ] VIM-004 `Ctrl+C` or `Enter` clears pending command state. (terminal/editor/vim)
- [ ] VIM-005 Only default bindings exist. The only rebindable one is Exit Vim insert mode. (terminal/editor/vim)
- [ ] VIM-006 Movement: `h j k l`, `<space>`, `<backspace>` with line wrap, `w W b B e E`, `ge gE`, `$`, `0`, `^`, `%`, `[`, `]`, `_`, `+`, `-`. (terminal/editor/vim; changelog/2025.01.08)
- [ ] VIM-007 Multi-line: `gg` and `G`, with a count prefix on `gg`. (terminal/editor/vim; changelog/2026.07.23)
- [ ] VIM-008 `j` and `k` move within a multi-line command. (changelog/2023.12.14)
- [ ] VIM-009 Editing: `r`, `d D`, `c C`, `s S`, `x X`, `y Y`, `p P`, `u`, `⌃r`, `~`, `gu`, `gU`, `J`, `.`. Visual mode uses `u` and `U` for case. (terminal/editor/vim)
- [ ] VIM-010 Text objects: `i` and `a` with `w W`, quote types, brackets, and `l`. (terminal/editor/vim; changelog/2026.09.23)
- [ ] VIM-011 `il` is the current line without surrounding whitespace, and `al` is the whole buffer. (terminal/editor/vim)
- [ ] VIM-012 Paragraph text objects work, for example `dip`. (changelog/2025.11.12)
- [ ] VIM-013 Character search: `t T f F`, then `;` and `,`. (terminal/editor/vim)
- [ ] VIM-014 `/`, `?`, `*` and `#` open Warp's command search instead of searching the buffer. (terminal/editor/vim)
- [ ] VIM-015 Modes: `i I a A o O v V`. (terminal/editor/vim)
- [ ] VIM-016 Registers: `"` prefix with `a`–`z`, `A`–`Z`, `+`, `*` and the unnamed `"`. (terminal/editor/vim)
- [ ] VIM-017 `+` and `*` are the system clipboard. (terminal/editor/vim)
- [ ] VIM-018 `vim_unnamed_system_clipboard` (default false) makes the unnamed register the system clipboard. (terminal/settings/all-settings; blog/how-to-use-vim-keybindings-to-edit-commands-in-warp)
- [ ] VIM-019 `vim_status_bar` (default true) shows the mode, and changes apply at once. (terminal/settings/all-settings; changelog/2024.05.09)
- [ ] VIM-020 In normal mode, `K` inspects the part of the command under the cursor. (changelog/2025.11.12)
- [ ] VIM-021 Cursor type setting is disabled while vim mode is on. (terminal/appearance/text-fonts-cursor)
- [ ] VIM-022 Vim settings don't appear in the palette when vim keybindings are off. (changelog/2024.05.09)
- [ ] VIM-023 `Esc` in insert mode switches to normal mode and doesn't close the up-arrow menu or clear autosuggestions. (changelog/2024.07.11; changelog/2025.05.07; changelog/2026.02.18)
- [ ] VIM-024 Visual line mode with the cursor at end of line applies operators to the right lines. (changelog/2024.06.06)
- [ ] VIM-025 Visual-mode paste keeps the selection after recalling from history. (changelog/2026.07.03)
- [ ] VIM-026 Cut word left and similar while the up-arrow menu is open behave correctly. (changelog/2024.05.02)
- [ ] VIM-027 An invalid vim command must not crash. (changelog/2024.03.07)
- [ ] VIM-028 The code editor shares the setting and adds `{ }`, `gcc`, `gc`, `> <`, `>> <<`, `⌃d`, `⌃u`, `zz`, and starts in normal mode. See [Code editor](#code-editor). (code/code-editor/code-editor-vim-keybindings; changelog/2026.05.14; changelog/2026.07.31)

## Completions, suggestions and history

### Tab completions

- [x] CMP-001 `Tab` opens the completions menu for commands, subcommands, options, arguments and paths. (terminal/command-completions/completions)
- [ ] CMP-002 Options and flags appear without needing to type `-` first. (changelog/2022.07.07)
- [ ] CMP-003 The menu lists matches fuzzily, so inexact spelling still finds results. (terminal/command-completions/completions; changelog/2022.09.01)
- [ ] CMP-004 Matching text is highlighted in the list. (changelog/2021.12.15; changelog/2022.10.13)
- [x] CMP-005 `↑` and `↓` or the mouse pick an item. (terminal/command-completions/completions)
- [ ] CMP-006 Pressing `↑` or `↓` with the menu open doesn't shift the menu's position. (changelog/2021.06.15)
- [x] CMP-007 As of 2026, no item is selected when the menu opens. `Enter` with nothing selected runs the input as typed. Selecting an item writes it straight into the input, closer to a traditional terminal. (changelog/2026.01.07)
- [ ] CMP-008 `classic_completions_mode` exists, default false. The docs don't say what it changes. (verify in app) (terminal/settings/all-settings)
- [x] CMP-009 Longest common prefix of the results fills into the input automatically. (changelog/2022.01.19; changelog/2022.02.23)
- [ ] CMP-010 Common-prefix handling is case-aware. (changelog/2023.07.20)
- [x] CMP-011 Accepting a completion appends a space. (changelog/2022.08.25)
- [x] CMP-012 Undocumented: whether a path that ends in a directory gets a space or stays open at `/`. (verify in app)
- [ ] CMP-013 `⌘Enter` runs the highlighted item directly. (changelog/2022.09.22)
- [ ] CMP-014 The menu closes once one suggestion remains and it's selected. (changelog/2025.01.08)
- [x] CMP-015 `Esc` closes the menu. (terminal/editor)
- [x] CMP-016 Stale results clear when the input changes. (changelog/2026.07.23)
- [ ] CMP-017 Items have icons for flags, folders, branches and similar kinds. (changelog/2022.09.15)
- [ ] CMP-018 Each item can show a description, displayed in a floating box and never truncated. Paths have one as well. (changelog/2021.07.07; changelog/2022.01.19)
- [ ] CMP-019 Tooltips stay inside the window. (changelog/2023.03.30)
- [ ] CMP-020 The menu position is correct in split panes. (changelog/2022.11.10)
- [x] CMP-021 Tab completion and Command Search can't both be open. (changelog/2022.12.01)
- [x] CMP-022 Completion works mid-line, including with the cursor at the start. (changelog/2021.08.18; changelog/2021.09.29)
- [x] CMP-023 Completions work after `&&`, on paths with spaces, and on commands prefixed with env vars. (changelog/2021.08.25; changelog/2022.10.06)
- [ ] CMP-024 `--flag=value` pairs get completions, highlighting and hover docs. (changelog/2026.03.25)
- [ ] CMP-025 After a POSIX `--`, flags complete correctly. (changelog/2026.09.30)
- [ ] CMP-026 Command names containing capitals complete. Not applied to aliases. (changelog/2024.08.22)
- [ ] CMP-027 Multi-byte text in completions works. (changelog/2021.08.31)
- [ ] CMP-028 Non-English paths are escaped correctly. (changelog/2022.05.11)
- [ ] CMP-029 Results exclude error text from helper commands. (changelog/2024.10.23)
- [ ] CMP-030 Results in remote sessions cover directories with spaces and symlinked directories. (changelog/2024.03.27; changelog/2026.08.13)
- [ ] CMP-031 `~` paths complete. (changelog/2023.12.21; changelog/2024.04.18)
- [ ] CMP-032 `.` and `..` are offered, along with a hidden result for the root directory. (changelog/2022.08.18; changelog/2022.12.06)
- [ ] CMP-033 Dotfiles are offered. (changelog/2021.08.09)
- [ ] CMP-034 File-only arguments also list directories. (changelog/2021.07.21)
- [x] CMP-035 Path completion is the fallback when nothing else matches. (changelog/2021.07.07; changelog/2026.10.07)
- [ ] CMP-036 Filepath completions don't need `cd` first. (changelog/2022.05.11)
- [ ] CMP-037 Symlinks to directories count as directories. (changelog/2024.03.21)
- [x] CMP-038 Non-command sources: aliases, env vars, shell functions, builtins, keywords, git aliases, npm aliases, fish aliases and abbreviations. (changelog/2021.08.25; changelog/2022.06.01; changelog/2022.09.22; changelog/2022.10.06; changelog/2023.05.11; changelog/2023.06.08)
- [ ] CMP-039 Shell aliases complete like the expanded command, so `gc` behaves as `git checkout`. (terminal/command-completions/completions)
- [ ] CMP-040 Subcommand aliases complete too, such as `git st`. (terminal/command-completions/completions)
- [ ] CMP-041 `ssh` completions list hosts from `~/.ssh/config` and `~/.ssh/known_hosts`. (terminal/warpify/ssh-legacy)
- [ ] CMP-042 Git: branches including remote-prefixed ones, tags on `git push origin`, commit SHAs newest first, modified files for `git diff` and `git add`. (changelog/2022.06.27; changelog/2024.07.19; changelog/2024.09.17; changelog/2022.06.08; changelog/2026.07.16)
- [ ] CMP-043 Dynamic argument values come from running helpers in the background, for example listing branches for `git checkout`. (terminal/warpify/subshells)
- [ ] CMP-044 Runtime-specific values include npm and yarn scripts, kubectl resources and namespaces, and `pkill` process names. (changelog/2021.07.28; changelog/2023.11.30; changelog/2026.08.13)
- [ ] CMP-045 Over 450 commands have specs, at Full or Partial depth. Full: bosh, brew, cargo, conda, defaults, docker, firebase, flutter, gh, git, go, heroku, killall, kubectl, kubectx, kubens, make, man, ng, node, npm, nx, phpunit-watcher, pip, pyenv, react-native, ssh, tar, terraform, tmux, tmuxinator. (terminal/command-completions/completions; changelog/2022.09.01)
- [ ] CMP-046 Warp's specs began from Fig's open-source specs. That's a lead for Rewarp, not a claim about current content. (changelog/2021.12.22)
- [ ] CMP-047 Native shell completions run alongside the built-in specs, on by default, and are generated only when `Tab` is pressed, not as you type. By default they're used when built-ins find nothing. (terminal/settings/all-settings; changelog/2026.09.16)
- [ ] CMP-048 Zsh native completions keep descriptions, including with clustered short options, and always return even when uninitialised. (changelog/2026.08.27; changelog/2026.10.07)
- [ ] CMP-049 Open completions menu as you type is off by default. (terminal/settings/all-settings; terminal/command-completions/completions)
- [ ] CMP-050 In that mode the menu closes while generating new results. (changelog/2022.12.06)
- [ ] CMP-051 `warp_completions_enabled` turns the built-in engine off, default on. (terminal/settings/all-settings)
- [ ] CMP-052 When `Tab key behavior` is not set to the completions menu, `⌃Space` opens it. (terminal/command-completions/completions)
- [ ] CMP-053 The action to open the menu can have a custom binding. (changelog/2023.03.09)
- [ ] CMP-054 Completing works once the shell has finished bootstrapping. (changelog/2026.04.15)
- [ ] CMP-055 Completion must not hammer the CPU or spawn runaway helpers. (changelog/2025.03.05)
- [ ] CMP-056 Palette item Disable Completion Menu hides the popup. (guides/getting-started/how-to-make-warps-ui-more-minimal)

### Autosuggestions

- [x] AUT-001 Ghost text suggests a full command as you type, from history and completions. (terminal/command-completions/autosuggestions)
- [ ] AUT-002 On by default, toggled from the palette. (terminal/settings/all-settings; terminal/command-completions/autosuggestions)
- [x] AUT-003 `→` or `⌃F` accepts all of it. (terminal/command-completions/autosuggestions)
- [ ] AUT-004 `⌃E` accepts when the cursor is at the end of the buffer. `⌘→` does too. (terminal/command-completions/autosuggestions; changelog/2022.02.16)
- [ ] AUT-005 `⌃→` accepts one component at a time. The older changelog also names `⌥→`, which is word movement elsewhere. (verify in app) (terminal/command-completions/autosuggestions; changelog/2022.02.23)
- [ ] AUT-006 `Tab key behavior` can make `Tab` accept the suggestion and moves the menu to `⌃Space`. (terminal/command-completions/autosuggestions; changelog/2023.07.20)
- [ ] AUT-007 In an empty-input zero state, `Tab` always accepts an active autosuggestion. (changelog/2024.10.11)
- [ ] AUT-008 `Esc` clears the suggestion, except in vim insert mode. (changelog/2025.04.16; changelog/2025.05.07)
- [ ] AUT-009 A keybinding hint shows next to the suggestion, default on. (terminal/settings/all-settings)
- [ ] AUT-010 With `show_ignore_button` on, an X next to the suggestion hides it for good. (terminal/settings/all-settings; changelog/2025.09.10)
- [ ] AUT-011 Commands with invalid arguments for this context, such as files, branches or images that don't exist, aren't suggested. (changelog/2025.04.16)
- [ ] AUT-012 Custom bindings for acceptance work. (changelog/2023.09.28)
- [ ] AUT-013 Blocklist-derived suggestions are computed asynchronously. (changelog/2026.05.18)
- [ ] AUT-014 Undocumented: ranking of history candidates, for example by recency, by directory or by exit status. (verify in app)

### Command history

- [ ] HIS-001 History is kept per shell session while it's running, so a command in one pane doesn't appear in another. (terminal/entry/command-history)
- [ ] HIS-002 Histories merge on close. (terminal/entry/command-history)
- [ ] HIS-003 History persists across sessions and restarts, ordered correctly after quit. (changelog/2021.11.10; changelog/2026.01.07)
- [x] HIS-004 `↑` in the input opens a history menu with prefix search on the current input. (terminal/entry/command-history; changelog/2021.08.31)
- [x] HIS-005 With text in the input, `↑` opens the menu filtered by that prefix. (changelog/2022.06.27)
- [ ] HIS-006 In a multi-line buffer, `↑` moves the cursor first. (verify in app) (changelog/2021.06.15)
- [ ] HIS-007 Undocumented: exactly when `↑` moves from cursor movement to opening the menu (first line only, or line and column). (verify in app)
- [x] HIS-008 Further `↑` and `↓` move through the menu one item at a time. (changelog/2022.02.23)
- [x] HIS-009 `⌘Enter` runs the highlighted item directly. (changelog/2022.09.22)
- [ ] HIS-010 Undocumented: whether plain `Enter` on a menu item fills the input or runs it. An old third-party note says it runs, but the existence of `⌘Enter` suggests otherwise. (verify in app) (3p/mvolkmann)
- [x] HIS-011 `Esc` closes the menu, and backspacing out of it takes one key press. (terminal/editor; changelog/2021.12.22)
- [ ] HIS-012 Clicking the X on an entry hides it for good. (changelog/2025.09.10)
- [ ] HIS-013 Rich details: exit code, directory, git branch, duration, last run time, and workflow name if any. (terminal/entry/command-history; changelog/2023.08.17; blog/show-rich-history-in-command-search)
- [ ] HIS-014 Bash `HISTCONTROL` is honoured. (changelog/2022.08.10)
- [ ] HIS-015 Zsh and bash ignore-space options are honoured. (changelog/2022.03.16; changelog/2022.05.02)
- [ ] HIS-016 Restored sessions' commands aren't written to a remote server's history. (changelog/2023.01.12)
- [ ] HIS-017 Up and down arrow must not crash at any buffer state. (changelog/2026.10.07)

### Command Search

- [x] CSR-001 `⌃R` opens the Command Search panel with a query box. (terminal/entry/command-search)
- [x] CSR-002 `Enter` puts the selected result in the input, without running it. (terminal/entry/command-search)
- [x] CSR-003 `⌘Enter` runs the highlighted command directly. (changelog/2022.09.15)
- [ ] CSR-004 Searches history and workflows, with bold on matched text. (terminal/entry/command-history; changelog/2022.11.15)
- [x] CSR-005 Fuzzy matching, ranked by relevance, and match quality and usage count in history. (terminal/entry/command-search; changelog/2026.09.16; changelog/2026.06.17)
- [ ] CSR-006 Extra whitespace around the query is ignored. (changelog/2023.06.08)
- [ ] CSR-007 Filter prefix `history:`, `h:` or `H-TAB` limits to history. Active filters are bold and italic. (terminal/entry/command-search)
- [ ] CSR-008 Dragging the right edge widens the panel, and the width persists. (terminal/entry/command-search; changelog/2023.03.23)
- [ ] CSR-009 Selecting a row shows a pop-out with rich history details. (blog/show-rich-history-in-command-search)
- [x] CSR-010 Clearing the input with `⌃C` also closes the panel. (changelog/2024.10.11)
- [ ] CSR-011 Opening doesn't lag. (changelog/2022.08.25)
- [ ] CSR-012 If the shell has rebound `⌃R` to fzf, atuin or fzf.fish, Warp lets the shell widget run instead. Command Search stays reachable from the palette. (terminal/entry/command-search; changelog/2026.09.16; changelog/2026.09.09)
- [ ] CSR-013 The typed query carries over into fzf's history search. (changelog/2026.09.30)
- [ ] CSR-014 For fzf, `⌃T` and `⌥C` hand off too. Atuin only gets `⌃R`. (terminal/entry/command-search; changelog/2026.09.30)
- [ ] CSR-015 `⌃⇧R` opens Workflow search directly. (terminal/entry/yaml-workflows; getting-started/keyboard-shortcuts)

### Command Corrections

- [ ] FIX-001 After a failed command, a corrected command is offered, on by default. (terminal/entry/command-corrections; terminal/settings/all-settings)
- [ ] FIX-002 The suggestion is offered as an input autosuggestion. The separate banner was removed. (changelog/2025.01.08)
- [ ] FIX-003 The docs still describe a panel above the input. `→` or a click inserts it. (verify in app) (terminal/entry/command-corrections)
- [ ] FIX-004 A keyboard shortcut accepts the most recent correction. (changelog/2025.03.26)
- [ ] FIX-005 Rule coverage: brew, cargo, cat, cd, chmod, conda, cp, docker, generic misspellings, git, go, grep, java, ls, mkdir, npm, pip, python, sed, sudo, yarn. (terminal/entry/command-corrections)
- [ ] FIX-006 Rule set is based on the open-source `thefuck` project. Examples: `gti` to `git`, wrong directory names fixed, `git push` gets `--set-upstream`, a script gets `chmod +x` first. (terminal/entry/command-corrections)
- [ ] FIX-007 Permission errors on `ssh` must not suggest `sudo`. (changelog/2024.12.19)
- [ ] FIX-008 Secrets in corrections follow the secret redaction setting. (changelog/2025.01.08)

### Alias expansion

- [ ] ALS-001 Off by default. Enable with Expand aliases as you type or the palette. (terminal/editor/alias-expansion)
- [ ] ALS-002 Typing an alias then `Space` expands it in the input. (terminal/editor/alias-expansion)
- [ ] ALS-003 `⌥Space` inserts a space and doesn't expand. (terminal/editor/alias-expansion)
- [ ] ALS-004 No expansion when the alias expands to the same command name, for example `ls='ls -G'`. (terminal/editor/alias-expansion)
- [ ] ALS-005 Aliases escaped with a backslash don't expand. (changelog/2024.04.04)
- [ ] ALS-006 Fish abbreviations expand, without their comments. (changelog/2023.04.27; changelog/2023.08.03)
- [ ] ALS-007 A banner offers to enable the feature. (privacy/events)

### Command Inspector

- [ ] XRY-001 Hovering a part of a command in the input shows documentation for that part. (terminal/editor/command-inspector)
- [ ] XRY-002 `⌘⇧I` per the Inspector page, or `⌘I` per the shortcuts table, inspects at the cursor. See [Source conflicts](#source-conflicts). (terminal/editor/command-inspector; getting-started/keyboard-shortcuts)
- [ ] XRY-003 Builtins, functions and shell keywords are recognised. (changelog/2024.02.29; changelog/2022.10.06)
- [ ] XRY-004 UTF-8 text in the buffer must not crash the hover. (changelog/2022.08.03)
- [ ] XRY-005 Undocumented: hover delay, and whether the tooltip can be selected or clicked. (verify in app)

### Syntax and error highlighting

- [ ] HLT-001 Input text is coloured by role: command, subcommand, flags, arguments, variables. On by default. (terminal/editor/syntax-error-highlighting)
- [ ] HLT-002 Colours seen by one user: command green, subcommand light blue, flags yellow, env vars magenta. (verify in app) (3p/mvolkmann)
- [ ] HLT-003 Invalid commands get a dashed red underline, on by default. (terminal/editor/syntax-error-highlighting)
- [ ] HLT-004 Invalid file paths get the same underline. (changelog/2022.11.10)
- [ ] HLT-005 Aliases such as `...` and fish abbreviations aren't underlined as errors. (changelog/2023.08.10; changelog/2023.08.24)
- [ ] HLT-006 Single-character commands and aliases are recognised. (changelog/2023.07.06)
- [ ] HLT-007 The error underline doesn't inherit to text typed after it, and clears once fixed. (blog/how-we-built-syntax-highlighting-for-the-terminal-input-editor)
- [ ] HLT-008 Styling updates immediately when a token ends, for example on space, paste or moving the cursor elsewhere. (blog/how-we-built-syntax-highlighting-for-the-terminal-input-editor)
- [ ] HLT-009 Multi-line and multi-byte input highlight correctly. (changelog/2023.02.23; changelog/2023.02.28)
- [ ] HLT-010 Paths with separators highlight correctly. (changelog/2023.03.30)
- [ ] HLT-011 In Warp, new commands or aliases aren't recognised until a new session opens, even after sourcing rc files. Rewarp should aim to do better. (terminal/editor/syntax-error-highlighting)
- [ ] HLT-012 Palette toggles appear once each. (changelog/2022.10.20)

## Palettes

### Command Palette

- [x] PAL-001 `⌘P` opens the palette, and `⌘P` again closes it. (terminal/command-palette; changelog/2022.01.12)
- [ ] PAL-002 A title-bar button also opens it. (changelog/2023.09.28)
- [x] PAL-003 It searches workflows, keyboard shortcuts, actions, toggles, settings pages, local files, sessions and launch configurations. (terminal/command-palette; changelog/2022.07.07; changelog/2023.06.08)
- [x] PAL-004 Search is fuzzy, with highlighted matches. (changelog/2021.12.15)
- [ ] PAL-005 With an empty query, the most useful features sit at the top. (changelog/2022.09.22)
- [x] PAL-006 Reopening resets the selected item. (changelog/2022.07.27)
- [ ] PAL-007 Filter chips can be clicked, or use a prefix: `workflows:`/`w:`, `files:`, `actions:`, `sessions:`, `launch_configs:`. (terminal/command-palette)
- [ ] PAL-008 `Page Up` and `Page Down` move faster through results. (changelog/2023.06.01)
- [ ] PAL-009 Items show their keybinding. (terminal/command-palette; getting-started/keyboard-shortcuts)
- [ ] PAL-010 Workflow results show their folder breadcrumb. (changelog/2023.08.10)
- [x] PAL-011 `Esc` closes. (verify in app)
- [ ] PAL-012 Every toggle in Settings has a palette entry, with each one labelled Enable or Disable according to state. (changelog/2022.07.07; changelog/2026.06.03)
- [ ] PAL-013 Launch Configuration opens through a palette in its own mode, with the search focused. (changelog/2023.11.30)
- [ ] PAL-014 Opening stays quick in big projects. (changelog/2026.05.14)
- [ ] PAL-015 `⌘O` opens the file search mode when in a repo, and pressing it again closes it. (code/code-editor; changelog/2026.03.18)
- [ ] PAL-016 File search handles `~`, excludes directories, and accepts a pasted absolute path. (changelog/2026.04.08; changelog/2026.07.23; changelog/2026.04.27)
- [ ] PAL-017 The palette has a Copy current path action and a copy current git branch action. (changelog/2026.07.16; changelog/2023.01.19)

### Navigation palette

- [x] NAV-001 `⇧⌘P` opens the Navigation Palette, or use the `sessions:` filter in the Command Palette. (getting-started/keyboard-shortcuts; terminal/sessions/session-navigation)
- [x] NAV-002 It lists every session across panes, tabs and windows, ordered by most recently focused. (terminal/sessions/session-navigation; privacy/events)
- [ ] NAV-003 Click, or `↑`/`↓` with `Enter`, jumps to a session. (terminal/sessions/session-navigation)
- [ ] NAV-004 It can search by prompt, running command, last command and status, such as Running…, Completed 10 minutes ago, Empty Session. (terminal/sessions/session-navigation)
- [ ] NAV-005 It shows only Warp's native prompt, with no PS1. (terminal/sessions/session-navigation)
- [ ] NAV-006 The current session has a label. (changelog/2022.08.25)
- [ ] NAV-007 Quit warning's Show running processes opens this palette filtered to running processes. (terminal/more-features/quit-warning)

## Tabs, panes and windows

### Tabs

- [x] TAB-001 `⌘T` or `+` opens a new tab. The binding can be remapped. (terminal/windows/tabs; changelog/2023.09.07)
- [x] TAB-002 New tabs go after the current tab by default. `new_tab_placement` can place them after all tabs. (terminal/settings/all-settings)
- [ ] TAB-003 New tabs start in the active tab's working directory by default, subject to working-directory settings. (terminal/windows/tabs; terminal/more-features/working-directory)
- [x] TAB-004 `⌘W` closes the current tab, or the active pane when there are several. (terminal/windows/tabs; terminal/windows/split-panes)
- [ ] TAB-005 Closing a tab activates the next tab to the right. (changelog/2026.05.20)
- [ ] TAB-006 Closing a tab with running commands warns first. (changelog/2024.10.11)
- [x] TAB-007 `⇧⌘T` reopens a closed tab, or a closed pane, within 60 seconds. (terminal/windows/tabs; changelog/2025.10.15; terminal/settings/all-settings)
- [ ] TAB-008 Grace period and enabled state are settings, 60 seconds and on. (terminal/settings/all-settings)
- [x] TAB-009 `⌘⇧{` and `⌘⇧}` activate the previous and next tab. (terminal/windows/tabs)
- [x] TAB-010 `⌃Tab` and `⌃⇧Tab` switch tabs. (changelog/2021.07.07)
- [ ] TAB-011 `Ctrl+Tab behavior` options: activate previous or next tab (default), cycle most recent session including panes, cycle most recent tab. (terminal/windows/tabs; terminal/settings/all-settings; changelog/2026.05.14)
- [ ] TAB-012 The `⌃Tab` switcher shows tab colours on icons and leads with the tab title. (changelog/2026.06.24)
- [x] TAB-013 `⌘1` to `⌘8` activate those tabs and `⌘9` the last tab. (terminal/windows/tabs)
- [x] TAB-014 `⌃⇧←` and `⌃⇧→` move the tab. (terminal/windows/tabs)
- [ ] TAB-015 Right-click on a tab offers: rename tab, rename pane, colour row, pin or unpin, new group with tab, move to group, remove from group, close tab, close other tabs, close tabs to the right, save as new config, copy tab and pane metadata. Exact order needs checking. (verify in app) (terminal/windows/tabs; changelog/2022.08.10; changelog/2026.05.06; changelog/2026.10.07; terminal/windows/tab-configs)
- [x] TAB-016 Close actions are also in the Mac menu and the palette. (changelog/2022.08.10)
- [x] TAB-017 Renaming focuses the rename field, starts from the custom title if any, and refocuses the input after. (changelog/2026.10.07; changelog/2026.03.18; changelog/2022.06.27)
- [x] TAB-018 A renamed tab keeps its custom title across pane switches, and in multi-pane tabs. (changelog/2022.08.03; changelog/2022.08.25)
- [ ] TAB-019 Renaming never shows stale text. (changelog/2023.06.01)
- [ ] TAB-020 The default tab title comes from the shell, and a shell can set it with `OSC 0` when `WARP_DISABLE_AUTO_TITLE=true`. (terminal/windows/tabs)
- [ ] TAB-021 Bash and zsh have useful default titles, also in remote sessions, with no stray backslash before `~`. (changelog/2022.05.04; changelog/2022.05.18; changelog/2022.05.26)
- [ ] TAB-022 The tab's directory and branch update when a process sends OSC 7. (changelog/2026.05.27)
- [ ] TAB-023 Clicking the `+` menu offers terminal tab, new tab group, tab configs, new worktree config and new tab config. (terminal/windows/tabs; terminal/windows/tab-configs; terminal/windows/vertical-tabs)
- [ ] TAB-024 The shell selector beside `+` lists shells found on the system, including Homebrew ones. (changelog/2024.12.13; changelog/2025.04.09)
- [ ] TAB-025 The tab bar background matches the terminal background. (changelog/2026.08.07)
- [ ] TAB-026 Tab bar is left-aligned correctly in macOS full screen, and doesn't slide under traffic lights. (changelog/2023.12.14; changelog/2026.06.17)
- [ ] TAB-027 Tabs get narrower and stay usable in narrow windows. (changelog/2025.08.20)
- [ ] TAB-028 Opening many tabs must not hit file descriptor limits. (changelog/2022.09.15)

### Tab colours

- [ ] TAB-029 The tab menu has a colour row. Colours come from the theme, so they stay readable. (terminal/windows/tabs)
- [ ] TAB-030 Clicking the active colour again, or the default option, removes it. (terminal/windows/tabs)
- [ ] TAB-031 Colouring a grouped tab colours its group. (terminal/windows/tabs)
- [ ] TAB-032 Cycle current tab color steps through the colours and back to none, with no default key. (terminal/windows/tabs; changelog/2026.08.13)
- [ ] TAB-033 `directory_tab_colors` maps directories to colours, so tabs pick them up automatically. (terminal/windows/tabs; changelog/2026.05.14)
- [ ] TAB-034 `preserve_active_tab_color` keeps the colour for new tabs from the active tab. (terminal/settings/all-settings; changelog/2026.02.18)

### Tab groups

- [ ] TAB-035 Groups have a name, colour and collapsed state, in both horizontal and vertical tabs. (terminal/windows/tabs)
- [ ] TAB-036 Create one with New group with tab, by grouping a multi-selection, or with New tab group in the `+` menu. (terminal/windows/tabs)
- [ ] TAB-037 New group with tab isn't offered for a tab already in a group. (changelog/2026.07.03)
- [ ] TAB-038 Typing a new group's name keeps focus in the name field, not the new terminal. (changelog/2026.09.16)
- [ ] TAB-039 Group header menu: Rename, colour, New tab in group, Ungroup tabs, close the group's tabs, Pin or Unpin group. (terminal/windows/tabs)
- [ ] TAB-040 Clicking the header collapses or expands the group. (terminal/windows/tabs)
- [ ] TAB-041 Tabs drag into groups, and groups can be reordered. (changelog/2026.07.03)
- [ ] TAB-042 Actions for group creation and removal are assignable in Keyboard shortcuts. (terminal/windows/tabs)

### Pinned tabs

- [ ] TAB-043 Pinned tabs and groups form a leading section, reorderable, in both tab layouts. (terminal/windows/tabs)
- [ ] TAB-044 Pin tab moves it to the end of the pinned section. (terminal/windows/tabs)
- [ ] TAB-045 Pinning a grouped tab takes it out of its group. (terminal/windows/tabs)
- [ ] TAB-046 Pin group moves the whole group as one unit. (terminal/windows/tabs)
- [ ] TAB-047 Unpinning moves the item to the start of the unpinned section. (terminal/windows/tabs)
- [ ] TAB-048 Pinned state survives reopening the window. (terminal/windows/tabs)
- [ ] TAB-049 Actions for pinning are assignable. (terminal/windows/tabs)

### Tab bar behaviour

- [ ] TAB-050 `Show tab indicators` is on by default, and shows maximized pane, synchronized input and failed command. (terminal/appearance/tabs-behavior; terminal/settings/all-settings)
- [ ] TAB-051 Maximized shows a full-screen icon. (changelog/2023.10.23)
- [ ] TAB-052 `Show the tab bar` options: Always, Only on hover, When windowed (default). (terminal/appearance/tabs-behavior; terminal/settings/all-settings)
- [ ] TAB-053 With Only on hover, traffic lights hide in windowed mode. (terminal/appearance/tabs-behavior)
- [ ] TAB-054 Close-button side: left or right, default right per settings. (terminal/appearance/tabs-behavior; terminal/settings/all-settings)
- [ ] TAB-055 Show tabs on hover and Zen mode are names for the same hidden-bar behaviour. (verify in app) (guides/getting-started/how-to-make-warps-ui-more-minimal; changelog/2025.01.08)

### Vertical tabs

- [x] VTB-001 Off by default. Turning on Use vertical tab layout, from Settings or the palette, replaces the tab bar with a resizable left sidebar. (terminal/windows/vertical-tabs)
- [ ] VTB-002 Compact density is the default, one row with icon and title plus an optional subtitle. (terminal/windows/vertical-tabs)
- [ ] VTB-003 Expanded density adds title, description and metadata such as git branch, diff stats and PR badge. (terminal/windows/vertical-tabs)
- [ ] VTB-004 A sliders icon in the panel's control bar opens a display settings popup, also reachable from Settings > Appearance > Tabs. (terminal/windows/vertical-tabs)
- [ ] VTB-005 View as: Panes (each pane is a row, default) or Tabs (one row per tab). (terminal/windows/vertical-tabs)
- [ ] VTB-006 Tab item, in Tabs view: Focused session (default) or Summary, a digest of up to three lines with a `+ N more` row. (terminal/windows/vertical-tabs)
- [ ] VTB-007 Pane title as: Command, Working Directory or Branch. Default Command. (terminal/windows/vertical-tabs)
- [ ] VTB-008 Additional metadata, compact only: Branch (default), Working Directory or Command, with duplicates removed. (terminal/windows/vertical-tabs)
- [ ] VTB-009 Show, expanded only: PR link, Diff stats. (terminal/windows/vertical-tabs)
- [ ] VTB-010 Show details on hover is on by default. (terminal/windows/vertical-tabs)
- [ ] VTB-011 Hover opens a floating card to the side of the row with the full directory, branch and title, without changing focus. (terminal/windows/vertical-tabs)
- [ ] VTB-012 The card stays open as the pointer moves into it, and closes when leaving both. (terminal/windows/vertical-tabs)
- [ ] VTB-013 Search filters tabs and panes by title, directory, branch, PR label, diff stats, and group name, with highlighting. (terminal/windows/vertical-tabs; changelog/2026.09.30)
- [ ] VTB-014 `+` in the control bar opens the new-tab menu. (terminal/windows/vertical-tabs)
- [ ] VTB-015 Dragging a group header reorders tabs. (terminal/windows/vertical-tabs)
- [ ] VTB-016 Dragging a pane header onto another group switches to that tab to place the pane. Dropping between groups makes a new tab there. (terminal/windows/vertical-tabs)
- [x] VTB-017 Double-click a tab row to rename inline, `Enter` confirms and `Esc` cancels. (terminal/windows/vertical-tabs)
- [ ] VTB-018 Panes themselves can be renamed from the tab menu and through a bindable action. The page still says panes can't be renamed. (changelog/2026.05.14; changelog/2026.10.07; terminal/windows/vertical-tabs)
- [x] VTB-019 Double-clicking empty space in the panel opens a new tab. (changelog/2026.06.17)
- [ ] VTB-020 Middle-click closes a tab here too. (changelog/2026.04.27)
- [ ] VTB-021 Closing the active tab activates the tab below. (changelog/2026.07.03)
- [x] VTB-022 Tab shortcuts all work unchanged. (terminal/windows/vertical-tabs)
- [ ] VTB-023 Synced-input indicator shows on synced tabs. (changelog/2026.08.07)
- [ ] VTB-024 Git branch and worktree path show automatically. (terminal/windows/vertical-tabs)
- [ ] VTB-025 `show_panel_in_restored_windows`, default false, restores the panel even if it was closed. (terminal/settings/all-settings)
- [ ] VTB-026 `hide_title_bar_search_bar`, default false, removes the title bar search. (terminal/settings/all-settings)

### Split panes

- [ ] PAN-001 `⌘D` splits right, `⇧⌘D` splits down, and right-click splits in any direction. (terminal/windows/split-panes)
- [ ] PAN-002 New panes open in the working directory set by settings. (terminal/more-features/working-directory)
- [ ] PAN-003 `⌘[` and `⌘]` activate the previous and next pane. (terminal/windows/split-panes)
- [ ] PAN-004 `⌥⌘` plus arrow moves between panes directionally. (terminal/windows/split-panes)
- [ ] PAN-005 Directional moves go to the most recently focused pane in that direction, and work when panes don't overlap on the axis. (changelog/2024.04.11; changelog/2025.01.15)
- [ ] PAN-006 `⌃⌘` plus arrow moves the divider. (getting-started/keyboard-shortcuts)
- [ ] PAN-007 `⇧⌘Enter` toggles maximize. (terminal/windows/split-panes)
- [ ] PAN-008 Pane switching works while maximized. (changelog/2022.08.10)
- [ ] PAN-009 Maximize is in the Mac menu too. (changelog/2022.08.10)
- [ ] PAN-010 `⌘W` closes the active pane, and closing the last pane closes the tab. (verify in app) (terminal/windows/split-panes; 3p/mvolkmann)
- [ ] PAN-011 Closing a pane moves focus to the pane used before it, tracked through a focus history. (changelog/2022.06.27)
- [ ] PAN-012 Closing a session with a long-running process warns first. (changelog/2025.01.08)
- [ ] PAN-013 Panes support drag and drop within the tab, to other tabs, and to a new tab. (terminal/windows/split-panes)
- [ ] PAN-014 Each pane is a separate session. (terminal/windows/split-panes)
- [ ] PAN-015 Rename Pane exists. (changelog/2026.05.14)
- [ ] PAN-016 Inactive pane dimming is off by default. (terminal/appearance/pane-dimming; terminal/settings/all-settings)
- [ ] PAN-017 Split panes show a triangle on the active pane's top-left corner. (terminal/appearance/pane-dimming)
- [ ] PAN-018 Pane layouts persist across app restarts. (changelog/2026.06.17)
- [ ] PAN-019 Sticky header placement is per pane. (terminal/blocks/sticky-command-header)

### Windows

- [ ] WIN-001 Multiple windows are supported, and Create New Window is a remappable shortcut. (changelog/2021.06.29; changelog/2026.09.09)
- [ ] WIN-002 `⌘N` opens a new window. (verify in app) (3p/mvolkmann)
- [ ] WIN-003 `⇧⌘W` closes the window. (changelog/2024.03.07)
- [ ] WIN-004 `⌘M` minimises. (changelog/2022.01.05)
- [ ] WIN-005 A keybinding toggles full screen. (changelog/2022.05.26)
- [ ] WIN-006 Quit Warp is in the palette. (changelog/2024.03.07)
- [ ] WIN-007 Window menu has Zoom, Minimize, tile left and right, Move to screen, Enter Full Screen and Bring All to Front. (changelog/2021.12.22)
- [ ] WIN-008 Option-click on the green button zooms rather than entering full screen. (changelog/2026.08.13)
- [ ] WIN-009 Traffic lights look right at all zoom levels. (changelog/2026.03.18)
- [ ] WIN-010 Window corners are square in full screen. (changelog/2026.08.13)
- [ ] WIN-011 Unfocused windows have a distinct header style. (changelog/2025.09.01)
- [ ] WIN-012 The macOS window title follows the active tab, so the Dock menu shows it, and custom tab names apply. (changelog/2023.02.09; changelog/2026.04.15)
- [ ] WIN-013 Closing the last window doesn't quit by default. `quit_on_last_window_closed` changes this. (terminal/settings/all-settings; changelog/2024.12.13)
- [ ] WIN-014 New Tab with no window open creates a window. (changelog/2023.02.16; changelog/2023.09.14)
- [ ] WIN-015 Window managers such as Magnet and Swish work, and Auto-Raise works. (changelog/2022.03.30; changelog/2023.02.28)
- [ ] WIN-016 Restoring must not produce a 1px-wide window after the green tile button. (changelog/2026.05.20)
- [ ] WIN-017 Window position is restored on multi-monitor setups. (changelog/2023.01.12)
- [ ] WIN-018 Settings opens in its own tab. A Settings tab can be dragged to another window. (changelog/2025.01.29; changelog/2026.09.16)
- [ ] WIN-019 `show_dock_icon`, default on, hides Warp from the Dock and the `⌘Tab` switcher. (terminal/settings/all-settings)

### Mac menu bar

- [ ] WIN-020 Standard File and Edit menus exist. (changelog/2021.06.15)
- [ ] WIN-021 Menus list Warp's actions so they can be found there. (changelog/2022.08.03)
- [ ] WIN-022 File has New Window, New Tab, Launch Configurations (a searchable, live-updating submenu) and New File. (terminal/sessions/launch-configurations; changelog/2023.06.29; changelog/2025.09.24)
- [ ] WIN-023 Edit has Synchronize Input. (terminal/entry/synchronized-inputs)
- [ ] WIN-024 View has Toggle Mouse Reporting. (terminal/more-features/full-screen-apps)
- [ ] WIN-025 Blocks has Show background blocks. (terminal/warpify/subshells)
- [ ] WIN-026 Menu items show special-key shortcuts correctly. (changelog/2022.09.01)
- [ ] WIN-027 Menu items must not become disabled when the hotkey window is in use. (changelog/2026.03.18)

### Configurable toolbar

- [ ] TBR-001 Header buttons can be reordered, moved between left and right, or hidden. (terminal/windows/configurable-toolbar)
- [ ] TBR-002 Open the editor by right-clicking a button or empty header space, then Rearrange toolbar items, or from Settings > Appearance > Tabs > Edit toolbar. (terminal/windows/configurable-toolbar; changelog/2026.04.22)
- [ ] TBR-003 Non-AI items: tabs panel, tools panel, code review. (terminal/windows/configurable-toolbar)
- [ ] TBR-004 Default: tabs panel and tools panel on the left, code review on the right. (terminal/windows/configurable-toolbar)
- [ ] TBR-005 The search bar and avatar can't move. (terminal/windows/configurable-toolbar)
- [ ] TBR-006 A button's side decides which side its panel opens on, and hover cards, resize handles and borders flip to match. (terminal/windows/configurable-toolbar)
- [ ] TBR-007 Panels on one side render in toolbar order. (terminal/windows/configurable-toolbar)
- [ ] TBR-008 A button shows only when its prerequisite is met, and the saved layout survives when it isn't. (terminal/windows/configurable-toolbar)
- [ ] TBR-009 Layout persists across restarts. (terminal/windows/configurable-toolbar)

### Global hotkey

- [ ] HKY-001 Global Hotkey under Settings > Features > Keys has three states: off, Dedicated hotkey window, Show/hide all windows. The two modes are mutually exclusive. (terminal/windows/global-hotkey; terminal/settings/all-settings)
- [ ] HKY-002 Dedicated window shows and hides a separate window that's pinned to a screen edge. (terminal/windows/global-hotkey)
- [ ] HKY-003 Pin position options: top, bottom, left, right, each with its own width and height percentages. (terminal/settings/all-settings)
- [ ] HKY-004 Size examples: top and bottom 100% by 30%, left and right 40% by 100%. (terminal/settings/all-settings)
- [ ] HKY-005 Pin screen: primary or a chosen external display. What an unset value means isn't stated, though the docs size the window against the active screen. (terminal/settings/all-settings; changelog/2022.05.02) (verify in app)
- [ ] HKY-006 Autohides on the loss of keyboard focus can be unchecked, so the window stays on top. (terminal/windows/global-hotkey; changelog/2022.05.02)
- [ ] HKY-007 Changes to hotkey settings apply live. (changelog/2024.02.29)
- [ ] HKY-008 The window retains its size. (changelog/2023.06.01)
- [ ] HKY-009 It floats above full-screen apps. (changelog/2022.09.08)
- [ ] HKY-010 It must not overlap Spotlight, Raycast, Alfred or the Dock. (changelog/2022.06.17)
- [ ] HKY-011 It takes keyboard focus when opened on a different monitor. (changelog/2026.08.13)
- [ ] HKY-012 It opens on the right screen after sleep and wake. (changelog/2026.03.05)
- [ ] HKY-013 Function keys, numeric keys, `Space` and `Shift` can be part of the binding. (changelog/2022.05.04; changelog/2022.04.01)
- [ ] HKY-014 The hotkey works on non-US keyboard input sources. (changelog/2025.02.12)
- [ ] HKY-015 If the binding doesn't fire, the fix is granting Accessibility permission. (terminal/windows/global-hotkey)
- [ ] HKY-016 Warp can be hidden from the Dock while using the dedicated window. (changelog/2026.06.24)
- [ ] HKY-017 Show/hide all windows toggles every window. (terminal/windows/global-hotkey)
- [ ] HKY-018 Keybinding format in the file is modifiers and key joined by `-`, for example `cmd-shift-a`. (terminal/settings/all-settings)
- [ ] HKY-019 System shortcuts such as `⌘Esc`, `` ⌘` ``, `⌘Tab`, `⌘.` and `⌘~` must be unbound first. (terminal/windows/global-hotkey)

## Sessions, restoration and reusable layouts

### Session restoration

- [ ] RST-001 Restoration is on by default and reopens windows, tabs, panes and recent blocks. (terminal/sessions/session-restoration; terminal/settings/all-settings)
- [ ] RST-002 Restored block content keeps colours, bold, underline, italic, strikethrough, inverse and double underline. (changelog/2022.01.19; changelog/2022.09.01; changelog/2025.02.19)
- [ ] RST-003 The last active window gets focus. (changelog/2022.01.26)
- [ ] RST-004 Each quit overwrites the saved state with the latest session. (terminal/sessions/session-restoration)
- [ ] RST-005 Warp stores this in a local SQLite database. (terminal/sessions/session-restoration)
- [ ] RST-006 Turning restoration off stops recording but leaves the old database in place. (terminal/sessions/session-restoration)
- [ ] RST-007 If `restore_session` is on, the restored window size wins over a custom new-window size. (terminal/appearance/size-opacity-blurring; changelog/2024.09.24)
- [ ] RST-008 History survives restoration. (changelog/2022.01.26)
- [ ] RST-009 Bold and colours survive, but bookmarks don't. (terminal/blocks/block-actions)
- [ ] RST-010 Database problems must surface and recover, not produce an empty window. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] RST-011 A deleted or inaccessible working directory must not crash a new session. (changelog/2022.12.15; changelog/2021.11.03)
- [ ] RST-012 Undocumented: how many blocks are restored per pane, and whether scrollback past a limit is dropped. (verify in app)
- [ ] RST-013 Undocumented: what a restored pane shows for a command that was still running at quit. (verify in app)

### Working directory

- [ ] CWD-001 `Working directory for new sessions` offers Home Directory, Previous session's directory, Custom directory and Advanced. (terminal/more-features/working-directory)
- [ ] CWD-002 Advanced sets each of new window, new tab and split pane separately. (terminal/more-features/working-directory; terminal/settings/all-settings)
- [ ] CWD-003 The default is listed as Home on one page and `previous_dir` on another. See [Source conflicts](#source-conflicts). (terminal/more-features/working-directory; terminal/settings/all-settings)

### Launch Configurations

Warp calls this legacy, replaced by Tab Configs. Both are in this spec because old configs still work.

- [ ] LCF-001 Save New Launch Configuration in the palette saves the current windows, tabs and panes, with a required name. (terminal/sessions/launch-configurations)
- [ ] LCF-002 `Enter` in the save modal saves. (changelog/2024.12.13)
- [ ] LCF-003 A YAML file is written to `~/.warp/launch_configurations/`, which can be opened from the modal and edited by hand. (terminal/sessions/launch-configurations; privacy/events)
- [ ] LCF-004 Open from the palette, from `⌃⌘L`, from File > Launch Configurations, or from right-clicking `+`. (terminal/sessions/launch-configurations; getting-started/keyboard-shortcuts)
- [ ] LCF-005 `⌘Enter` in the palette opens a single-window config in the active window. (terminal/sessions/launch-configurations)
- [ ] LCF-006 Fields at the top: `name`, `active_window_index`, `windows`. (terminal/sessions/launch-configurations)
- [ ] LCF-007 Window fields: `active_tab_index`, `tabs`, `tab_groups`. (terminal/sessions/launch-configurations)
- [ ] LCF-008 Tab fields: `title`, `color`, `layout`, `group`. (terminal/sessions/launch-configurations)
- [ ] LCF-009 `color` takes red, green, yellow, blue, magenta or cyan, resolved from the theme. (terminal/sessions/launch-configurations)
- [ ] LCF-010 Layout fields: `cwd`, `commands`, `split_direction`, `panes`, `is_focused`, nestable. (terminal/sessions/launch-configurations)
- [ ] LCF-011 `cwd` must be absolute or empty. The page says `~` hides the file, while the changelog says `~` is supported. (verify in app) (terminal/sessions/launch-configurations; changelog/2023.03.20)
- [ ] LCF-012 `commands` is a list of `exec:` items joined with `&&`, so commands after `ssh` may never run. (terminal/sessions/launch-configurations)
- [ ] LCF-013 `tab_groups` entries take `name`, `color`, `collapsed`, `pinned`. A tab's `group` is the zero-based index. (terminal/sessions/launch-configurations)
- [ ] LCF-014 Grouped tabs must be adjacent. A missing index or a repeated group opens the tab ungrouped, and empty groups aren't created. (terminal/sessions/launch-configurations)
- [ ] LCF-015 Saving captures group name, colour, collapsed and pinned state, membership, active window, tab and pane. (terminal/sessions/launch-configurations; changelog/2025.01.15; changelog/2025.01.22)
- [ ] LCF-016 Opening one respects restored and custom sizes. (changelog/2024.09.24)
- [ ] LCF-017 `warp://launch/<name>` opens one, including its tab-level commands. (changelog/2023.06.29; changelog/2026.07.16)
- [ ] LCF-018 Rapid file changes must not grow memory. (changelog/2026.08.27)

### Tab Configs

- [ ] TCF-001 A Tab Config is one `.toml` file in `~/.warp/tab_configs/` defining one tab. Default ones ship in `default_tab_configs/`. (terminal/windows/tab-configs; terminal/settings/file-locations)
- [ ] TCF-002 New files show in the `+` menu automatically, sorted alphabetically by name. (terminal/windows/tab-configs; changelog/2026.04.29)
- [ ] TCF-003 The menu doesn't overflow the window with many configs. (changelog/2026.07.23)
- [ ] TCF-004 `+ New tab config` creates a starter file and opens it. (terminal/windows/tab-configs)
- [ ] TCF-005 Right-click a tab, then Save as new config, to capture layout, commands and directory. (terminal/windows/tab-configs)
- [ ] TCF-006 Hovering an entry shows a side panel with Edit config, Remove and Make default. (terminal/windows/tab-configs)
- [ ] TCF-007 Make default assigns it to `⌘T`. (terminal/windows/tab-configs)
- [ ] TCF-008 Top-level fields: `name` (required), `title` (with `{{param}}`), `color` (black, red, green, yellow, blue, magenta, cyan, white). (terminal/windows/tab-configs)
- [ ] TCF-009 `[[panes]]` is a flat list and the first entry is the root. (terminal/windows/tab-configs)
- [ ] TCF-010 Leaf fields: `id`, `type` (`terminal`), `directory` (with `~` and params), `commands`, `shell`, `is_focused`. (terminal/windows/tab-configs)
- [ ] TCF-011 `shell` falls back to the default if it's missing. (terminal/windows/tab-configs)
- [ ] TCF-012 Split fields: `id`, `split` (`horizontal` left to right, `vertical` top to bottom), `children` with at least two. Children are equal in size. (terminal/windows/tab-configs)
- [ ] TCF-013 Commands run one at a time, each waiting for the previous one to finish. (terminal/windows/tab-configs; changelog/2026.05.18)
- [ ] TCF-014 `[params.<name>]` tables declare modal inputs with `type` (`text`, `branch`, `repo`), `description` and `default`. (terminal/windows/tab-configs)
- [ ] TCF-015 `Space` on a focused parameter dropdown selects the item. (changelog/2026.06.03)
- [ ] TCF-016 `{{autogenerated_branch_name}}` is reserved and generates a fresh branch name. (terminal/windows/tab-configs)
- [ ] TCF-017 New worktree config, from the `+` menu, makes a config after you pick a repo. Paths with spaces work. (terminal/windows/tab-configs; changelog/2026.07.31)
- [ ] TCF-018 Repo pickers abbreviate home to `~`, left-truncate, and show the full path on hover. (changelog/2026.05.14; changelog/2026.05.20)
- [ ] TCF-019 `warp://tab_config/<name>` opens one, matching the file stem case-insensitively, with or without `.toml`. (terminal/windows/tab-configs)
- [ ] TCF-020 `?new_window=true`, or having no window, opens it in a new window. (terminal/windows/tab-configs)
- [ ] TCF-021 Param modal shows for URL opens too. (terminal/windows/tab-configs)

### YAML workflows

Local file-based workflows only. Warp Drive workflows are excluded.

- [ ] WFL-001 Local workflows live in `~/.warp/workflows/`, repository ones in `<repo>/.warp/workflows/`. Symlinks are respected. (terminal/entry/yaml-workflows; changelog/2022.12.01)
- [ ] WFL-002 Valid files load automatically. Extension is `.yml` or `.yaml`. (terminal/entry/yaml-workflows)
- [ ] WFL-003 Fields: `name` and `command` required, `tags`, `description`, `source_url`, `author`, `author_url`, `shells`, `arguments`. (terminal/entry/yaml-workflows)
- [ ] WFL-004 `shells` limits to `zsh`, `bash`, `fish`, and absence means all. (terminal/entry/yaml-workflows)
- [ ] WFL-005 `{{argument}}` in the command marks an argument. (terminal/entry/yaml-workflows)
- [ ] WFL-006 Argument fields: `name` required, `description`, `default_value`. (terminal/entry/yaml-workflows)
- [ ] WFL-007 `default_value` replaces the argument name in the inserted command. (terminal/entry/yaml-workflows; changelog/2022.04.20)
- [ ] WFL-008 Open from Command Search, or Workflow Search with `⌃⇧R`. (terminal/entry/yaml-workflows)
- [ ] WFL-009 Typing filters by name, description or command, with command matches ranked higher. (terminal/entry/yaml-workflows; changelog/2023.04.06; changelog/2024.07.24)
- [ ] WFL-010 `Enter` on a workflow inserts it in the input. (terminal/entry/yaml-workflows)
- [ ] WFL-011 `⇧Tab` cycles through arguments. (terminal/entry/yaml-workflows)
- [ ] WFL-012 Same-named arguments get synced cursors. (knowledge-and-collaboration/warp-drive/workflows)
- [ ] WFL-013 A panel shows name, description and arguments while filling in, and resizes with the window. (knowledge-and-collaboration/warp-drive/workflows; changelog/2023.11.16)
- [ ] WFL-014 The Workflows menu has My Workflows and Repository Workflows tabs. (terminal/entry/yaml-workflows)
- [ ] WFL-015 Running a workflow while a command is running shows a warning. (changelog/2023.09.28)
- [ ] WFL-016 Global workflows show in search, as set by `show_global_workflows_in_universal_search`. (terminal/entry/command-search; terminal/settings/all-settings)
- [ ] WFL-017 Warp ships community workflows, sourced from a public repo. Rewarp can start with none. (terminal/entry/yaml-workflows)

### Synchronized inputs

- [ ] SYN-001 Modes are Synchronize All Panes in All Tabs, Synchronize All Panes in Current Tab and Stop Synchronizing Any Panes. (terminal/entry/synchronized-inputs)
- [ ] SYN-002 `⌥⌘I` toggles current-tab sync on and off. (terminal/entry/synchronized-inputs)
- [ ] SYN-003 Reachable from Edit > Synchronize Input and the palette. (terminal/entry/synchronized-inputs)
- [ ] SYN-004 Sync copies the input buffer's text across sessions rather than sending keystrokes. (terminal/entry/synchronized-inputs; blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs)
- [ ] SYN-005 Starting sync forces all synced buffers to be identical. (blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs)
- [ ] SYN-006 During long-running commands, sync falls back to raw keystroke broadcast. (blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs)
- [ ] SYN-007 In an alternative editor like vim, sync only applies to sessions running that same editor. (terminal/entry/synchronized-inputs)
- [ ] SYN-008 Only the focused input shows a cursor and UI such as completions, and only it computes suggestions. Others just take buffer updates. (blog/warped-expectations-the-iceberg-of-ux-ambiguity-behind-synced-inputs)
- [ ] SYN-009 History suggestions must not desync inputs. (changelog/2023.05.18)
- [ ] SYN-010 Leaving an alt-screen focuses the right session. (changelog/2023.05.18)
- [ ] SYN-011 Tab bar shows a sync indicator. (terminal/appearance/tabs-behavior)
- [ ] SYN-012 Undocumented: whether selection or cursor position syncs at all. The post implies neither does. (verify in app)

## Appearance

### Themes

- [ ] THM-001 Theme picker opens from Settings > Appearance, from `⌃⌘T`, or from Open theme picker in the palette. (terminal/appearance/themes; getting-started/keyboard-shortcuts)
- [ ] THM-002 Selecting a theme previews it live, the checkmark saves and X reverts. (terminal/appearance/themes)
- [ ] THM-003 `↑` and `↓` cycle through themes, and `Esc` leaves. (changelog/2022.02.16)
- [ ] THM-004 A search field filters themes. Arrow keys with no matches must not crash. (changelog/2021.11.24; changelog/2023.02.09)
- [ ] THM-005 Completions menu mustn't overlap the picker. (changelog/2021.09.15)
- [ ] THM-006 The selected theme persists. (terminal/appearance/themes)
- [ ] THM-007 Sync with OS picks a light and a dark theme, defaulting to Warp Light and Warp Dark. (terminal/appearance/themes; terminal/settings/all-settings)
- [ ] THM-008 Theme choice persists when the picker opens from the palette under Sync with OS. (changelog/2022.07.20)
- [ ] THM-009 Shipped themes: Warp Dark (default), Warp Light, Dracula, Solarized Dark, Solarized Light, Gruvbox Dark, Gruvbox Light, Jellyfish, Koi, Leafy, Marble, Pink City, Snowy, Dark City, Red Rock, Cyber Wave, Willow Dream, Fancy Dracula, Phenomenon, Solar Flare, Adeberry. (terminal/appearance/themes)
- [ ] THM-010 The picker's `+` opens a creator that derives a theme from an image, chooses a background colour, and saves with Create Theme. (terminal/appearance/themes)
- [ ] THM-011 The creator works when the themes directory doesn't exist. (changelog/2023.08.17)
- [ ] THM-012 Custom themes can be deleted from the UI. (changelog/2023.08.31)
- [ ] THM-013 Custom themes live in `~/.warp/themes/`, including subdirectories and symlinks. (terminal/appearance/custom-themes; changelog/2022.03.24; changelog/2022.12.01)
- [ ] THM-014 New files appear within seconds, though the first discovery of the directory may take minutes. (terminal/appearance/custom-themes)
- [ ] THM-015 YAML keys: `name`, `accent`, `cursor`, `background`, `foreground`, `details`, `terminal_colors` with `normal` and `bright`, each with 8 ANSI colours. (terminal/appearance/custom-themes)
- [ ] THM-016 `cursor` is optional and defaults to `accent`. (terminal/appearance/custom-themes; changelog/2024.08.22)
- [ ] THM-017 Colours are `#` hex, and 3-digit forms work. (terminal/appearance/custom-themes; changelog/2021.10.13)
- [ ] THM-018 `details` is `darker` or `lighter`. (terminal/appearance/custom-themes)
- [ ] THM-019 `background_image` takes `path`, relative to the themes directory, and a required `opacity` from 0 to 100. Only JPEG images are documented. (terminal/appearance/custom-themes)
- [ ] THM-020 A path may start with `~`. (changelog/2023.01.12)
- [ ] THM-021 Gradients: `accent` or `background` as two keys, `top` and `bottom` or `left` and `right`. (terminal/appearance/custom-themes)
- [ ] THM-022 Animated GIF background images play. (changelog/2026.09.02)
- [ ] THM-023 Background images don't slow scrolling, and blur applies to them. (changelog/2022.02.02; terminal/appearance/size-opacity-blurring)
- [ ] THM-024 Translucent colours in output keep full opacity range. (changelog/2021.08.09)
- [ ] THM-025 Theme ANSI colours render as specified with no dimming. (changelog/2024.05.30)
- [ ] THM-026 Links in light themes have correct colour. (changelog/2022.07.20)
- [ ] THM-027 The active custom theme key in `settings.toml` is an object with `name` and `path`. (terminal/settings/all-settings)

### Text and fonts

- [ ] TXT-001 Default font is Hack, 13 pt, line height 1.2. (terminal/settings/all-settings; terminal/appearance/text-fonts-cursor)
- [ ] TXT-002 Settings > Appearance > Text sets font, weight, size, line height, thin strokes, minimum contrast and ligatures. (terminal/appearance/text-fonts-cursor)
- [ ] TXT-003 Weights: thin, extra light, light, normal, medium, semibold, bold, extra bold, black. (terminal/settings/all-settings)
- [ ] TXT-004 The font picker has type-to-search. (changelog/2024.02.26)
- [ ] TXT-005 Any font can be used, not only monospaced, and View all available system fonts widens the list. What the short list contains isn't stated. (terminal/appearance/text-fonts-cursor; changelog/2022.05.11) (verify in app)
- [ ] TXT-006 Newly installed fonts need a restart. (terminal/appearance/text-fonts-cursor)
- [ ] TXT-007 Too-small or too-large font sizes and line heights are ignored. (changelog/2023.01.19)
- [ ] TXT-008 `⌘=`, `⌘-` and `⌘0` raise, lower and reset font size, and the value in Settings stays in sync. (getting-started/keyboard-shortcuts; changelog/2021.08.31)
- [ ] TXT-009 Cell size updates immediately after a font size change. (changelog/2023.02.16)
- [ ] TXT-010 Thin strokes options: never, on low-DPI, on high-DPI (default), always. (terminal/settings/all-settings; changelog/2024.10.17)
- [ ] TXT-011 Minimum contrast options: never, only named colours (default), always. (terminal/settings/all-settings; changelog/2022.11.10)
- [ ] TXT-012 Ligatures are off by default, and turning them on may slow rendering. Hack has none. (terminal/appearance/text-fonts-cursor; changelog/2025.01.15)
- [ ] TXT-013 Common Unicode block elements are drawn natively instead of using font glyphs. (changelog/2023.07.20)
- [ ] TXT-014 Fallback fonts cover CJK and emoji. (changelog/2021.11.03; changelog/2021.11.24)
- [ ] TXT-015 Emoji presentation selectors are honoured. (changelog/2024.06.06)
- [ ] TXT-016 Prompt text follows custom line height. (changelog/2024.07.19)
- [ ] TXT-017 A character turning double-width at line end must not crash. (changelog/2026.09.09)

### Cursor

- [ ] TXT-018 Cursor styles: bar (default), block, underline. (terminal/appearance/text-fonts-cursor; terminal/settings/all-settings)
- [ ] TXT-019 Blink is on by default, with a Cursor blink palette toggle. (terminal/appearance/text-fonts-cursor; terminal/settings/all-settings)
- [ ] TXT-020 The glyph under the cursor gets a high-contrast colour. (changelog/2024.06.21)
- [ ] TXT-021 The cursor blinks when a shell starts. (changelog/2022.10.20)

### Size, opacity and blur

- [ ] WAP-001 Open new windows with custom size sets columns and rows, 80 by 40 by default, and the setting is off by default. (terminal/appearance/size-opacity-blurring; terminal/settings/all-settings)
- [ ] WAP-002 Custom size applies to the first window after launch. (changelog/2024.09.24; changelog/2025.10.15)
- [ ] WAP-003 Opacity slider goes from 1 to 100, default 100. (terminal/appearance/size-opacity-blurring; terminal/settings/all-settings)
- [ ] WAP-004 Blur slider appears below 100 opacity, default 1, maximum 64. (terminal/appearance/size-opacity-blurring; terminal/settings/all-settings; changelog/2023.07.20)
- [ ] WAP-005 Big blur radii can hurt performance. (terminal/appearance/size-opacity-blurring)
- [ ] WAP-006 Blur applies to windows opened by dragging from Finder. (changelog/2023.04.13)
- [ ] WAP-007 `zoom_level` is a percentage, default 100. (terminal/settings/all-settings)
- [ ] WAP-008 Terminal size can be a non-integer number of cells, and the extra space shows as right and bottom padding. (terminal/more-features/full-screen-apps)

### App icon

- [ ] WAP-009 Settings > Appearance > Icon picks one of the built-in Dock icons: Default, Warp 1.0, Aurora, Classic 1, Classic 2, Classic 3, Comets, Cow, Glass Sky, Glitch, Glow, Holographic, Mono, Neon, Original, Starburst, Sticker. Rewarp would need its own art. (terminal/appearance/app-icons; terminal/settings/all-settings)
- [ ] WAP-010 Default adapts to macOS's Icon & Widget Style. (changelog/2026.03.25)

### Prompt

- [ ] PRM-001 Input type in Settings > Appearance > Input has Warp or Shell (PS1). Warp is the default. (terminal/appearance/prompt; terminal/settings/all-settings)
- [ ] PRM-002 Warp prompt chips show directory, git branch, Subversion, Kubernetes context, Python environment, conda, date, time and similar. (terminal/appearance/prompt; changelog/2021.11.10; changelog/2023.02.01)
- [ ] PRM-003 Added chips: Node.js version, git diff stats as a separate chip, git uncommitted file count, Git Branch Status with ahead and behind counts, and a 24-hour timestamp. (changelog/2025.07.23; changelog/2026.03.05; changelog/2022.11.03; changelog/2026.06.24; changelog/2023.10.05)
- [ ] PRM-004 Clicking the prompt preview in Settings or right-clicking then Edit prompt opens the editor. Drag chips into the dashed box and press Save changes. (terminal/appearance/prompt; blog/drag-and-drop-to-customize-your-command-line-prompt)
- [ ] PRM-005 Chips update across sessions without running a command. (blog/drag-and-drop-to-customize-your-command-line-prompt)
- [ ] PRM-006 Git chips show local branch and uncommitted changes, with optional tracking status and diff stats. (terminal/appearance/prompt)
- [ ] PRM-007 Detached HEAD shows the commit hash. (changelog/2022.08.18; changelog/2023.10.23)
- [ ] PRM-008 The git chip hides outside a repo and must not flicker. (changelog/2026.03.05; changelog/2026.05.06)
- [ ] PRM-009 Untracked directories such as nested repos don't hide the diff chip. (changelog/2026.06.17)
- [ ] PRM-010 Prompt checks must not spawn redundant `git status` processes or block the prompt. (changelog/2023.08.31; changelog/2026.04.15; changelog/2024.04.11)
- [ ] PRM-011 Kubernetes chip shows only while running a listed tool: kubectl, helm, kubens, kubectx, oc, istioctl, kogito, k9s, helmfile, flux, fluxctl, stern, kubeseal, skaffold, kubent, kubecolor, cmctl, sparkctl, etcd, fubectl. (terminal/appearance/prompt)
- [ ] PRM-012 It honours `KUBECONFIG`. (terminal/appearance/prompt)
- [ ] PRM-013 Node chip detection is cached and skipped when the chip is off. (changelog/2026.06.10)
- [ ] PRM-014 Virtualenv name shows in the native prompt. (changelog/2023.06.01)
- [ ] PRM-015 User and host display correctly after leaving SSH. (changelog/2022.06.17)
- [ ] PRM-016 Shell prompt mode shows PS1, with multi-line left prompts and right prompts in zsh and fish only. Multi-line right prompts aren't possible. (terminal/appearance/prompt; changelog/2023.06.20)
- [ ] PRM-017 Input must not overlap the right prompt. (changelog/2023.02.08)
- [ ] PRM-018 PS1 parsing handles bash `$?`, zsh default prompts, and `->` prompts. (changelog/2022.04.15; changelog/2023.01.12)
- [ ] PRM-019 Bash `PROMPT_COMMAND` can set `PS1`. (changelog/2024.12.13)
- [ ] PRM-020 Dynamic bash prompts aren't evaluated twice. (changelog/2026.09.09)
- [ ] PRM-021 Explicit-width zsh constructs stay aligned. (changelog/2026.07.31)
- [ ] PRM-022 OSC 4 in PS1 must not crash. (changelog/2023.03.20)
- [ ] PRM-023 Compatible tools: PS1 in bash and zsh, Starship, oh-my-posh, Powerlevel10k from 1.19.0, Spaceship, oh-my-zsh, Prezto prompt, over SSH. (terminal/appearance/prompt)
- [ ] PRM-024 Powerlevel10k transient prompts and gradients aren't supported, and instant prompt must not hang startup. (terminal/appearance/prompt; changelog/2021.08.31)
- [ ] PRM-025 Unsupported in Warp: oh-my-bash, bash-it, SBP, synth-shell-prompt, Powerline-shell, zplug, tide, oh-my-fish. Rewarp may do better. (terminal/appearance/prompt)
- [ ] PRM-026 Warp warns when it detects a known incompatible custom prompt. (changelog/2023.03.30)
- [ ] PRM-027 `TERM_PROGRAM=WarpTerminal` lets rc files branch on the terminal. It's also set in wrapped SSH sessions. (terminal/appearance/prompt; changelog/2022.11.15)
- [ ] PRM-028 iTerm2 shell integration conflicts, and is listed as a known incompatibility. (terminal/appearance/prompt)

### Input position

- [ ] POS-001 Three positions: Pin to the bottom (Warp mode, default), Pin to the top (Reverse mode), Start at the top (Classic mode). (terminal/appearance/input-position; terminal/settings/all-settings)
- [ ] POS-002 Pin to the bottom: blocks flow up and out of view, with past commands reached by scrolling up. (terminal/appearance/input-position)
- [ ] POS-003 Pin to the top: input stays on top, the latest result is first, older results flow down, and scrolling down visits past commands. (terminal/appearance/input-position)
- [ ] POS-004 Start at the top: input starts at the top and moves down as blocks stack above it, until the screen fills. (terminal/appearance/input-position)
- [ ] POS-005 Changes apply at once to all open panes. (terminal/appearance/input-position)
- [ ] POS-006 Set from Settings > Appearance > Input or the palette. (terminal/appearance/input-position)
- [ ] POS-007 Keys that depend on direction flip with position, including `⌘↑` and `⌘↓` for block selection. (terminal/blocks/block-basics)
- [ ] POS-008 Undocumented: whether plain `↑` in history and `↑`/`↓` for blocks also flip when pinned to the top. (verify in app)

## Terminal emulation and shells

### Text and escape-sequence support

- [ ] EMU-001 24-bit colour, bold, underline, strikethrough, reverse and emoji are supported. (terminal/comparisons/terminal-features)
- [ ] EMU-002 The feature table lists no support for dim, italic, curly underline, coloured underline, overline, blink, invisible, right-to-left text or Sixel. The table is old: the changelog shows dim and italic working. Rewarp gets most of these from libghostty and should keep them. (verify in app) (terminal/comparisons/terminal-features; changelog/2022.11.03; changelog/2022.09.01)
- [ ] EMU-003 Several ANSI styles on one character render together. (changelog/2023.06.29)
- [ ] EMU-004 Dim-styled colours are restored properly. (changelog/2022.11.03)
- [ ] EMU-005 OSC 8 hyperlinks work with any scheme, including `file://` with no host. (terminal/more-features/files-and-links)
- [ ] EMU-006 OSC 0 sets the title. (terminal/windows/tabs)
- [ ] EMU-007 OSC 7 updates the working directory and git indicator on a tab. (changelog/2026.05.27)
- [ ] EMU-008 OSC 9 raises a notification with a body. OSC 777 `notify` raises one with a title and body. Both on by default. (terminal/more-features/notifications)
- [ ] EMU-009 OSC 52 clipboard access: `deny` by default, with `write_only` and `read_write`. A banner warns when access is blocked. (terminal/settings/all-settings; changelog/2026.05.20)
- [ ] EMU-010 Focus reporting is sent, on by default, for full-screen and normal-screen apps. (terminal/settings/all-settings; changelog/2023.08.17; changelog/2026.06.10)
- [ ] EMU-011 OSC 4 and malformed OSC 1337 must not crash. (changelog/2023.03.20; changelog/2026.06.24)
- [ ] EMU-012 Inline images via the iTerm2 and Kitty protocols work, including during shell startup. Some tools need `TERM=kitty`. (terminal/more-features/files-and-links; changelog/2026.06.17)
- [ ] EMU-013 Bracketed paste doesn't leak markers such as `0~` and `1~`, including after an SSH drop. (changelog/2021.08.31; changelog/2022.03.16; changelog/2024.05.23)
- [ ] EMU-014 Pasting into nano keeps formatting. (changelog/2023.02.28)
- [ ] EMU-015 Paste works in full-screen apps. (changelog/2021.06.15)
- [ ] EMU-016 More alternate-screen enable sequences are recognised. (changelog/2024.08.07)
- [ ] EMU-017 Audible bell is off by default, toggled from Settings > Features > Terminal or the palette, and triggered by tools such as `ping -a`. (terminal/more-features/audible-bell)
- [ ] EMU-018 Undocumented: the `TERM` value, and `TERM_PROGRAM_VERSION`. (verify in app)
- [ ] EMU-019 Warp exposes a focus URL in session environments so outside tools can return focus to the originating pane. (changelog/2026.05.27)

### Keyboard encoding

- [ ] EMU-020 Kitty keyboard protocol is supported, with no configuration, when an app asks for it. Otherwise legacy encoding is used. (terminal/more-features/full-screen-apps; changelog/2026.03.25)
- [ ] EMU-021 With it, `⌃I` differs from `Tab`, and modifier-only and key-release events can be reported. (terminal/more-features/full-screen-apps)
- [ ] EMU-022 Cmd and Option with `Backspace`, `Delete` and arrows reach apps that use the protocol. (changelog/2026.08.07)
- [ ] EMU-023 `⌃2` to `⌃8` send C0 control codes. (changelog/2022.09.01)
- [ ] EMU-024 `⌃Space` reaches Emacs and other apps. (changelog/2022.01.05)
- [ ] EMU-025 `Shift+Tab` sends backward-tab, for vim and Neovim. (changelog/2023.05.11)
- [ ] EMU-026 `Shift+↑` and `Shift+↓` work in alt-screen editors. (changelog/2023.05.11)
- [ ] EMU-027 Function keys reach running programs. (changelog/2021.08.25)
- [ ] EMU-028 Numpad Enter works as Enter and not `⌃C`. (changelog/2021.07.21; changelog/2021.11.10)
- [ ] EMU-029 `Page Up` and `Page Down` work in vim and other full-screen apps. (changelog/2022.04.01)
- [ ] EMU-030 Meta combinations with special keys, such as `Meta+Delete`, work in the alt-screen. (changelog/2023.08.24)
- [ ] EMU-031 `⌥U`, `⌥I` and similar meta shortcuts aren't ignored. (changelog/2024.06.27)
- [ ] EMU-032 Alt sends Meta control codes in long-running blocks and the alt-screen. (changelog/2025.01.08)
- [ ] EMU-033 `⌥Enter`, `⌥Tab` and `⌥Esc` send correct sequences, not key names. (changelog/2026.05.06)
- [ ] EMU-034 Unhandled keystrokes must not arrive as typed characters in the alt-screen. (changelog/2024.12.19)
- [ ] EMU-035 Down-arrow encoding works with interactive prompts such as the GitHub CLI. (changelog/2021.07.21)

### Full-screen apps

- [ ] ALT-001 Vim, Emacs, htop and similar run in a full-screen surface, and most `⌘` shortcuts stay with Warp. (verify in app) (terminal/more-features/full-screen-apps)
- [ ] ALT-002 Alt-screen padding: Use custom padding in alt-screen is on, with uniform padding 0 px. Turning it off matches block-list padding. (terminal/more-features/full-screen-apps; terminal/settings/all-settings)
- [ ] ALT-003 Some apps redraw badly on the resize this padding causes. That's why it can be switched off. (terminal/more-features/full-screen-apps)
- [ ] ALT-004 `⌘F` opens the find bar in the alt-screen, including vim and less. (changelog/2022.12.01)
- [ ] ALT-005 All matches highlight in the alt-screen. (changelog/2024.10.17)
- [ ] ALT-006 Scrolling through alt-screen matches doesn't hang, and a match scrolled off screen is safe. (changelog/2024.10.17; changelog/2024.10.11)
- [ ] ALT-007 Background colour of `delta`-style output must not bleed across the whole viewport. (changelog/2026.05.06)
- [ ] ALT-008 Dragging a window while htop runs is safe. (changelog/2022.08.18)
- [ ] ALT-009 Password-wait detection must not misfire on neovim. (changelog/2026.01.21)

### tmux

No page covers tmux directly. These items are what can be inferred.

- [ ] TMX-001 tmux runs as an ordinary full-screen app, with Warp's blocks and input editor off inside it. (terminal/more-features/full-screen-apps) (verify in app)
- [ ] TMX-002 tmux can use the Kitty keyboard protocol. (terminal/more-features/full-screen-apps)
- [ ] TMX-003 tmux status line colours must not leak into alt-screen backgrounds. (changelog/2026.05.14)
- [ ] TMX-004 Tmux-based Warpification over SSH existed and has been removed. Don't copy it. (terminal/warpify/ssh; changelog/2026.06.17)
- [ ] TMX-005 Oh-My-Tmux is listed as incompatible, with no reason given. (verify in app) (support-and-community/troubleshooting-and-support/known-issues)
- [ ] TMX-006 A dropped SSH connection with tmux on the alt-screen must leave the session usable. (changelog/2024.05.23)
- [ ] TMX-007 `tmux` and `tmuxinator` have Full completion specs. (terminal/command-completions/completions)
- [ ] TMX-008 Undocumented: tmux control mode, and mouse-mode pass-through specifics. (verify in app)

### Shells

- [ ] SHL-001 Warp starts the user's login shell if it's bash, zsh, fish or PowerShell. If not, a banner appears and zsh loads. (getting-started/supported-shells)
- [ ] SHL-002 Fish needs 3.6 or above. pwsh needs 7.0 or above. (getting-started/supported-shells)
- [ ] SHL-003 Startup shell for new sessions overrides the shell, for new sessions only. (getting-started/supported-shells)
- [ ] SHL-004 The picker lists Homebrew-installed shells. A custom path can be set. (changelog/2025.04.09; terminal/appearance/prompt)
- [ ] SHL-005 Rc files load once, and rc files that check `PS1` to detect interactive use work. (changelog/2024.09.24; changelog/2022.05.04)
- [ ] SHL-006 Bootstrap survives `setopt nounset`, `sh_word_split`, `allexport` and prezto `cursor_mode`, and a bad `$PATH`. (changelog/2026.01.07; changelog/2023.08.31; changelog/2026.05.27; changelog/2026.08.18; changelog/2023.06.08)
- [ ] SHL-007 Rc files that wait for input can still take pasted text. (changelog/2024.02.29)
- [ ] SHL-008 Startup output from rc files doesn't break tool resolution. (changelog/2026.06.17)
- [ ] SHL-009 Locale: no `LC_ALL` side effects, Turkish locale safe, non-English quotes in dotfiles fine, CJK locale documented as a fix for rendering issues. (changelog/2023.03.20; changelog/2025.07.30; changelog/2022.05.02; support-and-community/troubleshooting-and-support/known-issues)
- [ ] SHL-010 Selecting a particular bash binary uses that binary. (changelog/2026.10.22)
- [ ] SHL-011 Fish `read` under older versions conflicts, and is fixed upstream. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] SHL-012 PROMPT_COMMAND must not hang the shell. (changelog/2021.07.28)
- [ ] SHL-013 Tools that need x86 can be used by running the app under Rosetta. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] SHL-014 macOS folder permissions: lacking them can make the app stall, and updates can trip `Operation not permitted`. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] SHL-015 Local Network permission is needed to SSH to LAN hosts. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] SHL-016 Permission descriptions cover media, Reminders and Calendar so that tools run from the terminal work. (changelog/2022.07.07; changelog/2026.07.16)
- [ ] SHL-017 Tools listed as conflicting: iTerm2 shell integration, Termium, `thefuck` instant mode, fubectl, zsh4h, znap, FZF, `rbenv init`, grml-zsh-config, some venv PS1 settings. (support-and-community/troubleshooting-and-support/known-issues)

### Subshells

- [ ] WFY-001 A subshell here means a nested interactive shell: local, in a container, or over SSH. (terminal/warpify/subshells)
- [ ] WFY-002 Recognised by default: `bash`, `zsh`, `fish`, `docker run`, `docker exec`, `podman run`, `podman exec`, `poetry shell`, `pipenv shell`, `aws-vault exec`, `flox activate`, `gcloud compute ssh`, `eb ssh`, `doctl compute ssh`. (terminal/warpify/subshells)
- [ ] WFY-003 Running one offers to enable blocks and the input editor, now in a footer rather than a banner. (terminal/warpify/subshells; changelog/2026.04.01)
- [ ] WFY-004 `⌃I` Warpifies the current subshell. (getting-started/keyboard-shortcuts)
- [ ] WFY-005 Added commands accept strings and regexes. (terminal/warpify/subshells; terminal/settings/all-settings)
- [ ] WFY-006 Denylisted commands never prompt. (terminal/warpify/subshells)
- [ ] WFY-007 A line printed at the end of the rc file, a DCS marker, makes this automatic. Warp then runs its setup script. (terminal/warpify/subshells)
- [ ] WFY-008 Subshells get a labelled wrapper and can nest. (blog/warp-supports-subshells)
- [ ] WFY-009 REPLs and other non-shell subshells stay plain. (support-and-community/troubleshooting-and-support/known-issues)
- [ ] WFY-010 Without Warpification a session falls back to a sparse plain mode. (blog/warp-supports-subshells)
- [ ] WFY-011 Local helpers run in forked shells, isolated from the interactive session. (terminal/warpify/subshells)
- [ ] WFY-012 Remote helpers run in the session during idle time, in a non-interactive subshell so they can't change state. (terminal/warpify/subshells)
- [ ] WFY-013 A preference can turn off in-band helpers, which also loses completions, highlighting, corrections and git prompt state in remote subshells. (terminal/warpify/subshells)
- [ ] WFY-014 Having text in the input must not crash Warpification. (changelog/2024.11.11)

### SSH

Design note: `docs/design.md` defers remote integration. Items here record what parity would mean. Warp's remote-server extension is listed under [Excluded](#excluded) as a straddler.

- [ ] SSH-001 `ssh` commands that look interactive are detected, and aliases are now detected too. Detection doesn't apply to scripts. (terminal/warpify/ssh; changelog/2026.03.18)
- [ ] SSH-002 After seeing `Last login:` or a prompt-like line, Warp offers to Warpify. (terminal/warpify/ssh)
- [ ] SSH-003 Non-interactive runs such as `-T` or with a command stay plain. (changelog/2022.03.24)
- [ ] SSH-004 Unsupported remote shells show an error, or stay plain, right away. (changelog/2024.12.26; changelog/2022.03.30)
- [ ] SSH-005 The wrapper keeps the login shell and adds blocks and the editor to bash and zsh. (terminal/warpify/ssh-legacy)
- [ ] SSH-006 `command ssh` opts out of the wrapper. (terminal/warpify/ssh-legacy)
- [ ] SSH-007 The wrapper needs `xxd` for zsh, and `RemoteCommand` in config falls back to plain ssh. (terminal/warpify/ssh-legacy; changelog/2026.07.09)
- [ ] SSH-008 Bootstrap commands use a leading space so they stay out of history. (terminal/warpify/ssh-legacy)
- [ ] SSH-009 MOTD and `/etc/profile` still run. (changelog/2023.05.11)
- [ ] SSH-010 `MaxSessions` must be at least 2 for wrapper helpers, and a banner offers Don't show me again when completions fail. (terminal/warpify/ssh-legacy; changelog/2026.07.09)
- [ ] SSH-011 Hosts on the denylist never prompt. (terminal/settings/all-settings)
- [ ] SSH-012 Lost connection shows a banner. (changelog/2026.05.27)
- [ ] SSH-013 Exiting SSH restores local prompt, user, host and local history. (changelog/2022.06.17; changelog/2026.05.18)
- [ ] SSH-014 Nested SSH isn't bootstrapped. (terminal/warpify/ssh-legacy)

## Other features

### Link and path detection

Mouse behaviour on links is in [Links and file paths in output](#links-and-file-paths-in-output).

- [ ] LNK-001 URLs in output are auto-detected, with several schemes including `https`, `ftp` and `file`. (terminal/more-features/files-and-links; changelog/2021.07.13)
- [ ] LNK-002 `file://` URLs keep query parameters. (changelog/2021.12.15)
- [ ] LNK-003 Relative and absolute file paths in blocks are detected. (terminal/more-features/files-and-links)
- [ ] LNK-004 `tree` output filenames count as links. (changelog/2026.05.14)
- [ ] LNK-005 Paths with position suffixes capture line and column: `file:line`, `file:line:column`, `file[line, column]`, `file(line, column)`, `file, line: N, column: M`, `file, line: N, in`. (terminal/more-features/files-and-links)
- [ ] LNK-006 Trailing periods and quotes aren't part of a link. (changelog/2023.01.05; changelog/2022.10.06; changelog/2026.07.03)
- [ ] LNK-007 Fullwidth or CJK punctuation isn't part of a link, and paths after such punctuation are detected. (changelog/2026.07.16; changelog/2026.05.14)
- [ ] LNK-008 Paths and URLs wrapped across lines are detected as one link. (changelog/2026.07.03; changelog/2023.06.08)
- [ ] LNK-009 Links inside lists underline correctly. (changelog/2023.06.08)
- [ ] LNK-010 Hover detects the whole URL reliably. (changelog/2025.01.22)
- [ ] LNK-011 Links open in the default browser. (terminal/more-features/files-and-links)
- [ ] LNK-012 Files open in the editor set under Settings > Code > Editor and Code Review > Choose an editor to open file links. Default App uses the system handler. (terminal/more-features/files-and-links)
- [ ] LNK-013 Supported editors include `$EDITOR`, VS Code, VS Code Insiders, JetBrains IDEs, Zed, Zed Preview, Cursor, Windsurf, Sublime Text and Android Studio. (terminal/more-features/files-and-links; terminal/settings/all-settings)
- [ ] LNK-014 Line and column open correctly in Zed. (changelog/2024.07.24)
- [ ] LNK-015 Markdown files can open in the viewer from `⌘`-click, tooltip or menu. (terminal/more-features/markdown-viewer)
- [ ] LNK-016 `git push` output shows a suggested URL for creating a PR. (verify in app) (changelog/2023.02.28)

### Finder and app integration

- [ ] FND-001 Dropping a folder or file on the Dock icon opens a new tab there. (terminal/more-features/files-and-links; changelog/2022.10.06)
- [ ] FND-002 Finder's Services menu has Open new Warp Tab here and Open new Warp Window here. (terminal/more-features/files-and-links)
- [ ] FND-003 Warp opens `.command` files and Unix executables from Finder, with paths escaped. Files must be executable. (terminal/more-features/files-and-links; changelog/2023.10.12)
- [ ] FND-004 Executable scripts opened through a `file://` URL run in the terminal. (changelog/2026.05.06)
- [ ] FND-005 Markdown and text files can open from Finder's Open With. (terminal/more-features/markdown-viewer; changelog/2026.04.01)
- [ ] FND-006 Warp doesn't register as an alternate handler for common file types. (changelog/2026.07.03)
- [ ] FND-007 Start at login: setting `login_item`, documented default true. Manual removal in System Settings is respected. (terminal/settings/all-settings; changelog/2025.04.02)
- [ ] FND-008 VS Code and JetBrains can launch it through their external terminal settings. (terminal/integrations-and-plugins)

### Markdown Viewer

- [ ] MKD-001 Local `.md` and `.markdown` files render in a pane. (terminal/more-features/markdown-viewer)
- [ ] MKD-002 A setting makes the viewer the default over the editor, and links respect it. (terminal/more-features/markdown-viewer; changelog/2026.05.18; changelog/2026.07.16)
- [ ] MKD-003 Running `cat`, `glow` or `less` on Markdown shows a banner with a button to open it. (terminal/more-features/markdown-viewer)
- [ ] MKD-004 `⌘E` or the pane header's Rendered and Raw buttons switch views, keeping scroll position. (terminal/more-features/markdown-viewer; changelog/2026.08.27)
- [ ] MKD-005 Code blocks with no language, or `sh`, `shell`, `bash`, `fish`, `zsh`, `warp-runnable-command`, count as shell commands. Inline code doesn't. (terminal/more-features/markdown-viewer)
- [ ] MKD-006 The `>_` icon inserts a command into the input. (terminal/more-features/markdown-viewer)
- [ ] MKD-007 Clicking a shell block or `⌘↑`/`⌘↓` enters keyboard navigation. Then `↑`, `↓`, `⌘↑`, `⌘↓` move, `⌘Enter` inserts, and `⌘L` returns to the terminal. (terminal/more-features/markdown-viewer)
- [ ] MKD-008 `{{param}}` in those blocks acts like workflow arguments. (terminal/more-features/markdown-viewer)
- [ ] MKD-009 Code blocks have a copy button. (terminal/more-features/markdown-viewer)
- [ ] MKD-010 Mermaid blocks render as diagrams, each with a Raw and Rendered toggle, and failures don't hang. (terminal/more-features/markdown-viewer; changelog/2026.05.14)
- [ ] MKD-011 `⌘F` searches inside the viewer. (changelog/2023.12.14)
- [ ] MKD-012 Rendering: H1 to H6, numbered lists keep their start number, nested lists use letters or Roman numerals, HTML comments hidden, local images refresh on change, tables can be selected. (changelog/2025.09.03; changelog/2023.12.21; changelog/2025.03.12; changelog/2026.07.31; changelog/2026.07.23; changelog/2026.07.16)
- [ ] MKD-013 An open file gets focused rather than a new pane each time. (changelog/2026.06.24)
- [ ] MKD-014 Animated images render as a first-frame preview. (changelog/2026.04.15)

### Notifications

- [ ] NTF-001 A desktop notification fires when a long command finishes or a command wants a password, only if Warp isn't the active app. (terminal/more-features/notifications)
- [ ] NTF-002 Long-running threshold default is 30 seconds. (terminal/settings/all-settings)
- [ ] NTF-003 Password prompt detection is on by default and must not misfire. (terminal/settings/all-settings; changelog/2026.01.21)
- [ ] NTF-004 Play notification sound is on by default. (terminal/settings/all-settings)
- [ ] NTF-005 First use asks for macOS permission. Both macOS and Warp need to allow it. (terminal/more-features/notifications)
- [ ] NTF-006 A discovery banner and an error banner exist in the block list. (privacy/events)
- [ ] NTF-007 Clicking a notification opens Warp at that session. (verify in app) (privacy/events)
- [ ] NTF-008 Toast duration defaults to 8 seconds, and there's a cap and expand behaviour for floods. (terminal/settings/all-settings; changelog/2026.07.31)
- [ ] NTF-009 OSC 9 and OSC 777 feed the same mechanism. Avoid newlines and semicolons in payloads. (terminal/more-features/notifications)
- [ ] NTF-010 Notification payload readability for password prompts is improved. (changelog/2025.04.30)

### Secret redaction

Only the local display part is in scope. There's nothing to send.

- [ ] SEC-001 Off by default. Toggle under Settings > Privacy > Secret redaction or the palette. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-002 Detection runs a regex list over terminal output as it prints. (support-and-community/privacy-and-security/secret-redaction; blog/dont-accidentally-leak-secrets-from-your-terminal)
- [ ] SEC-003 A recommended list covers IP addresses, phone numbers, MAC addresses, AWS, Google, GitHub, Stripe, Slack and Firebase tokens, and JWTs. The patterns are published on the page. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-004 Users add their own patterns with `name` and `pattern`. (terminal/settings/all-settings)
- [ ] SEC-005 Patterns are case-sensitive unless prefixed with `(?i)`. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-006 Display modes: strikethrough (default), asterisks, always show. (terminal/settings/all-settings; changelog/2025.08.06)
- [ ] SEC-007 Hide secrets in block list obscures them with asterisks. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-008 Clicking a secret opens a tooltip to reveal or copy it. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-009 Copying output containing secrets gives asterisks unless revealed or copied from the tooltip. (support-and-community/privacy-and-security/secret-redaction)
- [ ] SEC-010 Multi-byte characters before a match must not shift it. (changelog/2026.06.10)
- [ ] SEC-011 Redaction must not deadlock. (changelog/2026.05.20)
- [ ] SEC-012 With ligatures on, secrets use asterisks rather than a lock icon. (changelog/2025.07.16)

### Quit and close warnings

- [ ] QUT-001 Quitting, or closing a window that has a running process, shows a warning. On by default. (terminal/more-features/quit-warning; terminal/settings/all-settings)
- [ ] QUT-002 Options: Yes, quit. Show running processes. Cancel. A Don't ask again checkbox. (terminal/more-features/quit-warning)
- [ ] QUT-003 Closing a tab or pane with a running process warns too, under `should_confirm_close_session`. (terminal/settings/all-settings; changelog/2024.10.11)
- [ ] QUT-004 The dialog responds to `Enter` and `Esc`. (changelog/2025.03.26)
- [ ] QUT-005 Toggle from Settings or the palette. (terminal/more-features/quit-warning)

### Accessibility

- [ ] A11-001 VoiceOver support works by Warp announcing events itself. VO navigation keys don't work, as the UI isn't an accessibility tree. Rewarp should aim higher with native AppKit accessibility. (terminal/more-features/accessibility)
- [ ] A11-002 Blocks can be navigated by keyboard to read the command, result and output, and to copy them. (terminal/more-features/accessibility)
- [ ] A11-003 Verbosity is verbose (default) or concise, with `⌥⌘V` to change it. (terminal/settings/all-settings; getting-started/keyboard-shortcuts)
- [ ] A11-004 Palette has a11y actions, found by typing `a11y`. (terminal/more-features/accessibility)
- [ ] A11-005 `Backspace` and `Delete` are announced in the input. (changelog/2022.07.27)
- [ ] A11-006 Block context menu has an announced keybinding. (changelog/2022.10.06)
- [ ] A11-007 Almost every feature has a keybinding, and the palette is the discovery path. (terminal/more-features/accessibility)

### URI scheme

- [ ] URI-001 `warp://action/new_window?path=<folder>` and `warp://action/new_tab?path=<folder>` open a window or tab, with `~` expanded. (terminal/more-features/uri-scheme; changelog/2026.04.29)
- [ ] URI-002 `warp://action/open_file_editor` opens a file at a location. (changelog/2026.06.03)
- [ ] URI-003 `warp://launch/<path>` opens a launch configuration. (terminal/more-features/uri-scheme)
- [ ] URI-004 `warp://tab_config/<name>` opens a Tab Config. (terminal/more-features/uri-scheme)
- [ ] URI-005 `warp://settings` with `?q=`, `?widget=` and `/appearance`. (terminal/more-features/uri-scheme)
- [ ] URI-006 The scheme can't run commands, wait for results, or address an existing tab or pane. (terminal/more-features/uri-scheme)

### Slash commands in terminal mode

Warp's slash menu is mainly an agent feature, but a few entries work without AI. See [Excluded](#excluded) for the rest.

- [ ] SLS-001 Typing `/` in the input opens a reduced command menu. `↑`/`↓` move, `Enter` runs, `Esc` dismisses. `enable_slash_commands_in_terminal` (default true) turns it off. (agents/local-agents/interacting-with-agents/terminal-and-agent-modes; terminal/settings/all-settings)
- [ ] SLS-002 Non-AI entries: `/rename-tab <name>`, `/set-tab-color <colour>`, `/open-file`, `/open-settings-file`, `/open-code-review`, `/changelog`. (agents/capabilities/slash-commands)
- [ ] SLS-003 Undocumented: how `/` as the start of an actual path such as `/usr/bin/ls` is handled by this menu. (verify in app)

### Banners and transient UI

- [ ] BAN-001 `snackbar_enabled` (default on) controls snackbar notifications. The docs don't describe them, beyond a changelog entry placing one at the top of the window. (verify in app) (terminal/settings/all-settings; changelog/2022.09.29)
- [ ] BAN-002 Input message bar is on by default in Warp, showing hints. Its documented content is agent-related. (terminal/settings/all-settings; agents/local-agents/interacting-with-agents/terminal-and-agent-modes)
- [ ] BAN-003 Inline banners inside the block list offer features such as notifications, alias expansion, Vim and Warpify. (privacy/events)
- [ ] BAN-004 A dismissible settings-error banner has an Open settings file button and clears on its own. (terminal/settings)
- [ ] BAN-005 Clicking the X on the shortcut screen hides it for good. (getting-started/keyboard-shortcuts)
- [ ] BAN-006 A Resource Center with keyboard shortcuts opens from `⌃⇧?`, and `Esc` closes it. (getting-started/keyboard-shortcuts; changelog/2022.12.01)
- [ ] BAN-007 The changelog shows after an update, controlled by `show_changelog_after_update`. A `What's new` toast stays until dismissed. Rewarp can skip this. (terminal/settings/all-settings; changelog/2026.03.25)

### Settings UI

- [ ] STU-001 `⌘,` opens Settings, in its own tab, with a search bar. (terminal/settings; changelog/2025.01.29; changelog/2025.01.22)
- [ ] STU-002 Long search queries don't overflow. (changelog/2026.04.22)
- [ ] STU-003 Settings live in a TOML file, with changes applying at once when the file is saved, and the UI and file staying in sync both ways. (terminal/settings)
- [ ] STU-004 Invalid TOML or values show a banner, and affected settings fall back to defaults. (terminal/settings)
- [ ] STU-005 Deleting the file resets to defaults, and it reappears on the next UI change. (terminal/settings)
- [ ] STU-006 Open settings file is at the bottom of Settings. (terminal/settings)
- [ ] STU-007 A JSON schema ships with the app for editor validation. (terminal/settings)
- [ ] STU-008 Info icons open docs. (changelog/2026.04.01)
- [ ] STU-009 Pages under Settings: Account, Appearance, Features, Keyboard shortcuts, Privacy, Code, Warpify, Agents and others. Check the non-AI ones in the real app. (verify in app) (terminal/settings/all-settings; terminal/settings/file-locations)

### Importing from other terminals

- [ ] IMP-001 Import External Settings in the palette reads the iTerm2 default profile, with theme, 16 ANSI colours, font, shell, working directory behaviour, window size, opacity, blur, copy on select, mouse and scroll reporting, Option-as-Meta and global hotkey. (getting-started/migrate-to-warp/migrate-to-warp-from-iterm2)
- [ ] IMP-002 A preview step lets you choose what to keep. (getting-started/migrate-to-warp/migrate-to-warp-from-iterm2)
- [ ] IMP-003 Only the Default profile is imported. Several hotkeys in a profile are detected. (getting-started/migrate-to-warp/migrate-to-warp-from-iterm2; privacy/events)

### Updates and files

- [ ] UPD-001 Warp checks for updates on startup and periodically, shows a notice at top right, and has Check for Update in Settings and the palette. Rewarp's channel is its own decision. (support-and-community/troubleshooting-and-support/updating-warp)
- [ ] UPD-002 A banner appears when updating isn't possible, for example run from the disk image, and can be dismissed. (support-and-community/troubleshooting-and-support/updating-warp; changelog/2023.01.19)
- [ ] UPD-003 Warp supports macOS's proxy settings. (changelog/2023.10.12)
- [ ] UPD-004 The app works offline apart from cloud features. (support-and-community/troubleshooting-and-support/using-warp-offline)
- [ ] UPD-005 File layout: settings, keybindings, themes, tab configs, workflows and launch configurations under a dot folder, and logs under `~/Library/Logs`. (terminal/settings/file-locations)
- [ ] UPD-006 The log rotates by size within a session. (changelog/2026.05.27)
- [ ] UPD-007 Copying the app version is a settings-page button. (changelog/2022.06.27)

## Code features

`docs/design.md` doesn't list these. They aren't AI, so they're recorded here. Priority is the user's call.

### Code editor

- [ ] EDT-001 Files open in a built-in editor from a file-link's Open in Warp, from `⌘O` search, from the file tree or from New File in the palette and File menu. (code/code-editor; changelog/2025.09.24)
- [ ] EDT-002 `⌘S` saves. (code/code-editor)
- [ ] EDT-003 Group files into single editor pane puts files in a tabbed viewer, on by default for new users. (code/code-editor; terminal/settings/all-settings)
- [ ] EDT-004 File tabs can be reordered, closed and dragged between tabs, and panes can merge by dragging. (code/code-editor)
- [ ] EDT-005 Layout setting: split pane (default) or new tab. New tabs open right of the active tab. (code/code-editor; terminal/settings/all-settings; changelog/2025.12.10)
- [ ] EDT-006 Files from the tree open as a preview tab until touched, then get promoted. (changelog/2025.09.17; privacy/events)
- [ ] EDT-007 Syntax highlighting languages: Rust, Go, YAML, Python, JS/TS, JSX/TSX, Java/Groovy, C++, Shell, C#, HTML, CSS, C, JSON, HCL, Lua, Ruby, PHP, TOML, Swift, Kotlin, Starlark, SQL, PowerShell, Elixir, Scala, Vue, Dockerfile, Markdown. (code/code-editor; changelog/2025.08.27; changelog/2025.12.10; changelog/2026.03.25; changelog/2026.07.09)
- [ ] EDT-008 Views of the same file share a buffer, including on-disk changes. (code/code-editor)
- [ ] EDT-009 Line numbers: absolute (default) or relative. (terminal/settings/all-settings)
- [ ] EDT-010 `⌃G` opens Go to Line, with `line:column`. (changelog/2026.03.18)
- [ ] EDT-011 Jumping to a position auto-scrolls horizontally. (changelog/2026.01.21)
- [ ] EDT-012 Auto save is opt-in, saving as you type and on focus loss, without a prompt on close. (terminal/settings/all-settings; changelog/2026.07.23)
- [ ] EDT-013 Pane menus offer Copy file path and Reveal in Finder. (changelog/2026.07.09; changelog/2026.05.14)
- [ ] EDT-014 Multi-select is available. (changelog/2026.02.18)
- [ ] EDT-015 Vim mode starts in normal mode, with `{ }`, `gcc`, `gc`, `>`, `<`, `>>`, `<<`, counts, `⌃d`, `⌃u`, `zz`, `d%`, `c%`, `y%`. (code/code-editor/code-editor-vim-keybindings; changelog/2026.05.14; changelog/2026.07.31)
- [ ] EDT-016 Very large files stay within bounded memory, and tree-sitter has a size limit. (changelog/2026.08.27; changelog/2026.06.24)

### Find and replace

- [ ] FRP-001 `⌘F` highlights all matches, selecting the nearest one. (code/code-editor/find-and-replace)
- [ ] FRP-002 `Enter` or the down arrow moves forward, `⇧Enter` or the up arrow back. (code/code-editor/find-and-replace)
- [ ] FRP-003 Select All highlights every match and closes the bar. (code/code-editor/find-and-replace)
- [ ] FRP-004 Regex and case toggles live in the query editor. (code/code-editor/find-and-replace)
- [ ] FRP-005 A dropdown at the left opens replace. `Enter` replaces the current match. Replace All does all. (code/code-editor/find-and-replace)
- [ ] FRP-006 Preserve Case keeps casing across PascalCase, camelCase, hyphens and underscores. (code/code-editor/find-and-replace)
- [ ] FRP-007 Non-ASCII text can be found. (changelog/2026.06.24)

### File tree and search

- [ ] FTR-001 The tools panel's first tab is the project file tree, opened from the toolbar or `⌘\`, and it tracks the file system. (code/code-editor/file-tree)
- [ ] FTR-002 Click opens a file in the editor. (code/code-editor/file-tree)
- [ ] FTR-003 File menu: Open in new pane, Open in new tab, Copy path, Copy relative path. (code/code-editor/file-tree)
- [ ] FTR-004 Folder menu: Create new file, Copy path, Copy relative path. (code/code-editor/file-tree)
- [ ] FTR-005 Items can be renamed and deleted, and opened in Finder. (changelog/2025.09.10)
- [ ] FTR-006 Hidden files sit on top and show by default, with a toggle. Numbers sort naturally. (terminal/settings/all-settings; changelog/2026.03.18; changelog/2026.06.17)
- [ ] FTR-007 Common file types have icons. (code/code-editor/file-tree)
- [ ] FTR-008 Paths drag from the tree into a running command. (changelog/2025.12.03)
- [ ] FTR-009 Global search covers files in the current directories, pre-filled from any selection. (changelog/2026.01.21; changelog/2026.03.05)
- [ ] FTR-010 `left_panel_visibility_across_tabs`, default true, keeps the panel's open state consistent across tabs. (terminal/settings/all-settings; changelog/2026.02.04)
- [ ] FTR-011 Settings choose which tabs show in the tools panel. (changelog/2026.07.16)

### Language servers

- [ ] LSP-001 Supported: rust-analyzer, gopls, pyright, typescript-language-server, clangd. (code/code-editor/language-server-protocol)
- [ ] LSP-002 Servers are enabled per repo, offered in the editor footer, found through the shell's `PATH`, or installed by Warp. (code/code-editor/language-server-protocol)
- [ ] LSP-003 They start on `cd` into a workspace, and stop when nothing's open. (code/code-editor/language-server-protocol)
- [ ] LSP-004 Footer icon colours: green ready, yellow starting or busy, red failed, grey stopped. Clicking it offers restart, stop, start, logs. (code/code-editor/language-server-protocol)
- [ ] LSP-005 Hover shows types and docs after a short delay, with rich content. (code/code-editor/language-server-protocol)
- [ ] LSP-006 `⌘`+click goes to the definition, with the symbol underlined while `⌘` is held. (code/code-editor/language-server-protocol)
- [ ] LSP-007 `⌘`+click at the definition shows a Find References card. (code/code-editor/language-server-protocol)
- [ ] LSP-008 Diagnostics show as dashed underlines, with a message on hover. (code/code-editor/language-server-protocol)
- [ ] LSP-009 Format on save is on by default and can be turned off on its own. (terminal/settings/all-settings; changelog/2026.06.17)
- [ ] LSP-010 Right-click in the editor lists LSP actions. (code/code-editor/language-server-protocol)
- [ ] LSP-011 Local sessions only, one server per language, and repo-root scoped. (code/code-editor/language-server-protocol)

### Git diff review

The non-AI part of Warp's Code Review panel.

- [ ] REV-001 The panel shows uncommitted changes, ignoring `.gitignore`d files, and updates live. (code/code-review)
- [ ] REV-002 It can compare against main or master, auto-detected, or any branch. (code/code-review)
- [ ] REV-003 Open it with the git diff chip, the toolbar button, `⌘⇧+`, or `/open-code-review`. (code/code-review; agents/capabilities/slash-commands)
- [ ] REV-004 Opens as a pane on the right, draggable elsewhere. A file sidebar scrolls to files. (code/code-review)
- [ ] REV-005 A gutter action reverts a hunk. Discard removes one file's or all changes, after a confirmation. (code/code-review)
- [ ] REV-006 Diffs can be edited inline, and the header's expand button opens the file, syncing edits back. (code/code-review)
- [ ] REV-007 `⌘F` works in the panel. (changelog/2025.11.19)
- [ ] REV-008 Git operations: commit, push, publish, create PR, view PR, with tooltips saying why a button is disabled. (changelog/2026.06.17; changelog/2026.04.29)
- [ ] REV-009 `show_code_review_button` and `show_code_review_diff_stats` are both on by default. (terminal/settings/all-settings)
- [ ] REV-010 Inline comments and PR-comment import exist but mainly feed agents. (privacy/events; code/code-review)

### Worktrees

- [ ] WTR-001 A directory with a `.git` file is recognised as a worktree, and the diff chip, branch and review panel reflect it. (code/git-worktrees)
- [ ] WTR-002 Watching covers the worktree and the shared `.git`. (code/git-worktrees)
- [ ] WTR-003 Prompt branch picker handles branches checked out in linked worktrees. (changelog/2026.05.14)
- [ ] WTR-004 Branch switcher in the prompt can create branches. (changelog/2026.05.20)

## Settings and defaults

Every non-AI setting in Warp's reference, with its documented default. Keys are Warp's, grouped by TOML section, and all of these come from `terminal/settings/all-settings` unless noted. AI, agent, Drive, cloud and account settings are in [Excluded](#excluded). Each setting also has a palette toggle where it's boolean. (changelog/2026.06.03)

### General

- [ ] SET-001 `general.default_session_mode` = `terminal`. Rewarp keeps `terminal` and `tab_config`. (terminal/settings/all-settings)
- [ ] SET-002 `general.default_tab_config_path` = empty. Config to use when the mode above is `tab_config`. (terminal/settings/all-settings)
- [ ] SET-003 `general.link_tooltip` = true. Tooltip when hovering links. (terminal/settings/all-settings)
- [ ] SET-004 `general.login_item` = true. Launch at login. (terminal/settings/all-settings)
- [ ] SET-005 `general.mouse_scroll_multiplier` = 3.0. (terminal/settings/all-settings)
- [ ] SET-006 `general.new_tab_placement` = `after_current_tab`. Also `after_all_tabs`. (terminal/settings/all-settings)
- [ ] SET-007 `general.preserve_input_focus_on_block_selection` = false. (terminal/settings/all-settings)
- [ ] SET-008 `general.quit_on_last_window_closed` = false. (terminal/settings/all-settings)
- [ ] SET-009 `general.restore_session` = true. (terminal/settings/all-settings)
- [ ] SET-010 `general.should_confirm_close_session` = true. (terminal/settings/all-settings)
- [ ] SET-011 `general.show_changelog_after_update` = true. (terminal/settings/all-settings)
- [ ] SET-012 `general.show_warning_before_quitting` = true. (terminal/settings/all-settings)
- [ ] SET-013 `general.snackbar_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-014 `general.undo_close.enabled` = true. (terminal/settings/all-settings)
- [ ] SET-015 `general.undo_close.grace_period` = 60 seconds. (terminal/settings/all-settings)

### Appearance

- [ ] SET-016 `appearance.spacing` = `normal`. Also `compact`. (terminal/settings/all-settings)
- [ ] SET-017 `appearance.themes.theme` = `dark`. Options are the shipped themes or a custom object. (terminal/settings/all-settings)
- [ ] SET-018 `appearance.themes.system_theme` = false. (terminal/settings/all-settings)
- [ ] SET-019 `appearance.themes.selected_system_themes` = dark `dark`, light `light`. (terminal/settings/all-settings)
- [ ] SET-020 `appearance.text.font_name` = `Hack`. (terminal/settings/all-settings)
- [ ] SET-021 `appearance.text.font_size` = 13.0. (terminal/settings/all-settings)
- [ ] SET-022 `appearance.text.font_weight` = `normal`. (terminal/settings/all-settings)
- [ ] SET-023 `appearance.text.line_height_ratio` = 1.2. (terminal/settings/all-settings)
- [ ] SET-024 `appearance.text.ligature_rendering_enabled` = false. (terminal/settings/all-settings)
- [ ] SET-025 `appearance.text.use_thin_strokes` = `on_high_dpi_displays`. Also `never`, `on_low_dpi_displays`, `always`. (terminal/settings/all-settings)
- [ ] SET-026 `appearance.text.enforce_minimum_contrast` = `only_named_colors`. Also `never`, `always`. (terminal/settings/all-settings)
- [ ] SET-027 `appearance.cursor.cursor_display_type` = `bar`. Also `block`, `underline`. (terminal/settings/all-settings)
- [ ] SET-028 `appearance.cursor.cursor_blink` = `enabled`. (terminal/settings/all-settings)
- [ ] SET-029 `appearance.blocks.show_block_dividers` = true. (terminal/settings/all-settings)
- [ ] SET-030 `appearance.blocks.show_jump_to_bottom_of_block_button` = true. (terminal/settings/all-settings)
- [ ] SET-031 `appearance.blocks.should_show_bootstrap_block` = false. (terminal/settings/all-settings)
- [ ] SET-032 `appearance.blocks.should_show_in_band_command_blocks` = false. (terminal/settings/all-settings)
- [ ] SET-033 `appearance.blocks.should_show_ssh_block` = false. (terminal/settings/all-settings)
- [ ] SET-034 `appearance.tabs.workspace_decoration_visibility` = `hide_fullscreen`. Also `always_show`, `on_hover`. (terminal/settings/all-settings)
- [ ] SET-035 `appearance.tabs.tab_close_button_position` = `right`. Also `left`. (terminal/settings/all-settings)
- [ ] SET-036 `appearance.tabs.show_indicators_button` = true. (terminal/settings/all-settings)
- [ ] SET-037 `appearance.tabs.preserve_active_tab_color` = false. (terminal/settings/all-settings)
- [ ] SET-038 `appearance.tabs.directory_tab_colors` = empty map. (terminal/settings/all-settings)
- [ ] SET-039 `appearance.tabs.header_toolbar_chip_selection` = `default`. (terminal/settings/all-settings)
- [ ] SET-040 `appearance.vertical_tabs.enabled` = false. (terminal/settings/all-settings)
- [ ] SET-041 `appearance.vertical_tabs.view_mode` = `compact`. Also `expanded`. (terminal/settings/all-settings)
- [ ] SET-042 `appearance.vertical_tabs.primary_info` = `command`. Also `working_directory`, `branch`. (terminal/settings/all-settings)
- [ ] SET-043 `appearance.vertical_tabs.compact_subtitle` = `branch`. Also `working_directory`, `command`. (terminal/settings/all-settings)
- [ ] SET-044 `appearance.vertical_tabs.display_granularity` = `panes`. Also `tabs`. (terminal/settings/all-settings)
- [ ] SET-045 `appearance.vertical_tabs.tab_item_mode` = `focused_session`. Also `summary`. (terminal/settings/all-settings)
- [ ] SET-046 `appearance.vertical_tabs.show_details_on_hover` = true. (terminal/settings/all-settings)
- [ ] SET-047 `appearance.vertical_tabs.show_diff_stats` = true. (terminal/settings/all-settings)
- [ ] SET-048 `appearance.vertical_tabs.show_pr_link` = true. (terminal/settings/all-settings)
- [ ] SET-049 `appearance.vertical_tabs.hide_title_bar_search_bar` = false. (terminal/settings/all-settings)
- [ ] SET-050 `appearance.vertical_tabs.show_panel_in_restored_windows` = false. (terminal/settings/all-settings)
- [ ] SET-051 `appearance.panes.focus_pane_on_hover` = false. (terminal/settings/all-settings)
- [ ] SET-052 `appearance.panes.should_dim_inactive_panes` = false. (terminal/settings/all-settings)
- [ ] SET-053 `appearance.input.input_mode` = `pinned_to_bottom`. Also `pinned_to_top`, `waterfall`. (terminal/settings/all-settings)
- [ ] SET-054 `appearance.full_screen_apps.alt_screen_padding` = custom, uniform padding 0.0. (terminal/settings/all-settings)
- [ ] SET-055 `appearance.icon.app_icon` = `default`. (terminal/settings/all-settings)
- [ ] SET-056 `appearance.icon.show_dock_icon` = true. (terminal/settings/all-settings)
- [ ] SET-057 `appearance.window.override_opacity` = 100. Range 1 to 100. (terminal/settings/all-settings)
- [ ] SET-058 `appearance.window.override_blur` = 1. (terminal/settings/all-settings)
- [ ] SET-059 `appearance.window.zoom_level` = 100. (terminal/settings/all-settings)
- [ ] SET-060 `appearance.window.open_windows_at_custom_size` = false. (terminal/settings/all-settings)
- [ ] SET-061 `appearance.window.new_windows_num_columns` = 80. (terminal/settings/all-settings)
- [ ] SET-062 `appearance.window.new_windows_num_rows` = 40. (terminal/settings/all-settings)
- [ ] SET-063 `appearance.window.left_panel_visibility_across_tabs` = true. (terminal/settings/all-settings)

### Terminal

- [ ] SET-064 `terminal.copy_on_select` = true. (terminal/settings/all-settings)
- [ ] SET-065 `terminal.focus_reporting_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-066 `terminal.mouse_reporting_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-067 `terminal.scroll_reporting_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-068 `terminal.maximum_grid_size` = 50000 rows. (terminal/settings/all-settings)
- [ ] SET-069 `terminal.osc52_clipboard_access` = `deny`. Also `write_only`, `read_write`. (terminal/settings/all-settings)
- [ ] SET-070 `terminal.use_audible_bell` = false. (terminal/settings/all-settings)
- [ ] SET-071 `terminal.input.syntax_highlighting` = true. (terminal/settings/all-settings)
- [ ] SET-072 `terminal.input.honor_ps1` = false. (terminal/settings/all-settings)
- [ ] SET-073 `terminal.input.alias_expansion_enabled` = false. (terminal/settings/all-settings)
- [ ] SET-074 `terminal.input.command_corrections` = true. (terminal/settings/all-settings)
- [ ] SET-075 `terminal.input.error_underlining_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-076 `terminal.input.completions_open_while_typing` = false. (terminal/settings/all-settings)
- [ ] SET-077 `terminal.input.classic_completions_mode` = false. (terminal/settings/all-settings)
- [ ] SET-078 `terminal.input.warp_completions_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-079 `terminal.input.native_shell_completions_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-080 `terminal.input.show_hint_text` = true. (terminal/settings/all-settings)
- [ ] SET-081 `terminal.input.show_terminal_input_message_bar` = true. (terminal/settings/all-settings)
- [ ] SET-082 `terminal.input.enable_slash_commands_in_terminal` = true. (terminal/settings/all-settings)
- [ ] SET-083 `terminal.input.enable_ai_command_search_hash_trigger` = true. Opens Command Search on a leading `#`. (terminal/settings/all-settings)
- [ ] SET-084 `terminal.input.middle_click_paste_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-085 `terminal.input.right_click_behavior` = `context_menu`. Also `paste`. (terminal/settings/all-settings)
- [ ] SET-086 `terminal.input.extra_meta_keys` = left alt false, right alt false. (terminal/settings/all-settings)
- [ ] SET-087 `terminal.input.autosuggestions.enabled` = true. (terminal/settings/all-settings)
- [ ] SET-088 `terminal.input.autosuggestions.keybinding_hint` = true. (terminal/settings/all-settings)
- [ ] SET-089 `terminal.input.autosuggestions.show_ignore_button` = false. (terminal/settings/all-settings)
- [ ] SET-090 `terminal.smart_select.enabled` = true. (terminal/settings/all-settings)
- [ ] SET-091 `terminal.smart_select.word_char_allowlist` = `-.~/\`. (terminal/settings/all-settings)

### Session

- [ ] SET-092 `session.startup_shell_override` = none. (terminal/settings/all-settings)
- [ ] SET-093 `session.new_session_shell_override` = none. Also `system_default`, an executable path, or a custom command. (terminal/settings/all-settings)
- [ ] SET-094 `session.working_directory_config.advanced_mode` = false. (terminal/settings/all-settings)
- [ ] SET-095 `session.working_directory_config.global.mode` = `previous_dir`. Also `home_dir`, `custom_dir`. Sections `.split_pane`, `.new_tab`, `.new_window` apply in advanced mode. (terminal/settings/all-settings)
- [ ] SET-096 `session.working_directory_config.global.custom_dir` = empty. (terminal/settings/all-settings)

### Code

- [ ] SET-097 `code.editor.open_file_editor` = `system_default`. Also `warp`, `env_editor`, or an external editor. (terminal/settings/all-settings)
- [ ] SET-098 `code.editor.open_code_panels_file_editor` = `warp`. (terminal/settings/all-settings)
- [ ] SET-099 `code.editor.open_file_layout` = `split_pane`. Also `new_tab`. (terminal/settings/all-settings)
- [ ] SET-100 `code.editor.prefer_markdown_viewer` = true. (terminal/settings/all-settings)
- [ ] SET-101 `code.editor.prefer_tabbed_editor_view` = true. (terminal/settings/all-settings)
- [ ] SET-102 `code.editor.show_code_review_button` = true. (terminal/settings/all-settings)
- [ ] SET-103 `code.editor.show_code_review_diff_stats` = true. (terminal/settings/all-settings)
- [ ] SET-104 `code.editor.show_project_explorer` = true. (terminal/settings/all-settings)
- [ ] SET-105 `code.editor.show_global_search` = true. (terminal/settings/all-settings)
- [ ] SET-106 `code.editor.show_hidden_files` = true. (terminal/settings/all-settings)
- [ ] SET-107 `code.editor.use_warp_as_default_editor` = false. (terminal/settings/all-settings)
- [ ] SET-108 `code.editor.format_on_save` = true. (terminal/settings/all-settings)
- [ ] SET-109 `code.editor.auto_save` = false. (terminal/settings/all-settings)

### Keys, notifications, privacy and system

- [ ] SET-110 `keys.ctrl_tab_behavior_setting` = `activate_prev_next_tab`. Also `cycle_most_recent_session`. The changelog adds Cycle Most Recent Tab. (changelog/2026.05.14)
- [ ] SET-111 `notifications.toast_duration_secs` = 8. (terminal/settings/all-settings)
- [ ] SET-112 `notifications.preferences.mode` = `unset`. Also `dismissed`, `enabled`, `disabled`. (terminal/settings/all-settings)
- [ ] SET-113 `notifications.preferences.is_long_running_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-114 `notifications.preferences.long_running_threshold` = 30 seconds. (terminal/settings/all-settings)
- [ ] SET-115 `notifications.preferences.is_needs_attention_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-116 `notifications.preferences.is_password_prompt_enabled` = true. (terminal/settings/all-settings)
- [ ] SET-117 `notifications.preferences.play_notification_sound` = true. (terminal/settings/all-settings)
- [ ] SET-118 `privacy.custom_secret_regex_list` = empty. (terminal/settings/all-settings)
- [ ] SET-119 `privacy.secret_redaction.enabled` = false. (terminal/settings/all-settings)
- [ ] SET-120 `privacy.secret_redaction.hide_secrets_in_block_list` = false. (terminal/settings/all-settings)
- [ ] SET-121 `privacy.secret_redaction.secret_display_mode_setting` = `strikethrough`. Also `asterisks`, `always_show`. (terminal/settings/all-settings)
- [ ] SET-122 `system.prefer_low_power_gpu` = false. (terminal/settings/all-settings)

### Text editing

- [ ] SET-123 `text_editing.code_editor_line_number_mode` = `absolute`. Also `relative`. (terminal/settings/all-settings)
- [ ] SET-124 `text_editing.vim_mode_enabled` = false. (terminal/settings/all-settings)
- [ ] SET-125 `text_editing.vim_status_bar` = true. (terminal/settings/all-settings)
- [ ] SET-126 `text_editing.vim_unnamed_system_clipboard` = false. (terminal/settings/all-settings)
- [ ] SET-127 `text_editing.autocomplete_symbols` = true. (terminal/settings/all-settings)

### Other sections

- [ ] SET-128 `experimental.async_find_enabled` = false in the reference, though the changelog says async find is on for everyone. (terminal/settings/all-settings; changelog/2026.07.23)
- [ ] SET-129 `warpify.ssh.enable_ssh_warpification` = true. (terminal/settings/all-settings)
- [ ] SET-130 `warpify.ssh.reuse_existing_control_master` = false. (terminal/settings/all-settings)
- [ ] SET-131 `warpify.ssh.ssh_hosts_denylist` = empty. (terminal/settings/all-settings)
- [ ] SET-132 `warpify.subshells.added_subshell_commands` = empty. (terminal/settings/all-settings)
- [ ] SET-133 `warpify.subshells.subshell_commands_denylist` = empty. (terminal/settings/all-settings)
- [ ] SET-134 `workflows.show_global_workflows_in_universal_search` = false. (terminal/settings/all-settings)
- [ ] SET-135 `accessibility.accessibility_verbosity` = `verbose`. Also `concise`. (terminal/settings/all-settings)
- [ ] SET-136 `global_hotkey.toggle_all_windows.enabled` = false. Mutually exclusive with the dedicated window. (terminal/settings/all-settings)
- [ ] SET-137 `global_hotkey.toggle_all_windows.keybinding` = none. (terminal/settings/all-settings)
- [ ] SET-138 `global_hotkey.dedicated_window.enabled` = false. (terminal/settings/all-settings)
- [ ] SET-139 `global_hotkey.dedicated_window.settings.active_pin_position`, no default listed. Options `top`, `bottom`, `left`, `right`. (terminal/settings/all-settings)
- [ ] SET-140 `global_hotkey.dedicated_window.settings.hide_window_when_unfocused`, no default listed. (terminal/settings/all-settings)
- [ ] SET-141 `global_hotkey.dedicated_window.settings.keybinding`, no default listed. (terminal/settings/all-settings)
- [ ] SET-142 `global_hotkey.dedicated_window.settings.pin_screen`, no default listed. Options `primary`, an external index, or none. (terminal/settings/all-settings)
- [ ] SET-143 `global_hotkey.dedicated_window.settings.pin_position_to_size_percentages`, per position. Example values are in [Global hotkey](#global-hotkey). (terminal/settings/all-settings)

### Settings named in the docs but missing from the reference

- [ ] SET-144 Tab key behavior, under Settings > Features > Terminal Input. Opens the completions menu by default, or accepts the autosuggestion. (verify in app) (terminal/command-completions/completions; changelog/2023.07.20)
- [ ] SET-145 Same line prompt, under Settings > Appearance > Prompt, off for the Warp prompt. (verify in app) (changelog/2024.07.11)
- [ ] SET-146 Use custom padding in alt-screen, on by default. In the reference it's encoded in `alt_screen_padding`. (terminal/more-features/full-screen-apps)
- [ ] SET-147 Maximum rows in a block, under Settings > Features > Session. Probably `maximum_grid_size`. (verify in app) (changelog/2025.07.30)
- [ ] SET-148 View all available system fonts, under Settings > Appearance > Text. Default not given. (terminal/appearance/text-fonts-cursor)
- [ ] SET-149 A Dock-hiding option for hotkey-window users, under Settings > Features > Global hotkey. Default not given. (changelog/2026.06.24)
- [ ] SET-150 Disable in-band commands in remote subshells, a preference outside the settings file. (terminal/warpify/subshells)

## Default macOS keybindings

Warp's documented macOS defaults. Names are Warp's command labels. Unless noted, the source is `getting-started/keyboard-shortcuts`. `Meta` means Option when Option is set as Meta, or `Esc` then key.

### Keybinding editor

- [ ] KBE-001 Settings > Keyboard shortcuts lists remappable actions, searchable by action or by existing shortcut. (getting-started/keyboard-shortcuts)
- [ ] KBE-002 `⌃⌘K` opens the editor, with its search bar focused. (getting-started/keyboard-shortcuts; changelog/2023.06.01)
- [ ] KBE-003 Each action can be set, cleared or reset to default. (getting-started/keyboard-shortcuts; changelog/2023.03.09; privacy/events)
- [ ] KBE-004 Conflicting keybinds get an orange border. (getting-started/keyboard-shortcuts; changelog/2022.02.23)
- [ ] KBE-005 Bindings can also be set through a file, `keybindings.yaml`. Its format is documented in Warp's keysets repository, which wasn't read here. (getting-started/keyboard-shortcuts; terminal/settings/file-locations)
- [ ] KBE-006 The opening shortcut screen and the Resource Center list common bindings. (getting-started/keyboard-shortcuts)
- [ ] KBE-007 Bindings with `Space` persist across launches. (changelog/2023.02.09)
- [ ] KBE-008 `⌘⇧←` and `⌘⇧→` can be assigned to actions. (changelog/2025.01.08)
- [ ] KBE-009 Bindings that clash with macOS shortcuts can be remapped. (changelog/2025.10.08)
- [ ] KBE-010 Arrow navigation keys and the numbered tab keys are editable. (changelog/2022.03.02)
- [ ] KBE-011 System shortcuts must be unbound in macOS first. (getting-started/keyboard-shortcuts)
- [ ] KBE-012 Unsetting the binding that opens the shortcuts panel must not crash. (changelog/2023.03.20)
- [ ] KBE-013 Warp keeps its keybinding file under `~/.warp`. (changelog/2022.03.16)

### Essentials

- [ ] KEY-001 `⌘D` Split Pane Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-002 `⌃⌘L` Launch Configuration Palette. (getting-started/keyboard-shortcuts)
- [ ] KEY-003 `⌃⌘T` Open Theme Picker. (getting-started/keyboard-shortcuts)
- [ ] KEY-004 `⌃R` Command Search. (getting-started/keyboard-shortcuts)
- [ ] KEY-005 `⌃⇧R` Workflows. (getting-started/keyboard-shortcuts)
- [ ] KEY-006 `⌘L` Focus Terminal Input. (getting-started/keyboard-shortcuts)
- [ ] KEY-007 `⌃I` Warpify Subshell. (getting-started/keyboard-shortcuts)
- [ ] KEY-008 `⌘\` Toggle the left tools panel. The docs call this Warp Drive. (code/code-editor/file-tree)
- [ ] KEY-009 `⌘O` File search. (getting-started/keyboard-shortcuts)
- [ ] KEY-010 `⌘P` Command Palette. (getting-started/keyboard-shortcuts)

### Blocks

- [ ] KEY-011 `⌥↓` Select the Closest Bookmark Down. (getting-started/keyboard-shortcuts)
- [ ] KEY-012 `⌥↑` Select the Closest Bookmark Up. (getting-started/keyboard-shortcuts)
- [ ] KEY-013 `⌥⇧⌘C` Copy Command Output. (getting-started/keyboard-shortcuts)
- [ ] KEY-014 `⌘A` Select All Blocks. (getting-started/keyboard-shortcuts)
- [ ] KEY-015 `⌘K` Clear Blocks. (getting-started/keyboard-shortcuts)
- [ ] KEY-016 `⌘B` Bookmark Selected Block. (getting-started/keyboard-shortcuts)
- [ ] KEY-017 `⌘↓` Select Next Block. (getting-started/keyboard-shortcuts)
- [ ] KEY-018 `⌘↑` Select Previous Block. (getting-started/keyboard-shortcuts)
- [ ] KEY-019 `⌘I` Reinput Selected Commands. (getting-started/keyboard-shortcuts)
- [ ] KEY-020 `⇧⌘I` Reinput Selected Commands as Root. (getting-started/keyboard-shortcuts)
- [ ] KEY-021 `⌃M` Open Block Context Menu. (getting-started/keyboard-shortcuts)
- [ ] KEY-022 `⇧⌘C` Copy Command. (getting-started/keyboard-shortcuts)
- [ ] KEY-023 `⇧↓` Expand Selected Blocks Below. (getting-started/keyboard-shortcuts)
- [ ] KEY-024 `⇧↑` Expand Selected Blocks Above. (getting-started/keyboard-shortcuts)
- [ ] KEY-025 `⌥⇧F` Toggle Block Filter. (terminal/blocks/block-filtering)
- [ ] KEY-026 `⌘⌃S` Toggle Sticky Command Header. (terminal/blocks/sticky-command-header)
- [ ] KEY-027 `⌃S` Toggle Sticky Command Header in Active Pane. (terminal/blocks/sticky-command-header)

### Scrolling

- [ ] KEY-028 `Page Up` Scroll Up One Page. (getting-started/keyboard-shortcuts)
- [ ] KEY-029 `Page Down` Scroll Down One Page. (getting-started/keyboard-shortcuts)
- [ ] KEY-030 `Home` Scroll to Top. (getting-started/keyboard-shortcuts)
- [ ] KEY-031 `End` Scroll to Bottom. (getting-started/keyboard-shortcuts)
- [ ] KEY-032 `⇧⌘↑` Scroll to Top of Selected Block. (getting-started/keyboard-shortcuts)
- [ ] KEY-033 `⇧⌘↓` Scroll to Bottom of Selected Block. (getting-started/keyboard-shortcuts)
- [ ] KEY-034 No default: Scroll Terminal Output Up One Line, Down One Line. (getting-started/keyboard-shortcuts)

### Input editor

- [ ] KEY-035 `⌥⌫` Delete Word Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-036 `⌥⌦` Delete Word Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-037 `⌥⌘F` Fold Selected Ranges. (getting-started/keyboard-shortcuts)
- [ ] KEY-038 `⌥⌘[` Fold. (getting-started/keyboard-shortcuts)
- [ ] KEY-039 `⌥⌘]` Unfold. (getting-started/keyboard-shortcuts)
- [ ] KEY-040 `⌘A` Select All. (getting-started/keyboard-shortcuts)
- [ ] KEY-041 `⌘⌫` Delete All Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-042 `⌘⌦` Delete All Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-043 `⌘↓` Move Cursor to the Bottom. (getting-started/keyboard-shortcuts)
- [ ] KEY-044 `⌘I` Inspect Command, shared with Reinput. See [Source conflicts](#source-conflicts). (getting-started/keyboard-shortcuts)
- [ ] KEY-045 `⌘←` Home. (getting-started/keyboard-shortcuts)
- [ ] KEY-046 `⌘→` End. (getting-started/keyboard-shortcuts)
- [ ] KEY-047 `⌃A` Move to Start of Line. (getting-started/keyboard-shortcuts)
- [ ] KEY-048 `⌃B` Move Cursor Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-049 `⌃C` Clear Command Editor. (getting-started/keyboard-shortcuts)
- [ ] KEY-050 `⌃D` Delete. (getting-started/keyboard-shortcuts)
- [ ] KEY-051 `⌃E` Move to End of Line. (getting-started/keyboard-shortcuts)
- [ ] KEY-052 `⌃F` Move Cursor Right or Accept Autosuggestion. (getting-started/keyboard-shortcuts)
- [ ] KEY-053 `⌃G` Add Selection for Next Occurrence. (getting-started/keyboard-shortcuts)
- [ ] KEY-054 `⌃H` Remove the Previous Character. (getting-started/keyboard-shortcuts)
- [ ] KEY-055 `⌃J` Insert Newline. (getting-started/keyboard-shortcuts)
- [ ] KEY-056 `⌃K` Cut All Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-057 `⌃L` Clear Screen. (getting-started/keyboard-shortcuts)
- [ ] KEY-058 `⌃N` Move Cursor Down. (getting-started/keyboard-shortcuts)
- [ ] KEY-059 `⌃P` Move Cursor Up. (getting-started/keyboard-shortcuts)
- [ ] KEY-060 `⌃⇧A` Select to Start of Line. (getting-started/keyboard-shortcuts)
- [ ] KEY-061 `⌃⇧B` Select One Character to the Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-062 `⌃⇧E` Select to End of Line. (getting-started/keyboard-shortcuts)
- [ ] KEY-063 `⌃⇧F` Select One Character to the Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-064 `⌃⇧N` Select Down. (getting-started/keyboard-shortcuts)
- [ ] KEY-065 `⌃⇧P` Select Up. (getting-started/keyboard-shortcuts)
- [ ] KEY-066 `⌃⇧↓` Add Cursor Below. (getting-started/keyboard-shortcuts)
- [ ] KEY-067 `⌃⇧↑` Add Cursor Above. (getting-started/keyboard-shortcuts)
- [ ] KEY-068 `⌘Z` Undo. (getting-started/keyboard-shortcuts)
- [ ] KEY-069 `⌘⇧Z` Redo. (getting-started/keyboard-shortcuts)
- [ ] KEY-070 `⌃U` Copy and Clear Selected Lines. (getting-started/keyboard-shortcuts)
- [ ] KEY-071 `⌃W` Cut Word Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-072 `Meta+.` Insert Last Word of Previous Command. (getting-started/keyboard-shortcuts)
- [ ] KEY-073 `Meta+A` Move to the Start of the Paragraph. (getting-started/keyboard-shortcuts)
- [ ] KEY-074 `Meta+B` Move Backward One Word. (getting-started/keyboard-shortcuts)
- [ ] KEY-075 `Meta+D` Cut Word Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-076 `Meta+E` Move to the End of the Paragraph. (getting-started/keyboard-shortcuts)
- [ ] KEY-077 `Meta+F` Move Forward One Word. (getting-started/keyboard-shortcuts)
- [ ] KEY-078 `⌃⌥←` Move Backward One Subword. (getting-started/keyboard-shortcuts)
- [ ] KEY-079 `⌃⌥→` Move Forward One Subword. (getting-started/keyboard-shortcuts)
- [ ] KEY-080 `⇧⌘K` Clear Selected Lines. (getting-started/keyboard-shortcuts)
- [ ] KEY-081 `Shift+Meta+<` Move to the Start of the Buffer. (getting-started/keyboard-shortcuts)
- [ ] KEY-082 `Shift+Meta+>` Move to the End of the Buffer. (getting-started/keyboard-shortcuts)
- [ ] KEY-083 `Shift+Meta+B` Select One Word to the Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-084 `Shift+Meta+F` Select One Word to the Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-085 `⇧Enter`, `⌃Enter`, `⌥Enter` Insert newline. (terminal/editor)
- [ ] KEY-086 `⌥Space` Insert a space without expanding an alias. (terminal/editor/alias-expansion)
- [ ] KEY-087 `⌃Space` Open completions when `Tab` is rebound. (terminal/command-completions/completions)
- [ ] KEY-088 `⌃→` Partially accept autosuggestion. (terminal/command-completions/autosuggestions)
- [ ] KEY-089 `Esc` Close the suggestions or history menu. (terminal/editor)

### Terminal and panes

- [ ] KEY-090 `⌥⌘↓`, `⌥⌘←`, `⌥⌘→`, `⌥⌘↑` Switch Panes. (getting-started/keyboard-shortcuts)
- [ ] KEY-091 `⌃⌘↓`, `⌃⌘←`, `⌃⌘→`, `⌃⌘↑` Resize Pane, moving the divider. (getting-started/keyboard-shortcuts)
- [ ] KEY-092 `⌥⌘V` Accessibility: Set Concise or Verbose Announcements. (getting-started/keyboard-shortcuts)
- [ ] KEY-093 `⌘,` Open Settings. (getting-started/keyboard-shortcuts)
- [ ] KEY-094 `⌘G` Find Next Occurrence. (getting-started/keyboard-shortcuts)
- [ ] KEY-095 `⇧⌘G` Find Previous Occurrence. (getting-started/keyboard-shortcuts)
- [ ] KEY-096 `⌘[` Activate Previous Pane. (getting-started/keyboard-shortcuts)
- [ ] KEY-097 `⌘]` Activate Next Pane. (getting-started/keyboard-shortcuts)
- [ ] KEY-098 `⌃⌘K` Open Keybindings Editor. (getting-started/keyboard-shortcuts)
- [ ] KEY-099 `⌃⇧?` Open Resource Center. (getting-started/keyboard-shortcuts)
- [ ] KEY-100 `⇧⌘D` Split Pane Down. (getting-started/keyboard-shortcuts)
- [ ] KEY-101 `⇧⌘Enter` Toggle Maximize Active Pane. (getting-started/keyboard-shortcuts)
- [ ] KEY-102 `⇧⌘P` Toggle Navigation Palette. (getting-started/keyboard-shortcuts)
- [ ] KEY-103 `⌘⌥I` Synchronize All Panes in Current Tab, or Stop Synchronizing. (terminal/entry/synchronized-inputs)
- [ ] KEY-104 No default: Toggle Mouse Reporting. (getting-started/keyboard-shortcuts)
- [ ] KEY-105 No default: Split Pane Left, Split Pane Up. (verify in app) (3p/mvolkmann)

### Fundamentals

- [ ] KEY-106 `⌘-` Decrease Font Size. (getting-started/keyboard-shortcuts)
- [ ] KEY-107 `⌘=` Increase Font Size. (getting-started/keyboard-shortcuts)
- [ ] KEY-108 `⌘0` Reset Font Size to Default. (getting-started/keyboard-shortcuts)
- [ ] KEY-109 `⌘1` to `⌘8` Switch to that tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-110 `⌘9` Switch to Last Tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-111 `⌘C` Copy. (getting-started/keyboard-shortcuts)
- [ ] KEY-112 `⌘F` Find. (getting-started/keyboard-shortcuts)
- [ ] KEY-113 `⌘V` Paste. (getting-started/keyboard-shortcuts)
- [ ] KEY-114 `⌘X` Cut. (terminal/editor)
- [ ] KEY-115 `⌘T` Open New Tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-116 `⇧⌘T` Reopen Closed Tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-117 `⌘W` Close Tab or Pane. (terminal/windows/tabs; terminal/windows/split-panes)
- [ ] KEY-118 `⇧⌘W` Close Window. (changelog/2024.03.07)
- [ ] KEY-119 `⌘N` New Window. (verify in app) (3p/mvolkmann)
- [ ] KEY-120 `⌘M` Minimize. (changelog/2022.01.05)
- [ ] KEY-121 `⌃⇧←` Move Tab Left. (getting-started/keyboard-shortcuts)
- [ ] KEY-122 `⌃⇧→` Move Tab Right. (getting-started/keyboard-shortcuts)
- [ ] KEY-123 `⇧⌘{` Activate Previous Tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-124 `⇧⌘}` Activate Next Tab. (getting-started/keyboard-shortcuts)
- [ ] KEY-125 `⌃Tab`, `⌃⇧Tab` Switch tabs, or cycle recent sessions per setting. (changelog/2021.07.07; terminal/windows/tabs)
- [ ] KEY-126 `⌘E` Toggle Markdown rendered and raw. (terminal/more-features/markdown-viewer)
- [ ] KEY-127 `⌘S` Save file in the code editor. (code/code-editor)
- [ ] KEY-128 `⌃G` Go to Line in the code editor. (changelog/2026.03.18)
- [ ] KEY-129 `⌘/` Open the keyboard shortcuts pane. (verify in app) (changelog/2023.06.01)
- [ ] KEY-130 `⌘⇧+` Open Code Review. (code/code-review)

### Actions with no default key

Palette or user-bound only.

- [ ] KEY-131 Cycle current tab color. (terminal/windows/tabs)
- [ ] KEY-132 Rename Pane. (changelog/2026.05.14)
- [ ] KEY-133 Accept the most recent command correction. The shortcut exists but the key isn't named. (verify in app) (changelog/2025.03.26)
- [ ] KEY-134 Group creation, group removal, pin, unpin. (terminal/windows/tabs)
- [ ] KEY-135 New File. (changelog/2026.07.03)

## Source conflicts

Each of these needs a ruling from the real app before implementation. None has been resolved by guessing.

- [ ] CNF-001 `⌘I` is listed for Reinput Selected Commands and for Inspect Command. Warp's agent docs also use it to toggle Agent Mode. The Inspector page says `⌘⇧I`, which the shortcuts table gives to Reinput as Root. Rewarp has no agent mode, so `⌘I` is free to follow focus: reinput with a block selected, inspect in the input. (getting-started/keyboard-shortcuts; terminal/editor/command-inspector)
- [ ] CNF-002 `⌘↓` is Select Next Block and Move Cursor to the Bottom. `⌘A` is Select All Blocks and Select All. Both appear to depend on focus, which isn't stated. (getting-started/keyboard-shortcuts)
- [ ] CNF-003 `⌘⇧↑` and `⌘⇧↓` are documented as scrolling the selected block, even with the input focused, and also as selecting to the buffer top and bottom in the input. (changelog/2026.05.06; changelog/2025.04.02)
- [ ] CNF-004 `⌘←` and `⌘→` on soft-wrapped lines: logical or visual line. (terminal/editor; changelog/2026.07.09)
- [ ] CNF-005 Default working directory: Home per the feature page, `previous_dir` per the settings reference. The Tabs page agrees with `previous_dir`. (terminal/more-features/working-directory; terminal/settings/all-settings; terminal/windows/tabs)
- [ ] CNF-006 Default input type: `classic` in the reference, while the 2025.08.20 changelog made Universal the default. Terminal mode is a later rework. Rewarp is classic only. (terminal/settings/all-settings; changelog/2025.08.20)
- [ ] CNF-007 `prefer_markdown_viewer` is true in the reference, while the Markdown page reads as if viewer-by-default is opt-in. (terminal/settings/all-settings; terminal/more-features/markdown-viewer)
- [ ] CNF-008 `show_global_workflows_in_universal_search` is false in the reference, while the Command Search page talks about switching it off. (terminal/settings/all-settings; terminal/entry/command-search)
- [ ] CNF-009 `async_find_enabled` is false in the reference, while the changelog says it's on for everyone. (terminal/settings/all-settings; changelog/2026.07.23)
- [ ] CNF-010 Command correction UI: the page describes a panel above the input, and the changelog removed that banner in favour of an autosuggestion. (terminal/entry/command-corrections; changelog/2025.01.08)
- [ ] CNF-011 Pane rename: the Vertical Tabs page says panes can't be renamed, and the changelog added it. (terminal/windows/vertical-tabs; changelog/2026.05.14)
- [ ] CNF-012 Launch configuration `cwd`: `~` hides the file per the page, and the changelog says `~` is supported. (terminal/sessions/launch-configurations; changelog/2023.03.20)
- [ ] CNF-013 Filter editor: the page describes two buttons on the left but lists three toggles. (terminal/blocks/block-filtering)
- [ ] CNF-014 Partial autosuggestion accept: `⌃→` in the docs, also `⌥→` in an older changelog. (terminal/command-completions/autosuggestions; changelog/2022.02.23)
- [ ] CNF-015 `⌃U` is Copy and Clear the current line on one page and Copy and Clear Selected Lines on another. (terminal/editor; getting-started/keyboard-shortcuts)
- [ ] CNF-016 Cut targets: the editor page says `⌃K` copies to the clipboard, while `⌃W` and `Meta+D` use a separate shell clipboard. Whether `⌃K` and `⌃U` share it isn't clear. (terminal/editor; changelog/2023.04.27; changelog/2021.08.09)
- [ ] CNF-017 Feature table says italic and dim aren't supported, while the changelog shows both rendering. (terminal/comparisons/terminal-features; changelog/2022.09.01; changelog/2022.11.03)
- [ ] CNF-018 Sticky header toggle `⌃S` collides with terminal flow control while a command runs. How it's routed isn't stated. (terminal/blocks/sticky-command-header)
- [ ] CNF-019 `⌘,` is listed for both Open Settings and Open Settings: Account. `⌥⌘V` is listed for both a11y states. These are probably toggles. (getting-started/keyboard-shortcuts)
- [ ] CNF-020 Show background blocks in the Blocks menu reveals hidden helper-command blocks, not the background blocks feature. The name collides. (terminal/warpify/subshells; terminal/blocks/background-blocks)
- [ ] CNF-021 `⌘\` is labelled Warp Drive in the shortcut table and left panel in the file tree page. (getting-started/keyboard-shortcuts; code/code-editor/file-tree)
- [ ] CNF-022 Tab close default: the Tabs Behavior page calls left the macOS style, and the reference defaults to right. (terminal/appearance/tabs-behavior; terminal/settings/all-settings)

## Top items to verify

The ten ambiguities most likely to shape the design. Run these in Warp.app first.

- [ ] VFY-001 What a printable key does with a block selected and focus off the input. Most of the block keyboard model hangs on this. (COR-016)
- [ ] VFY-002 Whether the input editor stays on screen during a running command, what the threshold is, and where the cursor lives. Decides how `docs/design.md`'s editor and key encoder hand over. (COR-042)
- [ ] VFY-003 How text selection and block selection coexist: does a click clear a text selection, can a drag span blocks, and what does `⌘C` copy when both exist. Per-block terminals in `docs/design.md` make this one expensive to get wrong. (BLK-062, BLK-063)
- [ ] VFY-004 Exact click rules on block text: does a plain click select the block on mouse-down or mouse-up, does a small drag cancel it, does a click on a selected block deselect it, and how does the selection clear. (BLK-043)
- [ ] VFY-005 Exact `↑` transition in the input: multi-line cursor movement, when the history menu opens, what plain `Enter` does on an item, and how `↑` behaves with input pinned to the top. (HIS-007, HIS-010)
- [ ] VFY-006 Completion menu flow since 2026.01.07: selection preview in the input, how `Enter`, `Tab`, `→`, `Esc` and typing act with an item highlighted, and what `classic_completions_mode` changes. (CMP-007, CMP-008)
- [ ] VFY-007 What happens at the block row limit: which rows drop, whether anything is shown, and what copy and find do near the edge. (BLK-149)
- [ ] VFY-008 Block context menu: full item list, order, labels and shortcuts, on finished, running, background and multi-selected blocks. (BLK-065)
- [ ] VFY-009 Mouse in alt-screen when reporting is on and off: scroll without reporting, right-click, middle-click, `⌘`-click on links, and what `Shift` bypasses. (MOU-158)
- [ ] VFY-010 The mouse gesture for adding a cursor on macOS, and the behaviour of typing, paste, undo and `Esc` with several cursors. (MOU-064, INP-064)

## Excluded

The line drawn for this spec, so it can be moved. Excluded means a Rewarp engineer doesn't need to build it. `docs/design.md` lists AI, agents, Warp Drive, accounts, cloud sync, teams, block sharing and telemetry as non-goals.

### AI and agents

- [ ] EXC-001 Agent Mode, conversations, conversation history, forking, rewind, planning, task lists, prompt queueing, agent questions, agent profiles and permissions.
- [ ] EXC-002 Universal input, natural language detection, `@` context menu, attaching blocks or selections as context, and images as context.
- [ ] EXC-003 Generate (`` ⌃` ``), AI command search, Active AI, Next Command, prompt suggestions, suggested code diffs, and intelligent autosuggestions.
- [ ] EXC-004 AI-related hints and footers: `⌘Enter` new agent, `⌘Y`, the message-bar hints, Use Agent footer, zero-state block, AI sparkles icon on blocks.
- [ ] EXC-005 Voice input, Rules, skills, MCP, codebase indexing, codebase context, memory, model selection, BYOK, custom endpoints, routers.
- [ ] EXC-006 Third-party CLI agent support: toolbar, rich input, brand icons, status badges, notifications, remote control.
- [ ] EXC-007 Agent notifications, needs-attention mailbox, agent status badges in vertical tabs.
- [ ] EXC-008 Computer use, web search, Warp's Agent CLI and TUI.
- [ ] EXC-009 Oz, the Automation Platform, cloud agents, environments, orchestration, Warp Factories, handoff.

### Warp Drive, cloud, account, team

- [ ] EXC-010 Warp Drive: notebooks, shared workflows, prompts, environment variables, folders, trash, import and export, web viewer.
- [ ] EXC-011 Workflow aliases, enum and dynamic arguments, and AI autofill, since they exist only for Drive workflows.
- [ ] EXC-012 Accounts, login, SSO, teams, admin panel, billing, credits, referrals.
- [ ] EXC-013 Settings Sync.
- [ ] EXC-014 Telemetry, crash reporting, the network log, and session-sharing.
- [ ] EXC-015 Warp on Web, Warp's `warpctrl` CLI.

### Straddlers

These aren't AI but touch excluded systems. Each note says what stays.

- [ ] EXC-016 Block sharing: permalinks, embeds, Share modal, `⇧⌘S`, Shared blocks settings. Excluded as cloud, per `docs/design.md`. A local "copy as HTML or Markdown" would be new work, not parity.
- [ ] EXC-017 Save as Workflow on a block saved to Drive, bound to `⌘S`. Could write a local YAML workflow instead. Excluded as specified. (changelog/2023.11.09; privacy/events)
- [ ] EXC-018 Secret redaction: display, reveal and copy behaviour is in scope. Redacting before sending to servers, and redacting in shared blocks, is out.
- [ ] EXC-019 Code Review: diff viewing, reverts and git operations are listed under [Git diff review](#git-diff-review). AI commit messages, sending comments to agents and interactive review are out.
- [ ] EXC-020 File tree and code editor: in this spec, except Attach as context and agent diff features.
- [ ] EXC-021 Vertical tabs: PR chips and diff stats stay. Agent badges, notification dots and conversation titles go.
- [ ] EXC-022 Configurable toolbar: agent management and notification mailbox buttons go.
- [ ] EXC-023 Command Search: `prompts:`, `ai_history:` filters and AI search go. History and local workflows stay.
- [ ] EXC-024 Command Palette: `prompts:`, `notebook:`, `env_vars:`, `drive:` filters go.
- [ ] EXC-025 Up-arrow menu tabs that split commands and prompts go, with commands only.
- [ ] EXC-026 Tab Configs: `agent` and `cloud` pane types and the create and update skills go. Worktree configs stay.
- [ ] EXC-027 `default_session_mode`: `agent`, `cloud_agent`, `docker_sandbox` values go.
- [ ] EXC-028 Slash menu: only the entries listed under [Slash commands in terminal mode](#slash-commands-in-terminal-mode) stay. Whether to keep a menu for so few entries is a product call.
- [ ] EXC-029 SSH extension (remote server): file tree, editor and git over SSH aren't AI, but it installs a companion server from Warp's host. Excluded. Rewarp's design defers remote integration.
- [ ] EXC-030 Docker extension and Raycast extension: third-party integrations with Warp's marketplace. Excluded, though the URI scheme stays so such extensions could be written.
- [ ] EXC-031 In-app changelog, Resource Center, onboarding, welcome block, tips: Warp product surfaces. Listed as optional under [Banners and transient UI](#banners-and-transient-ui).
- [ ] EXC-032 Auto-update service: Warp's own channel. Rewarp needs its own if distributed.
- [ ] EXC-033 Global workflows sourced from Warp's public repo: content, not behaviour. Search behaviour stays.
- [ ] EXC-034 Linux and Windows behaviour, Wayland, WSL, PowerShell on Windows, per `docs/design.md`. PowerShell on macOS is noted in [Shells](#shells) but design only commits to zsh, bash and fish.
- [ ] EXC-035 Agent and AI settings, full list: everything under `[agents]`, `[cloud_platform]` and `[warp_drive]`, plus `general.user_native_preference`, `terminal.show_terminal_zero_state_block`, `terminal.input.input_box_type_setting`, `terminal.input.at_context_menu_in_terminal_mode`, `terminal.input.outline_codebase_symbols_for_at_context_menu`, `appearance.text.ai_font_name`, `appearance.text.match_ai_font`, `appearance.text.notebook_font_size`, `appearance.text.match_notebook_to_monospace_font_size`, `appearance.vertical_tabs.use_latest_prompt_as_title`, `code.editor.auto_open_code_review_pane_on_first_agent_change`, `code.indexing.*`, `notifications.preferences.is_agent_task_completed_enabled`, `privacy.telemetry_enabled`, `privacy.crash_reporting_enabled`, `account.is_settings_sync_enabled`, `warpify.ssh.ssh_extension_install_mode`, `warpify.ssh.enable_legacy_ssh_wrapper`, `warpify.ssh.use_ssh_tmux_wrapper`, `system.preferred_graphics_backend`, `system.linux_selection_clipboard`, `system.force_x11`.
