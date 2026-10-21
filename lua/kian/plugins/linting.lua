return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")

		lint.linters_by_ft = {
			lua = { "luacheck" },
			go = { "golangcilint" },
			python = { "ruff" },
			sql = { "sqlfluff" },
		}
		lint.linters.sqlfluff = function()
			local linter = vim.deepcopy(require("lint.linters.sqlfluff"))
			linter.args = require("kian.sql").args("lint", 0)
			local parser = linter.parser
			linter.parser = function(output, bufnr)
				if not require("kian.sql").context(bufnr) then
					return {}
				end
				return parser(output, bufnr)
			end
			return linter
		end

		local lint_group = vim.api.nvim_create_augroup("kian-lint", { clear = true })
		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			desc = "Lint current buffer",
			group = lint_group,
			callback = function(args)
				if vim.bo[args.buf].filetype == "sql" then
					if args.event ~= "InsertLeave" then
						require("kian.sql").lint(args.buf, false)
					end
				else
					lint.try_lint()
				end
			end,
		})
	end,
}
