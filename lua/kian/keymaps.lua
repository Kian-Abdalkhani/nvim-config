local map = vim.keymap.set

map("n", "<leader>pv", vim.cmd.Ex, { desc = "Open file explorer" })

map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down", silent = true })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up", silent = true })

map("x", "<leader>p", '"_dP', { desc = "Paste without replacing register" })

map({ "n", "v" }, "<leader>y", '"+y', { desc = "Yank to system clipboard" })
map("n", "<leader>Y", '"+Y', { desc = "Yank line to system clipboard" })

map("n", "<leader>v", "<cmd>vsplit<CR>", { desc = "Vertical split" })
map("n", "<leader>h", "<cmd>split<CR>", { desc = "Horizontal split" })

map("n", "<C-Left>", "<C-w><", { desc = "Shrink split width" })
map("n", "<C-Right>", "<C-w>>", { desc = "Expand split width" })
map("n", "<C-Up>", "<C-w>+", { desc = "Expand split height" })
map("n", "<C-Down>", "<C-w>-", { desc = "Shrink split height" })

map("n", "<leader>we", "<C-w>=", { desc = "Equalize split sizes" })
map("n", "<leader>wq", "<cmd>close<CR>", { desc = "Close split" })
