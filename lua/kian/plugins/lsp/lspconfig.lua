return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
	},
	config = function()
		local capabilities = require("cmp_nvim_lsp").default_capabilities()

		-- Shared on_attach: runs whenever an LSP attaches to a buffer
		local on_attach = function(_, bufnr)
			local opts = { buffer = bufnr, silent = true }
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
			vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
			vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
			vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
			vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
		end

		-- ─── Lua ────────────────────────────────────────────────────
		vim.lsp.config("lua_ls", {
			capabilities = capabilities,
			on_attach = on_attach,
			settings = {
				Lua = {
					runtime = { version = "LuaJIT" },
					diagnostics = { globals = { "vim" } },
					workspace = {
						library = vim.api.nvim_get_runtime_file("", true),
						checkThirdParty = false,
					},
					telemetry = { enable = false },
				},
			},
		})

		-- ─── Go ─────────────────────────────────────────────────────
		vim.lsp.config("gopls", {
			capabilities = capabilities,
			on_attach = on_attach,
			settings = {
				gopls = {
					analyses = { unusedparams = true },
					staticcheck = true,
				},
			},
		})

		-- ─── Python ─────────────────────────────────────────────────
		vim.lsp.config("basedpyright", {
			capabilities = capabilities,
			on_attach = on_attach,
		})
		-- Enable all configured servers
		vim.lsp.enable({ "lua_ls", "gopls", "basedpyright" })
	end,
}
