-- Run from the config root:
-- nvim --headless -i NONE -u tests/sql_schema_init.lua
--   "+lua dofile('tests/sql_schema_nvim.lua')" +qa!
local checks = 0
local messages = {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	messages[#messages + 1] = { message = tostring(message), level = level or vim.log.levels.INFO }
	return original_notify(message, level, opts)
end
local function check(condition, name)
	assert(condition, name)
	checks = checks + 1
end
local function wait_for(callback, name)
	check(vim.wait(15000, callback, 20), name)
end
local function index(bufnr)
	local result, err, done
	require("kian.sql_schema.index").get(bufnr, function(value, message)
		result, err, done = value, message, true
	end)
	wait_for(function()
		return done
	end, "schema request finishes")
	check(result ~= nil, err or "schema index exists")
	return result
end
local function picker(command, expected)
	vim.cmd(command)
	local current
	wait_for(function()
		if vim.bo.filetype ~= "TelescopePrompt" then
			return false
		end
		current = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
		return current and current.manager and current.manager:num_results() == expected
	end, command .. " opens the real Telescope picker")
	return current
end
local function select_entry(current, text)
	local selected
	for i = 1, current.manager:num_results() do
		local entry = current.manager:get_entry(i)
		if entry.value.label:find(text, 1, true) then
			current:set_selection(current:get_row(i))
			selected = true
			break
		end
	end
	check(selected, "picker contains " .. text)
	require("telescope.actions").select_default(current.prompt_bufnr)
	wait_for(function()
		return vim.bo.filetype ~= "TelescopePrompt"
	end, "picker selection closes")
end
local function cursor_on(bufnr, text, token)
	vim.api.nvim_set_current_buf(bufnr)
	for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		if line:find(text, 1, true) then
			vim.api.nvim_win_set_cursor(0, { i, (line:find(token or text, 1, true)) - 1 })
			return i
		end
	end
	error("Missing fixture text: " .. text)
end
local ok, err = xpcall(function()
	vim.o.columns, vim.o.lines = 160, 48
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local path = root .. "/schema.sql"
	local source = {
		"-- A schema, not a connection to a database.",
		"CREATE TABLE parents (",
		"  id INTEGER PRIMARY KEY,",
		"  label TEXT",
		");",
		"CREATE TABLE children (",
		"  id INTEGER PRIMARY KEY,",
		"  parent_id INTEGER,",
		"  CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES parents(id)",
		");",
	}
	vim.fn.writefile(source, path)
	vim.cmd.edit(path)
	local buf = vim.api.nvim_get_current_buf()
	vim.cmd("SQLDialect postgres")
	local model = index(buf)
	check(#model.tables == 2 and #model.foreign_keys == 1 and not model.partial, "PostgreSQL schema complete")
	check(#vim.lsp.get_clients({ bufnr = buf, name = "sqls" }) == 0, "offline indexing needs no database LSP")
	check(require("blink.cmp.sources.lib").get_enabled_providers("default").dadbod ~= nil, "Dadbod fallback preserved")
	local current = picker("SQLTables", 2)
	select_entry(current, "parents")
	check(vim.api.nvim_win_get_cursor(0)[1] == 2, "table outline jumps to declaration")
	current = picker("SQLColumns children", 2)
	select_entry(current, "parent_id")
	check(vim.api.nvim_win_get_cursor(0)[1] == 8, "column outline jumps to declaration")
	cursor_on(buf, "REFERENCES", "parents")
	vim.cmd("SQLDefinition")
	check(vim.api.nvim_win_get_cursor(0)[1] == 2, "foreign table definition jump")
	local line = vim.api.nvim_buf_get_lines(buf, 8, 9, false)[1]
	vim.api.nvim_win_set_cursor(0, { 9, #line - 3 })
	vim.cmd("SQLDefinition")
	check(vim.api.nvim_win_get_cursor(0)[1] == 3, "foreign target column definition jump")
	cursor_on(buf, "CREATE TABLE parents", "parents")
	current = picker("SQLReferences", 1)
	select_entry(current, "children")
	check(vim.api.nvim_win_get_cursor(0)[1] == 9, "incoming reference jumps to foreign key")
	cursor_on(buf, "CREATE TABLE children", "children")
	current = picker("SQLRelations", 1)
	select_entry(current, "parents")
	check(vim.api.nvim_win_get_cursor(0)[1] == 2, "outgoing foreign key follows target")
	check(vim.deep_equal(vim.fn.readfile(path), source), "navigation preserves disk contents")
	check(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source), "navigation preserves buffer contents")
	vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "  label TEXT,", "  unsaved TEXT" })
	model = index(buf)
	check(#model.tables[1].columns == 3, "unsaved column is indexed")
	check(vim.deep_equal(vim.fn.readfile(path), source), "unsaved indexing does not save the file")
	current = picker("SQLColumns parents", 3)
	select_entry(current, "unsaved")
	check(vim.api.nvim_win_get_cursor(0)[1] == 5, "outline uses unsaved source positions")
	vim.cmd("SQLDialect sqlite")
	model = index(buf)
	check(model.dialect == "sqlite" and not model.partial, "dialect change rebuilds SQLite schema")
	cursor_on(buf, "REFERENCES", "parents")
	vim.cmd("SQLDefinition")
	check(vim.api.nvim_win_get_cursor(0)[1] == 2, "SQLite foreign key follows target declaration")
	cursor_on(buf, "CREATE TABLE parents", "parents")
	current = picker("SQLReferences", 1)
	select_entry(current, "children")
	check(vim.api.nvim_win_get_cursor(0)[1] == 10, "SQLite incoming reference uses unsaved source positions")
	current = picker("SQLTables", 2)
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "-- changed while picker is open" })
	select_entry(current, "parents")
	check(
		messages[#messages].message:find("schema changed", 1, true) ~= nil,
		"stale picker cannot jump to old positions"
	)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"CREATE TABLE 'Odd.Table' ('Key' INTEGER PRIMARY KEY);",
	})
	model = index(buf)
	check(not model.partial, "SQLite single-quoted identifiers are indexed")
	current = picker("SQLColumns 'Odd.Table'", 1)
	select_entry(current, "'Key'")
	check(vim.api.nvim_win_get_cursor(0)[2] == 26, "SQLite quoted table argument preserves embedded dots")
	current = picker('SQLColumns "ODD.TABLE"', 1)
	select_entry(current, "'Key'")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "CREATE TABLE orphan (id INTEGER REFERENCES missing(id));" })
	model = index(buf)
	check(model.partial and #model.issues > 0, "unresolved references mark a partial index")
	vim.cmd("SQLSchemaIssues")
	check(#vim.fn.getloclist(0) > 0, "schema issues populate location list")
	vim.cmd.lclose()
	vim.api.nvim_set_current_buf(buf)
	vim.cmd("SQLSchemaRefresh")
	wait_for(function()
		return require("kian.sql_schema.index").peek(buf) ~= nil
	end, "explicit refresh completes")
	vim.cmd("SQLDialect postgres")
	local quoted = {
		'CREATE TABLE public."Café" ("clé" INTEGER PRIMARY KEY);',
		"CREATE TABLE public.orders (",
		'  customer_id INTEGER REFERENCES public."Café"("clé")',
		");",
	}
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, quoted)
	model = index(buf)
	check(not model.partial, "quoted PostgreSQL schema is complete")
	current = picker('SQLColumns PUBLIC."Café"', 1)
	select_entry(current, '"clé"')
	check(vim.api.nvim_win_get_cursor(0)[1] == 1, "qualified table argument obeys PostgreSQL case rules")
	cursor_on(buf, "REFERENCES", '"clé"')
	vim.cmd("SQLDefinition")
	check(
		vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, quoted[1]:find('"clé"', 1, true) - 1 }),
		"quoted Unicode column jump uses byte positions"
	)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"CREATE TABLE a.users (id INTEGER PRIMARY KEY);",
		"CREATE TABLE b.users (id INTEGER PRIMARY KEY);",
		"CREATE TABLE orders (user_id INTEGER REFERENCES users(id));",
	})
	model = index(buf)
	check(model.partial and model.foreign_keys[1].status == "ambiguous", "ambiguous foreign key is explicit")
	cursor_on(buf, "REFERENCES", "users")
	current = picker("SQLDefinition", 2)
	select_entry(current, "b.users")
	check(vim.api.nvim_win_get_cursor(0)[1] == 2, "ambiguous definition requires an explicit choice")
	check(vim.fn.maparg("<leader>a", "n", false, true).desc == "Add file to Harpoon", "Harpoon map preserved")
	check(vim.fn.maparg("<leader>ix", "n", false, true).desc == "Toggle Codex", "Sidekick map preserved")
	check(require("blink.cmp.config").keymap["<Tab>"][1] == "snippet_forward", "Blink Tab preserved")
	check(not vim.iter(messages):any(function(item)
		return item.level >= vim.log.levels.ERROR
	end), "no editor errors")
	check(vim.v.errmsg == "", "no asynchronous editor errors: " .. vim.v.errmsg)
	vim.bo[buf].modified = false
	vim.cmd("bwipeout! " .. buf)
	check(require("kian.sql_schema.index").peek(buf) == nil, "wiped schema cache is cleared")
end, debug.traceback)
print(vim.json.encode({ passed = ok, checks = checks, error = not ok and err or nil }))
if not ok then
	vim.cmd("cquit 1")
end
