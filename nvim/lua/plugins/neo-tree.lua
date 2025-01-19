return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },

    config = function()
        vim.keymap.set("n", "<C-e>", ":Neotree toggle<CR>", { noremap = true, silent = true, desc = "Toggle Neo-tree" })
        require("neo-tree").setup({
            window = {
                position = "right",
                -- width = 40
            },
            default_component_configs = {
                indent = {
                    indent_size = 1,
                    padding = 1, -- extra padding on left hand side
                    with_markers = false,
                    highlight = "NeoTreeIndentMarker",
                    with_expanders = true,
                    expander_collapsed = "",
                    expander_expanded = "",
                    expander_highlight = "NeoTreeExpander",
                },
            },
            filesystem = {
                follow_current_file = {
                    enabled = true,
                },
                filtered_items = {
                    visible = false,
                    hide_dotfiles = false,
                    hide_gitignore = true,
                    hide_by_pattern = {
                        "*.meta",
                    },
                    never_show = {
                        ".git",
                    },
                },
            },
        })
    end,
}
