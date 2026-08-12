return {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
        -- Gutter signs for changed lines (enabled)
        signcolumn = true,
        attach_to_untracked = false,
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
            -- Skip signs entirely for files with no commit history yet — a
            -- freshly `git add`ed new file is still "tracked", so
            -- attach_to_untracked above won't catch it, but every line would
            -- show as added (diffed against a HEAD that lacks the file).
            -- The no-history answer requires git to walk the entire history,
            -- so the check runs async and detaches after the fact (signs may
            -- flash briefly) instead of blocking every buffer open; the hunk
            -- keymaps below stay but no-op once detached.
            local filepath = vim.api.nvim_buf_get_name(bufnr)
            if filepath ~= "" then
                pcall(
                    vim.system,
                    { "git", "log", "-1", "--oneline", "--", filepath },
                    { cwd = vim.fs.dirname(filepath) },
                    vim.schedule_wrap(function(out)
                        -- The no-history answer is the slow one (full history
                        -- walk) — long enough for :saveas / an LSP rename to
                        -- repoint the buffer at a different file, so re-check
                        -- the name before detaching.
                        if
                            out.code == 0
                            and vim.trim(out.stdout or "") == ""
                            and vim.api.nvim_buf_is_valid(bufnr)
                            and vim.api.nvim_buf_get_name(bufnr) == filepath
                        then
                            require("gitsigns").detach(bufnr)
                        end
                    end)
                )
            end

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
