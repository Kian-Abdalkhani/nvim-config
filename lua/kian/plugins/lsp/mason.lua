return {
	{
		"mason-org/mason.nvim",
		lazy = false,
		build = ":MasonUpdate",
		opts = {
			registries = {
				"lua:kian.mason_registry",
				"github:mason-org/mason-registry",
			},
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		},
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		lazy = false,
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = {
				-- LSP servers
				"lua-language-server",
				"gopls",
				"basedpyright",
				"rust-analyzer",
				"typescript-language-server",
				"eslint-lsp",
				"tailwindcss-language-server",
				"emmet-language-server",
				"sqls",

				-- Formatters and linters
				"stylua",
				"goimports",
				"gofumpt",
				"ruff",
				"prettier",
				{ "luacheck", version = "1.2.0" },
				"golangci-lint",
				"sqlfluff",

				-- Debug adapters
				"debugpy",
				"delve",
				"js-debug-adapter",
				"codelldb",
			},
			auto_update = false,
			run_on_start = true,
			start_delay = 1000,
			debounce_hours = 24,
			integrations = {
				["mason-lspconfig"] = false,
				["mason-null-ls"] = false,
				["mason-nvim-dap"] = false,
			},
		},
	},
}
