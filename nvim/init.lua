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

local opts = {
	-- The luarocks on PATH here is 2.0.10 (LuaForWindows), which predates the
	-- `--tree <path>` argument lazy.nvim passes, so every plugin that ships a
	-- .rockspec (oxocarbon, telescope, plenary, gitsigns, nvim-dap, nui,
	-- lspconfig) fails to build with "Argument error: use --tree=<path>".
	-- None of them need luarocks, so skip the rocks integration entirely.
	rocks = { enabled = false },
}

require("vim-options")
require("config.autocmds")
require("lazy").setup("plugins", opts)

-- better-php-sense: custom PHP LSP
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'php',
  callback = function(args)
    vim.lsp.start({
      name = 'better-php-sense',
      cmd = { 'php', '/Users/maikls/Projects/better-php-sense/bin/server.php' },
      -- vim.fs.root resolves from the buffer's absolute path; args.file can
      -- be cwd-relative, which used to leak relative roots like "backend".
      root_dir = vim.fs.root(args.buf, { 'composer.json', '.git' }),
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
