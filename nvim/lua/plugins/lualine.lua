return {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
        options = {
            theme = "auto", -- follows your colorscheme (catppuccin / kanagawa)
            globalstatus = true, -- one statusline across all splits
            section_separators = { left = "", right = "" },
            component_separators = { left = "", right = "" },
        },
        sections = {
            lualine_a = { "mode" },
            lualine_b = {
                "branch",
                {
                    "diagnostics",
                    sources = { "nvim_diagnostic" },
                    sections = { "error", "warn", "info", "hint" },
                },
            },
            -- Filename only (path = 0). Use 1 for relative, 3 for absolute path.
            lualine_c = { { "filename", path = 0, file_status = true } },
            lualine_x = {
                {
                    "diff",
                    -- Pull added/modified/removed from gitsigns so counts reflect
                    -- the current buffer (including unsaved/added lines).
                    source = function()
                        local gs = vim.b.gitsigns_status_dict
                        if gs then
                            return { added = gs.added, modified = gs.changed, removed = gs.removed }
                        end
                    end,
                    symbols = { added = " ", modified = " ", removed = " " },
                },
                "filetype",
            },
            lualine_y = { "progress" }, -- percentage through the file
            lualine_z = { "location" }, -- line:column
        },
        inactive_sections = {
            lualine_c = { { "filename", path = 0 } },
            lualine_x = { "location" },
        },
    },
}
