local mac = vim.fn.has("mac") == 1

return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			go = { "goimports", "gofumpt" },
			python = { "ruff_format" },
			typescript = { "prettier" },
			javascript = { "prettier" },
			typescriptreact = { "prettier" },
			javascriptreact = { "prettier" },
			html = { "prettier" },
			css = { "prettier" },
			json = { "prettier" },
			jsonc = { "prettier" },
			yaml = { "prettier" },
			markdown = { "prettier" },
			rust = { "rustfmt" },
			swift = { "swift_format" },
			sql = { "sqlfluff" },
		},
		formatters = {
			swift_format = {
				command = mac and "xcrun" or "swift-format",
				-- The original filename lets swift-format find the nearest .swift-format.
				args = mac and { "swift-format", "format", "--assume-filename", "$FILENAME", "-" }
					or { "format", "--assume-filename", "$FILENAME", "-" },
				stdin = true,
			},
			sqlfluff = {
				args = function(_, ctx)
					return require("kian.sql").args("format", ctx.buf)
				end,
				cwd = function(_, ctx)
					local context = require("kian.sql").context(ctx.buf)
					return context and context.cwd
				end,
				require_cwd = false,
				condition = function(_, ctx)
					return require("kian.sql").context(ctx.buf) ~= nil
				end,
			},
		},
		format_on_save = function(bufnr)
			local filetype = vim.bo[bufnr].filetype
			if filetype == "sql" then
				if require("kian.sql").context(bufnr) then
					return { timeout_ms = 2000, lsp_format = "never" }
				end
				return nil
			end
			return { timeout_ms = filetype == "swift" and 3000 or 500, lsp_format = "fallback" }
		end,
	},
}
