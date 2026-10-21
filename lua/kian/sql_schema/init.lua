local M = {}
local warned = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "SQL schema" })
end

local function contains(location, cursor)
	local row, col = cursor[1], cursor[2]
	return row >= location.lnum
		and row <= location.end_lnum
		and (row ~= location.lnum or col >= location.col)
		and (row ~= location.end_lnum or col < location.end_col)
end

local function symbols(index)
	local result = {}
	for _, tbl in ipairs(index.tables) do
		result[tbl.id] = { label = tbl.qualified_name, location = tbl.location, table_id = tbl.id, kind = "table" }
		for _, column in ipairs(tbl.columns) do
			result[column.id] = {
				label = tbl.qualified_name .. "." .. column.name,
				location = column.location,
				table_id = tbl.id,
				kind = "column",
			}
		end
	end
	return result
end

local function occurrence(index, cursor)
	for _, item in ipairs(index.occurrences) do
		if contains(item.location, cursor) then
			return item
		end
	end
end

local function current_table(index, cursor)
	local item = occurrence(index, cursor)
	local lookup = symbols(index)
	if item and #item.targets > 1 then
		return nil
	end
	if item and #item.targets == 1 and lookup[item.targets[1]] then
		return lookup[item.targets[1]].table_id
	end
	for _, tbl in ipairs(index.tables) do
		if contains(tbl.range, cursor) then
			return tbl.id
		end
		for _, column in ipairs(tbl.columns) do
			if contains(column.location, cursor) then
				return tbl.id
			end
		end
	end
end

local function normalize(name, dialect)
	local quoted = name:sub(1, 1) == '"' and name:sub(-1) == '"'
	if dialect == "sqlite" then
		quoted = quoted
			or name:sub(1, 1) == "`" and name:sub(-1) == "`"
			or name:sub(1, 1) == "[" and name:sub(-1) == "]"
			or name:sub(1, 1) == "'" and name:sub(-1) == "'"
	end
	if quoted then
		local closing = name:sub(-1)
		name = name:sub(2, -2):gsub(vim.pesc(closing .. closing), closing)
	end
	return (dialect == "sqlite" or not quoted) and name:lower() or name
end

