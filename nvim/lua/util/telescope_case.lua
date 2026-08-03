-- JetBrains-style match-case toggle for find_files / live_grep (wired to the
-- keymaps in plugins/telescope.lua). Pickers always open case-insensitive —
-- Telescope's default live_grep is --smart-case, so one capital letter used
-- to silently make the search case-sensitive. A badge on the right side of
-- the prompt shows the state: a dim "Aa ⟨C-s⟩" hint while insensitive, a
-- highlighted "Aa ✓" while match case is on. <C-s> flips it for the current
-- picker only: the typed query is kept, and the next picker starts
-- insensitive again.
local M = {}

local ns = vim.api.nvim_create_namespace("telescope_case_badge")

-- Right-aligned state badge in the prompt line, JetBrains match-case button
-- style. Sits next to Telescope's own "m / n" counter (also right-aligned
-- virtual text), so keep it short.
local function place_badge(prompt_bufnr, sensitive)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        vim.api.nvim_buf_set_extmark(prompt_bufnr, ns, 0, 0, {
            virt_text = sensitive and { { " Aa ✓ ", "DiagnosticOk" } }
                or { { " Aa ⟨C-s⟩ ", "Comment" } },
            virt_text_pos = "right_align",
        })
    end)
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

local function launch(name, sensitive, text)
    local opts = {
        default_text = text,
        attach_mappings = function(prompt_bufnr, map)
            place_badge(prompt_bufnr, sensitive)
            local function toggle()
                -- Relaunch the same picker with flipped case, keeping the query.
                local line = require("telescope.actions.state").get_current_line()
                require("telescope.actions").close(prompt_bufnr)
                launch(name, not sensitive, line)
            end
            map({ "i", "n" }, "<C-s>", toggle, { desc = "Toggle match case" })
            return true
        end,
    }

    if name == "live_grep" then
        -- Explicit flag either way, otherwise rg falls back to --smart-case
        -- from the default vimgrep_arguments.
        opts.additional_args = { sensitive and "--case-sensitive" or "--ignore-case" }
    elseif sensitive then
        opts.sorter = sensitive_file_sorter()
    end

    require("telescope.builtin")[name](opts)
end

function M.find_files()
    launch("find_files", false)
end

function M.live_grep()
    launch("live_grep", false)
end

return M
