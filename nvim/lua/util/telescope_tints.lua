-- Full-width row tints for Telescope results (live_grep, find_files, …),
-- matching the neo-tree explorer: rows whose file lives under a test folder
-- get the light green background, package/vendor rows the gray one. Folder
-- classification and the pinned highlight groups come from util/tree_tints.
--
-- Same decoration-provider approach as tree_tints: Telescope rewrites the
-- results buffer on every keystroke, so persistent extmarks would be wiped
-- constantly; ephemeral marks recomputed at redraw time can't be. Rows are
-- painted as (row,0)..(row+1,0) ranges with hl_eol so the tint runs to the
-- window edge; fg-only match/icon highlights show through the bg-only tint.
local M = {}

local ns = vim.api.nvim_create_namespace("telescope_tints")
local tree_tints = require("util.tree_tints")

local tint_groups = {
    package = "NeoTreePackageTint",
    test = "NeoTreeTestTint",
}

-- Per results-buffer cache, valid for one changedtick:
-- { tick = n, picker = Picker|false, sel = row, [row] = hl group|false }.
-- Row groups are filled lazily by on_line, so only visible rows are mapped
-- (live_grep can hold thousands of results).
local cache = {}

-- Live TelescopeResults buffers, kept by the autocmds below. The decoration
-- provider is global and permanent: once registered, on_win fires for every
-- window on every redraw for the rest of the session (noice and friends force
-- redraws constantly), so its gate must be a plain table lookup
-- — even a vim.bo option read is too hot there.
local results_bufs = {}

local function picker_for(results_bufnr)
    local state = require("telescope.state")
    for _, prompt_bufnr in ipairs(state.get_existing_prompt_bufnrs()) do
        local status = state.get_status(prompt_bufnr)
        if status and status.picker and status.picker.results_bufnr == results_bufnr then
            return status.picker
        end
    end
end

-- Tint group for a results row, or nil. Separate from the provider callback
-- so it can be tested headlessly. Runs per visible row per redraw, so no
-- closure allocation here; picker.manager is nil until the finder produces
-- results (telescope guards it the same way).
function M._group_for_row(picker, row)
    local manager = picker.manager
    if not manager then
        return nil
    end
    local ok, index = pcall(picker.get_index, picker, row)
    local entry
    if ok then
        ok, entry = pcall(manager.get_entry, manager, index)
    end
    local filename = ok and entry and entry.filename
    if type(filename) ~= "string" then
        return nil
    end
    local kind = tree_tints.classify(filename, picker.cwd)
    return kind and tint_groups[kind]
end

vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, _, bufnr)
        if not results_bufs[bufnr] then
            return false
        end
        local tick = vim.api.nvim_buf_get_changedtick(bufnr)
        local c = cache[bufnr]
        if not c or c.tick ~= tick then
            c = { tick = tick, picker = picker_for(bufnr) or false }
            cache[bufnr] = c
        end
        if not c.picker then
            return false
        end
        -- Skip the selected row so TelescopeSelection stays fully visible
        -- (same reasoning as the cursorline skip in tree_tints).
        local ok, sel = pcall(c.picker.get_selection_row, c.picker)
        c.sel = ok and sel or nil
        return true
    end,
    on_line = function(_, _, bufnr, row)
        local c = cache[bufnr]
        if not c or not c.picker then
            return
        end
        local group = c[row]
        if group == nil then
            group = M._group_for_row(c.picker, row) or false
            c[row] = group
        end
        if group and row ~= c.sel then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                ephemeral = true,
                end_row = row + 1,
                end_col = 0,
                hl_group = group,
                hl_eol = true,
                priority = 10,
            })
        end
    end,
})

local group = vim.api.nvim_create_augroup("telescope_tints", { clear = true })

-- Telescope sets this filetype on every results buffer it creates
-- (pickers.lua, nvim_set_option_value on results_bufnr).
vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "TelescopeResults",
    callback = function(args)
        results_bufs[args.buf] = true
    end,
})

-- Telescope wipes its results buffers on close; drop their cache entries.
vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
        results_bufs[args.buf] = nil
        cache[args.buf] = nil
    end,
})

return M
