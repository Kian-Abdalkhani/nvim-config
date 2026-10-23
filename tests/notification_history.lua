-- Run from the config root:
-- nvim --headless -u NONE -i NONE -n -l tests/notification_history.lua
-- Exercise the configured Fidget spec with installed plugins and isolated state.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
vim.env.XDG_CACHE_HOME = temporary .. "/cache"
vim.env.NVIM_LOG_FILE = temporary .. "/nvim.log"
vim.g.mapleader = " "
vim.o.loadplugins = true
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

local checks = 0
local client_id
local function check(condition, name)
	assert(condition, name)
	checks = checks + 1
end
local function wait_for(callback, name)
	check(vim.wait(5000, callback, 10), name)
end

local ok, err = xpcall(function()
	local warning = "Notification-history regression warning"
	require("lazy").setup({
		spec = {
			dofile(root .. "/lua/kian/plugins/fidget.lua"),
			{
				name = "notification-history-startup-probe",
				dir = temporary,
				lazy = false,
				config = function()
					vim.notify(warning, vim.log.levels.WARN)
				end,
			},
		},
		lockfile = temporary .. "/lazy-lock.json",
		install = { missing = false },
		checker = { enabled = false },
		change_detection = { enabled = false },
		local_spec = false,
		rocks = { enabled = false },
	})

	-- The probe warns during plugin startup, before any LSP or Fidget command.
	local notification = require("fidget.notification")
	local function history_item(message)
		for _, item in ipairs(notification.get_history()) do
			if item.message == message then
				return item
			end
		end
	end
	wait_for(function()
		return history_item(warning) ~= nil
	end, "ordinary startup warning enters notification history")

	-- A small in-process server exercises Neovim's actual LSP progress handler,
	-- its LspProgress event, and Fidget's progress ingestion without executables.
	local server
	local closing = false
	local request_id = 0
	client_id = vim.lsp.start({
		name = "notification-history-test",
		cmd = function(dispatchers)
			server = dispatchers
			return {
				request = function(method, _, callback)
					request_id = request_id + 1
					local id = request_id
					vim.schedule(function()
						callback(nil, method == "initialize" and { capabilities = {} } or nil, id)
					end)
					return true, id
				end,
				notify = function()
					return true
				end,
				is_closing = function()
					return closing
				end,
				terminate = function()
					closing = true
					dispatchers.on_exit(0, 0)
				end,
			}
		end,
	})
	check(client_id ~= nil, "in-process LSP client starts")
	wait_for(function()
		local client = vim.lsp.get_client_by_id(client_id)
		return client and client.initialized
	end, "in-process LSP client initializes")
	server.notification("$/progress", {
		token = "history-regression",
		value = { kind = "begin", title = "History test", message = "History test running" },
	})
	wait_for(function()
		return history_item("History test running") ~= nil
	end, "LSP progress enters notification history")
	local completed = "History test completed"
	server.notification("$/progress", {
		token = "history-regression",
		value = { kind = "end", message = completed },
	})
	wait_for(function()
		local item = history_item(completed)
		return item and item.data == true
	end, "completed LSP progress remains in notification history")
	vim.lsp.get_client_by_id(client_id):stop(true)
	wait_for(function()
		return vim.lsp.get_client_by_id(client_id) == nil
	end, "in-process LSP client stops")
	wait_for(function()
		local item = history_item(completed)
		return item and item.removed
	end, "completed progress survives removal from the active display")

	-- Capture the real command's rendered output while invoking the user shortcut.
	local rendered = {}
	local echo = vim.api.nvim_echo
	vim.api.nvim_echo = function(chunks, ...)
		for _, chunk in ipairs(chunks) do
			rendered[#rendered + 1] = chunk[1]
		end
		return echo(chunks, ...)
	end
	local shortcut_ok, shortcut_error = pcall(vim.api.nvim_feedkeys, " fn", "xt", false)
	vim.api.nvim_echo = echo
	check(shortcut_ok, shortcut_error or "notification-history shortcut executes")
	local output = table.concat(rendered, "")
	check(output:find(warning, 1, true) ~= nil, "<leader>fn displays ordinary warning history")
	check(output:find(completed, 1, true) ~= nil, "<leader>fn displays completed LSP progress history")
	check(vim.v.errmsg == "", "no asynchronous editor errors: " .. vim.v.errmsg)
end, debug.traceback)

if client_id then
	local client = vim.lsp.get_client_by_id(client_id)
	if client then
		client:stop(true)
	end
	vim.wait(1000, function()
		return vim.lsp.get_client_by_id(client_id) == nil
	end, 10)
end
print(vim.json.encode({ passed = ok, checks = checks, error = not ok and err or nil }))
if not ok then
	vim.cmd("cquit 1")
end
