return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = function()
    require('nvim-treesitter').update()
  end,
  init = function()
    -- Enable highlighting and indentation on every filetype
    vim.api.nvim_create_autocmd('FileType', {
      callback = function()
        pcall(vim.treesitter.start)
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })

    -- Install parsers that aren't already present
    local ensure_installed = {
      'lua', 'go', 'python', 'typescript', 'javascript',
      'bash', 'json', 'yaml', 'toml', 'markdown', 'markdown_inline',
      'sql', 'dockerfile', 'html', 'css',
    }
    local already_installed = require('nvim-treesitter.config').get_installed()
    local to_install = vim.iter(ensure_installed)
      :filter(function(p)
        return not vim.tbl_contains(already_installed, p)
      end)
      :totable()
    if #to_install > 0 then
      require('nvim-treesitter').install(to_install)
    end
  end,
}
