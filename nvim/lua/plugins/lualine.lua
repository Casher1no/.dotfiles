return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
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
            lualine_b = { "branch", "diff", "diagnostics" },
            -- Relative file path (path = 1). Use 3 for absolute path.
            lualine_c = { { "filename", path = 1, file_status = true } },
            lualine_x = { "filetype" },
            lualine_y = { "progress" }, -- percentage through the file
            lualine_z = { "location" }, -- line:column
        },
        inactive_sections = {
            lualine_c = { { "filename", path = 1 } },
            lualine_x = { "location" },
        },
    },
}
