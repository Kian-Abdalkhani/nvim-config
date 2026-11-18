local function select_xcode()
	local developer_dir = "/Applications/Xcode.app/Contents/Developer"
	if vim.env.DEVELOPER_DIR ~= nil or vim.fn.executable(developer_dir .. "/usr/bin/xcodebuild") ~= 1 then
		return
	end

	local selected = vim.system({ "/usr/bin/xcode-select", "-p" }, { text = true }):wait()
	if selected.code ~= 0 or vim.trim(selected.stdout or "") ~= "/Library/Developer/CommandLineTools" then
		return
	end

	vim.env.DEVELOPER_DIR = developer_dir
	-- Include clients still initializing so an early Xcode command also switches their toolchain.
	for _, client in ipairs(vim.lsp.get_clients({ name = "sourcekit", _uninitialized = true })) do
		client:_restart()
	end
end

return {
	"wojciech-kulik/xcodebuild.nvim",
	branch = "main",
	commit = "45cd4a8daabcc1c4716388fadc036e06732756bd", -- Includes the Xcode 27 destination parser fix.
	cond = vim.fn.has("mac") == 1,
	cmd = {
		"XcodebuildSetup",
		"XcodebuildPicker",
		"XcodebuildSelectScheme",
		"XcodebuildSelectDevice",
		"XcodebuildSelectTestPlan",
		"XcodebuildBuild",
		"XcodebuildCleanBuild",
		"XcodebuildBuildRun",
		"XcodebuildRun",
		"XcodebuildTest",
		"XcodebuildTestNearest",
		"XcodebuildTestClass",
		"XcodebuildTestRepeat",
		"XcodebuildToggleLogs",
		"XcodebuildCancel",
		"XcodebuildBuildDebug",
		"XcodebuildDebug",
		"XcodebuildAttachDebugger",
		"XcodebuildDetachDebugger",
	},
	dependencies = {
		"nvim-telescope/telescope.nvim",
		"mfussenegger/nvim-dap",
		{ "MunifTanjim/nui.nvim", tag = "0.4.0" },
	},
	opts = {
		project_config = {
			store_in_project_dir = false,
			reload_on_cwd_change = true,
		},
		integrations = {
			xcode_build_server = { enabled = true },
			oil_nvim = { enabled = false },
			pymobiledevice = { enabled = false },
			telescope_nvim = { enabled = true },
		},
	},
	config = function(_, opts)
		select_xcode()
		require("xcodebuild").setup(opts)

		-- Use the app debugger's native commands without changing DAP's global settings.
		local dap = require("dap")
		local lldb = require("xcodebuild.integrations.lldb")
		local adapter = lldb.get_adapter_name()
		require("xcodebuild.platform.debugger").set_implementation(lldb)
		dap.adapters[adapter] = function(callback)
			callback(lldb.get_adapter())
		end
		dap.defaults[adapter].exception_breakpoints = {}
		dap.configurations.swift = { lldb.get_ios_configuration() }
		require("xcodebuild.integrations.dap").register_user_commands()
	end,
}
