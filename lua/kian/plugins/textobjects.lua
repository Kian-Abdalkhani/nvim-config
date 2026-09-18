return {
	"nvim-treesitter/nvim-treesitter-textobjects",
	branch = "main",
	lazy = false,
	dependencies = { "nvim-treesitter/nvim-treesitter" },
	config = function()
		require("nvim-treesitter-textobjects").setup({})

		local select = require("nvim-treesitter-textobjects.select").select_textobject
		local function select_map(lhs, capture, desc)
			vim.keymap.set({ "x", "o" }, lhs, function()
				select(capture, "textobjects")
			end, { desc = desc })
		end

		select_map("am", "@function.outer", "Around function")
		select_map("im", "@function.inner", "Inside function")
		select_map("ac", "@class.outer", "Around class")
		select_map("ic", "@class.inner", "Inside class")
		select_map("aa", "@parameter.outer", "Around parameter")
		select_map("ia", "@parameter.inner", "Inside parameter")

		local move = require("nvim-treesitter-textobjects.move")
		vim.keymap.set("n", "<leader>mn", function()
			move.goto_next_start("@function.outer", "textobjects")
		end, { desc = "Next function" })
		vim.keymap.set("n", "<leader>mp", function()
			move.goto_previous_start("@function.outer", "textobjects")
		end, { desc = "Previous function" })

		local swap = require("nvim-treesitter-textobjects.swap")
		vim.keymap.set("n", "<leader>ms", function()
			swap.swap_next("@parameter.inner")
		end, { desc = "Swap parameter with next" })
		vim.keymap.set("n", "<leader>mS", function()
			swap.swap_previous("@parameter.inner")
		end, { desc = "Swap parameter with previous" })
	end,
}
