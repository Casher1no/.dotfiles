return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree", -- also load when invoked as :Neotree (e.g. from the dashboard)
    keys = {
        {
            "<leader>e",
            function()
                -- Smart toggle:
                --   closed            -> open + focus
                --   open, not focused -> focus it
                --   open + focused    -> close it
                if vim.bo.filetype == "neo-tree" then
                    vim.cmd("Neotree close")
                else
                    vim.cmd("Neotree focus right")
                end
            end,
            desc = "Toggle/focus file explorer",
        },
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
            -- Return focus to the previously focused (code) window, leaving the
            -- explorer open.
            focus_previous_window = function()
                vim.cmd("wincmd p")
            end,
        },
        window = {
            position = "right",
            width = 35,
            mappings = {
                ["<esc>"] = "focus_previous_window",
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
                -- Hide Unity's .meta sidecar files. Still revealable with "H"
                -- (toggle_hidden) since they're hidden, not never_show.
                hide_by_pattern = { "*.meta" },
            },
        },
    },
    config = function(_, opts)
        require("neo-tree").setup(opts)
        -- Mouse must be on for clicking the tree
        vim.opt.mouse = "a"
    end,
}
