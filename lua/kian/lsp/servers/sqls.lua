return {
	-- A connection belongs to a project, not every SQL file opened in Neovim.
	root_markers = { ".sqls.yml" },
	workspace_required = true,
	cmd = function(dispatchers, config)
		return vim.lsp.rpc.start({ "sqls", "-config", vim.fs.joinpath(config.root_dir, ".sqls.yml") }, dispatchers, {
			cwd = config.root_dir,
			env = config.cmd_env,
			detached = config.detached,
		})
	end,
	on_attach = function(client)
		-- SQLFluff through Conform owns SQL formatting.
		client.server_capabilities.documentFormattingProvider = false
		client.server_capabilities.documentRangeFormattingProvider = false
	end,
}
