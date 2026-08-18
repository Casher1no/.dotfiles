-- Real multiple cursors (IDE-style): several carets edit at once and every
-- keystroke lands on all of them live — unlike vim's built-in block insert,
-- which replays the edit on the other lines only after leaving insert mode.
--
-- Two ways in:
--   Ctrl+Alt+Up/Down — stack a caret above/below the current one (hold to
--     add more), then i/a/c/o… and type; edits appear on every line at once.
--   Alt+V (visual block, see vim-options.lua) → grow with j/k or the arrows
--     → i/a (or I/A) — turns the column into one caret per line.
-- Esc once stops editing, Esc again drops the extra carets.
-- https://github.com/jake-stewart/multicursor.nvim
return {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
        local mc = require("multicursor-nvim")
        -- The public module doesn't expose the "busy" flag, only core does.
        local core = require("multicursor-nvim.core")
        mc.setup()

        -- While an action runs, multicursor feeds keys with the "x" flag,
        -- which flushes whatever is already sitting in the typeahead. A key
        -- that repeats faster than the action completes (holding a key, or a
        -- fast double tap) therefore re-enters the mapping mid-action and
        -- multicursor aborts with "An action is already being performed".
        -- Dropping the re-entrant call is harmless: the pending keypress just
        -- doesn't add a cursor.
        local function guard(fn)
            return function()
                if core.performingAction then
                    return
                end
                fn()
            end
        end

        -- Stack a caret above / below, keeping the current column.
        vim.keymap.set({ "n", "x" }, "<C-A-Up>", guard(function()
            mc.lineAddCursor(-1)
        end), { desc = "Add cursor above" })
        vim.keymap.set({ "n", "x" }, "<C-A-Down>", guard(function()
            mc.lineAddCursor(1)
        end), { desc = "Add cursor below" })

        -- Turn the visual selection into one cursor per line and enter
        -- insert (before the selection) / append (after it).
        vim.keymap.set("x", "I", guard(mc.insertVisual), { desc = "Insert on every selected line" })
        vim.keymap.set("x", "A", guard(mc.appendVisual), { desc = "Append on every selected line" })

        -- In visual *block* mode, plain i/a do the same — nobody wants an
        -- iw-style text object there. Other visual modes keep the built-in
        -- text-object behavior ("\22" is the CTRL-V blockwise mode).
        vim.keymap.set("x", "i", guard(function()
            if vim.fn.mode() == "\22" then
                mc.insertVisual()
            else
                vim.api.nvim_feedkeys("i", "n", false)
            end
        end), { desc = "Insert on every selected line / inner text object" })
        vim.keymap.set("x", "a", guard(function()
            if vim.fn.mode() == "\22" then
                mc.appendVisual()
            else
                vim.api.nvim_feedkeys("a", "n", false)
            end
        end), { desc = "Append on every selected line / around text object" })

        -- Keys that only exist while extra cursors are active.
        mc.addKeymapLayer(function(layerSet)
            -- First Esc re-enables paused cursors, second Esc removes them
            -- (and falls back to the global Esc mapping afterwards).
            layerSet("n", "<Esc>", function()
                if not mc.cursorsEnabled() then
                    mc.enableCursors()
                else
                    mc.clearCursors()
                end
            end)
        end)
    end,
}
