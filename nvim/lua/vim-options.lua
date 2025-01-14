vim.cmd("set expandtab")
vim.cmd("set tabstop=4")
vim.cmd("set softtabstop=4")
vim.cmd("set shiftwidth=4")
vim.cmd("set wrap!")
vim.cmd("set relativenumber")
vim.cmd("set cursorline")

vim.opt.number = true
vim.opt.signcolumn = "number"
vim.opt.colorcolumn = "120"

-- Save file with Ctrl+S
vim.keymap.set('n', '<C-S>', ':w<CR>', { desc = "Save file" })
vim.keymap.set('i', '<C-S>', '<Esc>:w<CR>', { desc = "Save file" })

vim.g.mapleader = " "

-- Copy (yank) with Ctrl+C in visual mode
vim.keymap.set('v', '<C-c>', '"+y', { desc = "Copy to clipboard" })

-- Paste with Ctrl+V in normal and visual modes
vim.keymap.set('n', '<C-v>', '"+p', { desc = "Paste from clipboard" })
vim.keymap.set('v', '<C-v>', '"+p', { desc = "Paste from clipboard" })

-- Cut (delete) with Ctrl+X in visual mode
vim.keymap.set('v', '<C-x>', '"+d', { desc = "Cut to clipboard" })

-- Move selected code up/down
vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

-- Undo
vim.keymap.set('n', '<C-z>', 'u', { desc = "Undo last action" })
vim.keymap.set('i', '<C-z>', '<C-o>u', { desc = "Undo last action in insert mode" })