local function name_parts(name, dialect)
	local parts, start, closing, i = {}, 1, nil, 1
	while i <= #name do
		local char = name:sub(i, i)
		if closing then
			if char == closing then
				if name:sub(i + 1, i + 1) == closing then
					i = i + 1
				else
					closing = nil
				end
			end
		elseif char == '"' or dialect == "sqlite" and (char == "`" or char == "[" or char == "'") then
			closing = char == "[" and "]" or char
		elseif char == "." then
			parts[#parts + 1] = normalize(vim.trim(name:sub(start, i - 1)), dialect)
			start = i + 1
		end
		i = i + 1
	end
	parts[#parts + 1] = normalize(vim.trim(name:sub(start)), dialect)
	return parts
end

local function table_ids(index, argument, cursor)
	if argument ~= "" then
		local result = {}
		local wanted = name_parts(argument, index.dialect)
		for _, tbl in ipairs(index.tables) do
			local candidate = #wanted > 1 and name_parts(tbl.qualified_name, index.dialect)
				or { normalize(tbl.name, index.dialect) }
			if vim.deep_equal(candidate, wanted) then
				result[tbl.id] = true
			end
		end
		return result
	end
	local id = current_table(index, cursor)
	return id and { [id] = true } or nil
end

local function jump(bufnr, location, tick)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
		notify("The schema changed; run the navigation command again", vim.log.levels.WARN)
		return
	end
	if vim.api.nvim_get_current_buf() ~= bufnr then
		vim.api.nvim_set_current_buf(bufnr)
	end
	vim.cmd("normal! m'")
	vim.api.nvim_win_set_cursor(0, { location.lnum, location.col })
	vim.cmd("normal! zvzz")
end

local function pick(bufnr, tick, title, entries)
	if #entries == 0 then
		notify("No " .. title:lower() .. " found in this buffer")
		return
	end
	local ok, pickers = pcall(require, "telescope.pickers")
	if not ok then
		vim.ui.select(entries, {
			prompt = title,
			format_item = function(item)
				return item.label
			end,
		}, function(item)
			if item then
				jump(bufnr, item.location, tick)
			end
		end)
		return
	end
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local ns = vim.api.nvim_create_namespace("kian-sql-schema-preview")
	pickers
		.new({}, {
			prompt_title = title,
			finder = require("telescope.finders").new_table({
				results = entries,
				entry_maker = function(item)
					return { value = item, display = item.label, ordinal = item.label }
				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			previewer = require("telescope.previewers").new_buffer_previewer({
				title = "Schema buffer",
				get_buffer_by_name = function()
					return string.format("sql-schema:%d:%d", bufnr, tick)
				end,
				define_preview = function(self, entry)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.bo[self.state.bufnr].filetype = "sql"
					vim.api.nvim_buf_clear_namespace(self.state.bufnr, ns, 0, -1)
					local row = entry.value.location.lnum - 1
					vim.api.nvim_buf_set_extmark(
						self.state.bufnr,
						ns,
						row,
						0,
						{ line_hl_group = "TelescopePreviewLine" }
					)
					-- Telescope attaches a new preview buffer on the next event-loop turn.
					local winid, preview_buf = self.state.winid, self.state.bufnr
					vim.schedule(function()
						if
							winid
							and vim.api.nvim_win_is_valid(winid)
							and vim.api.nvim_win_get_buf(winid) == preview_buf
						then
							vim.api.nvim_win_set_cursor(winid, { row + 1, 0 })
						end
					end)
				end,
			}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if entry then
						jump(bufnr, entry.value.location, tick)
					end
				end)
				return true
			end,
		})
		:find()
end

local function with_index(callback, refresh)
	local bufnr = vim.api.nvim_get_current_buf()
	require("kian.sql_schema.index").get(bufnr, function(index, err)
		if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
			return
		end
		if not index then
			notify(err or "Unable to index this schema", vim.log.levels.WARN)
			return
		end
		if index.partial and warned[bufnr] ~= index then
			warned[bufnr] = index
			notify("Schema index is partial; :SQLSchemaIssues shows details", vim.log.levels.WARN)
		end
		callback(index, bufnr, vim.api.nvim_buf_get_changedtick(bufnr), vim.api.nvim_win_get_cursor(0))
	end, { force = refresh })
end

function M.setup()
	require("kian.sql_schema.index").setup()
	vim.api.nvim_create_user_command("SQLTables", function()
		with_index(function(index, bufnr, tick)
			local entries = {}
			for _, tbl in ipairs(index.tables) do
				entries[#entries + 1] = {
					label = string.format("%s  (%d columns)", tbl.qualified_name, #tbl.columns),
					location = tbl.location,
				}
			end
			pick(bufnr, tick, "SQL tables", entries)
		end)
	end, { desc = "Search tables in the current SQL schema buffer" })
	vim.api.nvim_create_user_command("SQLColumns", function(opts)
		with_index(function(index, bufnr, tick, cursor)
			local ids = table_ids(index, opts.args, cursor)
			local entries = {}
			for _, tbl in ipairs(index.tables) do
				if not ids or ids[tbl.id] then
					for _, column in ipairs(tbl.columns) do
						entries[#entries + 1] = {
							label = tbl.qualified_name .. "." .. column.name .. "  " .. column.data_type,
							location = column.location,
						}
					end
				end
			end
			pick(bufnr, tick, "SQL columns", entries)
		end)
	end, { nargs = "?", desc = "Search columns of the current table or a named table" })
	vim.api.nvim_create_user_command("SQLDefinition", function()
		with_index(function(index, bufnr, tick, cursor)
			local item = occurrence(index, cursor)
			local entries, lookup = {}, symbols(index)
			for _, id in ipairs(item and item.targets or {}) do
				if lookup[id] then
					entries[#entries + 1] = lookup[id]
				end
			end
			if #entries == 1 then
				jump(bufnr, entries[1].location, tick)
			elseif #entries > 1 then
				pick(bufnr, tick, "SQL definition candidates", entries)
			else
				notify(item and item.reason or "No indexed schema definition under the cursor", vim.log.levels.WARN)
			end
		end)
	end, { desc = "Jump to a schema table or column definition without a database" })
	local function relations(index, bufnr, tick, cursor, argument, incoming_only)
		local ids = table_ids(index, argument, cursor)
		local item = argument == "" and occurrence(index, cursor)
		local column_ids = incoming_only and item and item.kind == "column" and item.targets
		local entries, lookup = {}, symbols(index)
		for _, fk in ipairs(index.foreign_keys) do
			local incoming = not ids
			for _, id in ipairs(fk.target_table_ids) do
				incoming = incoming or ids and ids[id]
			end
			if column_ids then
				incoming = vim.iter(column_ids):any(function(id)
					return vim.tbl_contains(fk.target_column_ids, id)
				end)
			end
			local outgoing = not incoming_only and ids and ids[fk.source_table_id]
			if incoming or outgoing then
				local source = lookup[fk.source_table_id]
				local label = (source and source.label or "?") .. "(" .. table.concat(fk.source_columns, ", ") .. ")"
				label = label .. " -> " .. fk.target_name .. "(" .. table.concat(fk.target_columns, ", ") .. ")"
				if fk.status ~= "resolved" then
					label = label .. " [" .. fk.status .. "]"
				end
				local target = #fk.target_table_ids == 1 and lookup[fk.target_table_ids[1]]
				entries[#entries + 1] = {
					label = label,
					location = outgoing and target and target.location or fk.location,
				}
			end
		end
		pick(bufnr, tick, incoming_only and "SQL foreign-key references" or "SQL relationships", entries)
	end
	vim.api.nvim_create_user_command("SQLReferences", function(opts)
		with_index(function(index, bufnr, tick, cursor)
			relations(index, bufnr, tick, cursor, opts.args, true)
		end)
	end, { nargs = "?", desc = "Find incoming foreign keys for the schema table or column" })
	vim.api.nvim_create_user_command("SQLRelations", function(opts)
		with_index(function(index, bufnr, tick, cursor)
			relations(index, bufnr, tick, cursor, opts.args, false)
		end)
	end, { nargs = "?", desc = "Browse incoming and outgoing schema foreign keys" })
	vim.api.nvim_create_user_command("SQLSchemaIssues", function()
		with_index(function(index, bufnr)
			local items = {}
			for _, issue in ipairs(index.issues) do
				local loc = issue.location or { lnum = 1, col = 0 }
				items[#items + 1] = { bufnr = bufnr, lnum = loc.lnum, col = loc.col + 1, text = issue.message }
			end
			if #items == 0 then
				notify("No schema indexing issues found")
			else
				vim.fn.setloclist(0, {}, "r", { title = "SQL schema index issues", items = items })
				vim.cmd.lopen()
			end
		end)
	end, { desc = "Show schema parse errors, unresolved references, and unsupported statements" })
	vim.api.nvim_create_user_command("SQLSchemaRefresh", function()
		with_index(function(index)
			notify(string.format("Indexed %d tables and %d foreign keys", #index.tables, #index.foreign_keys))
		end, true)
	end, { desc = "Rebuild the schema index from the current SQL buffer" })
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = vim.api.nvim_create_augroup("kian-sql-schema-ui", { clear = true }),
		callback = function(args)
			warned[args.buf] = nil
		end,
	})
end

return M
