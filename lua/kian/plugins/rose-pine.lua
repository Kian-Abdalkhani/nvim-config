return {
	"rose-pine/neovim",
	name = "rose-pine",
	lazy = false,
	priority = 1000,
	opts = {
		styles = {
			transparency = true,
		},
		highlight_groups = {
			BlinkCmpSignatureHelp = { bg = "surface" },
			BlinkCmpSignatureHelpBorder = { fg = "muted", bg = "surface" },
		},
	},
	config = function(_, opts)
		require("rose-pine").setup(opts)
		vim.cmd("colorscheme rose-pine")
	end,
}
