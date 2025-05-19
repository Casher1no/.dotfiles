vim.api.nvim_create_autocmd("FocusGained", {
	callback = function()
		vim.cmd("checktime")
	end,
})
