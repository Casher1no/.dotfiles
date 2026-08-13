-- Palette-style action buttons for grug-far, sitting right under the Paths
-- input (the shortcut cheat-sheet header is hidden via helpLine.enabled =
-- false in plugins/grug-far.lua). Two empty virtual lines after the last
-- input reserve a gap in the layout; a borderless, focusable float sits in
-- that gap:
--
--      Replace
--      Replace All
--
-- The menu behaves like part of the buffer: <Down> from the Paths line
-- moves the cursor into it, <Down> past the last entry drops into the
-- results, <Up> walks back the same way (j/k skip over it). While inside,
-- cursorline shows the selection like the palette; <CR> presses the entry,
-- <Esc>/q bail back to the search fields. "Replace" applies the change on
-- the current result line and moves to the next match (JetBrains
-- "Replace") without opening any window; "Replace All" applies everything.
-- The float follows the inputs as they grow/scroll and hides when they
-- leave the viewport.
local M = {}

local BUTTONS = {
    {
        icon = "",
        label = "Replace",
        run = function(inst)
            inst:apply_next_change({ open_location = false })
        end,
    },
    {
        icon = "",
        label = "Replace All",
        run = function(inst)
            inst:replace()
        end,
    },
}

vim.api.nvim_set_hl(0, "GrugFarButtonIcon", { link = "GrugFarInputLabel", default = true })

local ns = vim.api.nvim_create_namespace("grug_buttons")

-- 0-based row of the last input line (the gap anchors below it).
local function last_input_row(inst, grug_buf)
    local ok, header = pcall(function()
        return require("grug-far.inputs").getHeaderRow(inst._context, grug_buf)
    end)
    if ok and header and header > 0 then
        return header - 1
    end
end

