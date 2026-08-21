-- IDE-style match-case toggle for find_files / live_grep (wired to the
-- keymaps in plugins/telescope.lua). Pickers always open case-insensitive —
-- Telescope's default live_grep is --smart-case, so one capital letter used
-- to silently make the search case-sensitive. A badge on the right side of
-- the prompt shows the state: the "Aa ⟨C-s⟩" hint stays put and only its
-- color changes, so the prompt never reflows as you toggle. <C-s> flips it
-- for the current picker only: the typed query is kept, and the next picker
-- starts insensitive again.
--
-- Same pattern for hiding tests: <C-t> flips a "tests ⟨C-t⟩" filter that
-- drops results in test folders and colocated test files (classification
-- shared with the explorer via util/tree_tints). Pickers open with the
-- filter already on; <leader>fF / <leader>fG open with tests included.
--
-- Both pickers rank their results by file relevance (util/search_rank):
-- source files in the project's own languages first, config/data and docs
-- below them, generated output last.
local M = {}

local ns = vim.api.nvim_create_namespace("telescope_case_badge")

-- Right-aligned state badges in the prompt line, filter-button
-- style. Sit next to Telescope's own "m / n" counter (also right-aligned
-- virtual text), so keep them short.
local function place_badge(prompt_bufnr, state)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        -- Same label in both states, only the highlight changes.
        local virt = {
            { " tests ⟨C-t⟩ ", state.no_tests and "DiagnosticWarn" or "Comment" },
            { " Aa ⟨C-s⟩ ", state.sensitive and "DiagnosticOk" or "Comment" },
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

-- Highlight the typed query inside the grep preview (IDE-style: every
-- occurrence of the searched word lights up, not just the matched line).
-- The preview WINDOW survives entry switches, so one window-local matchadd
-- covers every previewed file; it's refreshed on each prompt edit and its
-- case-sensitivity follows the <C-s> state. TelescopePreviewMatch is the
-- group telescope's own previewers use (links to Search).
local function attach_preview_highlight(prompt_bufnr, sensitive)
    local match_id
    local function update()
        local action_state = require("telescope.actions.state")
        local picker = action_state.get_current_picker(prompt_bufnr)
        local pstate = picker and picker.previewer and picker.previewer.state
        local win = pstate and pstate.winid
        if not (win and vim.api.nvim_win_is_valid(win)) then
            return
        end
        vim.api.nvim_win_call(win, function()
            if match_id then
                pcall(vim.fn.matchdelete, match_id)
                match_id = nil
            end
            local query = vim.trim(action_state.get_current_line() or "")
            if query == "" then
                return
            end
            local case = sensitive and "\\C" or "\\c"
            -- rg treats the prompt as a regex; very-magic covers the common
            -- syntax (|, (), +, ?, []). An unparsable pattern falls back to
            -- a literal match so partial regexes don't flash errors mid-typing.
            local ok, id = pcall(vim.fn.matchadd, "TelescopePreviewMatch", case .. "\\v" .. query)
            if not ok then
                ok, id = pcall(vim.fn.matchadd, "TelescopePreviewMatch", case .. "\\V" .. vim.fn.escape(query, "\\"))
            end
            match_id = ok and id or nil
        end)
    end
    -- buf_attach rather than TextChanged autocmds: it fires for every way
    -- the prompt can change (typing, <C-v> paste, API edits). Detaches
    -- automatically when telescope wipes the prompt buffer on close.
    vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
            vim.schedule(update)
        end,
    })
    -- Initial paint for relaunches carrying default_text — deferred because
    -- the previewer window only exists after the first results render (every
    -- later keystroke re-runs update anyway, so a miss here self-heals).
    vim.defer_fn(update, 100)
end

-- state = { sensitive = bool, no_tests = bool }
local function launch(name, state, text)
    local opts = {
        default_text = text,
        attach_mappings = function(prompt_bufnr, map)
            place_badge(prompt_bufnr, state)
            if name == "live_grep" then
                attach_preview_highlight(prompt_bufnr, state.sensitive)
            end
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
    end

    -- Both sorters rank results by file relevance (util/search_rank): code
    -- above templates above json/markdown above generated files.
    local rank = require("util.search_rank")
    if name == "live_grep" then
        opts.sorter = rank.grep_sorter()
        -- live_grep respawns rg on every keystroke; debounce so fast typing
        -- doesn't fork a process per character. find_files stays undebounced —
        -- its per-keystroke filter is in-memory and instant feel matters more.
        opts.debounce = 80
        -- Explicit flag either way, otherwise rg falls back to --smart-case
        -- from the default vimgrep_arguments.
        opts.additional_args = { state.sensitive and "--case-sensitive" or "--ignore-case" }
    else
        opts.sorter = rank.file_sorter(state.sensitive and sensitive_file_sorter() or nil)
    end

    require("telescope.builtin")[name](opts)
end

-- Tests are filtered out by default; <C-t> (or the *_with_tests variants)
-- brings them back.
function M.find_files()
    launch("find_files", { no_tests = true })
end

function M.live_grep()
    launch("live_grep", { no_tests = true })
end

function M.find_files_with_tests()
    launch("find_files", {})
end

function M.live_grep_with_tests()
    launch("live_grep", {})
end

return M
