local function location()
	local path
	local is_directory = vim.bo.filetype == "oil"
	if is_directory then
		path = require("oil").get_current_dir()
	elseif vim.bo.buftype == "" then
		path = vim.api.nvim_buf_get_name(0)
	end

	if not path or path == "" then
		return vim.fn.expand("%:t") ~= "" and vim.fn.expand("%:t") or "[No Name]"
	end

	local label = require("kian.project_path").display(path, is_directory)
	if not is_directory then
		if vim.bo.modified then
			label = label .. " [+]"
		end
		if not vim.bo.modifiable or vim.bo.readonly then
			label = label .. " [-]"
		end
	end

	return (label:gsub("%%", "%%%%"))
end

return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		require("lualine").setup({
			sections = {
				lualine_c = { location },
			},
			inactive_sections = {
				lualine_c = { location },
			},
		})
	end,
}
