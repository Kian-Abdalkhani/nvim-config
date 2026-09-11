# Neovim configuration

A small, language-focused Neovim configuration managed by
[lazy.nvim](https://github.com/folke/lazy.nvim). The first launch bootstraps the
plugin manager, installs plugins from `lazy-lock.json`, and asks Mason to install
the configured language tools.

## Requirements

- Neovim 0.11 or newer (0.12 is recommended)
- Git
- ripgrep for Telescope text search
- Node.js for the TypeScript, ESLint, Tailwind, Emmet, and JavaScript debug tools
- A C compiler for Tree-sitter parsers when a prebuilt parser is unavailable
- A Rust toolchain with `rustfmt` for Rust formatting
- A Nerd Font for the configured UI icons

Database command-line clients are optional and only needed for the databases used
through vim-dadbod.

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
