local M = {}

local config_names = { ".sqlfluff", "pyproject.toml", "setup.cfg", "tox.ini", "pep8.ini" }

local function config_file(directory)
	for _, name in ipairs(config_names) do
		local path = vim.fs.joinpath(directory, name)
		if vim.fn.filereadable(path) == 1 then
			if name == ".sqlfluff" then
				return path
			end
			for _, line in ipairs(vim.fn.readfile(path)) do
				if
					line:match("^%s*%[sqlfluff%]")
					or line:match("^%s*%[sqlfluff:")
					or line:match("^%s*%[tool%.sqlfluff%]")
					or line:match("^%s*%[tool%.sqlfluff%.")
				then
					return path
				end
			end
		end
	end
end

-- Share filename, dialect, and working directory between Conform and nvim-lint.
-- SQLFluff itself resolves nested configuration and templating settings.
function M.context(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	if vim.bo[bufnr].filetype ~= "sql" or vim.bo[bufnr].buftype ~= "" then
		return nil
	end
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local directory = filename ~= "" and vim.fs.dirname(filename) or vim.fn.getcwd()
	local config = config_file(directory)
	if not config then
		for parent in vim.fs.parents(directory) do
			config = config_file(parent)
			if config then
				break
			end
		end
	end
	local dialect = vim.b[bufnr].sql_dialect
	if not config and not dialect then
		return nil
	end
	return {
		filename = filename ~= "" and filename or vim.fs.joinpath(directory, "untitled.sql"),
		cwd = (config and vim.fs.dirname(config)) or vim.fs.root(directory, { ".sqls.yml", ".git" }) or directory,
		config = config,
		dialect = dialect,
	}
end

function M.args(action, bufnr)
	local context = assert(M.context(bufnr), "Choose :SQLDialect postgres or sqlite, or add a SQLFluff project config")
	local args = { action, "--stdin-filename", context.filename, "--nocolor", "--disable-progress-bar" }
	if action == "lint" then
		vim.list_extend(args, { "--format", "json" })
	end
	if context.dialect then
		vim.list_extend(args, { "--dialect", context.dialect })
		if not context.config then
			vim.list_extend(args, { "--templater", "raw" })
		end
	end
	args[#args + 1] = "-"
	return args
end

local function ready(bufnr, notify)
	local context = M.context(bufnr)
	if not context then
		if notify then
			vim.notify("Choose :SQLDialect postgres or sqlite, or add a SQLFluff project config", vim.log.levels.WARN)
		end
		return nil
	end
	if vim.fn.executable("sqlfluff") ~= 1 then
		if notify then
			vim.notify("SQLFluff is missing; run :MasonToolsInstall", vim.log.levels.WARN)
		end
		return nil
	end
	return context
end

function M.lint(bufnr, notify)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local context = ready(bufnr, notify)
	if context then
		vim.api.nvim_buf_call(bufnr, function()
			require("lint").try_lint("sqlfluff", { cwd = context.cwd })
		end)
	elseif package.loaded.lint then
		vim.diagnostic.reset(require("lint").get_namespace("sqlfluff"), bufnr)
	end
end

function M.setup()
	-- Homebrew's libpq is keg-only. Keep an existing psql first, otherwise expose
	-- only its client tools to Neovim without changing the user's shell profile.
	if vim.fn.executable("psql") == 0 then
		for _, directory in ipairs({ "/opt/homebrew/opt/libpq/bin", "/usr/local/opt/libpq/bin" }) do
			if vim.fn.executable(directory .. "/psql") == 1 then
				vim.env.PATH = directory .. ":" .. vim.env.PATH
				break
			end
		end
	end

	vim.api.nvim_create_user_command("SQLDialect", function(opts)
		if vim.bo.filetype ~= "sql" then
			vim.notify("SQLDialect is available in SQL buffers", vim.log.levels.WARN)
			return
		end
		if opts.args == "" then
			local context = M.context(0)
			vim.notify("SQL dialect: " .. (vim.b.sql_dialect or (context and context.config) or "not configured"))
			return
		end
		if opts.args ~= "postgres" and opts.args ~= "sqlite" and opts.args ~= "clear" then
			vim.notify("Use :SQLDialect postgres, sqlite, or clear", vim.log.levels.WARN)
			return
		end
		vim.b.sql_dialect = opts.args ~= "clear" and opts.args or nil
		require("kian.sql_schema.index").invalidate(vim.api.nvim_get_current_buf())
		M.lint(vim.api.nvim_get_current_buf(), false)
	end, {
		nargs = "?",
		complete = function()
			return { "postgres", "sqlite", "clear" }
		end,
		desc = "Set this SQL buffer's dialect or return to project configuration",
	})
	vim.api.nvim_create_user_command("SQLFormat", function()
		local bufnr = vim.api.nvim_get_current_buf()
		if ready(bufnr, true) then
			require("conform").format({ bufnr = bufnr, async = true, lsp_format = "never" })
		end
	end, { desc = "Format SQL asynchronously with SQLFluff" })
	vim.api.nvim_create_user_command("SQLLint", function()
		M.lint(vim.api.nvim_get_current_buf(), true)
	end, { desc = "Lint SQL with SQLFluff" })
	require("kian.sql_schema").setup()
end

return M
