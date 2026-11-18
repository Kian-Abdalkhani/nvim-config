return {
	cmd = vim.fn.has("mac") == 1 and { "xcrun", "sourcekit-lsp" } or { "sourcekit-lsp" },
	filetypes = { "swift" },
}
