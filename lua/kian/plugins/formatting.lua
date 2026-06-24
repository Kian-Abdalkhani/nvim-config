return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	config = function()
		require("conform").setup({
			formatters_by_ft = {
				lua = { "stylua" },
				go = { "goimports", "gofumpt" },
				python = { "ruff" },
				typescript = { "prettier" },
				javascript = { "prettier" },
				rust = { "rustfmt" },
			},
			formatters = {
				rustfmt = {
					command = "cargo",
					args = { "fmt", "--" },
				},
			},
			format_on_save = {
				timeout_ms = 500,
				lsp_fallback = true, -- fall back to LSP formatting if no formatter defined
			},
		})
	end,
}
