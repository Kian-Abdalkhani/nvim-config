-- access file system
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Move highlighted text up and down
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Paste without replacing registry
vim.keymap.set("x", "<leader>p", '"_dP')

-- yank into system register
vim.keymap.set("n", "<leader>y", '"+y')
vim.keymap.set("v", "<leader>y", '"+y')
vim.keymap.set("n", "<leader>Y", '"+Y')
