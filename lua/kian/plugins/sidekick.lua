return {
	"folke/sidekick.nvim",
	cmd = "Sidekick",
	dependencies = { "nvim-telescope/telescope.nvim" },
	opts = function()
		return {
			nes = { enabled = false },
			copilot = { status = { enabled = false } },
			cli = {
				picker = "telescope",
				win = { layout = "right", split = { width = 0.4 } },
				mux = {
					backend = "tmux",
					enabled = vim.fn.executable("tmux") == 1,
					-- Keep focus, hiding, and file watching in Neovim while tmux persists the agent.
					create = "terminal",
				},
			},
		}
	end,
	keys = {
		{
			"<leader>ii",
			function()
				require("sidekick.cli").toggle()
			end,
			desc = "Toggle AI terminal",
		},
		{
			"<leader>ic",
			function()
				require("sidekick.cli").toggle({ name = "claude", focus = true })
			end,
			desc = "Toggle Claude Code",
		},
		{
			"<leader>ix",
			function()
				require("sidekick.cli").toggle({ name = "codex", focus = true })
			end,
			desc = "Toggle Codex",
		},
		{
			"<leader>is",
			function()
				require("sidekick.cli").select({ filter = { installed = true } })
			end,
			desc = "Select AI session",
		},
		{
			"<leader>if",
			function()
				require("sidekick.cli").send({ msg = "{file}" })
			end,
			desc = "Send file to AI",
		},
		{
			"<leader>iv",
			function()
				require("sidekick.cli").send({ msg = "{selection}" })
			end,
			mode = "x",
			desc = "Send selection to AI",
		},
		{
			"<leader>ip",
			function()
				require("sidekick.cli").prompt()
			end,
			mode = { "n", "x" },
			desc = "Select AI prompt",
		},
		{
			"<leader>id",
			function()
				require("sidekick.cli").close()
			end,
			desc = "Detach AI session",
		},
	},
}