---@param grug_buf integer
function M.attach(grug_buf)
    if vim.b[grug_buf].grug_buttons_attached then
        return
    end
    vim.b[grug_buf].grug_buttons_attached = true
    local inst = require("grug-far").get_instance(grug_buf)
    if not inst then
        return
    end

    -- the menu buffer
    local buf = vim.api.nvim_create_buf(false, true)
    local width = 0
    local lines = {}
    for i, b in ipairs(BUTTONS) do
        lines[i] = " " .. b.icon .. "  " .. b.label
        width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    for i, b in ipairs(BUTTONS) do
        vim.hl.range(buf, ns, "GrugFarButtonIcon", { i - 1, 0 }, { i - 1, 1 + #b.icon })
    end

    local win -- created lazily by reposition()
    local gap_mark

    -- keep two empty virtual lines under the last input so the float has
    -- room instead of covering the results separator
    local function place_gap(row)
        local line = vim.api.nvim_buf_get_lines(grug_buf, row, row + 1, false)[1] or ""
        gap_mark = vim.api.nvim_buf_set_extmark(grug_buf, ns, row, #line, {
            id = gap_mark,
            virt_lines = { { { "", "" } }, { { "", "" } } },
        })
    end

    local function reposition()
        if not vim.api.nvim_buf_is_valid(grug_buf) then
            return
        end
        local grug_win = vim.fn.bufwinid(grug_buf)
        local row = last_input_row(inst, grug_buf)
        local pos = row and vim.fn.screenpos(grug_win, row + 1, 1)
        local visible = grug_win ~= -1 and pos and pos.row > 0
        if not visible then
            if win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_set_config(win, { hide = true })
            end
            return
        end
        place_gap(row)
        local config = {
            relative = "editor",
            -- pos is 1-based; float rows are 0-based, so pos.row lands
            -- exactly one screen line below the last input: our gap
            row = pos.row,
            col = pos.col - 1,
            width = width + 2,
            height = #BUTTONS,
            hide = false,
        }
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_config(win, config)
        else
            config.style = "minimal"
            config.focusable = true
            win = vim.api.nvim_open_win(buf, false, config)
            vim.wo[win].winhighlight = "NormalFloat:Normal"
        end
    end

    local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
    end

    map("<CR>", function()
        local i = vim.api.nvim_win_get_cursor(0)[1]
        BUTTONS[i].run(inst)
    end, "Press button")

    local function back_to_search(line)
        local target = vim.fn.bufwinid(grug_buf)
        if target ~= -1 then
            vim.fn.win_gotoid(target)
            if line then
                local max = vim.api.nvim_buf_line_count(grug_buf)
                vim.api.nvim_win_set_cursor(target, { math.min(line, max), 0 })
            end
        end
    end
    map("<Esc>", back_to_search, "Back to search")
    map("q", back_to_search, "Back to search")

    -- arrows walk out of the menu at either end, as if it were buffer text
    local function menu_move(step)
        return function()
            local i = vim.api.nvim_win_get_cursor(0)[1] + step
            local anchor = last_input_row(inst, grug_buf) -- 0-based last input
            if i < 1 then
                back_to_search(anchor and anchor + 1)
            elseif i > #BUTTONS then
                back_to_search(anchor and anchor + 2) -- first line under the gap
            else
                vim.api.nvim_win_set_cursor(0, { i, 1 })
            end
        end
    end
    map("<Down>", menu_move(1), "Next entry / into results")
    map("<Up>", menu_move(-1), "Previous entry / back to inputs")

    local function enter_menu(line)
        if win and vim.api.nvim_win_is_valid(win) and not vim.api.nvim_win_get_config(win).hide then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, { line, 1 })
            return true
        end
    end

    -- <Down> on the Paths line (either mode) slides into the menu; <Up> on
    -- the line right under it slides back in from below
    vim.keymap.set({ "n", "i" }, "<Down>", function()
        local anchor = last_input_row(inst, grug_buf)
        if anchor and vim.api.nvim_win_get_cursor(0)[1] == anchor + 1 then
            vim.schedule(function()
                vim.cmd("stopinsert")
                enter_menu(1)
            end)
            return ""
        end
        return "<Down>"
    end, { buffer = grug_buf, expr = true, desc = "Down (into buttons from Paths)" })
    vim.keymap.set("n", "<Up>", function()
        local anchor = last_input_row(inst, grug_buf)
        if anchor and vim.api.nvim_win_get_cursor(0)[1] == anchor + 2 then
            vim.schedule(function()
                enter_menu(#BUTTONS)
            end)
            return ""
        end
        return "<Up>"
    end, { buffer = grug_buf, expr = true, desc = "Up (into buttons from results)" })

    -- plain text while idle; the selection line only shows when navigating
    -- inside the menu
    vim.api.nvim_create_autocmd({ "BufEnter", "BufLeave" }, {
        buffer = buf,
        callback = function(ev)
            if win and vim.api.nvim_win_is_valid(win) then
                vim.wo[win].cursorline = ev.event == "BufEnter"
            end
        end,
    })

    -- follow renders (results arriving), input edits, scrolling, resizes
    vim.api.nvim_buf_attach(grug_buf, false, {
        on_lines = function()
            if not vim.b[grug_buf].grug_buttons_attached then
                return true -- detach
            end
            vim.schedule(reposition)
        end,
    })
    local group = vim.api.nvim_create_augroup("GrugFarButtons_" .. grug_buf, {})
    vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
        group = group,
        callback = vim.schedule_wrap(reposition),
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = vim.schedule_wrap(function(ev)
            if ev.buf == grug_buf then
                reposition() -- instance re-opened in a new window
            end
        end),
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = grug_buf,
        callback = function()
            vim.b[grug_buf].grug_buttons_attached = nil
            pcall(vim.api.nvim_del_augroup_by_id, group)
            if win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end,
    })
    -- hide the float alongside its grug-far window
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(ev)
            if tonumber(ev.match) == vim.fn.bufwinid(grug_buf) and win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_set_config(win, { hide = true })
            end
        end,
    })

    inst:when_ready(vim.schedule_wrap(reposition))
end

return M
