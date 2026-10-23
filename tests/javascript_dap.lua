-- Uses the installed nvim-dap with fake processes/sockets; no network is needed.
-- Run from the config root:
-- nvim --headless -u NONE -i NONE -l tests/javascript_dap.lua
local repository = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(repository)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-dap")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.env.XDG_STATE_HOME = root .. "/state"
local dap = require("dap")
local Session = require("dap.session")
local uv = vim.uv
local originals = {}
for _, name in ipairs({ "new_tcp", "new_pipe", "spawn", "getaddrinfo" }) do
	originals[name] = uv[name]
end
local original_initialize = Session.initialize
local spawns, connections, sessions, pipes = {}, {}, {}, {}
local next_port = 43100
uv.new_tcp = function()
	local socket = { closed = false, writes = {} }
	function socket:bind(host, port)
		assert(host == "127.0.0.1" and port == 0)
		next_port = next_port + 1
		self.port = next_port
	end
	function socket:getsockname()
		return { port = self.port }
	end
	function socket.shutdown(_, callback)
		if callback then
			callback()
		end
	end
	function socket:close()
		self.closed = true
	end
	function socket:is_closing()
		return self.closed
	end
	function socket.connect(_, host, port, callback)
		connections[#connections + 1] = { host = host, port = port }
		vim.schedule(function()
			callback(nil)
		end)
	end
	function socket:read_start(callback)
		self.read_callback = callback
	end
	function socket:write(message)
		self.writes[#self.writes + 1] = message
	end
	return socket
end
uv.new_pipe = function()
	local pipe = { close = function() end }
	function pipe:read_start(callback)
		self.read_callback = callback
	end
	pipes[#pipes + 1] = pipe
	return pipe
end
uv.spawn = function(command, options)
	spawns[#spawns + 1] = { command = command, options = vim.deepcopy(options) }
	return {
		close = function() end,
		is_closing = function()
			return false
		end,
		kill = function() end,
	},
		12345
end
uv.getaddrinfo = function(_, _, _, callback)
	vim.schedule(function()
		callback(nil, { { addr = "127.0.0.1" } })
	end)
	return {}
end
Session.initialize = function(self, config)
	self.initial_config = config
end
local checks = 0
local function check(label, passed)
	assert(passed, label)
	checks = checks + 1
end
local function connect(adapter)
	local connected = false
	local session = Session.connect(adapter, { type = "pwa-node", name = "Test", request = "launch" }, {}, function(err)
		assert(not err, err)
		connected = true
	end)
	sessions[#sessions + 1] = session
	assert(
		vim.wait(1000, function()
			return connected
		end),
		"Connection callback timed out"
	)
	return session
end
local ok, err = xpcall(function()
	require("kian.dap.javascript").setup(dap)
	for _, filetype in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
		local config = dap.configurations[filetype]
		check(filetype .. " launch uses the adapter used by Neotest", config[1].type == "pwa-node")
		check(filetype .. " attach retains process picker", type(config[2].processId) == "function")
	end
	for _, name in ipairs({ "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" }) do
		check(name .. " retains native child-session support", type(dap.adapters[name]) == "table")
	end
	local first = connect(dap.adapters["pwa-node"])
	check("Native DAP resolves the allocated port", first.adapter.port == 43101)
	check(
		"Server receives the allocated port and loopback host",
		vim.deep_equal(spawns[1].options.args, { "43101", "127.0.0.1" })
	)
	check("Mason's standalone server is launched", spawns[1].command == "js-debug-adapter")
	check("Connection uses the allocated port", connections[1].port == 43101)
	pipes[1].read_callback(nil, "Debug server listening at 127.0.0.1:43101\n")
	check("Server status output cannot become the connection port", first.adapter.port == 43101)
	local second = connect(dap.adapters["pwa-node"])
	check("Independent launches receive different ports", second.adapter.port == 43102)
	check("Registered adapter remains reusable", dap.adapters["pwa-node"].port == "${port}")
	first.handlers.reverse_requests.startDebugging(first, {
		seq = 10,
		command = "startDebugging",
		arguments = {
			request = "launch",
			configuration = { type = "pwa-node", name = "Node child", __pendingTargetId = "child" },
		},
	})
	check(
		"Native child session is created",
		vim.wait(1000, function()
			return next(first.children) ~= nil
		end)
	)
	local child = select(2, next(first.children))
	sessions[#sessions + 1] = child
	check("Child session reuses the parent server", child.adapter.port == first.adapter.port and #spawns == 2)
	check(
		"Child DAP launch preserves its target",
		child.initial_config.__pendingTargetId == "child" and child.initial_config.request == "launch"
	)
	check("Child session is linked to its parent", child.parent == first)
end, debug.traceback)
for index = #sessions, 1, -1 do
	sessions[index]:close()
end
Session.initialize = original_initialize
for name, value in pairs(originals) do
	uv[name] = value
end
for _, logger in pairs(require("dap.log")._loggers) do
	logger:close()
end
vim.fn.delete(root, "rf")
assert(ok, err)
print(("JavaScript DAP: %d checks passed"):format(checks))
