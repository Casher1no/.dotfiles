-- Project-wide find & replace on ripgrep — JetBrains "Replace in Files".
-- Opens a buffer UI: type the search and replacement, results update live
-- with the keybinds listed in its header (replace-all, sync a single line,
-- open a result). <leader>sr stays the file-scoped :substitute; this is the
-- multi-file half.
return {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    keys = {
        {
            "<leader>sR",
            function()
                require("grug-far").open()
            end,
            desc = "Replace in project (grug-far)",
        },
        {
            "<leader>sR",
            function()
                -- prefill the search with the visual selection
                require("grug-far").with_visual_selection()
            end,
            mode = "x",
            desc = "Replace selection in project (grug-far)",
        },
        {
            "<leader>sw",
            function()
                require("grug-far").open({ prefills = { search = vim.fn.expand("<cword>") } })
            end,
            desc = "Replace word under cursor in project",
        },
    },
    opts = {
        -- JetBrains-style: literal matching by default, so replacing ":"
        -- with "-" needs no regex escaping; delete the flag in the UI's
        -- Flags field for a regex search
        engines = { ripgrep = { extraArgs = "--fixed-strings" } },
        keymaps = {
            -- by default <up>/<down> open the prev/next match in a window;
            -- unbind so arrow keys just move the cursor
            openNextLocation = false,
            openPrevLocation = false,
        },
        -- the shortcut cheat-sheet header; util/grug_buttons.lua puts a
        -- Replace / Replace All button bar above the window instead
        helpLine = { enabled = false },
    },
    config = function(_, opts)
        require("grug-far").setup(opts)
        -- FileType covers first open; BufWinEnter covers re-opening a
        -- hidden instance (attach no-ops while a bar is already up)
        vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
            group = vim.api.nvim_create_augroup("GrugFarButtons", {}),
            callback = function(ev)
                if vim.bo[ev.buf].filetype == "grug-far" then
                    require("util.grug_buttons").attach(ev.buf)
                end
            end,
        })
    end,
}
