-- Run from the config root:
-- nvim --headless -u NONE -i NONE -l tests/sql_schema_cache.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(repository)
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.XDG_CACHE_HOME = root .. "/cache"
vim.env.NVIM_LOG_FILE = root .. "/nvim.log"
vim.fn.writefile({ "[sqlfluff]", "dialect=postgres", "templater=raw" }, root .. "/.sqlfluff")
vim.fn.writefile({ "CREATE TABLE disk_old (id INTEGER);" }, root .. "/schema.sql")
local original_system = vim.system
local calls = {}
vim.system = function(args, opts, callback)
	local call = { args = args, opts = opts, callback = callback }
	calls[#calls + 1] = call
	return {
		kill = function(_, signal)
			call.killed = signal
		end,
	}
end
local function result(label, options)
	return vim.tbl_extend("force", {
		code = 0,
		stdout = vim.json.encode({
			version = 1,
			dialect = "postgres",
			partial = false,
			issues = {},
			tables = { { id = label, name = label } },
			foreign_keys = {},
			occurrences = {},
		}),
		stderr = "",
	}, options or {})
end
local function finish(number, label, options)
	calls[number].callback(result(label, options))
	vim.wait(50, function()
		return false
	end, 5)
end
local checks = 0
local function check(name, passed)
	assert(passed, name)
	checks = checks + 1
end
local ok, err = xpcall(function()
	local index = require("kian.sql_schema.index")
	index.setup()
	vim.cmd.edit(root .. "/schema.sql")
	vim.bo.filetype = "sql"
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	vim.wait(450, function()
		return false
	end, 10)
	check("No parse before feature activation", #calls == 0)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE unsaved (id INTEGER);" })
	local first, second
	index.get(buf, function(value, e)
		first = value or e
	end)
	index.get(buf, function(value, e)
		second = value or e
	end)
	check("Concurrent requests coalesced", #calls == 1)
	local request = vim.json.decode(calls[1].opts.stdin)
	check("Unsaved source sent through stdin", request.source == "CREATE TABLE unsaved (id INTEGER);\n")
	check("Parser uses project working directory", calls[1].opts.cwd == root)
	check("Parser has 30 second timeout", calls[1].opts.timeout == 30000)
	finish(1, "unsaved")
	check("Coalesced callbacks resolved", first.tables[1].name == "unsaved" and second == first)
	check(
		"Cache includes buffer identity and changedtick",
		first.bufnr == buf and first.changedtick == vim.api.nvim_buf_get_changedtick(buf)
	)
	local cached
	index.get(buf, function(value)
		cached = value
	end)
	check("Fresh cache avoids parser launch", #calls == 1 and cached == first and index.peek(buf) == first)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE newer (id INTEGER);" })
	check("Stale cache is never exposed", index.peek(buf) == nil)
	local newer, newest
	index.get(buf, function(value, e)
		newer = value or e
	end)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE newest (id INTEGER);" })
	index.get(buf, function(value, e)
		newest = value or e
	end)
	check("Obsolete parser cancelled", calls[2].killed == 15 and #calls == 3)
	finish(2, "old")
	check("Cancelled parser cannot overwrite newer state", newer == nil and newest == nil and index.peek(buf) == nil)
	finish(3, "newest")
	check("Callbacks follow latest source", newer.tables[1].name == "newest" and newest == newer)
	local following
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE before_finish (id INTEGER);" })
	index.get(buf, function(value, e)
		following = value or e
	end)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE after_finish (id INTEGER);" })
	finish(4, "before_finish")
	check("Edit during parse automatically requests latest", #calls == 5 and following == nil)
	finish(5, "after_finish")
	check("Waiting command receives latest result", following.tables[1].name == "after_finish")
	vim.b.sql_dialect = "sqlite"
	local switched
	index.get(buf, function(value, e)
		switched = value or e
	end)
	check("Dialect change invalidates cache", #calls == 6 and vim.json.decode(calls[6].opts.stdin).dialect == "sqlite")
	finish(6, "sqlite")
	check("Dialect request callback resolved", switched.tables[1].name == "sqlite")
	vim.uv.fs_utime(root .. "/.sqlfluff", 123456789, 123456789)
	index.get(buf)
	check("Project config mtime invalidates cache", #calls == 7)
	finish(7, "config_changed")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE auto_refresh (id INTEGER);" })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	check("Activated refresh is debounced", #calls == 7)
	check(
		"Latest event triggers one refresh",
		vim.wait(1000, function()
			return #calls == 8
		end, 20)
	)
	finish(8, "auto_refresh")
	index.invalidate(buf)
	check("Explicit invalidation launches fresh parse", #calls == 9 and index.peek(buf) == nil)
	finish(9, "invalidated")
	local error_message
	index.refresh(buf, function(value, e)
		error_message = value or e
	end)
	calls[10].callback({ code = 1, stdout = "", stderr = "missing dependency" })
	vim.wait(50, function()
		return false
	end, 5)
	check(
		"Parser failures are actionable",
		type(error_message) == "string" and error_message:find("missing dependency", 1, true)
	)
	local partial
	index.get(buf, function(value)
		partial = value
	end)
	finish(11, "partial", { code = 1 })
	check("Structured partial results retained with issue", partial.partial and #partial.issues == 1)
	local wiped, wiped_calls = nil, 0
	index.refresh(buf, function(value, e)
		wiped, wiped_calls = value or e, wiped_calls + 1
	end)
	vim.api.nvim_buf_delete(buf, { force = true })
	check("Buffer wipe cancels parser", calls[12].killed == 15)
	check("Buffer wipe resolves callbacks", wiped_calls == 1 and wiped:find("closed", 1, true))
	finish(12, "too_late")
	check("Late result cannot repeat closed callback", wiped_calls == 1)
	vim.fn.mkdir(root .. "/parent/nested", "p")
	vim.fn.writefile({ "[sqlfluff]", "dialect=postgres" }, root .. "/parent/.sqlfluff")
	vim.fn.writefile({ "[tool.sqlfluff.core]", 'templater="raw"' }, root .. "/parent/nested/pyproject.toml")
	vim.fn.writefile({ "CREATE TABLE inherited (id INTEGER);" }, root .. "/parent/nested/schema.sql")
	vim.cmd.edit(root .. "/parent/nested/schema.sql")
	vim.bo.filetype = "sql"
	local nested = vim.api.nvim_get_current_buf()
	index.get(nested)
	check("Nearest nested SQLFluff config selected", calls[13].opts.cwd == root .. "/parent/nested")
	finish(13, "inherited")
	vim.uv.fs_utime(root .. "/parent/.sqlfluff", 987654321, 987654321)
	index.get(nested)
	check("Inherited parent config mtime invalidates cache", #calls == 14)
	finish(14, "parent_updated")
	vim.fn.writefile({ "[project]", 'name="unrelated"' }, root .. "/parent/pyproject.toml")
	index.get(nested)
	check("Unrelated ancestor config does not invalidate cache", #calls == 14)
end, debug.traceback)
for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_get_name(bufnr):sub(1, #root + 1) == root .. "/" then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
end
vim.system = original_system
vim.fn.delete(root, "rf")
print(vim.json.encode({ passed = ok, checks = checks, error = not ok and err or nil }))
if not ok then
	vim.cmd("cquit 1")
end
