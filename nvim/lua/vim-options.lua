vim.cmd("set expandtab")
vim.cmd("set tabstop=4")
vim.cmd("set softtabstop=4")
vim.cmd("set shiftwidth=4")
vim.cmd("set wrap!")
vim.cmd("set relativenumber")
vim.cmd("set cursorline")

vim.opt.scrolloff = 10

vim.opt.number = true
vim.opt.signcolumn = "number"
vim.opt.colorcolumn = "120"

vim.g.mapleader = " "

-- Save file with Ctrl+S
vim.keymap.set('n', '<C-S>', ':w<CR>', { desc = "Save file" })
vim.keymap.set('i', '<C-S>', '<Esc>:w<CR>', { desc = "Save file" })

vim.keymap.set('n', '<C-v>', '"+p', { desc = "Paste from clipboard" })
vim.keymap.set('v', '<C-v>', '"+p', { desc = "Paste from clipboard" })

vim.keymap.set('v', '<C-x>', '"+d', { desc = "Cut to clipboard" })
vim.keymap.set('v', '<C-c>', '"+y', { desc = "Copy to clipboard" })

vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

vim.keymap.set('n', '<C-z>', 'u', { desc = "Undo last action" })
vim.keymap.set('i', '<C-z>', '<C-o>u', { desc = "Undo last action in insert mode" })

vim.keymap.set('i', '<C-h>', '<C-w>', { desc = "Delete previous word in insert mode" })

vim.api.nvim_set_keymap('n', '<C-h>', ':vertical resize -2<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-j>', ':resize +2<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-k>', ':resize -2<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-l>', ':vertical resize +2<CR>', { noremap = true, silent = true })
