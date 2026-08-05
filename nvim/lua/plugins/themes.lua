return {
    {
        "zaldih/themery.nvim",
        lazy = false,
        config = function()
            local config = require("themery")
            -- Upstream bug (themery bfa58f4): normalizePaths() reads the
            -- misspelled key `themeConfigFile` instead of the documented
            -- `themesConfigFile`, so it normalizes nil into "<cwd>/v:null" and
            -- then decides the option is "set" unless that string still
            -- contains "v:null". On Windows the normalized path comes back as
            -- "C:\...\v:\null", the match fails, and the deprecation warning
            -- fires on every startup (with a hit-enter prompt) even though
            -- nothing below sets it. Swallow only that one message.
            local real_print = print
            print = function(...)
                local msg = ...
                if type(msg) == "string" and msg:find("themeConfigFile", 1, true) then
                    return
                end
                return real_print(...)
            end
            local ok, err = pcall(config.setup, {
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
                    "everforest",
                    "cyberdream",
                    "vscode",
                    "dracula",
                    "nord",
                },
                livePreview = true,
            })
            print = real_print
            if not ok then
                error(err)
            end
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
    {
        "neanias/everforest-nvim",
        lazy = false,
    },
    {
        "scottmckendry/cyberdream.nvim",
        lazy = false,
    },
    {
        "Mofiqul/vscode.nvim",
        lazy = false,
    },
    {
        "Mofiqul/dracula.nvim",
        lazy = false,
    },
    {
        "gbprod/nord.nvim",
        lazy = false,
    },
}
