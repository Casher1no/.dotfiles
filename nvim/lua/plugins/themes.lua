return {
    {
        "zaldih/themery.nvim",
        lazy = false,
        config = function()
            local config = require("themery")
            config.setup({
                -- Switchable colorschemes. Also exposed in the command palette
                -- (<leader><space> → Themes), which calls setThemeByName to apply
                -- and persist the choice.
                themes = {
                    "catppuccin",
                    "kanagawa-wave",
                    "gruvbox",
                    "oxocarbon",
                    "onedark",
                    "rose-pine",
                },
                livePreview = true,
            })
        end,
    },

    -- themes
    {
        "rebelot/kanagawa.nvim",
        lazy = false,
    },
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,
    },
    {
        "nyoom-engineering/oxocarbon.nvim",
        lazy = false,
    },
    {
        -- One Dark Pro. Provides the "onedark" colorscheme (plus onelight,
        -- onedark_vivid, onedark_dark).
        "olimorris/onedarkpro.nvim",
        lazy = false,
    },
    {
        "rose-pine/neovim",
        name = "rose-pine",
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
