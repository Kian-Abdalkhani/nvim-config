return {
	filetypes = { "typescriptreact", "javascriptreact", "html", "css" },
	root_dir = function(bufnr, on_dir)
		local root = require("lspconfig.util").root_pattern(
			"tailwind.config.js",
			"tailwind.config.ts",
			"tailwind.config.cjs",
			"tailwind.config.mjs",
			"postcss.config.js",
			"postcss.config.cjs",
			"package.json"
		)(vim.api.nvim_buf_get_name(bufnr))
		on_dir(root)
	end,
	settings = {
		tailwindCSS = {
			experimental = {
				classRegex = {
					{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
					{ "cx\\(([^)]*)\\)", "[\"'`]([^\"'`]*)[\"'`]" },
				},
			},
		},
	},
}
