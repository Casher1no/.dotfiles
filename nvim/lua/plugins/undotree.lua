-- A browsable view of the undo tree — the local history of the buffer.
--
-- vim-options.lua already persists that history to disk ('undofile', 10000
-- levels), so every state a file has been in since you first opened it is
-- still on disk tomorrow. Until now there was no way to *reach* it: <C-z>
-- walks backwards one step at a time, and the moment you type after undoing,
-- vim forks a new branch and the states you undid past are unreachable by
-- <C-z> / <C-S-z> entirely — they are still in the tree, just not on the
-- path those keys walk. This is the window onto the branches.
--
-- <leader>u opens it on the left (neo-tree lives on the right, so the two
-- don't fight over the same side). Move with j/k for every state, J/K to skip
-- to the next actual change, <CR> to restore the buffer to the highlighted
-- state, q to close. The diff of the highlighted state against the current
-- one renders in a float rather than a bottom split.
--
-- Pure Lua, no paths and no subprocess, so there is nothing here to differ
-- across Windows / macOS / Linux.
-- https://github.com/jiaoshijie/undotree
return {
    "jiaoshijie/undotree",
    dependencies = "nvim-lua/plenary.nvim",
    keys = {
        {
            "<leader>u",
            function()
                require("undotree").toggle()
            end,
            desc = "Undo history (local history)",
        },
    },
    opts = {
        -- The diff of the highlighted state against the current one renders
        -- in a centered float instead of a split under the panel. Note that
        -- this switches off `layout` and `window.height` entirely — both are
        -- only read on the split path (undotree/ui.lua:30,32), so setting
        -- them here would look configured and do nothing.
        float_diff = true,
        position = "left",
        window = {
            width = 0.25, -- fraction of the editor width, panel only
            border = "rounded",
        },
        -- Buffers with no undo history worth browsing. The plugin's own two
        -- filetypes are in here because <leader>u is global: pressing it
        -- inside the panel should not try to open a panel for the panel.
        ignore_filetype = {
            "undotree",
            -- Capitalised exactly as the plugin sets it (runtime.lua:172).
            -- Its own README spells this "undotreeDiff", which never matches.
            "UndotreeDiff",
            "neo-tree",
            "snacks_dashboard",
            "snacks_terminal",
            "terminal",
            "TelescopePrompt",
            "grug-far",
            "trouble",
            "qf",
            "help",
        },
    },
}
