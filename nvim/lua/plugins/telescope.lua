return {
    "nvim-telescope/telescope.nvim",
    -- Track the default branch: the old 0.1.x release still calls the
    -- deprecated vim.lsp.util.jump_to_location.
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
    },
    keys = {
        -- JetBrains-style: <C-p> for files, double-shift feel via <leader>ff
        { "<C-p>", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep (search in files)" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Open buffers" },
        { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
        { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
        { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Search word under cursor" },
    },
    opts = {
        defaults = {
            -- JetBrains "Search Everywhere" look:
            -- prompt + file list on top, content preview on the bottom.
            layout_strategy = "vertical",
            layout_config = {
                vertical = {
                    prompt_position = "top",
                    mirror = true, -- results above preview
                    preview_height = 0.5,
                    width = 0.9,
                    height = 0.9,
                },
            },
            sorting_strategy = "ascending", -- best match directly under the prompt
            path_display = { "truncate" },
            mappings = {
                i = {
                    ["<C-j>"] = "move_selection_next",
                    ["<C-k>"] = "move_selection_previous",
                    ["<Esc>"] = "close", -- single Esc closes
                },
            },
        },
        pickers = {
            find_files = {
                hidden = true, -- show dotfiles
            },
        },
    },
}
