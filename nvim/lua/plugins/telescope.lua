-- Recent files limited to the current project (cwd), most-recent first, max 8.
-- Uses Telescope's file entry maker so each row gets a filetype icon, and the
-- default vertical layout puts a live preview under the list.
local function project_recent_files()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local make_entry = require("telescope.make_entry")
    local conf = require("telescope.config").values

    local cwd = vim.loop.cwd()
    -- Live MRU order (current file first, previously visited next, …), max 12.
    local files = require("util.mru").for_cwd(cwd, 12)

    pickers
        .new({}, {
            prompt_title = "Recent Files — " .. vim.fn.fnamemodify(cwd, ":t"),
            finder = finders.new_table({
                results = files,
                entry_maker = make_entry.gen_from_file({ cwd = cwd }),
            }),
            sorter = conf.file_sorter({}),
            previewer = conf.file_previewer({}),
            -- Start on the *previous* file so a quick <CR> flips back to it.
            default_selection_index = math.min(2, #files),
        })
        :find()
end

return {
    "nvim-telescope/telescope.nvim",
    -- Track the default branch: the old 0.1.x release still calls the
    -- deprecated vim.lsp.util.jump_to_location.
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
    },
    cmd = "Telescope", -- also load when invoked as :Telescope (e.g. from the dashboard)
    keys = {
        -- JetBrains-style: <C-p> for files, double-shift feel via <leader>ff
        { "<C-p>", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
        { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep (search in files)" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Open buffers" },
        { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files (all)" },
        { "<leader>fp", project_recent_files, desc = "Recent files (this project, max 12)" },
        { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
        { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Search word under cursor" },
        -- Changed/added/removed files with a diff preview underneath.
        { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git changes (status + diff)" },
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
            -- Hide Unity's .meta sidecar files from every picker (find_files,
            -- live_grep, grep_string, …). Lua patterns, matched against the path.
            file_ignore_patterns = { "%.meta$" },
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
