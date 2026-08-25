-- Renders the command-line (`:`) as a small centered floating popup with its
-- completion suggestions attached, instead of the bottom command line, and
-- takes over LSP hover/signature rendering (K shows docs as highlighted
-- markdown in a rounded float, IDE-style). Messages/notifications are left
-- alone to keep the change minimal.
return {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
        "MunifTanjim/nui.nvim",
    },
    -- Docs-float scrolling lives on <S-Up>/<S-Down> in lua/vim-options.lua,
    -- which prefers an open K popup and falls back to a 45-line cursor jump.
    opts = {
        cmdline = {
            enabled = true,
            view = "cmdline_popup",
        },
        messages = { enabled = false },
        notify = { enabled = false },
        lsp = {
            -- Route doc rendering through noice for treesitter-highlighted
            -- markdown instead of the plain default float.
            override = {
                ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
                ["vim.lsp.util.stylize_markdown"] = true,
            },
            hover = { enabled = true, silent = true }, -- no "no info" spam
            -- Pretty rendering for <C-k> signature help, but never auto-popup
            -- while typing.
            signature = { enabled = true, auto_open = { enabled = false } },
            message = { enabled = false },
            documentation = {
                view = "hover",
                opts = {
                    border = { style = "rounded", padding = { 0, 1 } },
                    size = { max_width = 90, max_height = 25 },
                    win_options = { concealcursor = "n", conceallevel = 3 },
                },
            },
        },
        popupmenu = {
            enabled = true,
        },
        -- LSP progress stays visible for the meaningful one-time phases
        -- (importing projects, building workspace, service ready) but the
        -- per-keystroke spam jdtls emits on every edit is dropped.
        routes = {
            { filter = { event = "lsp", kind = "progress", find = "Validate documents" }, opts = { skip = true } },
            { filter = { event = "lsp", kind = "progress", find = "Publish Diagnostics" }, opts = { skip = true } },
        },
        -- Centers the cmdline popup and its suggestion popupmenu together.
        presets = {
            command_palette = true,
        },
    },
}
