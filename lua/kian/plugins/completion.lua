return {
	"saghen/blink.cmp",
	version = "1.*",
	event = "InsertEnter",
	opts = {
		keymap = {
			preset = "none",
			["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "hide", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-b>"] = { "scroll_documentation_up", "fallback" },
			["<C-f>"] = { "scroll_documentation_down", "fallback" },
			["<C-y>"] = { "select_and_accept", "fallback" },
			["<CR>"] = { "accept", "fallback" },
			["<Tab>"] = { "snippet_forward", "fallback" },
			["<S-Tab>"] = { "snippet_backward", "fallback" },
			["<C-s>"] = { "show_signature", "hide_signature", "fallback" },
		},
		completion = {
			documentation = { auto_show = true, auto_show_delay_ms = 300 },
		},
		signature = { enabled = true },
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
			per_filetype = {
				sql = { inherit_defaults = true, "dadbod" },
				mysql = { inherit_defaults = true, "dadbod" },
				plsql = { inherit_defaults = true, "dadbod" },
			},
			providers = {
				dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },
			},
		},
		fuzzy = { implementation = "prefer_rust" },
	},
	opts_extend = { "sources.default" },
}
