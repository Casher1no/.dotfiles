return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    keys = {
        { "<leader>e", "<cmd>Neotree toggle right<cr>", desc = "Toggle file explorer" },
        { "<leader>o", "<cmd>Neotree focus right<cr>", desc = "Focus file explorer" },
    },
    opts = {
        close_if_last_window = true,
        enable_git_status = true,
        enable_diagnostics = true,
        commands = {
            -- Open files / expand folders, but when collapsing an already-expanded
            -- folder, recursively collapse everything inside it too. That way the
            -- next time you expand it, its child folders start collapsed.
            toggle_or_recursive_collapse = function(state)
                local cc = require("neo-tree.sources.filesystem.commands")
                local node = state.tree:get_node()
                if node and node.type == "directory" and node:is_expanded() then
                    cc.close_all_subnodes(state)
                else
                    cc.open(state)
                end
            end,
        },
        window = {
            position = "right",
            width = 35,
            mappings = {
                ["<cr>"] = "toggle_or_recursive_collapse",
                ["<2-LeftMouse>"] = "toggle_or_recursive_collapse", -- double-click
                ["o"] = "toggle_or_recursive_collapse",
                ["<right>"] = "open", -- expand folder / open file
                ["<left>"] = "close_node", -- collapse folder
                ["s"] = "open_vsplit",
                ["S"] = "open_split",
                ["P"] = { "toggle_preview", config = { use_float = true } },
                ["a"] = "add",
                ["d"] = "delete",
                ["r"] = "rename",
                ["y"] = "copy_to_clipboard",
                ["x"] = "cut_to_clipboard",
                ["p"] = "paste_from_clipboard",
                ["R"] = "refresh",
                ["H"] = "toggle_hidden",
            },
        },
        filesystem = {
            follow_current_file = { enabled = true }, -- highlight the file you're editing
            use_libuv_file_watcher = true, -- auto-refresh on external changes
            filtered_items = {
                hide_dotfiles = false,
                hide_gitignored = false,
            },
        },
    },
    config = function(_, opts)
        require("neo-tree").setup(opts)
        -- Mouse must be on for clicking the tree
        vim.opt.mouse = "a"
    end,
}
