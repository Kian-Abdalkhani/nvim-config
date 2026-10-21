-- Load the actual configuration without installers, update checks, or user state.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.env.XDG_STATE_HOME = temporary .. "/state"
vim.env.XDG_CACHE_HOME = temporary .. "/cache"
vim.env.NVIM_LOG_FILE = temporary .. "/nvim.log"
vim.env.DATABASE_URL = nil
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
local lazy = require("lazy")
local setup = lazy.setup
lazy.setup = function(opts)
	opts.install = { missing = false }
	opts.checker = { enabled = false }
	opts.change_detection = { enabled = false }
	opts.local_spec = false
	opts.rocks = { enabled = false }
	table.insert(opts.spec, { "WhoIsSethDaniel/mason-tool-installer.nvim", opts = { run_on_start = false } })
	return setup(opts)
end
dofile(root .. "/init.lua")
