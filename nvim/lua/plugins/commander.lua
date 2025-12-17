return {
    "FeiyouG/commander.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    keys = {
        { "<leader>fc", "<CMD>Telescope commander<CR>", mode = "n", desc = "Commander" },
    },
    config = function()
        local commander = require("commander")
        commander.setup({
            components = {
                "DESC",
                "KEYS",
                "CAT",
            },
            sort_by = {
                "DESC",
                "KEYS",
                "CAT",
                "CMD",
            },
            integration = {
                telescope = {
                    enable = true,
                },
                lazy = {
                    enable = true,
                    set_plugin_name_as_cat = true,
                },
            },
        })

        commander.add({
            {
                desc = "Mason",
                cmd = "<CMD>Mason<CR>",
            },
            {
                desc = "Load Project",
                cmd = "<CMD>NeovimProjectDiscover<CR>",
            },
        })
    end,
}
