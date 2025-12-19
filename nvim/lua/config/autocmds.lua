-- automatically reloads file if changes where made outside nivm --
vim.api.nvim_create_autocmd("FocusGained", {
	callback = function()
		vim.cmd("checktime")
	end,
})
