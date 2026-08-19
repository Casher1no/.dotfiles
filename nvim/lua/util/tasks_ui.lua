-- The <leader>rr runner: saved commands in one window, recent runs in a
-- second one under it.
--
-- It used to be a single vim.ui.select list with the history glued on below a
-- drawn "─── History ───" row — a fake entry that had to be ignored when
-- picked, and a list where "build" the saved task and "build" the thing you
-- actually ran last looked identical. Two windows say which is which without
-- a divider, and the panes navigate as one circular list, so ↓ off the bottom
-- of the commands lands on the newest run rather than dead-ending.
--
-- Windows and keys follow util/palette.lua: rounded floats, ▶ on the focused
-- row, buffer-local nowait maps, ⏎ to run.
local M = {}

local NS = vim.api.nvim_create_namespace("tasks_ui")

local MIN_WIDTH = 56
local MAX_WIDTH = 100
local MAX_TASK_ROWS = 12 -- taller lists scroll inside the window
local MAX_HIST_ROWS = 5 -- matches tasks.history_limit

local state = {
    pane = "tasks", -- which window has focus: "tasks" | "history"
    idx = { tasks = 1, history = 1 },
    list = { tasks = {}, history = {} },
    win = { tasks = nil, history = nil },
    buf = { tasks = nil, history = nil },
    name_w = 0,
    width = MIN_WIDTH,
}

local function other(pane)
    return pane == "tasks" and "history" or "tasks"
end

local function close()
    for _, pane in ipairs({ "tasks", "history" }) do
        local win = state.win[pane]
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        state.win[pane] = nil
    end
end

-- ----------------------------------------------------------------- rendering

-- Empty panes still draw a row so the window doesn't collapse to a sliver,
-- and it doubles as the place to say what to press.
local function rows(pane)
    local list = state.list[pane]
    if #list > 0 then
        return list
    end
    return { { empty = true, name = pane == "tasks" and "No saved commands — press a to add one"
        or "Nothing run yet in this project" } }
end

