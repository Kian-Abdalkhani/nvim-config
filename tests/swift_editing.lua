-- Run with the installed editor plugins and Swift tools:
-- nvim --headless -u NONE -i NONE -n -l tests/swift_editing.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local plugins = vim.fn.stdpath("data") .. "/lazy/"
vim.opt.rtp:prepend(repository)
for _, plugin in ipairs({ "nvim-lspconfig", "blink.cmp", "conform.nvim", "nvim-lint" }) do
	vim.opt.rtp:prepend(plugins .. plugin)
end
vim.cmd("filetype on")
vim.o.hidden = true

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
temporary = vim.fs.normalize(assert(vim.uv.fs_realpath(temporary)))
local unrelated = temporary .. "/unrelated"
vim.fn.mkdir(unrelated, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
vim.env.XDG_CACHE_HOME = temporary .. "/cache"
vim.env.NVIM_LOG_FILE = temporary .. "/nvim.log"
vim.env.CLANG_MODULE_CACHE_PATH = temporary .. "/module-cache"
vim.cmd.cd(unrelated)

local failures = {}
local function test(name, callback)
	local ok, err = xpcall(callback, debug.traceback)
	if ok then
		print("PASS " .. name)
	else
		failures[#failures + 1] = "FAIL " .. name .. "\n" .. err
	end
end

local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	assert(vim.fn.writefile(lines, path) == 0)
end

local function open(path)
	vim.cmd.edit(path)
	assert(vim.bo.filetype == "swift", "Swift filetype is detected")
	return vim.api.nvim_get_current_buf()
end

test("SourceKit attaches, completes, navigates, and clears diagnostics", function()
	require("kian.plugins.lsp.lspconfig").config()
	assert(vim.lsp.is_enabled("sourcekit"), "SourceKit is enabled")
	local project = temporary .. "/Swift Package"
	local source = project .. "/Sources/Fixture"
	local definition = source .. "/Greeting.swift"
	local file = source .. "/Caller.swift"
	write(project .. "/Package.swift", {
		"// swift-tools-version: 6.0",
		"import PackageDescription",
		'let package = Package(name: "Fixture", targets: [.target(name: "Fixture")])',
	})
	write(definition, { 'func uniqueGreeting() -> String { "Hello" }' })
	write(file, { "let greeting = uniqueGreeting()", "let invalid: Int = greeting" })
	local buffer = open(file)
	local client
	assert(
		vim.wait(10000, function()
			client = vim.lsp.get_clients({ bufnr = buffer, name = "sourcekit" })[1]
			return client and client.initialized
		end, 20),
		"SourceKit initializes in the Swift buffer"
	)
	assert(vim.fs.normalize(client.root_dir) == project, "SourceKit uses the SwiftPM package root")
	assert(
		client.config.capabilities.textDocument.completion.completionItem.snippetSupport,
		"Blink capabilities are advertised"
	)
	assert(
		client.config.capabilities.textDocument.diagnostic.relatedDocumentSupport,
		"Upstream SourceKit diagnostic support is preserved"
	)
	assert(vim.fn.maparg("gd", "n", false, true).buffer == 1, "LSP navigation is mapped")

	local function diagnostics()
		return vim.diagnostic.get(buffer, { severity = vim.diagnostic.severity.ERROR })
	end

	assert(
		vim.wait(25000, function()
			return vim.iter(diagnostics()):any(function(diagnostic)
				return diagnostic.lnum == 1 and diagnostic.message:find("String", 1, true)
			end)
		end, 50),
		"SourceKit diagnoses an invalid assignment using the sibling file"
	)
	vim.api.nvim_buf_set_lines(buffer, 1, -1, false, { "let valid: String = greeting" })
	assert(
		vim.wait(10000, function()
			return #diagnostics() == 0
		end, 20),
		"SourceKit clears the diagnostic after fixing the code"
	)

	local document = { uri = vim.uri_from_bufnr(buffer) }
	local location = client:request_sync("textDocument/definition", {
		textDocument = document,
		position = { line = 0, character = 20 },
	}, 10000, buffer)
	assert(location and vim.iter(location.result or {}):any(function(item)
		return (item.uri or item.targetUri) == vim.uri_from_fname(definition)
	end), "Definition resolves to the other Swift source file")

	vim.api.nvim_buf_set_lines(buffer, 1, -1, false, { "let completing = uniqueG" })
	local completion = client:request_sync("textDocument/completion", {
		textDocument = document,
		position = { line = 1, character = 24 },
	}, 10000, buffer)
	local items = completion and completion.result and (completion.result.items or completion.result) or {}
	assert(
		vim.iter(items):any(function(item)
			return item.label:find("uniqueGreeting", 1, true)
		end),
		"SourceKit completes a Swift symbol from the package"
	)

	local c_file = project .. "/Fixture.c"
	write(c_file, { "int main(void) { return 0; }" })
	vim.cmd.edit(c_file)
	assert(#vim.lsp.get_clients({ bufnr = 0, name = "sourcekit" }) == 0, "SourceKit does not attach to C")
end)

test("Swift format on save uses each file's project configuration", function()
	require("conform").setup(require("kian.plugins.formatting").opts)
	write(unrelated .. "/.swift-format", { '{"version":1,"indentation":{"spaces":8}}' })
	for _, spaces in ipairs({ 4, 6, 2 }) do
		local project = temporary .. "/Format " .. spaces
		local path = project .. "/Sources/Formatting.swift"
		-- The unconfigured file should use the toolchain's two-space default.
		if spaces ~= 2 then
			write(project .. "/.swift-format", { vim.json.encode({ version = 1, indentation = { spaces = spaces } }) })
		end
		write(path, { "func fixture(){}" })
		local buffer = open(path)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "func fixture(){", 'print("fresh buffer contents")', "}" })
		vim.cmd.write()
		assert(
			vim.deep_equal(vim.fn.readfile(path), {
				"func fixture() {",
				string.rep(" ", spaces) .. 'print("fresh buffer contents")',
				"}",
			}),
			"The first write formats unsaved edits with the file's .swift-format"
		)
	end
	assert(vim.fs.normalize(vim.fn.getcwd()) == unrelated, "Formatting preserves the editor's cwd")
end)

test("SwiftLint opts in per buffer and uses the nearest configuration only", function()
	require("kian.plugins.linting").config()
	assert(vim.fn.executable("swiftlint") == 1, "SwiftLint must be installed for this integration test")
	local lint = require("lint")
	local namespace = lint.get_namespace("swiftlint")

	local function diagnostics(buffer)
		return vim.diagnostic.get(buffer, { namespace = namespace })
	end

	local function expect_rule(buffer, rule)
		assert(
			vim.wait(5000, function()
				local items = diagnostics(buffer)
				return #items == 1 and items[1].message:find(rule, 1, true) ~= nil
			end, 20),
			"Expected the buffer's rule " .. rule .. ", found " .. vim.inspect(diagnostics(buffer))
		)
	end

	local first = temporary .. "/Lint One"
	local second = temporary .. "/Lint Two"
	write(unrelated .. "/.swiftlint.yml", { "only_rules: [force_cast]" })
	write(first .. "/.swiftlint.yml", { "only_rules: [force_cast]", "reporter: json" })
	write(second .. "/.swiftlint.yml", { "only_rules: [force_cast]" })
	write(second .. "/Nested/.swiftlint.yml", { "only_rules: [force_try]" })
	local fixture = { "func infer() throws -> Any { 1 }", "let output = try! infer() as! Int" }
	local first_file = first .. "/Linted.swift"
	local second_file = second .. "/Nested/Linted.swift"
	local opt_out = temporary .. "/No SwiftLint/Unlinted.swift"
	for _, path in ipairs({ first_file, second_file, opt_out }) do
		write(path, fixture)
	end

	local first_buffer = open(first_file)
	expect_rule(first_buffer, "force_cast")
	local second_buffer = open(second_file)
	expect_rule(second_buffer, "force_try")
	local opt_out_buffer = open(opt_out)
	assert(#lint.get_running(opt_out_buffer) == 0, "No SwiftLint runs for the unconfigured file")
	assert(#diagnostics(opt_out_buffer) == 0, "No SwiftLint diagnostics leak from other buffers")

	assert(
		vim.wait(5000, function()
			return #lint.get_running(second_buffer) == 0
		end, 20),
		"The previous SwiftLint run completes"
	)
	vim.api.nvim_exec_autocmds("InsertLeave", { group = "kian-lint", buffer = second_buffer })
	assert(#lint.get_running(second_buffer) == 0, "SwiftLint does not run after leaving insert mode")
	vim.fn.delete(second .. "/Nested/.swiftlint.yml")
	vim.api.nvim_exec_autocmds("BufWritePost", { group = "kian-lint", buffer = second_buffer })
	expect_rule(second_buffer, "force_cast")
	assert(vim.api.nvim_get_current_buf() == opt_out_buffer, "Background SwiftLint preserves the active buffer")

	vim.fn.delete(second .. "/.swiftlint.yml")
	vim.api.nvim_exec_autocmds("BufWritePost", { group = "kian-lint", buffer = second_buffer })
	assert(#diagnostics(second_buffer) == 0, "Removing SwiftLint configuration clears its old diagnostics")
	assert(vim.fs.normalize(vim.fn.getcwd()) == unrelated, "SwiftLint preserves the editor's cwd")
end)

for _, client in ipairs(vim.lsp.get_clients()) do
	client:stop(true)
end
vim.wait(2000, function()
	return #vim.lsp.get_clients() == 0
end, 20)
vim.cmd.cd(repository)
vim.fn.delete(temporary, "rf")

if #failures > 0 then
	io.stderr:write(table.concat(failures, "\n") .. "\n")
	vim.cmd("cquit 1")
end
