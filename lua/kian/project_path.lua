local M = {}

function M.display(path, is_directory)
	local root = vim.fs.root(is_directory and path or vim.fs.dirname(path), ".git") or vim.fn.getcwd()
	local relative = vim.fs.relpath(root, path)

	if not relative then
		-- The path is outside both a Git project and the working directory.
		relative = vim.fn.fnamemodify(path, ":~")
	end

	if is_directory then
		return relative == "." and "./" or relative .. "/"
	end

	return relative
end

return M
