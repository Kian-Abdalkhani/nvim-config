return {
	"nvim-telescope/telescope.nvim",
	version = "*",
	cmd = "Telescope",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = {
		{
			"<leader>pf",
			function()
				require("telescope.builtin").find_files()
			end,
			desc = "Find files",
		},
		{
			"<C-p>",
			function()
				require("telescope.builtin").git_files()
			end,
			desc = "Find Git files",
		},
		{
			"<leader>ps",
			function()
				require("telescope.builtin").grep_string({ search = vim.fn.input("Grep > ") })
			end,
			desc = "Grep for text",
		},
	},
}
