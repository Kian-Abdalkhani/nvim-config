# Neovim shortcut cheat sheet

`<leader>` is **Space**. Shortcuts are for Normal mode unless a mode is noted.
Uppercase letters matter. `<C-…>` means Ctrl; `<CR>` means Enter.
This lists shortcuts enabled by this config; plugin windows may have more.

## Find, open, and navigate

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `-`, `<leader>pv` | Browse the current file's directory | Oil |
| `<leader>pf`, `<C-p>` | Find a project file, or a Git-tracked file | Telescope |
| `<leader>ps`, `<leader>fg` | Search text once, or search live as you type | Telescope |
| `<leader>a`, `<C-e>` | Add the current file to Harpoon, or open its menu | Harpoon |
| `<C-h/j/k/l>` | Open Harpoon file 1/2/3/4 | Harpoon |
| `<C-S-P>`, `<C-S-N>` | Previous/next Harpoon file | Harpoon |
| `<C-\>`, `<C-_>` | Toggle the terminal | ToggleTerm |
| `<leader>v`, `<leader>h` | Open a vertical/horizontal split | Core |
| `<leader>we`, `<leader>wq` | Equalize splits, or close a split | Core |
| `<C-Left/Right/Up/Down>` | Resize the current split | Core |

## Edit text

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `ys{motion}{char}` | Add surrounding text; `ysiw)` wraps a word in `()` | Surround |
| `ds{char}`, `cs{old}{new}` | Delete or change a surrounding pair | Surround |
| `S{char}` (Visual) | Surround the selection | Surround |
| `am`/`im`, `ac`/`ic`, `aa`/`ia` | Around/inside function, class, or parameter | Tree-sitter text objects |
| `<leader>mn`, `<leader>mp` | Next/previous function | Tree-sitter text objects |
| `<leader>ms`, `<leader>mS` | Swap parameter with next/previous | Tree-sitter text objects |
| `<leader>u` | Toggle undo history | Undotree |
| `J`/`K` (Visual) | Move selected lines down/up | Core |
| `<leader>p` (Visual) | Paste without replacing the unnamed register | Core |
| `<leader>y` (Normal/Visual), `<leader>Y` (Normal) | Copy selection/line to system clipboard | Core |

Text objects work **after an operator** or **in Visual mode**: `dam` deletes a
function, `yim` yanks its body, and `vam` selects a function. Typing `am` alone
in Normal mode enters Insert mode. A matching Tree-sitter parser and code
structure are required.

## Code intelligence and diagnostics

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `gd`, `gr`, `K` | Definition, references, hover help | LSP |
| `<leader>rn`, `<leader>ca` | Rename symbol, code action | LSP |
| `[d`, `]d` | Previous/next diagnostic | LSP |
| `<leader>xx`, `<leader>xX` | Workspace/current-buffer diagnostics | Trouble |
| `<leader>cs`, `<leader>cl` | Document symbols, LSP locations | Trouble |
| `<leader>xL`, `<leader>xQ` | Location list, quickfix list | Trouble |
| `<leader>fn` | Notification history | Fidget |

LSP shortcuts are available only when a language server attaches to the buffer.

### Completion (Insert mode)

| Shortcut | Action |
| --- | --- |
| `<C-Space>` | Show completion or documentation |
| `<C-j>` / `<C-k>` | Next/previous suggestion |
| `<CR>` / `<C-y>` | Accept selection / select and accept first suggestion |
| `<C-b>` / `<C-f>` | Scroll documentation up/down |
| `<Tab>` / `<S-Tab>` | Next/previous snippet placeholder |
| `<C-s>` / `<C-e>` | Toggle signature help / close completion |

These are Blink mappings. Autopairs and tag closing work automatically while typing.

## SQL commands

| Command | Action |
| --- | --- |
| `:SQLDialect postgres`, `:SQLDialect sqlite` | Select a buffer dialect, including standalone SQL files |
| `:SQLDialect clear` | Remove the buffer override and use project settings |
| `:SQLFormat` | Format the current SQL buffer asynchronously |
| `:SQLLint` | Run SQLFluff diagnostics for the current SQL buffer |
| `:SQLTables` | Search the current file's table outline with source previews |
| `:SQLColumns [table]` | List columns for the current or named table, or all columns |
| `:SQLDefinition` | Follow a schema declaration or foreign-key identifier |
| `:SQLReferences [table]` | List incoming foreign-key references to a table or column |
| `:SQLRelations [table]` | Browse incoming and outgoing foreign keys |
| `:SQLSchemaIssues` | Show parse problems and partial-index limitations |
| `:SQLSchemaRefresh` | Rebuild the current buffer's offline schema index |
| `:ConformInfo` | Inspect formatter availability |
| `:DBUI`, `:DBUIToggle` | Open or toggle Dadbod's database UI |
| `:DBUIAddConnection` | Add a database connection |
| `:%DB` | Execute the current buffer against its selected database |
| `:'<,'>DB` (Visual range) | Execute the selected SQL |

