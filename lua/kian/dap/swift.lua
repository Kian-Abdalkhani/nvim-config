local M = {}

function M.setup(dap)
	dap.adapters["swift-lldb"] = function(callback)
		local mac = vim.fn.has("mac") == 1
		local adapter
		if mac then
			local started, process = pcall(vim.system, { "xcrun", "--find", "lldb-dap" }, { text = true })
			local result = started and process:wait()
			adapter = result and result.code == 0 and vim.trim(result.stdout or "")
		else
			adapter = vim.fn.exepath("lldb-dap")
		end
		if not adapter or vim.fn.executable(adapter) ~= 1 then
			local location = mac and "the active Apple developer tools" or "PATH"
			vim.notify("Swift debugging requires lldb-dap in " .. location .. ".", vim.log.levels.ERROR)
			return
		end

		callback({ type = "executable", command = adapter })
	end
end

return M
