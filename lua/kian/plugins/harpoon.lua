local function select_file(index)
	return function()
		require("harpoon"):list():select(index)
	end
end

return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = {
		{
			"<leader>a",
			function()
				require("harpoon"):list():add()
			end,
			desc = "Add file to Harpoon",
		},
		{
			"<C-e>",
			function()
				local harpoon = require("harpoon")
				harpoon.ui:toggle_quick_menu(harpoon:list())
			end,
			desc = "Open Harpoon menu",
		},
		{ "<C-h>", select_file(1), desc = "Select Harpoon file 1" },
		{ "<C-j>", select_file(2), desc = "Select Harpoon file 2" },
		{ "<C-k>", select_file(3), desc = "Select Harpoon file 3" },
		{ "<C-l>", select_file(4), desc = "Select Harpoon file 4" },
		{
			"<C-S-P>",
			function()
				require("harpoon"):list():prev()
			end,
			desc = "Previous Harpoon file",
		},
		{
			"<C-S-N>",
			function()
				require("harpoon"):list():next()
			end,
			desc = "Next Harpoon file",
		},
	},
	config = function()
		require("harpoon"):setup()
	end,
}
