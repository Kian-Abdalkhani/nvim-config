return {
	"mrcjkb/rustaceanvim",
	version = "^9",
	lazy = false,
	dependencies = { "saghen/blink.cmp" },
	init = function()
		vim.g.rustaceanvim = {
			server = {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
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
