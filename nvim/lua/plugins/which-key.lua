return {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        delay = 10,
        icons = {
            rules = false,
        },
        layout = { align = "center" },
        preset = "modern",
    },
    keys = {
        {
            "<leader>?",
            function()
                require("which-key").show({ global = false })
            end,
            desc = "Buffer Local Keymaps (which-key)",
        },
    },
}
