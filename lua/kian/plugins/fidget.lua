return {
	"j-hui/fidget.nvim",
	version = "*",
	lazy = false,
	priority = 900, -- Capture startup notifications after the colorscheme is ready.
	cmd = "Fidget",
	keys = {
		{ "<leader>fn", "<cmd>Fidget history<cr>", desc = "Notification history" },
	},
	opts = {
		notification = { override_vim_notify = true },
		progress = { display = { skip_history = false } },
	},
}
