return {
	"mrcjkb/rustaceanvim",
	version = "^9",
	lazy = false,
	dependencies = { "hrsh7th/cmp-nvim-lsp" },
	init = function()
		vim.g.rustaceanvim = {
			server = {
				capabilities = require("cmp_nvim_lsp").default_capabilities(),
				on_attach = function(client, _)
					client.server_capabilities.semanticTokensProvider = nil
				end,
				default_settings = {
					["rust-analyzer"] = {
						check = {
							command = "clippy",
						},
					},
				},
			},
		}
	end,
}
