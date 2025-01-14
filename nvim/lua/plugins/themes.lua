return {
    {
        "zaldih/themery.nvim",
        lazy = false,
        config = function()
            local config = require("themery")
            config.setup({
                themes = { "catppuccin", "kanagawa-wave" },
                livePreview = true,
            })
        end
    },

    -- themes
    {
        "rebelot/kanagawa.nvim",
        lazy = false,
    },
    {
        "catppuccin/nvim",
        lazy = false,
        name = "catppuccin",
        priority = 1000,

        config = function()
            vim.cmd.colorscheme("catppuccin")
        end,
    },
}
