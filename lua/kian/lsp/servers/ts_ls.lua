return {
	filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
	settings = {
		typescript = {
			inlayHints = {
				includeInlayParameterNameHints = "all",
				includeInlayFunctionResultTypeHints = true,
			},
		},
		javascript = {
			inlayHints = {
				includeInlayParameterNameHints = "all",
			},
		},
	},
}
