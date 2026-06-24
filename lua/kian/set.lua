vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = ""

vim.g.mapleader = " "

-- Makes splitting open in the right direction
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Splitting
vim.keymap.set("n", "<leader>v", "<cmd>vsp<CR>", { desc = "Vertical split" })
vim.keymap.set("n", "<leader>h", "<cmd>sp<CR>", { desc = "Horizontal split" })

-- Resizing
vim.keymap.set("n", "<C-Left>", "<C-w><", { desc = "Shrink split width" })
vim.keymap.set("n", "<C-Right>", "<C-w>>", { desc = "Expand split width" })
vim.keymap.set("n", "<C-Up>", "<C-w>+", { desc = "Expand split height" })
vim.keymap.set("n", "<C-Down>", "<C-w>-", { desc = "Shrink split height" })

vim.keymap.set("n", "<leader>we", "<C-w>=", { desc = "Equalize split sizes" })
vim.keymap.set("n", "<leader>wq", "<cmd>close<CR>", { desc = "Close split" })

-- zsh file type configuration
vim.filetype.add({
	filename = {
		[".zshrc"] = "zsh",
		[".zshenv"] = "zsh",
		[".zprofile"] = "zsh",
	},
})