SQL formatting runs on save once a dialect is configured, and SQL linting runs
on opening and saving files. Project `.sqlfluff` settings select `postgres` or
`sqlite`; use `:SQLDialect` for a buffer override. Schema completion uses the
development database selected in the project's `.sqls.yml`; Dadbod has its
own connection selection. See [SQL setup](README.md#postgresql-and-sqlite).
In a Dadbod result window, `R` reruns the query and `gq` closes the result.

Offline schema navigation uses the selected PostgreSQL or SQLite dialect and the
current buffer, including unsaved edits. It needs no database connection. The
first navigation command activates an index that refreshes after edits. Existing
LSP keymaps are unchanged. In `:SQLRelations`, selecting an outgoing relationship
jumps to its target, while an incoming relationship jumps to its source reference.
Inspect `:SQLSchemaIssues` when the index reports partial coverage. See
[offline schema analysis](README.md#offline-schema-analysis).

## Git

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `]h`, `[h` | Next/previous changed hunk | Gitsigns |
| `<leader>gs`, `<leader>gr` | Stage/reset hunk (also works on Visual selection) | Gitsigns |
| `<leader>gS`, `<leader>gR` | Stage/reset entire buffer | Gitsigns |
| `<leader>gp`, `<leader>gb` | Preview hunk, show line blame | Gitsigns |
| `<leader>gd`, `<leader>gD` | Diff against index/parent | Gitsigns |
| `<leader>gt`, `<leader>gw` | Toggle line blame/word diff | Gitsigns |
| `<leader>gg` | Open Git interface | Neogit |

## AI coding agents

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `<leader>ic`, `<leader>ix` | Open/toggle Claude Code or Codex | Sidekick |
| `<leader>ii` | Toggle an AI terminal; choose if several are attached | Sidekick |
| `<leader>is` | Select an installed agent or reconnect to a session | Sidekick |
| `<leader>if` | Insert the current file reference into an agent prompt | Sidekick |
| `<leader>iv` (Visual) | Insert the selection into an agent prompt | Sidekick |
| `<leader>ip` (Normal/Visual) | Choose a prompt, including diagnostics and code review | Sidekick |
| `<leader>id` | Detach an AI session; tmux keeps it running | Sidekick |

Context is inserted without submitting; press Enter in the agent to send it.
When multiple sessions are attached, choose the recipient. Inside an AI terminal,
`<C-z>` returns to the editor, `<C-q>` enters Normal mode, and Normal-mode `q`
hides the split. With tmux installed, sessions survive hiding or quitting Neovim;
otherwise the native terminal ends when Neovim exits. Copilot suggestions are
disabled, and existing Harpoon and completion mappings are unchanged.

## Tests and debugging

| Shortcut | Action | Plugin |
| --- | --- | --- |
| `<leader>tn`, `<leader>tf`, `<leader>tl` | Run nearest test, file, or last test | Neotest |
| `<leader>td` | Debug nearest test | Neotest + DAP |
| `<leader>ts`, `<leader>to` | Toggle test summary, show output | Neotest |
| `<leader>db`, `<leader>dc` | Toggle breakpoint, continue | DAP |
| `<leader>di`, `<leader>do`, `<leader>dO` | Step into, over, out | DAP |
| `<leader>dr`, `<leader>du` | Toggle debug REPL/UI | DAP |

## Plugins without a configured shortcut

- `:Lazy` opens the plugin manager; `:Mason` manages language tools.
- `:ConformInfo` shows formatter status. Formatting and linting run automatically.
- Tree-sitter highlighting, Todo comments, Rose Pine, Lualine, Rust support,
  completion for SQL, debug overlays, and plugin dependencies run without a
  dedicated top-level mapping in this config.

`<C-a>` is left unmapped for tmux. Use a plugin window's own help for its local keys.
