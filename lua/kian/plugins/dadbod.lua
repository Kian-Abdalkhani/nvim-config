return {
	{
		"tpope/vim-dadbod",
		lazy = true,
	},
	{
		"kristijanhusak/vim-dadbod-completion",
		ft = { "sql", "mysql", "plsql" },
		dependencies = {
			"tpope/vim-dadbod",
			"hrsh7th/nvim-cmp",
		},
		config = function()
			local cmp = require("cmp")
			cmp.setup.filetype({ "sql", "mysql", "plsql" }, {
				sources = cmp.config.sources({
					{ name = "vim-dadbod-completion" },
					{ name = "buffer" },
				}),
			})
		end,
	},
	{
		"kristijanhusak/vim-dadbod-ui",
		dependencies = {
			"tpope/vim-dadbod",
			"kristijanhusak/vim-dadbod-completion",
		},
		cmd = {
			"DBUI",
			"DBUIToggle",
			"DBUIAddConnection",
			"DBUIFindBuffer",
		},
		init = function()
			vim.g.db_ui_use_nerd_fonts = 1
		end,
	},
}
