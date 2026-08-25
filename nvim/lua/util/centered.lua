-- Centered view for wide monitors: holds the code column at a fixed width in
-- the middle of the screen. Toggle with <leader>zz; the choice is remembered
-- across restarts (state_file below).
--
-- The margins are two empty windows, one on each side of the code window.
-- Neovim has no per-window margin: the alternative, padding the gutter
-- through 'statuscolumn', is hard-capped at 47 columns — enough for a laptop,
-- nowhere near enough for a 300-column terminal.
--
-- What the padding windows don't do is behave like ordinary splits:
--   * their buffers are unlisted scratch buffers — invisible to :ls, to the
--     buffer picker and to saved sessions;
--   * focus can never land in one: entering carries straight on the way it
--     was going, so <C-w>h/l and mouse clicks act as if they weren't there;
--   * they carry the filetype "centered_pad", which plugins that go looking
--     for a window to open a file in are told to skip (see the
--     open_files_do_not_replace_types list in plugins/neo-tree.lua);
--   * no numbers, signs, cursorline, tildes or separator lines, so the
--     margin is indistinguishable from empty background;
--   * they tear themselves down before :q, before a session is written, and
--     whenever the layout stops having room for them.
local M = {}

-- Width of the code column, and the smallest margin worth a window.
M.width = 150
M.min_pad = 4

local state_file = vim.fn.stdpath("state") .. "/centered-view"
local enabled = false
local augroup

-- tabpage handle -> { left = winid, right = winid, content = { winid… } },
-- plus winid -> { side, buf } for every pad, so is_pad() is a lookup rather
-- than a search.
local layout = {}
local pads = {}

local function valid(win)
    return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_pad(win)
    local pad = pads[win]
    -- A window that has been handed some other buffer (a plugin picking a
    -- window to open a file in, say) has stopped being padding: let go of it
    -- rather than closing it with the file inside.
    return pad ~= nil and valid(win) and vim.api.nvim_win_get_buf(win) == pad.buf
end

-- Forget pads that were closed or taken over, handing back the options we
-- set on them.
local function prune()
    for win, pad in pairs(pads) do
        if not valid(win) then
            pads[win] = nil
        elseif vim.api.nvim_win_get_buf(win) ~= pad.buf then
            vim.wo[win].fillchars = ""
            vim.wo[win].winfixwidth = false
            pads[win] = nil
        end
    end
end

-- Layout changes made here must not feed back into the autocmds that call
-- refresh(), and must stay invisible to plugins watching for new windows.
local function quietly(fn)
    local save = vim.o.eventignore
    vim.o.eventignore = "all"
    local ok, err = pcall(fn)
    vim.o.eventignore = save
    if not ok then
        vim.notify("Centered view: " .. tostring(err), vim.log.levels.WARN)
    end
end

