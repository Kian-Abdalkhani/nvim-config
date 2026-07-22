return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		"hrsh7th/cmp-nvim-lsp",
	},
	config = function()
		local capabilities = require("cmp_nvim_lsp").default_capabilities()

		-- Global LSP keymaps: fires for ANY client attaching to ANY buffer,
		-- including rustaceanvim's rust-analyzer, gopls, lua_ls, etc.
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local opts = { buffer = args.buf, silent = true }
				vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
				vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
				vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
				vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
				vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
				vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
				vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
			end,
		})

		-- ─── Lua ────────────────────────────────────────────────────
		vim.lsp.config("lua_ls", {
			capabilities = capabilities,
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
		})

		-- ─── TypeScript ─────────────────────────────────────────────
		vim.lsp.config("ts_ls", {
			capabilities = capabilities,
			filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
			settings = {
				typescript = {
					inlayHints = {
						includeInlayParameterNameHints = "all",
						includeInlayFunctionResultTypeHints = true,
					},
				},
				javascript = {
					inlayHints = {
						includeInlayParameterNameHints = "all",
					},
				},
			},
		})
		-- ─── ESLint ─────────────────────────────────────────────────
		vim.lsp.config("eslint", {
			capabilities = capabilities,
			settings = {
				workingDirectories = { mode = "auto" },
			},
			on_attach = function(client, bufnr)
				-- auto-fix on save
				vim.api.nvim_create_autocmd("BufWritePre", {
					buffer = bufnr,
					callback = function()
						local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "eslint" })
						if #clients == 0 then
							return
						end
						pcall(vim.cmd, "EslintFixAll")
					end,
				})
			end,
		})
		-- ─── Tailwind CSS ───────────────────────────────────────────
		vim.lsp.config("tailwindcss", {
			capabilities = capabilities,
			filetypes = { "typescriptreact", "javascriptreact", "html", "css" },
			root_dir = function(bufnr, on_dir)
				local util = require("lspconfig.util")
				local root = util.root_pattern(
					"tailwind.config.js",
					"tailwind.config.ts",
					"tailwind.config.cjs",
					"tailwind.config.mjs",
					"postcss.config.js",
					"postcss.config.cjs",
					"package.json"
				)(vim.api.nvim_buf_get_name(bufnr))
				on_dir(root)
			end,
			settings = {
				tailwindCSS = {
					experimental = {
						classRegex = {
							{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
							{ "cx\\(([^)]*)\\)", "[\"'`]([^\"'`]*)[\"'`]" },
						},
					},
				},
			},
		})
		-- ─── HTML LSP  ───────────────────────────────────────────
		vim.lsp.config.emmet_language_server = {
			cmd = { "emmet-language-server", "--stdio" },
			filetypes = { "html", "css", "javascriptreact", "typescriptreact" },
			init_options = {
				includeLanguages = {},
				excludeLanguages = {},
				showAbbreviationSuggestions = true,
				showExpandedAbbreviation = "always",
			},
		}

		-- Enable all configured servers
		vim.lsp.enable({ "lua_ls", "gopls", "basedpyright", "ts_ls", "eslint", "tailwindcss", "emmet_language_server" })
	end,
}
