-- Run on macOS with the Neovim plugins installed:
-- nvim --headless -u NONE -i NONE -l tests/swift_xcode.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local plugins = vim.fn.stdpath("data") .. "/lazy"
local root = vim.fn.tempname()
local developer_dir = "/Applications/Xcode.app/Contents/Developer"
local clt_dir = "/Library/Developer/CommandLineTools"
vim.fn.mkdir(root, "p")
vim.env.XDG_DATA_HOME = root .. "/data"
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.XDG_CACHE_HOME = root .. "/cache"
vim.opt.rtp:prepend(repository)
vim.opt.rtp:prepend(plugins .. "/lazy.nvim")
vim.go.loadplugins = true
vim.uv.chdir(root)

local function track_sourcekit(workspace, initializing)
	local events = { launches = {}, shutdowns = 0 }
	local buffer = vim.api.nvim_create_buf(true, false)
	local id = vim.lsp.start({
		name = "sourcekit",
		root_dir = workspace,
		cmd = function(dispatchers)
			events.launches[#events.launches + 1] = vim.env.DEVELOPER_DIR or false
			local closing = false
			local function close()
				closing = true
				vim.schedule(function()
					dispatchers.on_exit(0, 0)
				end)
			end
			return {
				request = function(method, _, callback)
					if method == "initialize" and initializing and #events.launches == 1 then
						return true
					end
					if method == "shutdown" then
						events.shutdowns = events.shutdowns + 1
					end
					if method == "initialize" or method == "shutdown" then
						vim.schedule(function()
							callback(nil, method == "initialize" and { capabilities = {} } or nil)
						end)
					end
					return true
				end,
				notify = function(method)
					if method == "exit" then
						close()
					end
					return true
				end,
				is_closing = function()
					return closing
				end,
				terminate = close,
			}
		end,
	}, { bufnr = buffer })
	assert(id, "Start the SourceKit test transport")
	return events, id, buffer
end

local function sourcekit_for(buffer)
	return vim.lsp.get_clients({ bufnr = buffer, name = "sourcekit" })[1]
end

local ok, err = xpcall(function()
	vim.env.DEVELOPER_DIR = nil
	local xcode_installed = true
	local selected_dir = clt_dir
	local executable = vim.fn.executable
	local system = vim.system
	vim.fn.executable = function(path)
		if path == developer_dir .. "/usr/bin/xcodebuild" then
			return xcode_installed and 1 or 0
		end
		return executable(path)
	end
	vim.system = function(command, ...)
		if command[1] == "/usr/bin/xcode-select" and command[2] == "-p" then
			return {
				wait = function()
					return { code = 0, stdout = selected_dir .. "\n" }
				end,
			}
		end
		return system(command, ...)
	end

	local xcode = require("kian.plugins.xcodebuild")
	require("lazy").setup({
		spec = {
			require("kian.plugins.dap"),
			require("kian.plugins.telescope"),
			xcode,
		},
		root = plugins,
		lockfile = root .. "/lazy-lock.json",
		install = { missing = false },
	})
	local plugin = require("lazy.core.config").plugins["xcodebuild.nvim"]
	assert(plugin and not plugin._.loaded, "Xcode tooling should start unloaded")
	assert(vim.bo.filetype == "", "Test starts outside a Swift buffer")

	local dap = require("dap")
	local swift = dap.adapters["swift-lldb"]
	assert(type(swift) == "function", "The package adapter must resolve only when requested")
	local lldb
	swift(function(config)
		lldb = config
	end)
	assert(lldb and lldb.type == "executable", "The package debugger uses LLDB's stdio transport")
	assert(lldb.command == vim.trim(vim.fn.system({ "xcrun", "--find", "lldb-dap" })), "Use the active toolchain")
	assert(not plugin._.loaded, "Swift package debugging must leave the Xcode plugin unloaded")
	assert(vim.env.DEVELOPER_DIR == nil, "Package debugging must leave the selected developer directory alone")

	local active, old_client, buffer = track_sourcekit(root)
	assert(
		vim.wait(1000, function()
			return sourcekit_for(buffer) ~= nil
		end),
		"SourceKit should be attached before the Xcode command"
	)
	local other_root = root .. "/other"
	vim.fn.mkdir(other_root, "p")
	local initializing, _, other_buffer = track_sourcekit(other_root, true)

	local rust = dap.adapters.codelldb
	local js = dap.adapters["pwa-node"]
	local notify = require("dap.utils").notify
	local exception_breakpoints = dap.defaults.fallback.exception_breakpoints

	for _, command in ipairs({
		"XcodebuildSetup",
		"XcodebuildPicker",
		"XcodebuildBuild",
		"XcodebuildBuildRun",
		"XcodebuildTest",
		"XcodebuildTestNearest",
		"XcodebuildBuildDebug",
	}) do
		assert(vim.fn.exists(":" .. command) == 2, command .. " must be available before filetype detection")
	end
	local built, build_error = pcall(vim.cmd.XcodebuildBuild)
	assert(not built and build_error:find("Please run XcodebuildSetup first", 1, true), tostring(build_error))
	assert(plugin._.loaded, "An Xcode command must load the plugin outside a Swift buffer")
	assert(vim.env.DEVELOPER_DIR == developer_dir, "An Xcode command must get full Xcode when only CLT is selected")
	assert(
		vim.wait(1000, function()
			local client = sourcekit_for(buffer)
			return client and client.id ~= old_client and sourcekit_for(other_buffer)
		end),
		"SourceKit must reattach to its existing buffer"
	)
	assert(vim.deep_equal(active.launches, { false, developer_dir }), "Restart active SourceKit in full Xcode")
	assert(vim.deep_equal(initializing.launches, { false, developer_dir }), "Restart initializing SourceKit too")

	vim.env.DEVELOPER_DIR = "/Applications/Custom Xcode.app/Contents/Developer"
	xcode.config(nil, xcode.opts)
	assert(vim.env.DEVELOPER_DIR == "/Applications/Custom Xcode.app/Contents/Developer", "Honor explicit overrides")

	vim.env.DEVELOPER_DIR = nil
	selected_dir = "/Applications/Custom Xcode.app/Contents/Developer"
	xcode.config(nil, xcode.opts)
	assert(vim.env.DEVELOPER_DIR == nil, "Honor full Xcode selected using xcode-select")

	selected_dir = clt_dir
	xcode_installed = false
	xcode.config(nil, xcode.opts)
	assert(vim.env.DEVELOPER_DIR == nil, "Leave CLT selected when no standard Xcode is installed")
	assert(active.shutdowns == 1 and initializing.shutdowns == 0, "Skip SourceKit restart when there is no change")
	vim.fn.executable = executable
	vim.system = system
	local config = require("xcodebuild.core.config").options
	assert(config.integrations.xcode_build_server.enabled, "Scheme selection must configure the app BSP")
	assert(config.integrations.telescope_nvim.enabled, "Use Telescope for Xcode workflows")
	assert(not config.integrations.oil_nvim.enabled, "Oil operations must leave Xcode project files alone")
	assert(not config.integrations.pymobiledevice.enabled, "Physical device integration is disabled")
	local appdata = require("xcodebuild.project.appdata")
	assert(vim.startswith(appdata.appdir, vim.fn.stdpath("data") .. "/xcodebuild/"), "Store project data in Neovim")

	assert(dap.adapters["lldb-dap"], "Register the upstream Xcode LLDB adapter")
	assert(dap.adapters["swift-lldb"] == swift, "Xcode must preserve the package adapter")
	assert(rust and dap.adapters.codelldb == rust, "Xcode must preserve the Rust adapter")
	assert(js and dap.adapters["pwa-node"] == js, "Xcode must preserve the JavaScript adapter")
	assert(require("dap.utils").notify == notify, "Xcode must preserve DAP notifications")
	assert(dap.defaults.fallback.exception_breakpoints == exception_breakpoints, "Preserve DAP exception defaults")

	local xcodebuild = root .. "/xcodebuild"
	vim.fn.writefile({
		"#!/bin/sh",
		"printf '%s\\n' 'Destinations compatible with the \"Probe\" scheme:'",
		"printf '%s\\n' '{ platform:macOS, arch:arm64, id:fixture, name:My Mac }'",
	}, xcodebuild)
	assert(vim.uv.fs_chmod(xcodebuild, 493))
	vim.env.PATH = root .. ":" .. vim.env.PATH
	local destinations
	require("xcodebuild.core.xcode").get_destinations("Probe.xcodeproj", "Probe", root, function(result)
		destinations = result
	end)
	assert(
		vim.wait(1000, function()
			return destinations ~= nil
		end),
		"Xcode destination discovery did not finish"
	)
	assert(#destinations == 1 and destinations[1].id == "fixture", "Read Xcode 27 destinations")
end, debug.traceback)

for _, client in ipairs(vim.lsp.get_clients({ _uninitialized = true })) do
	client:stop(true)
end
vim.wait(1000, function()
	return #vim.lsp.get_clients({ _uninitialized = true }) == 0
end)
vim.uv.chdir(repository)
vim.fn.delete(root, "rf")
assert(ok, err)
print("Swift and Xcode integration checks passed")
