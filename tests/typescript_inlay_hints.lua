-- Run with the isolated configuration in tests/sql_schema_init.lua.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "{}" }, root .. "/package-lock.json")
vim.fn.writefile({ '{"compilerOptions":{"allowJs":true,"checkJs":true,"strict":true}}' }, root .. "/tsconfig.json")
local checks = 0
local messages = {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	if (level or vim.log.levels.INFO) >= vim.log.levels.ERROR then
		messages[#messages + 1] = tostring(message)
	end
	return original_notify(message, level, opts)
end
local function check(condition, name)
	assert(condition, name)
	checks = checks + 1
end
local function wait_for(callback, name)
	check(vim.wait(20000, callback, 20), name)
end
local function hint_labels(bufnr)
	local labels = {}
	for _, hint in ipairs(vim.lsp.inlay_hint.get({ bufnr = bufnr })) do
		local label = hint.inlay_hint.label
		if type(label) == "table" then
			label = table.concat(vim.tbl_map(function(part)
				return part.value
			end, label))
		end
		labels[#labels + 1] = label
	end
	return table.concat(labels, " ")
end
local ok, err = xpcall(function()
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	vim.lsp.enable({ "eslint", "tailwindcss", "emmet_language_server" }, false)
	local typescript = root .. "/fixture.ts"
	vim.fn.writefile({
		"export function greet(name: string) {",
		'  return "Hello " + name;',
		"}",
		'greet("Ada");',
	}, typescript)
	vim.cmd.edit(typescript)
	local tsbuf = vim.api.nvim_get_current_buf()
	local client
	wait_for(function()
		client = vim.lsp.get_clients({ bufnr = tsbuf, name = "ts_ls" })[1]
		return client and client.initialized and vim.lsp.inlay_hint.is_enabled({ bufnr = tsbuf })
	end, "TypeScript server attaches and enables buffer hints")
	wait_for(function()
		local labels = hint_labels(tsbuf)
		return labels:find("name:", 1, true) and labels:find(": string", 1, true)
	end, "actual TypeScript server supplies parameter and inferred return-type hints")
	local commands = vim.api.nvim_buf_get_commands(tsbuf, {})
	check(commands.LspTypescriptSourceAction ~= nil, "upstream TypeScript source-action command is preserved")
	check(commands.LspTypescriptGoToSourceDefinition ~= nil, "upstream source-definition command is preserved")
	check(vim.fn.maparg("gd", "n", false, true).buffer == 1, "normal LSP navigation remains mapped")
	local hover = client:request_sync("textDocument/hover", {
		textDocument = { uri = vim.uri_from_bufnr(tsbuf) },
		position = { line = 0, character = 17 },
	}, 10000, tsbuf)
	check(hover and hover.result and hover.result.contents ~= nil, "TypeScript hover still works")
	local javascript = root .. "/fixture.js"
	vim.fn.writefile({
		"function square(value) { return value * value; }",
		"square(4);",
		"module.exports = square;",
	}, javascript)
	vim.cmd.edit(javascript)
	local jsbuf = vim.api.nvim_get_current_buf()
	wait_for(function()
		return vim.lsp.inlay_hint.is_enabled({ bufnr = jsbuf }) and hint_labels(jsbuf):find("value:", 1, true)
	end, "JavaScript server attaches and displays parameter hints")
	vim.cmd.enew()
	check(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "unrelated buffers do not inherit enabled hints")
	check(#messages == 0, "no editor errors: " .. table.concat(messages, "; "))
	check(vim.v.errmsg == "", "no asynchronous editor errors: " .. vim.v.errmsg)
end, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients({ name = "ts_ls" })) do
	client:stop(true)
end
vim.wait(1000, function()
	return #vim.lsp.get_clients({ name = "ts_ls" }) == 0
end, 20)
vim.notify = original_notify
for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_get_name(bufnr):sub(1, #root + 1) == root .. "/" then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
end
vim.fn.delete(root, "rf")
print(vim.json.encode({ passed = ok, checks = checks, error = not ok and err or nil }))
if not ok then
	vim.cmd("cquit 1")
end
