-- "Inline ask" for claudecode.nvim: highlight code, type a one-line instruction,
-- and it runs in the *background* Claude Code session while you keep working.
-- The selected lines are attached as an @-reference, your instruction is typed
-- into the (hidden) Claude pane and submitted, and Claude's edit lands on disk
-- and auto-reloads into your buffer (see config/autocmds.lua).
--
-- This reuses your existing Claude Code auth (no API key) — it just drives the
-- terminal session programmatically so you never have to look at or type in it.
local M = {}

-- Close any window showing the Claude terminal, but keep the buffer/job alive so
-- the background session persists and can still receive text.
local function hide_terminal()
    local ok, terminal = pcall(require, "claudecode.terminal")
    if not ok then
        return
    end
    local bufnr = terminal.get_active_terminal_bufnr and terminal.get_active_terminal_bufnr()
    if not bufnr then
        return
    end
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        pcall(vim.api.nvim_win_close, win, false)
    end
end

-- After an edit is requested, poll :checktime for a while so Claude's on-disk
-- change is pulled into the buffer promptly (not only on the next focus/idle).
local function poll_reload()
    local tries, timer = 0, vim.uv.new_timer()
    timer:start(
        1200,
        1200,
        vim.schedule_wrap(function()
            tries = tries + 1
            vim.cmd("silent! checktime")
            if tries >= 25 then -- ~30s
                timer:stop()
                timer:close()
            end
        end)
    )
end

-- Save a normal file buffer if it has unsaved changes.
local function save_if_dirty(buf)
    if vim.bo[buf].buftype == "" and vim.bo[buf].modified and vim.api.nvim_buf_get_name(buf) ~= "" then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent! write")
        end)
    end
end

-- line1/line2: the highlighted range (1-indexed, already ordered).
function M.ask(line1, line2)
    local cc = require("claudecode")
    local terminal = require("claudecode.terminal")
    local selection = require("claudecode.selection")
    local source_buf = vim.api.nvim_get_current_buf()

    -- Save first so Claude reads the latest content and disk == buffer; that lets
    -- the post-edit auto-reload swap Claude's change in without a W12 conflict.
    save_if_dirty(source_buf)

    vim.ui.input({ prompt = "Ask Claude about selection: " }, function(instruction)
        if not instruction or instruction == "" then
            return
        end

        -- Attach the highlighted lines as context (queued if not yet connected).
        selection.send_at_mention_for_visual_selection(line1, line2)

        -- Type the instruction into the background session and submit it without
        -- moving focus; then hide the pane and start watching for the edit.
        local function submit()
            local ok = terminal.send_to_terminal(instruction, { submit = true, focus = false })
            if not ok then
                vim.notify(
                    "Claude not ready — selection was queued; type your request in the Claude pane.",
                    vim.log.levels.WARN
                )
                return
            end
            vim.defer_fn(hide_terminal, 120)
            poll_reload()
        end

        if cc.is_claude_connected() then
            vim.defer_fn(submit, 150) -- let the @-reference land first
            return
        end

        -- Cold start: bring up a background session and wait for it to connect.
        terminal.ensure_visible()
        local tries, timer = 0, vim.uv.new_timer()
        timer:start(
            300,
            300,
            vim.schedule_wrap(function()
                tries = tries + 1
                if cc.is_claude_connected() then
                    timer:stop()
                    timer:close()
                    vim.defer_fn(submit, 250)
                elseif tries >= 40 then -- ~12s
                    timer:stop()
                    timer:close()
                    vim.notify("Claude didn't connect in time. Type your request in the Claude pane.", vim.log.levels.WARN)
                end
            end)
        )
    end)
end

return M