-- The windows to centre. One normal file window is the usual case. Several
-- stacked on top of each other (:split) share one column, so they are
-- centered as a block — the pads then have to span the full height, which is
-- only unambiguous when nothing else (an explorer, a terminal) is sharing the
-- row. Side by side windows (:vsplit) are already using the width, so the
-- padding steps aside for them. Pickers and floats never count.
local function content_wins(tab)
    local wins, others = {}, 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab or 0)) do
        if not is_pad(win) and vim.api.nvim_win_get_config(win).relative == "" then
            if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
                wins[#wins + 1] = win
            else
                others = others + 1
            end
        end
    end
    if #wins < 2 then
        return wins
    end
    if others > 0 then
        return {}
    end
    -- One column: same width, same left edge.
    local width, col = vim.api.nvim_win_get_width(wins[1]), vim.fn.win_screenpos(wins[1])[2]
    for _, win in ipairs(wins) do
        if vim.api.nvim_win_get_width(win) ~= width or vim.fn.win_screenpos(win)[2] ~= col then
            return {}
        end
    end
    return wins
end

-- A vertical separator is drawn by the window on its left, so hiding both
-- edges of the code column means blanking the 'vert' fillchar on the left pad
-- and on the code window itself. The code window's value is restored on
-- teardown, and only 'vert' is touched — its ~ end-of-buffer markers stay.
local function hide_separator(win, is_padding)
    vim.wo[win].fillchars = is_padding and "vert: ,eob: " or "vert: "
end

-- `target` is the window to sit next to, or nil to span the full height of
-- the tab (a column of stacked windows).
local function make_pad(side, target, width)
    local win
    if target then
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].filetype = "centered_pad"
        win = vim.api.nvim_open_win(buf, false, {
            split = side,
            win = target,
            width = width,
            style = "minimal", -- no numbers, signs, folds, cursorline or list chars
        })
    else
        local previous = vim.api.nvim_get_current_win()
        vim.cmd((side == "left" and "topleft" or "botright") .. " vertical " .. width .. "new")
        win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].buflisted = false
        vim.bo[buf].filetype = "centered_pad"
        for option, value in pairs({
            number = false,
            relativenumber = false,
            cursorline = false,
            list = false,
            spell = false,
            signcolumn = "no",
            foldcolumn = "0",
            colorcolumn = "",
            statuscolumn = "",
            winbar = "",
        }) do
            vim.wo[win][option] = value
        end
        vim.api.nvim_set_current_win(previous)
    end
    vim.wo[win].winfixwidth = true
    hide_separator(win, true)
    pads[win] = { side = side, buf = vim.api.nvim_win_get_buf(win) }
    return win
end

local function close_pads()
    quietly(function()
        prune()
        for win in pairs(pads) do
            if is_pad(win) then
                vim.api.nvim_win_close(win, true)
            end
        end
        pads = {}
        for _, entry in pairs(layout) do
            for _, win in ipairs(entry.content or {}) do
                if valid(win) then
                    vim.wo[win].fillchars = ""
                end
            end
        end
        layout = {}
    end)
end

-- Columns the code column and its pads occupy together, separators included.
local function span(entry, content)
    local total = vim.api.nvim_win_get_width(content)
    for _, side in ipairs({ "left", "right" }) do
        if valid(entry[side]) then
            total = total + vim.api.nvim_win_get_width(entry[side]) + 1
        end
    end
    return total
end

local function refresh()
    if not enabled then
        return
    end
    prune()
    local tab = vim.api.nvim_get_current_tabpage()
    local entry = layout[tab] or {}
    layout[tab] = entry

    local wins = content_wins(tab)
    local content = wins[1]
    if not content then
        close_pads()
        return
    end
    -- A stacked column has no single window to hang the pads off; they get
    -- created at the edges of the tab instead.
    local anchor = #wins == 1 and content or nil
    -- The code moved to a different window (a split was closed, say): give
    -- the old ones their separator back before adopting the new set.
    for _, win in ipairs(entry.content or {}) do
        if valid(win) and not vim.tbl_contains(wins, win) then
            vim.wo[win].fillchars = ""
        end
    end
    entry.content = wins

    local free = span(entry, content) - M.width
    if free < 2 * M.min_pad then
        close_pads()
        return
    end

    quietly(function()
        local left = math.floor(free / 2) - 1 -- one column each goes to the separators
        local right = free - left - 2
        if valid(entry.left) then
            vim.api.nvim_win_set_width(entry.left, left)
        else
            entry.left = make_pad("left", anchor, left)
        end
        if valid(entry.right) then
            vim.api.nvim_win_set_width(entry.right, right)
        else
            entry.right = make_pad("right", anchor, right)
        end
        for _, win in ipairs(wins) do
            hide_separator(win)
        end
        -- Splitting rounds and 'equalalways' nudges widths around; the code
        -- column is the one that has to come out exact.
        vim.api.nvim_win_set_width(content, M.width)
    end)
