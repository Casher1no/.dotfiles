-- Auto-reload: pull in changes made on disk by external tools (Unity's asset
-- pipeline, git, …). autoread only swaps the buffer in when it
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

-- C# uses Allman style (opening brace on its own line), unlike the K&R style
-- mini.pairs' default `{}` pairing assumes. When `{` is typed at the end of a
-- statement (if/foreach/method/class/...), push it onto a new line with a
-- blank indented line and the matching `}` below, instead of pairing inline.
local function cs_allman_open_brace()
	local ok_pairs, MiniPairs = pcall(require, "mini.pairs")
	local function default_open()
		if ok_pairs then
			vim.api.nvim_feedkeys(MiniPairs.open("{}", "^[^\\]"), "n", true)
		else
			vim.api.nvim_feedkeys("{", "n", true)
		end
	end

	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local before = line:sub(1, col)
	local after = line:sub(col + 1)

	-- Only expand when `{` closes off a fresh statement: something before
	-- it, nothing but trailing whitespace after (not a mid-line initializer
	-- like `new() { ... }` or an interpolated string `$"{expr}"`).
	if before:match("^%s*$") or after:match("%S") then
		default_open()
		return
	end

	local ts_ok, node = pcall(vim.treesitter.get_node, { pos = { row - 1, math.max(col - 1, 0) } })
	if ts_ok and node then
		local node_type = node:type()
		if node_type:find("comment") or node_type:find("string") then
			default_open()
			return
		end
	end

	local indent = line:match("^%s*")
	local shiftwidth = vim.bo.shiftwidth > 0 and vim.bo.shiftwidth or vim.bo.tabstop
	local inner_indent = vim.bo.expandtab and (indent .. string.rep(" ", shiftwidth)) or (indent .. "\t")

	vim.api.nvim_buf_set_lines(0, row - 1, row, false, {
		before,
		indent .. "{",
		inner_indent,
		indent .. "}",
	})
	vim.api.nvim_win_set_cursor(0, { row + 2, #inner_indent })
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "cs",
	group = vim.api.nvim_create_augroup("cs_allman_braces", { clear = true }),
	callback = function(args)
		vim.keymap.set("i", "{", cs_allman_open_brace, {
			buffer = args.buf,
			desc = "Open brace on a new line, Allman-style (C#)",
		})
	end,
})
