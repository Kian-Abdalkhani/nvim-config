local swift = require("kian.swift")
local undo = { vim.b.undo_ftplugin }
for _, name in ipairs({ "SwiftBuild", "SwiftRun", "SwiftTest", "SwiftDebug" }) do
	vim.api.nvim_buf_create_user_command(0, name, function(opts)
		swift.execute(name, opts.args)
	end, { nargs = name == "SwiftBuild" and 0 or "?" })
	undo[#undo + 1] = "silent! delcommand -buffer " .. name
end
vim.b.undo_ftplugin = table.concat(undo, " | ")
