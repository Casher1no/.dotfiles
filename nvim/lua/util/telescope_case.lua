-- JetBrains-style match-case toggle for find_files / live_grep (wired to the
-- keymaps in plugins/telescope.lua). Pickers always open case-insensitive —
-- Telescope's default live_grep is --smart-case, so one capital letter used
-- to silently make the search case-sensitive. A badge on the right side of
-- the prompt shows the state: a dim "Aa ⟨C-s⟩" hint while insensitive, a
-- highlighted "Aa ✓" while match case is on. <C-s> flips it for the current
-- picker only: the typed query is kept, and the next picker starts
-- insensitive again.
--
-- Same pattern for hiding tests: <C-t> flips a "tests" filter that drops
-- results in test folders and colocated test files (classification shared
-- with the explorer via util/tree_tints). <leader>fF / <leader>fG open with
-- the filter already on.
local M = {}

local ns = vim.api.nvim_create_namespace("telescope_case_badge")

-- Right-aligned state badges in the prompt line, JetBrains filter-button
-- style. Sit next to Telescope's own "m / n" counter (also right-aligned
-- virtual text), so keep them short.
local function place_badge(prompt_bufnr, state)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        local virt = {
            state.no_tests and { " tests ✗ ", "DiagnosticWarn" } or { " tests ⟨C-t⟩ ", "Comment" },
            state.sensitive and { " Aa ✓ ", "DiagnosticOk" } or { " Aa ⟨C-s⟩ ", "Comment" },
        }
        vim.api.nvim_buf_set_extmark(prompt_bufnr, ns, 0, 0, {
            virt_text = virt,
            virt_text_pos = "right_align",
        })
    end)
end

-- file_ignore_patterns that hide tests, derived from the same folder/file
-- classification the explorer tints use (util/tree_tints), so "green in the
-- tree" and "hidden by the filter" always agree.
function M.test_ignore_patterns()
    local tt = require("util.tree_tints")
    local patterns = {}
    for dir in pairs(tt.test_dirs) do
        local esc = dir:gsub("(%p)", "%%%1")
        vim.list_extend(patterns, { "^" .. esc .. "/", "/" .. esc .. "/" })
    end
    for _, pat in ipairs(tt.test_file_patterns) do
        if pat:sub(1, 1) == "^" then
            -- Anchored to the file name (test_user.py): also match it as the
            -- last path segment, since pickers filter on the full path.
            vim.list_extend(patterns, { pat, "/" .. pat:sub(2) })
        else
            patterns[#patterns + 1] = pat
        end
    end
    return patterns
end

-- Case-sensitive fuzzy filter: every prompt char must appear in the line in
-- order, with exact case. The stock fuzzy file sorter matches lowercased
-- text only, so this is the extra gate that makes find_files strict.
local function subsequence(prompt, line)
    local pos = 1
    for i = 1, #prompt do
        local found = line:find(prompt:sub(i, i), pos, true)
        if not found then
            return false
        end
        pos = found + 1
    end
    return true
end

local function sensitive_file_sorter()
    local sorter = require("telescope.sorters").get_fuzzy_file()
    local score = sorter.scoring_function
    sorter.scoring_function = function(self, prompt, line, ...)
        if not subsequence(prompt, line) then
            return -1 -- telescope discards entries scored -1
        end
        return score(self, prompt, line, ...)
    end
    return sorter
end

-- state = { sensitive = bool, no_tests = bool }
local function launch(name, state, text)
    local opts = {
        default_text = text,
        attach_mappings = function(prompt_bufnr, map)
            place_badge(prompt_bufnr, state)
            -- Relaunch the same picker with one flag flipped, keeping the query.
            local function toggle(flag)
                return function()
                    local line = require("telescope.actions.state").get_current_line()
                    require("telescope.actions").close(prompt_bufnr)
                    local next_state = vim.tbl_extend("force", {}, state, { [flag] = not state[flag] })
                    launch(name, next_state, line)
                end
            end
            map({ "i", "n" }, "<C-s>", toggle("sensitive"), { desc = "Toggle match case" })
            map({ "i", "n" }, "<C-t>", toggle("no_tests"), { desc = "Toggle hide tests" })
            return true
        end,
    }

    if state.no_tests then
        -- Per-picker file_ignore_patterns replace the configured defaults
        -- (plugins/telescope.lua), so extend a copy of those.
        local defaults = require("telescope.config").values.file_ignore_patterns or {}
        opts.file_ignore_patterns = vim.list_extend(vim.deepcopy(defaults), M.test_ignore_patterns())
        opts.prompt_title = (name == "live_grep" and "Live Grep" or "Find Files") .. " — tests hidden"
    end

    if name == "live_grep" then
        -- Explicit flag either way, otherwise rg falls back to --smart-case
        -- from the default vimgrep_arguments.
        opts.additional_args = { state.sensitive and "--case-sensitive" or "--ignore-case" }
    elseif state.sensitive then
        opts.sorter = sensitive_file_sorter()
    end

    require("telescope.builtin")[name](opts)
end

function M.find_files()
    launch("find_files", {})
end

function M.live_grep()
    launch("live_grep", {})
end

function M.find_files_no_tests()
    launch("find_files", { no_tests = true })
end

function M.live_grep_no_tests()
    launch("live_grep", { no_tests = true })
end

return M
