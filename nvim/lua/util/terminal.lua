-- Keep terminals on the input line.
--
-- Terminal windows drop into terminal-normal mode easily (double-Esc, a stray
-- <C-\><C-n>, a job exiting), and there your keys are vim commands, not input
-- — so it looks like the terminal stopped accepting typing and Enter does
-- nothing. This puts you back in terminal mode whenever the focused terminal
-- still has a live job, and makes a *finished* one dismissible instead of a
-- dead buffer you can only escape by closing the window.

local M = {}

-- jobwait with a 0 timeout polls: -1 means still running.
local function job_alive(buf)
	local id = vim.b[buf].terminal_job_id
	if not id then
		return false
	end
	local ok, res = pcall(vim.fn.jobwait, { id }, 0)
	return ok and res[1] == -1
end

-- A finished terminal keeps its output on screen (you want to read the error),
-- but must not trap you in it.
local function mark_dead(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].dead_terminal then
		return
	end
	vim.b[buf].dead_terminal = true
	for _, key in ipairs({ "q", "<CR>", "<Esc>" }) do
		vim.keymap.set("n", key, function()
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end, { buffer = buf, nowait = true, desc = "Close finished terminal" })
	end
end

local function focus(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
		return
	end
	if not job_alive(buf) then
		mark_dead(buf)
		return
	end
	-- Deferred, and re-checked: the <C-w>h/j/k/l terminal mappings in
	-- vim-options.lua leave terminal mode *in order to* switch windows, and
	-- startinsert would otherwise land in whatever file they moved to.
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf and job_alive(buf) then
			pcall(vim.cmd.startinsert)
		end
	end)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("terminal_focus", { clear = true })

	-- Entering a terminal window, and falling out of terminal mode while
	-- already in one (t:nt is the accidental case you can't otherwise undo).
	vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter", "WinEnter" }, {
		group = group,
		callback = function(args)
			focus(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "t:nt",
		callback = function(args)
			focus(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("TermClose", {
		group = group,
		callback = function(args)
			local buf = args.buf
			-- Deferred: on a clean exit snacks closes the window itself, and
			-- then there's nothing left to mark.
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end
				mark_dead(buf)
				if vim.api.nvim_get_current_buf() == buf then
					vim.cmd.stopinsert()
					vim.notify("Terminal finished — q, Enter or Esc to close", vim.log.levels.INFO)
				end
			end)
		end,
	})
end

return M
