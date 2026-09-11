return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
	},
	config = function()
		local capabilities = require("cmp_nvim_lsp").default_capabilities()

		local lsp_group = vim.api.nvim_create_augroup("kian-lsp-attach", { clear = true })
		vim.api.nvim_create_autocmd("LspAttach", {
			desc = "Configure LSP keymaps",
			group = lsp_group,
			callback = function(args)
				local function map(lhs, rhs, desc)
					vim.keymap.set("n", lhs, rhs, { buffer = args.buf, silent = true, desc = desc })
				end

				map("gd", vim.lsp.buf.definition, "Go to definition")
				map("gr", vim.lsp.buf.references, "List references")
				map("K", vim.lsp.buf.hover, "Show hover documentation")
				map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
				map("<leader>ca", vim.lsp.buf.code_action, "Code action")
				map("[d", function()
					vim.diagnostic.jump({ count = -1, float = true })
				end, "Previous diagnostic")
				map("]d", function()
					vim.diagnostic.jump({ count = 1, float = true })
				end, "Next diagnostic")
			end,
		})

		local servers = { "lua_ls", "gopls", "basedpyright", "ts_ls", "eslint", "tailwindcss", "emmet_language_server" }
		for _, server in ipairs(servers) do
			local config = require("kian.lsp.servers." .. server)
			config.capabilities = capabilities
			vim.lsp.config(server, config)
		end

		vim.lsp.enable(servers)
	end,
}
