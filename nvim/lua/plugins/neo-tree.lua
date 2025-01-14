return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },

    config = function()
        vim.keymap.set('n', '<C-e>', ':Neotree toggle<CR>', {})

        local config = require("neo-tree")
        config.setup({
            window = {
                position = "right",
                -- width = 40
            },
            default_component_configs = {
                indent = {
                    indent_size = 1,
                    padding = 1, -- extra padding on left hand side
                    -- indent guides
                    with_markers = false,
                    -- indent_marker = "│",
                    -- last_indent_marker = "└",
                    highlight = "NeoTreeIndentMarker",
                }
            },
            filesystem = {
                filtered_items = {
                    visible = false,
                    hide_dotfiles = false,
                    hide_gitignore = true,
                    hide_by_pattern = {
                        "*.meta"
                    },
                    never_show = {
                        ".git"
                    }
                }
            },
            follow_current_file = {
                enabled = true,
            }
        })
    end
}
