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
- Python 3 for SQLFluff and Python tooling
- A Go toolchain for SQLs installation
- LuaRocks and Lua 5.4 with development headers for Mason's LuaCheck installation
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
Emmet, and SQL language servers, along with the corresponding formatters, linters,
and debug adapters. SQL uses `sqls` and SQLFluff. `rustfmt` remains part of the
external Rust toolchain because it is not distributed through Mason.

LuaCheck uses a small local Mason recipe that installs version 1.2.0 with Lua 5.4;
Lua 5.5 rejects assignments to loop variables in LuaCheck's current releases.
On macOS, run `brew install luarocks lua@5.4`. The recipe finds Homebrew's Lua 5.4
on Apple Silicon or Intel Macs, or a standard `lua5.4` installation on PATH. This
selects the runtime only for LuaCheck and leaves the system Lua configuration
unchanged. LuaCheck remains installed and managed through Mason.
The repository's `.luacheckrc` selects LuaJIT and recognizes Neovim's `vim` global;
other Lua projects retain their own LuaCheck settings.

## PostgreSQL and SQLite

SQL files use Tree-sitter highlighting and indentation, Blink completion, SQLFluff
formatting and linting, and Dadbod for queries. The shared
[SQLs language server](https://github.com/sqls-server/sqls) supplies completion
and hover help, and starts only in projects containing `.sqls.yml`. Completion
uses the schema of the connected database; unapplied migration files do not create
that schema.
Dadbod completion remains available when the SQL language server is not attached.

Dadbod needs `sqlite3` for SQLite and `psql` for PostgreSQL. On macOS, install the
PostgreSQL client and expose it to the terminal running Neovim:

```sh
brew install libpq
export PATH="$(brew --prefix libpq)/bin:$PATH"
```

This configuration also finds Homebrew's keg-only `libpq` client directory on
Apple Silicon and Intel Macs when `psql` is absent from Neovim's PATH. The export
above is useful for running `psql` directly in your shell.

### Project dialect and formatting

Place a `.sqlfluff` file in the project, using `postgres` or `sqlite` as appropriate:

```ini
[sqlfluff]
dialect = postgres
templater = raw
```

Existing SQLFluff configuration in `.sqlfluff`, `pyproject.toml`, and supported
INI files is respected. Use the project's templater when its SQL contains
templates. Formatting and linting receive the SQL file's path so nested settings
are resolved from that file. See [SQLFluff configuration](https://docs.sqlfluff.com/en/stable/configuration/).

For a standalone file, use `:SQLDialect postgres` or `:SQLDialect sqlite`.
`:SQLDialect clear` removes the buffer override and returns to project settings.
An unconfigured file is not assigned a dialect automatically.

SQL formatting runs on save with its own timeout; `:SQLFormat` formats the current
buffer asynchronously. SQLFluff handles formatting, while SQL linting runs on
opening and saving files rather than each time Insert mode ends. `:SQLLint` runs
it manually, and `:ConformInfo` shows formatter availability. SQLFluff diagnostics
appear in the existing diagnostic and Trouble views.

### Offline schema analysis

For a single schema file, start with:

```text
nvim schema.sql
:SQLDialect postgres
:SQLTables
:SQLColumns
:SQLRelations
```

Use `:SQLDialect sqlite` for a SQLite schema. A project `.sqlfluff` can select the
dialect instead. The offline index uses the SQLFluff Python installation already
managed by Mason and reads the current buffer, including unsaved edits. It needs
no database connection, and indexing does not execute SQL or write the file.

- `:SQLTables` opens a searchable table outline with source previews.
- `:SQLColumns [table]` lists columns for the table at the cursor, or all columns
  when there is no current table. An optional table name selects that table.
- `:SQLDefinition` follows the table or column identifier under the cursor in
  schema declarations and foreign keys.
- `:SQLReferences [table]` lists incoming foreign-key references to the table or
  column at the cursor. With no current symbol, it lists all references.
- `:SQLRelations [table]` lists incoming and outgoing foreign keys. Select an
  outgoing relationship to visit its target declaration, or an incoming one to
  visit the source reference.
- `:SQLSchemaIssues` shows parsing problems and index limitations in a location
  list; `:SQLSchemaRefresh` explicitly rebuilds the index.

The first navigation command activates indexing for that buffer. Subsequent edits
refresh it asynchronously after a short delay. These commands have no new
keymaps, so the existing LSP shortcuts keep their meanings.

The index supports raw PostgreSQL and SQLite schema declarations: `CREATE TABLE`,
column types, primary keys, inline and table-level foreign keys, composite keys,
and common `ALTER TABLE ADD COLUMN` / `ADD CONSTRAINT` forms. Quoted and qualified
names are retained. Missing or ambiguous references are shown without guessing a
target. Unsupported schema changes, dynamic or templated SQL, and parse errors
mark the index as partial; inspect `:SQLSchemaIssues` before relying on its
coverage. This navigation describes declarations in the current file, rather
than validating an entire database or analyzing arbitrary queries.

### Verify offline schema indexing

With the configured plugins and Mason's SQLFluff installed, run these checks from
the repository root:

```sh
~/.local/share/nvim/mason/packages/sqlfluff/venv/bin/python -m unittest discover -s tests/sql_schema
nvim --headless -i NONE -u tests/sql_schema_init.lua "+lua dofile('tests/sql_schema_nvim.lua')" +qa!
nvim --headless -u NONE -i NONE -l tests/sql_schema_cache.lua
```

These cover schema extraction, the real Neovim navigation UI, and asynchronous
cache/lifecycle behavior. The UI bootstrap disables package installation and
update checks and isolates editor state/cache directories. Schema fixtures are
temporary.
Adjust the Python path if Mason uses a custom installation directory.

### Database connections

Create `.sqls.yml` in a PostgreSQL development project's root:

```yaml
connections:
  - alias: app-postgres-dev
    driver: postgresql
    dataSourceName: "host=127.0.0.1 port=5432 user=app_dev dbname=app_dev"
```

Keep PostgreSQL passwords outside the project file, using a local `.pgpass` file
or Neovim's `PGPASSWORD` environment variable. SQLs does not expand variables
inside YAML values. For a SQLite project, use an existing development database's
absolute path instead:

```yaml
connections:
  - alias: app-sqlite-dev
    driver: sqlite3
    dataSourceName: "/absolute/path/to/app-dev.sqlite3"
```

Restart Neovim after creating or changing the connection file. Use a development
database; connection settings and queries are independent of dialect selection.

Dadbod has its own connection selection. Use `:DBUI` and `:DBUIAddConnection`, or
set the current SQL buffer's connection directly:

```vim
:let b:db = 'postgresql://app_dev@127.0.0.1:5432/app_dev'
:let b:db = 'sqlite:/absolute/path/to/app-dev.sqlite3'
```

Choose one connection above. PostgreSQL query credentials follow `psql`'s normal
configuration, such as a local password file. `:%DB` executes the buffer;
`:'<,'>DB` executes a Visual selection. Results open in a preview window, where
`R` reruns the query and `gq` closes the result. Queries run only when requested.

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
