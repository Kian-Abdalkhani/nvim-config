-- Run from the config root with installed nvim-lint, Go, and golangci-lint 2.x:
-- nvim --headless -u NONE -i NONE -l tests/go_lint.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local data = vim.fn.stdpath("data")
vim.opt.rtp:prepend(repository)
vim.opt.rtp:prepend(data .. "/lazy/nvim-lint")
vim.env.PATH = data .. "/mason/bin:" .. vim.env.PATH
local root = assert(vim.uv.fs_mkdtemp("/private/tmp/nvim-go-lint-XXXXXX"))
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.XDG_CACHE_HOME = root .. "/cache"
vim.env.NVIM_LOG_FILE = root .. "/nvim.log"
vim.env.GOCACHE = root .. "/go-cache"
vim.env.GOLANGCI_LINT_CACHE = root .. "/lint-cache"
vim.env.GOMODCACHE = root .. "/mod-cache"
vim.env.GOPROXY = "off"
vim.env.GOSUMDB = "off"
vim.env.GOTOOLCHAIN = "local"
vim.env.GOWORK = nil

local checks = 0
local notifications = {}
vim.notify = function(message)
	notifications[#notifications + 1] = tostring(message)
end
vim.notify_once = vim.notify
local function check(name, passed)
	assert(passed, name)
	checks = checks + 1
end
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end
local function module(path, name)
	write(path .. "/go.mod", { "module " .. name, "", "go 1.24" })
end
local function config(path)
	write(path .. "/.golangci.yml", { 'version: "2"', "linters:", "  default: none", "  enable:", "    - govet" })
end

local ok, err = xpcall(function()
	check("Go toolchain is installed", vim.fn.executable("go") == 1)
	check("golangci-lint is installed", vim.fn.executable("golangci-lint") == 1)
	local lint = require("lint")
	require("kian.plugins.linting").config()
	local namespace = lint.get_namespace("golangcilint")
	local published = {}
	local set_diagnostics = vim.diagnostic.set
	vim.diagnostic.set = function(ns, buf, diagnostics, opts)
		set_diagnostics(ns, buf, diagnostics, opts)
		if ns == namespace then
			published[buf] = (published[buf] or 0) + 1
		end
	end
	local unrelated = root .. "/unrelated"
	vim.fn.mkdir(unrelated, "p")
	vim.cmd.cd(unrelated)
	local scratch = vim.api.nvim_get_current_buf()
	local function run(path, background)
		local buf = vim.fn.bufadd(path)
		vim.fn.bufload(buf)
		vim.bo[buf].filetype = "go"
		vim.cmd("noautocmd buffer " .. (background and scratch or buf))
		local before = published[buf] or 0
		vim.api.nvim_exec_autocmds("InsertLeave", { group = "kian-lint", buffer = buf })
		check(
			"Go lint publishes diagnostics",
			vim.wait(30000, function()
				return (published[buf] or 0) > before and #lint.get_running(buf) == 0
			end, 20)
		)
		check("Go lint preserves editor cwd", vim.fn.getcwd() == unrelated)
		if background then
			check("Background buffer lint restores current buffer", vim.api.nvim_get_current_buf() == scratch)
		end
		check("Go lint finishes without tool errors: " .. table.concat(notifications, "; "), #notifications == 0)
		return vim.diagnostic.get(buf, { namespace = namespace })
	end
	local function has_message(diagnostics, text)
		local found = vim.iter(diagnostics):any(function(diagnostic)
			return diagnostic.message:find(text, 1, true) ~= nil
		end)
		assert(found, "Expected " .. text .. " in " .. vim.inspect(diagnostics))
		return found
	end

	local project = root .. "/project"
	module(project, "example.test/project")
	config(project)
	write(project .. "/main.go", { "package main", "", "func main() { sibling() }" })
	write(project .. "/helper.go", { "package main", "", "func sibling() {}" })
	check("Module lint includes sibling source files", #run(project .. "/main.go") == 0)
	write(
		project .. "/main.go",
		{ "package main", 'import "fmt"', 'func main() { sibling(); fmt.Printf("%d", "text") }' }
	)
	check("Module lint detects a real govet error", has_message(run(project .. "/main.go"), "fmt.Printf format %d"))
	write(project .. "/main.go", { "package main", "", "func main() { sibling() }" })
	check("Non-current module buffer lint includes sibling files", #run(project .. "/main.go", true) == 0)

	local standalone = root .. "/standalone"
	config(standalone)
	write(standalone .. "/main.go", { "package main", "", "func main() {}" })
	-- A standalone target must remain a single file even after linting module buffers.
	write(standalone .. "/other.go", { "package main", "", "func other() { invalid() }" })
	check("Standalone file lint excludes unrelated siblings", #run(standalone .. "/main.go") == 0)
	write(standalone .. "/main.go", { "package main", "", "func main() { absent() }" })
	check("Standalone file lint detects a real error", has_message(run(standalone .. "/main.go"), "undefined: absent"))

	local workspace = root .. "/workspace"
	config(workspace)
	module(workspace .. "/app", "example.test/app")
	module(workspace .. "/shared", "example.test/shared")
	write(workspace .. "/go.work", { "go 1.24", "", "use (", "  ./app", "  ./shared", ")" })
	write(workspace .. "/app/main.go", {
		"package main",
		'import "example.test/shared"',
		"func main() { sibling(); shared.Call() }",
	})
	write(workspace .. "/app/helper.go", { "package main", "func sibling() {}" })
	write(workspace .. "/shared/shared.go", { "package shared", "func Call() {}" })
	check("Go workspace resolves sibling modules and package files", #run(workspace .. "/app/main.go") == 0)
	write(
		workspace .. "/app/main.go",
		{ "package main", 'import "fmt"', 'func main() { sibling(); fmt.Printf("%d", "text") }' }
	)
	check(
		"Go workspace lint detects a real govet error",
		has_message(run(workspace .. "/app/main.go"), "fmt.Printf format %d")
	)
	check("Returning to module lint preserves package targeting", #run(project .. "/main.go") == 0)
end, debug.traceback)

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_get_name(buf):sub(1, #root + 1) == root .. "/" then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end
vim.cmd.cd(repository)
vim.fn.delete(root, "rf")
print(vim.json.encode({ passed = ok, checks = checks, error = not ok and err or nil }))
if not ok then
	vim.cmd("cquit 1")
end
