-- Auto-reload: pull in changes made on disk by external tools (Claude Code,
-- Unity's asset pipeline, git, …). autoread only swaps the buffer in when it
-- has no unsaved changes — the auto-save below keeps buffers clean so this can
-- almost always reload silently instead of throwing the W12 conflict prompt.
vim.opt.autoread = true
local reload_group = vim.api.nvim_create_augroup("auto_reload", { clear = true })
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI", "TermLeave" }, {
	group = reload_group,
	callback = function()
		-- Don't checktime from the cmdline window or while typing a command.
		if vim.fn.getcmdwintype() == "" and vim.fn.mode() ~= "c" then
			vim.cmd("silent! checktime")
		end
	end,
})

-- Auto-save: write modified, named, real-file buffers at natural pause points
-- (leaving insert, switching buffer/window, losing focus, idle) so external
-- tools never collide with unsaved edits. Skipped on every keystroke on purpose
-- so Unity doesn't recompile mid-typing.
local function autosave(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
		return -- skip terminals/prompts/help and read-only buffers
	end
	if not vim.bo[buf].modified or vim.api.nvim_buf_get_name(buf) == "" then
		return -- nothing to write, or [No Name]
	end
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("silent! lockmarks update") -- `update` writes only if modified
	end)
end

vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "FocusLost", "CursorHold" }, {
	group = vim.api.nvim_create_augroup("auto_save", { clear = true }),
	callback = function(args)
		autosave(args.buf)
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
