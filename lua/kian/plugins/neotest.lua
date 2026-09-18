return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		"nvim-neotest/neotest-python",
		"fredrikaverpil/neotest-golang",
		"nvim-neotest/neotest-jest",
		"marilari88/neotest-vitest",
		"mrcjkb/rustaceanvim",
	},
	keys = {
		{
			"<leader>tn",
			function()
				require("neotest").run.run()
			end,
			desc = "Run nearest test",
		},
		{
			"<leader>tf",
			function()
				require("neotest").run.run(vim.fn.expand("%:p"))
			end,
			desc = "Run test file",
		},
		{
			"<leader>tl",
			function()
				require("neotest").run.run_last()
			end,
			desc = "Run last test",
		},
		{
			"<leader>td",
			function()
				require("dap")
				require("neotest").run.run({ strategy = "dap" })
			end,
			desc = "Debug nearest test",
		},
		{
			"<leader>ts",
			function()
				require("neotest").summary.toggle()
			end,
			desc = "Toggle test summary",
		},
		{
			"<leader>to",
			function()
				require("neotest").output.open({ enter = true })
			end,
			desc = "Show test output",
		},
	},
	config = function()
		require("neotest").setup({
			adapters = {
				require("neotest-python")({}),
				require("neotest-golang")({}),
				require("neotest-jest")({}),
				require("neotest-vitest")({}),
				require("rustaceanvim.neotest"),
			},
		})
	end,
}
