return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = function()
		require("nvim-treesitter").update()
	end,
	init = function()
		local treesitter_group = vim.api.nvim_create_augroup("kian-treesitter", { clear = true })
		vim.api.nvim_create_autocmd("FileType", {
			desc = "Enable Tree-sitter highlighting and indentation",
			group = treesitter_group,
			callback = function()
				local started = pcall(vim.treesitter.start)
				if started then
					vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})

		local ensure_installed = {
			"lua",
			"go",
			"python",
			"typescript",
			"tsx",
			"javascript",
			"bash",
			"json",
			"yaml",
			"toml",
			"markdown",
			"markdown_inline",
			"sql",
			"dockerfile",
			"html",
			"css",
			"rust",
		}
		local already_installed = require("nvim-treesitter.config").get_installed()
		local to_install = vim.iter(ensure_installed)
			:filter(function(p)
				return not vim.tbl_contains(already_installed, p)
			end)
			:totable()
		if #to_install > 0 then
			require("nvim-treesitter").install(to_install)
		end
	end,
}
