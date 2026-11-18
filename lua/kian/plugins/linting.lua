local function swiftlint_config(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	if filename == "" or vim.bo[bufnr].buftype ~= "" then
		return nil
	end
	return vim.fs.find(".swiftlint.yml", { path = vim.fs.dirname(filename), upward = true, type = "file" })[1]
end

local function swiftlint_env()
	if vim.fn.has("mac") ~= 1 or vim.env.XCODE_DEFAULT_TOOLCHAIN_OVERRIDE or vim.env.TOOLCHAIN_DIR then
		return nil
	end
	local result = vim.system({ "/usr/bin/xcrun", "--find", "swift" }, { text = true }):wait(1000)
	local toolchain = result.code == 0 and vim.trim(result.stdout):match("^(.*)/usr/bin/swift$")
	if toolchain == "/Library/Developer/CommandLineTools" then
		-- SourceKitten skips the Command Line Tools path when discovering toolchains.
		return vim.tbl_extend("force", vim.fn.environ(), { TOOLCHAIN_DIR = toolchain })
	end
end

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
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
			desc = "Run SwiftLint when the file has a project configuration",
			group = lint_group,
			pattern = "*.swift",
			callback = function(args)
				if vim.bo[args.buf].filetype ~= "swift" then
					return
				end
				local config = swiftlint_config(args.buf)
				if not config or vim.fn.executable("swiftlint") ~= 1 then
					vim.diagnostic.reset(lint.get_namespace("swiftlint"), args.buf)
					return
				end
				vim.api.nvim_buf_call(args.buf, function()
					lint.try_lint("swiftlint", {
						cwd = vim.fs.dirname(config),
						wrap_linter = function(linter)
							-- The built-in adapter caches the first config it finds.
							linter.stdin = false
							linter.args =
								{ "lint", "--quiet", "--force-exclude", "--reporter", "xcode", "--config", config }
							linter.env = swiftlint_env() or linter.env
							local parser = linter.parser
							linter.parser = function(output, bufnr, cwd)
								if swiftlint_config(bufnr) ~= config then
									return {}
								end
								return parser(output, bufnr, cwd)
							end
							return linter
						end,
					})
				end)
			end,
		})
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
