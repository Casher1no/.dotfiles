-- Real multiple cursors (IDE-style): every line of a visual selection
-- gets its own cursor and edits appear on all lines live as you type —
-- unlike vim's built-in block insert, which replays the edit on the other
-- lines only after leaving insert mode.
-- Flow: Alt+V (visual block, see vim-options.lua) → grow the selection with
-- j/k or arrows → i/a (or I/A) → type; Esc once to stop editing, Esc again
-- to drop the extra cursors.
-- https://github.com/jake-stewart/multicursor.nvim
return {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
        local mc = require("multicursor-nvim")
        mc.setup()

        -- Turn the visual selection into one cursor per line and enter
        -- insert (before the selection) / append (after it).
        vim.keymap.set("x", "I", mc.insertVisual, { desc = "Insert on every selected line" })
        vim.keymap.set("x", "A", mc.appendVisual, { desc = "Append on every selected line" })

        -- In visual *block* mode, plain i/a do the same — nobody wants an
        -- iw-style text object there. Other visual modes keep the built-in
        -- text-object behavior ("\22" is the CTRL-V blockwise mode).
        vim.keymap.set("x", "i", function()
            if vim.fn.mode() == "\22" then
                mc.insertVisual()
            else
                vim.api.nvim_feedkeys("i", "n", false)
            end
        end, { desc = "Insert on every selected line / inner text object" })
        vim.keymap.set("x", "a", function()
            if vim.fn.mode() == "\22" then
                mc.appendVisual()
            else
                vim.api.nvim_feedkeys("a", "n", false)
            end
        end, { desc = "Append on every selected line / around text object" })

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
