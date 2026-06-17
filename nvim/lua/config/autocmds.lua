-- automatically reloads file if changes where made outside nivm --
vim.api.nvim_create_autocmd("FocusGained", {
	callback = function()
		vim.cmd("checktime")
	end,
})

-- Remember the project (cwd) only when persistence actually saves a session
-- (i.e. real files were open). Launching/quitting from the dashboard with no
-- files open won't fire this, so the last real project sticks.
vim.api.nvim_create_autocmd("User", {
	pattern = "PersistenceSavePost",
	callback = function()
		require("util.session").save()
	end,
})

-- Track most-recently-used files for the project recent-files picker.
vim.api.nvim_create_autocmd("BufEnter", {
	callback = function(args)
		if vim.bo[args.buf].buftype ~= "" then
			return -- skip terminals, help, prompts, etc.
		end
		local name = vim.api.nvim_buf_get_name(args.buf)
		if name ~= "" and vim.fn.filereadable(name) == 1 then
			require("util.mru").touch(name)
		end
	end,
})
