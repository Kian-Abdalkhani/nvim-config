# Neovim configuration

A small, language-focused Neovim configuration managed by
[lazy.nvim](https://github.com/folke/lazy.nvim). The first launch bootstraps the
plugin manager, installs plugins from `lazy-lock.json`, and asks Mason to install
the configured language tools.

## Requirements

- Neovim 0.11.2 or newer (0.12 is recommended)
- Git
- ripgrep for Telescope text search
- Node.js for the TypeScript, ESLint, Tailwind, Emmet, and JavaScript debug tools
- A C compiler for Tree-sitter parsers when a prebuilt parser is unavailable
- A Rust toolchain with `rustfmt` for Rust formatting
- A Nerd Font for the configured UI icons

Neotest uses the test runner from each project: Python needs pytest or unittest,
Go needs the Go toolchain, Rust needs Cargo, and JavaScript/TypeScript projects
need Jest or Vitest installed locally.

Database command-line clients are optional and only needed for the databases used
through vim-dadbod.

For AI coding, install and authenticate the Claude Code and/or Codex CLI on the
machine running Neovim. Install tmux for persistent AI terminal sessions; without
it, Sidekick uses a native Neovim terminal.

## Install

Back up any existing Neovim configuration, then clone this repository:

```sh
git clone https://github.com/Kian-Abdalkhani/nvim-config ~/.config/nvim
nvim
```

The initial launch may take a few minutes while plugins, language servers,
formatters, linters, debug adapters, and Tree-sitter parsers are downloaded.
Run `:Lazy restore` to restore the exact plugin revisions from the lockfile and
`:MasonToolsInstall` to retry any missing language tools.

## Managed language tooling

Mason installs the configured Lua, Go, Python, TypeScript/JavaScript, Tailwind,
and Emmet language servers, along with the corresponding formatters, linters, and
debug adapters. `rustfmt` remains part of the external Rust toolchain because it
is not distributed through Mason.

## Everyday key bindings

See the [shortcut cheat sheet](KEYMAPS.md) for the complete quick reference.

### Completion

- `<C-Space>` opens completion or its documentation.
- `<C-j>` and `<C-k>` select the next and previous completion.
- `<CR>` accepts the selected completion; `<C-y>` selects and accepts the first
  item when needed.
- `<C-b>` and `<C-f>` scroll documentation.
- `<Tab>` and `<S-Tab>` move through snippet placeholders.
- `<C-s>` toggles signature help and `<C-e>` closes completion.

### Files and diagnostics

- `-` or `<leader>pv` opens Oil at the current file's directory. Edit names and
  paths like text, then write the buffer to apply filesystem changes.
- `<leader>fg` searches project text live as you type.
- `<leader>xx` opens workspace diagnostics and `<leader>xX` opens diagnostics for
  the current buffer.
- `<leader>cs` shows document symbols and `<leader>cl` shows LSP locations.
- `<leader>xL` and `<leader>xQ` show the location and quickfix lists.
- `<leader>fn` opens Fidget's notification history.

### Editing and code navigation

- Surround text with `ys{motion}{char}` (for example, `ysiw)`), remove a pair
  with `ds{char}`, or change one with `cs{old}{new}`.
- `am`/`im`, `ac`/`ic`, and `aa`/`ia` select around/inside a function, class,
  or parameter in visual mode or after an operator. In normal mode, use `dam`
  to delete a function or `yim` to yank its body; typing `am` or `im` alone
  starts Insert mode. In visual mode, press `v` before `am` or `im`.
- `<leader>mn` and `<leader>mp` jump to the next and previous function.
- `<leader>ms` and `<leader>mS` swap the current parameter with its next or
  previous neighbor.

### Git

- `]h` and `[h` move between changed hunks.
- `<leader>gs` stages a hunk and `<leader>gr` resets it; both work on visual
  selections. `<leader>gS` and `<leader>gR` apply to the entire buffer.
- `<leader>gp` previews a hunk, `<leader>gb` shows line blame, and `<leader>gd`
  diffs the buffer.
- `<leader>gt` toggles current-line blame and `<leader>gw` toggles word diff.
- `<leader>gg` opens Neogit.

`<C-a>` is intentionally left unmapped for tmux.

### AI coding agents

[Sidekick](https://github.com/folke/sidekick.nvim) opens the agent TUI in a
right-hand Neovim split. When tmux is installed, the split attaches to a persistent
tmux session, so hiding the terminal or quitting Neovim leaves the agent running.
Use `<leader>is` to select or reconnect to a session. Without tmux, quitting Neovim
ends its agent terminal.

- `<leader>ic` opens or toggles Claude Code; `<leader>ix` does the same for Codex.
- `<leader>ii` toggles an AI terminal; if several sessions are attached, choose one.
- `<leader>if` inserts the current file reference into an agent prompt.
- `<leader>iv` sends a Visual selection; `<leader>ip` opens the prompt menu in
  Normal or Visual mode. Review the inserted context and press Enter in the agent
  to submit it. If several sessions are attached, Sidekick asks which one to use.
- Inside the AI terminal, `<C-z>` returns to the editor without hiding it,
  `<C-.>` hides it if supported by your terminal, and `<C-q>` enters Normal mode.
  In Normal mode, `q` hides it. `<leader>id` detaches the selected session; with
  tmux, it remains available to reconnect.

Sidekick reloads externally changed files when their buffers have no unsaved
edits. Review repository changes with `<leader>gg` (Neogit), then
`:DiffviewOpen HEAD` for a project diff; `:DiffviewRefresh` refreshes the changed
file list. Existing Gitsigns shortcuts still work for individual files.

Copilot Next Edit Suggestions and Copilot status tracking are disabled; the AI
CLI workflow does not need Copilot. `:checkhealth sidekick` still checks Copilot
and may report a missing Copilot LSP server; that section is unrelated to this
CLI-only setup. The AI CLI sections check tmux and installed agent executables.

### Tests

- `<leader>tn` runs the nearest test; `<leader>tf` runs the current test file.
- `<leader>tl` reruns the last test; `<leader>td` debugs the nearest test with DAP.
- `<leader>ts` toggles the test summary; `<leader>to` shows test output.