end

-- Focus never rests in the padding: it carries on the way it was going, so a
-- pad is passed through rather than bounced off. Direction matters — sending
-- focus back where it came from strands you on whichever side you started:
-- <C-w>l out of a left-hand terminal, or <C-w>h out of the explorer, would
-- step into the padding and be handed straight back. Only when there is
-- nothing beyond the pad does focus return to where it came from.
local bouncing = false

local function bounce()
    -- The wincmd below lands in another window, firing WinEnter again.
    if bouncing or not is_pad(vim.api.nvim_get_current_win()) then
        return
    end
    local pad = vim.api.nvim_get_current_win()
    local previous = vim.fn.win_getid(vim.fn.winnr("#"))
    -- Coming from the left means heading right, and vice versa. Anything
    -- else (a mouse click, a plugin focusing the pad) counts as heading
    -- inward, towards the code.
    local dir = "l"
    if valid(previous) and not is_pad(previous) and vim.fn.win_screenpos(previous)[2] > vim.fn.win_screenpos(pad)[2] then
        dir = "h"
    end

    bouncing = true
    local ok, err = pcall(function()
        -- Several pads can sit side by side once a split is thrown in.
        while is_pad(vim.api.nvim_get_current_win()) do
            local from = vim.api.nvim_get_current_win()
            vim.cmd("wincmd " .. dir)
            if vim.api.nvim_get_current_win() == from then
                break -- edge of the screen
            end
        end
        if is_pad(vim.api.nvim_get_current_win()) then
            local target = (valid(previous) and not is_pad(previous)) and previous or content_wins(0)[1]
            if valid(target) then
                vim.api.nvim_set_current_win(target)
            end
        end
    end)
    bouncing = false
    if not ok then
        vim.notify("Centered view: " .. tostring(err), vim.log.levels.WARN)
    end
end

function M.is_enabled()
    return enabled
end

function M.enable()
    enabled = true
    augroup = vim.api.nvim_create_augroup("centered_view", { clear = true })
    -- Every way the layout can change: splits opening and closing, the
    -- explorer or a terminal appearing, the terminal window resizing, another
    -- buffer being shown.
    vim.api.nvim_create_autocmd(
        { "WinNew", "WinClosed", "WinResized", "VimResized", "BufWinEnter", "TabEnter" },
        {
            group = augroup,
            callback = function()
                vim.schedule(refresh)
            end,
        }
    )
    vim.api.nvim_create_autocmd("WinEnter", {
        group = augroup,
        callback = function()
            bounce()
            vim.schedule(refresh)
        end,
    })
    -- Fold the padding away before it can be counted as a window: without
    -- this, :q on the last real window would leave two empty pads behind
    -- instead of quitting, and a session would be written with them in it.
    vim.api.nvim_create_autocmd({ "QuitPre", "VimLeavePre" }, {
        group = augroup,
        callback = close_pads,
    })
    refresh()
end

function M.disable()
    enabled = false
    if augroup then
        vim.api.nvim_del_augroup_by_id(augroup)
        augroup = nil
    end
    close_pads()
end

function M.toggle()
    if enabled then
        M.disable()
    else
        M.enable()
    end
    if enabled then
        vim.fn.writefile({}, state_file)
    else
        vim.fn.delete(state_file)
    end
    vim.notify("Centered view " .. (enabled and "on" or "off"), vim.log.levels.INFO)
end

-- Called from vim-options.lua. Restores the last state once the startup
-- layout exists — including after a session is loaded, which replaces the
-- window layout wholesale.
function M.setup()
    if vim.fn.filereadable(state_file) ~= 1 then
        return
    end
    vim.api.nvim_create_autocmd({ "VimEnter", "SessionLoadPost" }, {
        callback = function()
            vim.schedule(function()
                if enabled then
                    refresh()
                else
                    M.enable()
                end
            end)
        end,
    })
end

return M
