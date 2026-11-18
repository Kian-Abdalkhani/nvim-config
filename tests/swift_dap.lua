-- Run from the configuration root with nvim --headless -u NONE -i NONE -l tests/swift_dap.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local filename = vim.fn.has("win32") == 1 and "lldb-dap.exe" or "lldb-dap"
local binary = vim.fs.joinpath(directory, filename)
assert(vim.uv.fs_copyfile(vim.v.progpath, binary))
vim.env.PATH = directory

-- Also exercise the PATH lookup when this test runs on macOS.
local has = vim.fn.has
vim.fn.has = function(feature)
	if feature == "mac" then
		return 0
	end
	return has(feature)
end
local dap = { adapters = {} }
require("kian.dap.swift").setup(dap)
local launch
dap.adapters["swift-lldb"](function(adapter)
	launch = adapter
end)
assert(launch and launch.type == "executable", "Resolve lldb-dap from PATH without xcrun")
assert(vim.uv.fs_realpath(launch.command) == vim.uv.fs_realpath(binary), "Use the platform's executable filename")
vim.fn.delete(directory, "rf")
print("SwiftPM PATH adapter check passed")
