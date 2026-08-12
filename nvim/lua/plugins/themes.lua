return {
    {
        "zaldih/themery.nvim",
        -- The persisted theme is applied at startup by catppuccin's config
        -- below, straight from themery's state file, so themery only has to
        -- load for the picker and for persisting a new choice. The command
        -- palette's require("themery") (util/palette.lua, Themes category)
        -- auto-loads it too; its previews use plain vim.cmd.colorscheme and
        -- never touch themery.
        cmd = "Themery",
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

    -- themes: all lazy. lazy.nvim's ColorSchemePre autocmd loads whichever
    -- unloaded plugin ships colors/<name> when :colorscheme asks for it
    -- (lazy.nvim loader.lua M.colorscheme), so the startup apply below,
    -- themery's live preview and the palette previews all keep working.
    {
        "rebelot/kanagawa.nvim",
        lazy = true,
    },
    {
        "ellisonleao/gruvbox.nvim",
        lazy = true,
    },
    {
        "nyoom-engineering/oxocarbon.nvim",
        lazy = true,
    },
    {
        -- One Dark Pro. Provides the "onedark" colorscheme (plus onelight,
        -- onedark_vivid, onedark_dark).
        "olimorris/onedarkpro.nvim",
        lazy = true,
    },
    {
        "rose-pine/neovim",
        name = "rose-pine",
        lazy = true,
    },
    {
        "catppuccin/nvim",
        lazy = false,
        name = "catppuccin",
        priority = 1000,

        config = function()
            -- Apply the theme themery persisted without loading themery, so
            -- exactly one colorscheme runs per startup. State format (themery
            -- bfa58f4, persistence.lua saveTheme): stdpath("data")/themery/
            -- state.json, JSON with a "colorscheme" string. Its before/after
            -- code fields are ignored here — the themes list above registers
            -- plain strings, so they are always empty. Catppuccin is the
            -- fallback when there is no usable state.
            local applied = false
            local file = io.open(vim.fn.stdpath("data") .. "/themery/state.json", "r")
            if file then
                local ok, state = pcall(vim.json.decode, file:read("*a"))
                file:close()
                if ok and type(state) == "table" and type(state.colorscheme) == "string" then
                    applied = pcall(vim.cmd.colorscheme, state.colorscheme)
                end
            end
            if not applied then
                vim.cmd.colorscheme("catppuccin")
            end
        end,
    },
    {
        "neanias/everforest-nvim",
        lazy = true,
    },
    {
        "scottmckendry/cyberdream.nvim",
        lazy = true,
    },
    {
        "Mofiqul/vscode.nvim",
        lazy = true,
    },
    {
        "Mofiqul/dracula.nvim",
        lazy = true,
    },
    {
        "gbprod/nord.nvim",
        lazy = true,
    },
}
