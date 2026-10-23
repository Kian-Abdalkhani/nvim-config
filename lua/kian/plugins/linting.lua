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
				elseif vim.bo[args.buf].filetype == "go" then
					vim.api.nvim_buf_call(args.buf, function()
						local filename = vim.api.nvim_buf_get_name(args.buf)
						if
							filename == ""
							or vim.fn.executable("go") ~= 1
							or vim.fn.executable("golangci-lint") ~= 1
						then
							return
						end
						local directory = vim.fs.dirname(filename)
						local module_root = vim.fs.root(directory, "go.mod")
						local cwd = module_root or vim.fs.root(directory, "go.work") or directory
						lint.try_lint("golangcilint", {
							cwd = cwd,
							wrap_linter = function(linter)
								-- The built-in linter chooses its target once, using the cwd on first load.
								-- Resolve it per buffer so module packages include sibling files.
								linter.args[#linter.args] = module_root and directory or filename
								return linter
							end,
						})
					end)
				else
					lint.try_lint()
				end
			end,
		})
	end,
}
