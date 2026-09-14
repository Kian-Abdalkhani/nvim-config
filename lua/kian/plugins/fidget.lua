return {
	"j-hui/fidget.nvim",
	version = "*",
	event = "LspAttach",
	cmd = "Fidget",
	keys = {
		{ "<leader>fn", "<cmd>Fidget history<cr>", desc = "Notification history" },
	},
	opts = {},
}
