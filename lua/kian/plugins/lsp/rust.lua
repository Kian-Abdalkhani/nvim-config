return {
	"mrcjkb/rustaceanvim",
	version = "^6",
	lazy = false,
	ft = { "rust" },
	config = function()
		vim.g.rustaceanvim = {
			server = {
				capabilities = require("cmp_nvim_lsp").default_capabilities(),
				on_attach = function(client, _)
					client.server_capabilities.semanticTokensProvider = nil
				end,
				settings = {
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
