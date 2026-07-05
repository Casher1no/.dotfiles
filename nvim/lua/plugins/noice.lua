-- Renders the command-line (`:`) as a small centered floating popup with its
-- completion suggestions attached, instead of the bottom command line. Scoped
-- to just cmdline + its popupmenu — messages/notifications/LSP UI are left
-- alone to keep the change minimal.
return {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
        "MunifTanjim/nui.nvim",
    },
    opts = {
        cmdline = {
            enabled = true,
            view = "cmdline_popup",
        },
        messages = { enabled = false },
        notify = { enabled = false },
        lsp = {
            hover = { enabled = false },
            signature = { enabled = false },
            message = { enabled = false },
        },
        popupmenu = {
            enabled = true,
        },
        -- Centers the cmdline popup and its suggestion popupmenu together.
        presets = {
            command_palette = true,
        },
    },
}
