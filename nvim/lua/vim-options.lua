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

-- What persistence.nvim stores in a session (buffers, layout, cwd, …)
vim.opt.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

vim.g.mapleader = " "

-- Save file with Ctrl+S
vim.keymap.set("n", "<C-S>", ":w<CR>", { desc = "Save file" })
vim.keymap.set("i", "<C-S>", "<Esc>:w<CR>", { desc = "Save file" })

vim.keymap.set("n", "<C-v>", '"+p', { desc = "Paste from clipboard" })
vim.keymap.set("v", "<C-v>", '"+p', { desc = "Paste from clipboard" })

vim.keymap.set("v", "<C-x>", '"+d', { desc = "Cut to clipboard" })
vim.keymap.set("v", "<C-c>", '"+y', { desc = "Copy to clipboard" })

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected lines down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selected lines up" })

vim.keymap.set("n", "<C-z>", "u", { desc = "Undo last action" })
vim.keymap.set("i", "<C-z>", "<C-o>u", { desc = "Undo last action in insert mode" })

-- Go to previous (alternate) file with Cmd+6.
-- In iTerm2 this fires because Cmd+6 is set to send 0x1e (= <C-^>); this
-- mapping also makes Cmd+6 work directly in GUI clients like Neovide.
vim.keymap.set("n", "<D-6>", "<C-^>", { desc = "Go to previous file" })

vim.keymap.set("i", "<C-h>", "<C-w>", { desc = "Delete previous word in insert mode" })

vim.api.nvim_set_keymap("n", "<C-h>", ":vertical resize -2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", ":resize +2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-k>", ":resize -2<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-l>", ":vertical resize +2<CR>", { noremap = true, silent = true })

-- Focus the next / previous window (split), e.g. jump between two side-by-side files
vim.keymap.set("n", "<leader>nb", "<C-w>w", { desc = "Focus next window" })
vim.keymap.set("n", "<leader>pb", "<C-w>W", { desc = "Focus previous window" })

-- Window navigation (jump between splits, e.g. into the references/quickfix panel)
vim.keymap.set("n", "<leader>ww", "<C-w>w", { desc = "Cycle to next window" })
vim.keymap.set("n", "<leader>wh", "<C-w>h", { desc = "Go to left window" })
vim.keymap.set("n", "<leader>wj", "<C-w>j", { desc = "Go to lower window" })
vim.keymap.set("n", "<leader>wk", "<C-w>k", { desc = "Go to upper window" })
vim.keymap.set("n", "<leader>wl", "<C-w>l", { desc = "Go to right window" })

-- Delete without yanking
vim.keymap.set("n", "d", '"_d', { noremap = true })
vim.keymap.set("v", "d", '"_d', { noremap = true })

-- Keep 'dd' to delete line without yanking
vim.keymap.set("n", "dd", '"_dd', { noremap = true })

-- Optional: Use leader+d for "cut" (normal delete behavior)
vim.keymap.set("n", "<leader>d", "d", { noremap = true })
vim.keymap.set("v", "<leader>d", "d", { noremap = true })

-- Centered command palette of this config's own keymaps (see lua/util/palette.lua)
vim.keymap.set("n", "<leader><space>", function()
	require("util.palette").open()
end, { desc = "Command palette" })

-- Run a saved project task (manage them in the palette → Project Commands)
vim.keymap.set("n", "<leader>r", function()
	require("util.tasks").run_interactive()
end, { desc = "Run project task" })

-- Terminal: let <C-w> window motions work straight from terminal-insert mode
-- so you can jump out of terminals (e.g. Claude Code) without first pressing
-- <C-\><C-n>. Esc stays untouched for terminal TUIs.
vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], { desc = "Go to left window" })
vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], { desc = "Go to lower window" })
vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], { desc = "Go to upper window" })
vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], { desc = "Go to right window" })
vim.keymap.set("t", "<C-w>w", [[<C-\><C-n><C-w>w]], { desc = "Cycle to next window" })
vim.keymap.set("t", "<C-w><Left>", [[<C-\><C-n><C-w>h]], { desc = "Go to left window" })
vim.keymap.set("t", "<C-w><Down>", [[<C-\><C-n><C-w>j]], { desc = "Go to lower window" })
vim.keymap.set("t", "<C-w><Up>", [[<C-\><C-n><C-w>k]], { desc = "Go to upper window" })
vim.keymap.set("t", "<C-w><Right>", [[<C-\><C-n><C-w>l]], { desc = "Go to right window" })
