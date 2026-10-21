local M = {}

local entries = {}
local helper = vim.fs.joinpath(
	vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))),
	"scripts",
	"sql_schema_index.py"
)

local function buffer_number(bufnr)
	return (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
end

local function config_fingerprint(filename)
	local directories = { vim.fs.dirname(filename) }
	for directory in vim.fs.parents(directories[1]) do
		directories[#directories + 1] = directory
	end
	local result = {}
	for _, directory in ipairs(directories) do
		for _, name in ipairs({ ".sqlfluff", "pyproject.toml", "setup.cfg", "tox.ini", "pep8.ini" }) do
			local path = vim.fs.joinpath(directory, name)
			local stat = vim.uv.fs_stat(path)
			local relevant = name == ".sqlfluff"
			if stat and stat.type == "file" then
				if not relevant then
					for _, line in ipairs(vim.fn.readfile(path)) do
						if
							line:match("^%s*%[sqlfluff%]")
							or line:match("^%s*%[sqlfluff:")
							or line:match("^%s*%[tool%.sqlfluff%]")
							or line:match("^%s*%[tool%.sqlfluff%.")
						then
							relevant = true
							break
						end
					end
				end
				if relevant then
					result[#result + 1] = { path, stat.size, stat.mtime.sec, stat.mtime.nsec }
				end
			end
		end
	end
	return result
end

local function snapshot(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return nil, "The SQL buffer was closed"
	end
	local context = require("kian.sql").context(bufnr)
	if not context then
		return nil, "Choose :SQLDialect postgres or sqlite, or add a SQLFluff project config"
	end
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)
	return {
		context = context,
		tick = tick,
		key = vim.json.encode({
			tick,
			context.filename,
			context.cwd,
			context.dialect or "",
			context.config or "",
			config_fingerprint(context.filename),
		}),
	}
end

local function python()
	local root = vim.fs.joinpath(vim.fn.stdpath("data"), "mason")
	local ok, settings = pcall(require, "mason.settings")
	if ok then
		root = settings.current.install_root_dir
	end
	local candidates = {
		vim.fs.joinpath(root, "packages", "sqlfluff", "venv", "bin", "python"),
		vim.fs.joinpath(root, "packages", "sqlfluff", "venv", "Scripts", "python.exe"),
	}
	local command = vim.fn.exepath("sqlfluff")
	local resolved = command ~= "" and vim.uv.fs_realpath(command) or nil
	if resolved then
		table.insert(candidates, vim.fs.joinpath(vim.fs.dirname(resolved), "python"))
	end
	for _, candidate in ipairs(candidates) do
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
	return nil, "SQLFluff's Python runtime is missing; run :MasonToolsInstall"
end

local function deliver(callbacks, index, err)
	for _, callback in ipairs(callbacks) do
		local ok, message = pcall(callback, index, err)
		if not ok then
			vim.notify(message, vim.log.levels.ERROR)
		end
	end
end

local function cancel(pending)
	if pending and pending.process then
		pcall(pending.process.kill, pending.process, 15)
	end
end

local function failed(entry, callbacks, err)
	entry.index, entry.key, entry.error = nil, nil, err
	deliver(callbacks, nil, err)
end

local function complete(bufnr, entry, pending, result)
	if entries[bufnr] ~= entry or entry.pending ~= pending then
		return
	end
	entry.pending = nil
	local current, err = snapshot(bufnr)
	if not current then
		failed(entry, pending.callbacks, err)
		return
	end
	if current.key ~= pending.key then
		-- A command waiting on the old buffer receives the newest index, never
		-- positions from text that has since changed.
		for _, callback in ipairs(pending.callbacks) do
			M.get(bufnr, callback)
		end
		if #pending.callbacks == 0 then
			M.get(bufnr)
		end
		return
	end
	local decoded_ok, index = pcall(vim.json.decode, result.stdout or "")
	if
		not decoded_ok
		or type(index) ~= "table"
		or index.version ~= 1
		or type(index.tables) ~= "table"
		or type(index.foreign_keys) ~= "table"
		or type(index.occurrences) ~= "table"
	then
		local detail = vim.trim(result.stderr or "")
		if detail == "" then
			detail = result.code == 124 and "Parsing timed out after 30 seconds" or "The parser returned invalid output"
		end
		failed(entry, pending.callbacks, "Unable to index SQL: " .. detail)
		return
	end
	if result.code ~= 0 then
		index.partial = true
		index.issues = index.issues or {}
		if #index.issues == 0 then
			table.insert(index.issues, { message = "SQL parsing did not complete successfully" })
		end
	end
	index.bufnr, index.changedtick = bufnr, current.tick
	entry.index, entry.key, entry.error = index, pending.key, nil
	deliver(pending.callbacks, index)
end

---Return a fresh index asynchronously. Concurrent requests share a parser job.
---@param bufnr? integer
---@param callback? fun(index: table?, err: string?)
---@param opts? { force?: boolean }
function M.get(bufnr, callback, opts)
	bufnr = buffer_number(bufnr)
	local current, err = snapshot(bufnr)
	local entry = entries[bufnr] or { debounce = 0 }
	entries[bufnr] = entry
	local callbacks = callback and { callback } or {}
	if not current then
		if entry.pending then
			vim.list_extend(callbacks, entry.pending.callbacks)
			cancel(entry.pending)
			entry.pending = nil
		end
		failed(entry, callbacks, err)
		return
	end
	if not (opts and opts.force) and entry.key == current.key and entry.index then
		deliver(callbacks, entry.index)
		return
	end
	if entry.pending then
		if entry.pending.key == current.key and not (opts and opts.force) then
			vim.list_extend(entry.pending.callbacks, callbacks)
			return
		end
		vim.list_extend(callbacks, entry.pending.callbacks)
		cancel(entry.pending)
		entry.pending = nil
	end
	local executable, runtime_error = python()
	if not executable then
		failed(entry, callbacks, runtime_error)
		return
	end
	if vim.fn.filereadable(helper) ~= 1 then
		failed(entry, callbacks, "The SQL schema parser helper is missing: " .. helper)
		return
	end
	local pending = { key = current.key, callbacks = callbacks }
	entry.pending = pending
	local source = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
	local ok, process = pcall(vim.system, { executable, helper }, {
		text = true,
		cwd = current.context.cwd,
		timeout = 30000,
		stdin = vim.json.encode({
			source = source,
			filename = current.context.filename,
			dialect = current.context.dialect,
		}),
	}, function(result)
		vim.schedule(function()
			complete(bufnr, entry, pending, result)
		end)
	end)
	if ok then
		pending.process = process
	else
		entry.pending = nil
		failed(entry, callbacks, "Unable to start the SQL parser: " .. tostring(process))
	end
end

function M.peek(bufnr)
	bufnr = buffer_number(bufnr)
	local current = snapshot(bufnr)
	local entry = entries[bufnr]
	return current and entry and entry.key == current.key and entry.index or nil
end

function M.refresh(bufnr, callback)
	M.get(bufnr, callback, { force = true })
end

function M.invalidate(bufnr)
	bufnr = buffer_number(bufnr)
	local entry = entries[bufnr]
	if entry then
		entry.key, entry.index = nil, nil
		M.get(bufnr)
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("kian-sql-schema-index", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		group = group,
		callback = function(args)
			local entry = entries[args.buf]
			if not entry then
				return
			end
			entry.debounce = entry.debounce + 1
			local sequence = entry.debounce
			vim.defer_fn(function()
				if entries[args.buf] == entry and entry.debounce == sequence then
					M.get(args.buf)
				end
			end, 400)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			local entry = entries[args.buf]
			entries[args.buf] = nil
			if entry and entry.pending then
				cancel(entry.pending)
				deliver(entry.pending.callbacks, nil, "The SQL buffer was closed")
			end
		end,
	})
end

return M
