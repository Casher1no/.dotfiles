local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)
vim.opt.clipboard = "unnamedplus"

local opts = {}

require("vim-options")
require("config.autocmds")
require("lazy").setup("plugins")

-- better-php-sense: custom PHP LSP
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'php',
  callback = function(args)
    vim.lsp.start({
      name = 'better-php-sense',
      cmd = { 'php', '/Users/maikls/Projects/better-php-sense/bin/server.php' },
      root_dir = vim.fs.dirname(
        vim.fs.find({ 'composer.json', '.git' }, { path = args.file, upward = true })[1]
      ),
    })
  end,
})

-- handy keymaps for PHP buffers
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local opts = { buffer = args.buf }
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts) -- code actions
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)      -- rename
    -- format lives on the global <leader>fc (see util/format.lua)
  end,
})
