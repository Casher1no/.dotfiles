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
    },
    cmd = "Telescope", -- also load when invoked as :Telescope (e.g. from the dashboard)
    keys = {
        -- IDE-style: <C-p> for files, double-shift feel via <leader>ff
        { "<C-p>", function() require("util.telescope_case").find_files() end, desc = "Find files" },
        -- ff/fg go through util/telescope_case.lua: always case-insensitive
        -- and with tests filtered out on open; <C-s> / <C-t> in the prompt
        -- toggle match case and the test filter for that search only — see
        -- the badges on the right of the prompt.
        { "<leader>ff", function() require("util.telescope_case").find_files() end, desc = "Find files" },
        { "<leader>fg", function() require("util.telescope_case").live_grep() end, desc = "Live grep (search in files)" },
        -- Capital variants start with tests included; <C-t> in the prompt
        -- flips the filter either way.
        { "<leader>fF", function() require("util.telescope_case").find_files_with_tests() end, desc = "Find files (with tests)" },
        { "<leader>fG", function() require("util.telescope_case").live_grep_with_tests() end, desc = "Live grep (with tests)" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Open buffers" },
        { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files (all)" },
        { "<leader>fp", project_recent_files, desc = "Recent files (this project, max 12)" },
        { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
        { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Search word under cursor" },
        -- Changed/added/removed files with a diff preview underneath.
        { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git changes (status + diff)" },
        -- File history, IDE-style: commits that touched this file, each one
        -- previewed as code with red/green lines (util/git_history.lua).
        -- <CR> opens that revision in a diff against the working copy.
        { "<leader>gh", function() require("util.git_history").open() end, desc = "File history (commits touching this file)" },
        { "<leader>gh", function() require("util.git_history").open_range() end, mode = "x", desc = "History of the selected lines" },
    },
    opts = function()
        -- Row tints matching the explorer: results in test folders get the
        -- green background, package folders the gray one (util/telescope_tints).
        require("util.telescope_tints")

        -- Hide Unity's .meta sidecar files from every picker (find_files,
        -- live_grep, grep_string, …). Lua patterns, matched against the path.
        -- Also skip dependency/package folders: in projects without git,
        -- rg/fd have no .gitignore to respect, so vendor and node_modules
        -- would otherwise flood every search.
        -- .git/ too: find_files runs with hidden = true (dotfiles are often
        -- what's being looked for), which otherwise drags in every hook
        -- sample and object file under .git.
        local file_ignore_patterns = { "%.meta$", "^%.git/", "/%.git/" }
        for _, dir in ipairs({ "node_modules", "vendor", "%.venv", "venv", "__pycache__" }) do
            vim.list_extend(file_ignore_patterns, { "^" .. dir .. "/", "/" .. dir .. "/" })
        end
        if require("util.unity").is_unity_project() then
            -- Prefabs/scenes/assets are huge serialized YAML blobs, not code —
            -- searching them just buries real matches under noise.
            vim.list_extend(file_ignore_patterns, {
                "%.prefab$",
                "%.unity$",
                "%.asset$",
            })
        end

        return {
            defaults = {
                -- "Search Everywhere" look:
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
                -- The preview re-renders on every selection change while
                -- typing — cap it so one big file can't stall the picker.
                preview = {
                    filesize_limit = 1, -- MB
                    timeout = 250, -- ms
                },
                path_display = { "truncate" },
                file_ignore_patterns = file_ignore_patterns,
                mappings = {
                    i = {
                        ["<C-j>"] = "move_selection_next",
                        ["<C-k>"] = "move_selection_previous",
                        ["<Esc>"] = "close", -- single Esc closes
                        -- Paste the system clipboard into the prompt. The prompt
                        -- is a normal insert-mode buffer, so feed <C-r>+ to pull
                        -- in the + (system clipboard) register.
                        ["<C-v>"] = function()
                            vim.api.nvim_feedkeys(
                                vim.api.nvim_replace_termcodes("<C-r>+", true, false, true),
                                "n",
                                false
                            )
                        end,
                    },
                },
            },
            pickers = {
                find_files = {
                    hidden = true, -- show dotfiles
                },
            },
        }
    end,
}
