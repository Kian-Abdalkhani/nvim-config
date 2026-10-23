local M = {}

function M.setup(dap)
	for _, adapter in ipairs({ "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" }) do
		-- Mason supplies the standalone DAP server. Let nvim-dap allocate its port
		-- and handle startDebugging requests for Node child sessions.
		dap.adapters[adapter] = {
			type = "server",
			host = "127.0.0.1",
			port = "${port}",
			id = adapter,
			executable = {
				command = "js-debug-adapter",
				args = { "${port}", "127.0.0.1" },
			},
		}
	end

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