local function render(pane)
    local buf, focused = state.buf[pane], state.pane == pane
    local lines, entries = {}, rows(pane)
    for i, entry in ipairs(entries) do
        if entry.empty then
            lines[i] = "  " .. entry.name
        else
            local marker = (focused and i == state.idx[pane]) and "▶ " or "  "
            -- Display width, not byte length — task names carry glyphs.
            local pad = math.max(1, state.name_w - vim.fn.strdisplaywidth(entry.name) + 2)
            lines[i] = marker .. entry.name .. string.rep(" ", pad) .. entry.cmd
        end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    for i, entry in ipairs(entries) do
        if entry.empty then
            vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, { end_row = i, end_col = 0, hl_group = "Comment" })
        else
            -- The command itself is the quiet half: you scan the names.
            local col = #("  " .. entry.name) + math.max(1, state.name_w - vim.fn.strdisplaywidth(entry.name) + 2)
            vim.api.nvim_buf_set_extmark(buf, NS, i - 1, col, { end_row = i - 1, end_col = #lines[i], hl_group = "Comment" })
            if focused and i == state.idx[pane] then
                vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, { line_hl_group = "CursorLine" })
            end
        end
    end

    -- Dim the border of whichever pane isn't focused, so the two windows read
    -- as one control rather than two competing lists.
    local win = state.win[pane]
    if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winhighlight = focused and "FloatBorder:FloatBorder,FloatTitle:FloatTitle"
            or "FloatBorder:Comment,FloatTitle:Comment"
        -- Keep the selected row in view once a list outgrows its window.
        pcall(vim.api.nvim_win_set_cursor, win, { math.min(state.idx[pane], #entries), 0 })
    end
end

local function render_all()
    render("tasks")
    render("history")
end

-- ---------------------------------------------------------------- navigation

local function focus(pane)
    state.pane = pane
    if state.win[pane] and vim.api.nvim_win_is_valid(state.win[pane]) then
        vim.api.nvim_set_current_win(state.win[pane])
    end
    render_all()
end

-- Both panes behave as one wrapping list: ↓ off the last command steps into
-- the first recent run, ↑ off the first command wraps to the last one.
local function move(delta)
    local pane = state.pane
    local list = state.list[pane]
    local nxt = state.idx[pane] + delta
    if #list == 0 or nxt < 1 or nxt > #list then
        local dest = other(pane)
        if #state.list[dest] > 0 then
            state.idx[dest] = delta > 0 and 1 or #state.list[dest]
            return focus(dest)
        end
        -- Nothing in the other pane: wrap within this one.
        if #list > 0 then
            state.idx[pane] = delta > 0 and 1 or #list
        end
        return render_all()
    end
    state.idx[pane] = nxt
    render_all()
end

local function selected()
    local list = state.list[state.pane]
    return list[state.idx[state.pane]]
end

-- --------------------------------------------------------------------- open

local function reopen()
    vim.schedule(function()
        M.open()
    end)
end

function M.open()
    local tasks = require("util.tasks")
    state.list.tasks = tasks.list()
    state.list.history = tasks.history()
    state.pane = #state.list.tasks > 0 and "tasks" or "history"
    state.idx = { tasks = 1, history = 1 }

    if #state.list.tasks == 0 and #state.list.history == 0 then
        -- Nothing to show in either pane: go straight to adding one.
        return tasks.add_interactive(reopen)
    end

    -- Column widths from both lists at once, so the two panes line up.
    state.name_w, state.width = 0, MIN_WIDTH
    for _, pane in ipairs({ "tasks", "history" }) do
        for _, entry in ipairs(state.list[pane]) do
            state.name_w = math.max(state.name_w, vim.fn.strdisplaywidth(entry.name))
        end
    end
    state.name_w = math.min(state.name_w, 28)
    for _, pane in ipairs({ "tasks", "history" }) do
        for _, entry in ipairs(state.list[pane]) do
            state.width = math.max(state.width, 4 + state.name_w + vim.fn.strdisplaywidth(entry.cmd))
        end
    end
    state.width = math.min(state.width, MAX_WIDTH, vim.o.columns - 8)

    local task_h = math.max(1, math.min(#state.list.tasks, MAX_TASK_ROWS))
    local hist_h = math.max(1, math.min(#state.list.history, MAX_HIST_ROWS))
    local total_h = task_h + hist_h + 5 -- two borders per window, one row gap
    local row = math.max(0, math.floor((vim.o.lines - total_h) / 2) - 1)
    local col = math.floor((vim.o.columns - state.width) / 2)

    local function pane_win(pane, height, at_row, opts)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        state.buf[pane] = buf
        state.win[pane] = vim.api.nvim_open_win(
            buf,
            false,
            vim.tbl_extend("force", {
                relative = "editor",
                width = state.width,
                height = height,
                row = at_row,
                col = col,
                style = "minimal",
                border = "rounded",
                title_pos = "center",
            }, opts)
        )
        vim.wo[state.win[pane]].cursorline = false
    end

    pane_win("tasks", task_h, row, { title = " Commands " })
    pane_win("history", hist_h, row + task_h + 3, {
        title = " Recent runs ",
        footer = " ⏎ run   a add   d delete   ⇥ pane   q close ",
        footer_pos = "center",
    })

    render_all()
    focus(state.pane)

    local function map(lhs, fn)
        for _, pane in ipairs({ "tasks", "history" }) do
            vim.keymap.set("n", lhs, fn, { buffer = state.buf[pane], nowait = true, silent = true })
        end
    end

    map("j", function() move(1) end)
    map("k", function() move(-1) end)
    map("<Down>", function() move(1) end)
    map("<Up>", function() move(-1) end)
    for _, lhs in ipairs({ "<Tab>", "<S-Tab>", "h", "l", "<Left>", "<Right>" }) do
        map(lhs, function()
            local dest = other(state.pane)
            if #state.list[dest] > 0 then
                state.idx[dest] = math.min(state.idx[dest], #state.list[dest])
                focus(dest)
            end
        end)
    end

    map("<CR>", function()
        local entry = selected()
        if not entry then
            return
        end
        local pane = state.pane
        close()
        -- History entries are stored already expanded, so re-running one
        -- repeats the exact command instead of asking for its {} values again.
        if pane == "history" then
            require("util.tasks").run_recent(entry)
        else
            require("util.tasks").run(entry)
        end
    end)

    map("a", function()
        close()
        require("util.tasks").add_interactive(reopen)
    end)

    map("d", function()
        local entry = selected()
        if not entry then
            return
        end
        local tasks_mod = require("util.tasks")
        if state.pane == "tasks" then
            tasks_mod.remove(state.idx.tasks)
        else
            tasks_mod.forget(state.idx.history)
        end
        close()
        reopen()
    end)

    for _, lhs in ipairs({ "q", "<Esc>" }) do
        map(lhs, close)
    end

    -- Clicking or jumping away from both windows shouldn't leave them
    -- floating over the buffer.
    for _, pane in ipairs({ "tasks", "history" }) do
        vim.api.nvim_create_autocmd("BufLeave", {
            buffer = state.buf[pane],
            callback = function()
                vim.schedule(function()
                    local cur = vim.api.nvim_get_current_win()
                    if cur ~= state.win.tasks and cur ~= state.win.history then
                        close()
                    end
                end)
            end,
        })
    end
end

return M
