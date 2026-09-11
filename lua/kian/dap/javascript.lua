local M = {}

function M.setup(dap)
	require("dap-vscode-js").setup({
		debugger_cmd = { "js-debug-adapter" },
		adapters = { "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" },
	})

	for _, filetype in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
		dap.configurations[filetype] = {
			{
				type = "pwa-node",
				request = "launch",
				name = "Launch file",
				program = "${file}",
				cwd = "${workspaceFolder}",
			},
			{
				type = "pwa-node",
				request = "attach",
				name = "Attach to process",
				processId = require("dap.utils").pick_process,
				cwd = "${workspaceFolder}",
			},
		}
	end
end

return M
