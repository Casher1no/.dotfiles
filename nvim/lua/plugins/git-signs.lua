return {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
        -- Gutter signs for changed lines (enabled)
        signcolumn = true,
        -- Off by default — toggle live with the keymaps below
        word_diff = false, -- highlight the exact changed words within a line
        numhl = false, -- highlight the line number
        linehl = false, -- highlight the whole line background
        current_line_blame = false, -- inline "who/when" annotation
        current_line_blame_opts = {
            virt_text = true,
            virt_text_pos = "eol",
            delay = 300,
        },
        signs = {
            add = { text = "▎" },
            change = { text = "▎" },
            delete = { text = "▁" },
            topdelete = { text = "▔" },
            changedelete = { text = "~" },
            untracked = { text = "▎" },
        },
        on_attach = function(bufnr)
            local gs = require("gitsigns")
            local function map(mode, l, r, desc)
                vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
            end

            -- Navigate between changed hunks
            map("n", "]h", function()
                gs.nav_hunk("next")
            end, "Next git hunk")
            map("n", "[h", function()
                gs.nav_hunk("prev")
            end, "Previous git hunk")

            -- Inspect / act on changes
            map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
            map("n", "<leader>hd", gs.diffthis, "Diff this file")
            map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
            map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
            map("n", "<leader>hb", function()
                gs.blame_line({ full = true })
            end, "Blame line (full)")

            -- Toggle the optional display modes on/off live
            map("n", "<leader>tb", gs.toggle_current_line_blame, "Toggle line blame")
            map("n", "<leader>tw", gs.toggle_word_diff, "Toggle word diff")
            map("n", "<leader>tl", gs.toggle_linehl, "Toggle line highlight")
            map("n", "<leader>td", gs.toggle_deleted, "Toggle deleted lines")
        end,
    },
}
