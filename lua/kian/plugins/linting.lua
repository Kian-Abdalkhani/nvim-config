return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")

		lint.linters_by_ft = {
			lua = { "luacheck" },
			go = { "golangcilint" },
			python = { "ruff" },
		}

		local lint_group = vim.api.nvim_create_augroup("kian-lint", { clear = true })
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			desc = "Lint current buffer",
			group = lint_group,
			callback = function()
				lint.try_lint()
			end,
		})
	end,
}
