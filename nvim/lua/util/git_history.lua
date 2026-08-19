-- File history, IDE-style: every commit that touched the current file, with
-- the change rendered as code — real syntax highlighting, red/green line
-- backgrounds, old/new line numbers down the left — instead of a +/- patch.
--
-- Telescope's own git_bcommits is close but previews `git diff <sha>~ <sha>
-- -- <current path>`, so every commit older than a rename shows an empty
-- preview: the path it asks about didn't exist yet. `git log --follow
-- --name-only` reports the path *as of each commit*, so each preview asks
-- about the name the file had back then and history stays unbroken across
-- the reorganise-the-tree commits.
local M = {}

local MAX_COMMITS = 300
local CONTEXT = 3 -- lines of unchanged code around each hunk

-- Record separator \0, field separator \31: both impossible in a commit
-- subject, unlike the tabs and pipes a subject can legitimately contain.
local LOG_FORMAT = "%x00%H%x1f%h%x1f%s%x1f%an%x1f%ar"

local function git(args, cwd)
    local out = vim.system(vim.list_extend({ "git", "--no-pager" }, args), { cwd = cwd, text = true }):wait()
    if out.code ~= 0 then
        return nil, (out.stderr or ""):gsub("%s+$", "")
    end
    return vim.split(out.stdout or "", "\n", { plain = true })
end

-- Every path here — the ones --name-only reports, the ones `git show` is
-- asked about — is relative to the repository root, and git resolves a
-- pathspec against the *current directory*. Run everything from the root so
-- the two agree; from the file's own directory `git show -- src/Foo.java`
-- quietly matches nothing and every preview comes back empty.
local function repo_root(file)
    local out = vim.system(
        { "git", "rev-parse", "--show-toplevel" },
        { cwd = vim.fn.fnamemodify(file, ":h"), text = true }
    ):wait()
    if out.code ~= 0 then
        return nil
    end
    return vim.trim(out.stdout or "")
end

-- One `git log` pass gives the commit metadata and, from --name-only, the
-- path the file was known by in that commit.
local function commits(relpath, cwd, range)
    local args = { "log", "--format=" .. LOG_FORMAT, "--name-only", "-n", tostring(MAX_COMMITS) }
    if range then
        -- -L follows the lines, which rules out --follow (git rejects the
        -- pair), so a range search stops at the file's last rename.
        vim.list_extend(args, { "-L", string.format("%d,%d:%s", range[1], range[2], relpath), "--no-patch" })
    else
        vim.list_extend(args, { "--follow", "--", relpath })
    end

    local lines, err = git(args, cwd)
    if not lines then
        return nil, err
    end

    local out = {}
    local current
    for _, line in ipairs(lines) do
        local header = line:match("^%z(.*)$")
        if header then
            local hash, short, subject, author, date = header:match("^(.-)\31(.-)\31(.-)\31(.-)\31(.*)$")
            current = { hash = hash, short = short, subject = subject, author = author, date = date }
            -- -L reports no file names; the path can't have changed under it.
            current.path = range and relpath or nil
            out[#out + 1] = current
        elseif current and line ~= "" and not current.path then
            current.path = line
        end
    end

    -- A commit that renamed the file only reads as a rename if git is given
    -- both names at once; with just the new one it reports the whole file as
    -- added, which is how a tree reorganisation ends up looking like every
    -- line changed. The next (older) entry carries the name it had before.
    for i, commit in ipairs(out) do
        local older = out[i + 1]
        if older and older.path and older.path ~= commit.path then
            commit.prev_path = older.path
        end
    end
    return out
end

-- ------------------------------------------------------------------ rendering

-- Turn a unified diff into displayable code: the markers come off the front
-- of each line and become a highlight instead, the way a diff viewer shows it.
local function parse_patch(patch)
    local rows = {} -- { text, kind = "add"|"del"|"ctx"|"sep", old, new }
    local old_ln, new_ln
    for _, line in ipairs(patch) do
        local a, b = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
        if a then
            if #rows > 0 then
                rows[#rows + 1] = { text = "", kind = "sep" }
            end
            old_ln, new_ln = tonumber(a), tonumber(b)
        elseif old_ln then
            local marker, text = line:sub(1, 1), line:sub(2)
            if marker == "+" then
                rows[#rows + 1] = { text = text, kind = "add", new = new_ln }
                new_ln = new_ln + 1
            elseif marker == "-" then
                rows[#rows + 1] = { text = text, kind = "del", old = old_ln }
                old_ln = old_ln + 1
            elseif marker == " " then
                rows[#rows + 1] = { text = text, kind = "ctx", old = old_ln, new = new_ln }
                old_ln, new_ln = old_ln + 1, new_ln + 1
            end
            -- "\ No newline at end of file" and anything else: not code, drop it
        end
    end
    return rows
end

local ns = vim.api.nvim_create_namespace("git_history_diff")
local hint_ns = vim.api.nvim_create_namespace("git_history_hint")

-- Key hints on the right of the prompt line, the same badge the find_files /
-- live_grep pickers wear (util/telescope_case.lua) — the preview is a wall of
-- code, and nothing on screen otherwise says it scrolls. Passing a hash flips
-- the badge to a confirmation for a moment: vim.notify lands in the message
-- area, which is behind the picker and gone on the next redraw, so a copy
-- looked like it did nothing.
local function place_hint(prompt_bufnr, copied)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        vim.api.nvim_buf_set_extmark(prompt_bufnr, hint_ns, 0, 0, {
            id = 1, -- one badge, replaced in place
            virt_text = copied and { { " ✓ copied " .. copied .. " ", "DiagnosticOk" } }
                or {
                    { " ⟨C-d⟩/⟨C-u⟩ scroll ", "Comment" },
                    { " ⟨CR⟩ diff ", "Comment" },
                    { " ⟨C-g⟩ sha ", "Comment" },
                },
            virt_text_pos = "right_align",
        })
    end)
end

local function render(bufnr, rows, ft)
    local text = {}
    for i, row in ipairs(rows) do
        text[i] = row.text
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text)
    vim.bo[bufnr].modifiable = false
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    -- Highlight it as the language it is, not as a patch. Treesitter parses
    -- happily through the removed lines mixed in; where there's no parser,
    -- 'filetype' gets regex syntax to do the same job.
    if ft and ft ~= "" then
        local lang = vim.treesitter.language.get_lang(ft)
        if not (lang and pcall(vim.treesitter.start, bufnr, lang)) then
            vim.bo[bufnr].filetype = ft
        end
    end

    -- Two line-number gutters, old and new, like a side-by-side view folded
    -- into one column. Inline virtual text so it can't be selected or copied
    -- along with the code.
    local width = 0
    for _, row in ipairs(rows) do
        width = math.max(width, #tostring(row.old or 0), #tostring(row.new or 0))
    end
    for i, row in ipairs(rows) do
        local hl = row.kind == "add" and "DiffAdd" or row.kind == "del" and "DiffDelete" or nil
        local gutter = row.kind == "sep" and string.rep(" ", width * 2 + 3)
            or string.format("%" .. width .. "s %" .. width .. "s ", row.old or "", row.new or "")
        vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, {
            virt_text = { { gutter, "LineNr" } },
            virt_text_pos = "inline",
            line_hl_group = hl,
        })
    end
end

-- ------------------------------------------------------------------ the picker

-- Open the file as it was at `commit` next to the buffer, in diff mode.
-- Deliberately not telescope's default action for bcommits, which is a
-- checkout — reading history shouldn't rewrite the working tree.
local function diff_against_working_copy(entry, file, cwd)
    local content, err = git({ "show", entry.value.hash .. ":" .. entry.value.path }, cwd)
    if not content then
        return vim.notify("git show failed: " .. err, vim.log.levels.ERROR)
    end
    local ft = vim.bo.filetype
    vim.cmd("diffthis")

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, content)
    vim.api.nvim_buf_set_name(scratch, entry.value.short .. " " .. vim.fn.fnamemodify(entry.value.path, ":t"))
    vim.bo[scratch].modifiable = false
    vim.cmd("leftabove vert sbuffer " .. scratch)
    vim.bo[scratch].filetype = ft
    vim.cmd("diffthis")

    -- Closing either side leaves the other in diff mode with no counterpart;
    -- clean up so the file window goes back to normal.
    vim.api.nvim_create_autocmd("WinClosed", {
        buffer = scratch,
        nested = true,
        once = true,
        callback = function()
            pcall(vim.api.nvim_buf_delete, scratch, { force = true })
            vim.cmd("diffoff!")
        end,
    })
    vim.notify(entry.value.short .. " " .. entry.value.subject, vim.log.levels.INFO)
end

---@param range integer[]|nil {first, last} line numbers to narrow the history to
function M.open(range)
    local file = vim.api.nvim_buf_get_name(0)
    if file == "" or vim.fn.filereadable(file) ~= 1 then
        return vim.notify("No file in this buffer", vim.log.levels.WARN)
    end
    local cwd = repo_root(file)
    if not cwd then
        return vim.notify(vim.fn.fnamemodify(file, ":t") .. " is not in a git repository", vim.log.levels.WARN)
    end
    local relpath = vim.fs.relpath(cwd, file) or file
    local ft = vim.bo.filetype

    local log, err = commits(relpath, cwd, range)
    if not log then
        return vim.notify("git log failed: " .. err, vim.log.levels.ERROR)
    end
    if #log == 0 then
        return vim.notify(vim.fn.fnamemodify(file, ":t") .. " has no commits yet", vim.log.levels.INFO)
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")

    local displayer = entry_display.create({
        separator = "  ",
        items = {
            { width = 8 },
            { width = math.min(60, math.floor(vim.o.columns * 0.4)) },
            { width = 14 },
            { remaining = true },
        },
    })

    local previewer = previewers.new_buffer_previewer({
        title = "Change",
        dyn_title = function(_, entry)
            return entry.value.short .. "  " .. entry.value.subject
        end,
        get_buffer_by_name = function(_, entry)
            return entry.value.hash
        end,
        define_preview = function(self, entry)
            local args = { "show", "--format=", "--no-color", "-M", "-U" .. CONTEXT, entry.value.hash, "--", entry.value.path }
            if entry.value.prev_path then
                args[#args + 1] = entry.value.prev_path
            end
            local patch = git(args, cwd)
            local rows = patch and parse_patch(patch) or {}
            if #rows == 0 then
                -- A pure rename, a mode change, or a merge commit recorded
                -- against this path: nothing was written, so say that rather
                -- than showing the blank pane this whole module exists to fix.
                local summary = { "", "  " .. entry.value.short .. "  " .. entry.value.subject, "" }
                for _, line in ipairs(patch or {}) do
                    if line:match("^rename from") or line:match("^rename to") or line:match("^old mode") or line:match("^new mode") then
                        summary[#summary + 1] = "  " .. line
                    end
                end
                if #summary == 3 then
                    summary[#summary + 1] = "  No change to " .. entry.value.path .. " in this commit."
                end
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, summary)
                return
            end
            render(self.state.bufnr, rows, ft)
        end,
    })

    pickers
        .new({}, {
            prompt_title = "History — " .. vim.fn.fnamemodify(file, ":t") .. (range and " (selected lines)" or ""),
            finder = finders.new_table({
                results = log,
                entry_maker = function(commit)
                    return {
                        value = commit,
                        ordinal = commit.subject .. " " .. commit.author .. " " .. commit.short,
                        display = function()
                            return displayer({
                                { commit.short, "TelescopeResultsIdentifier" },
                                commit.subject,
                                { commit.author, "TelescopeResultsComment" },
                                { commit.date, "TelescopeResultsComment" },
                            })
                        end,
                    }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewer,
            attach_mappings = function(prompt_bufnr, map)
                place_hint(prompt_bufnr)
                actions.select_default:replace(function()
                    local entry = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    if entry then
                        diff_against_working_copy(entry, file, cwd)
                    end
                end)
                -- <C-y> is redo everywhere else in this config
                -- (vim-options.lua), so the hash copy stays off it.
                map({ "i", "n" }, "<C-g>", function()
                    local entry = action_state.get_selected_entry()
                    if entry then
                        vim.fn.setreg("+", entry.value.hash)
                        place_hint(prompt_bufnr, entry.value.short)
                        vim.defer_fn(function()
                            place_hint(prompt_bufnr)
                        end, 2000)
                    end
                end, { desc = "Copy commit hash" })
                return true
            end,
        })
        :find()
end

---History of just the visually selected lines (git log -L).
function M.open_range()
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    if first > last then
        first, last = last, first
    end
    -- Leave visual mode before the picker opens, or the selection lingers
    -- highlighted behind it.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    M.open({ first, last })
end

return M
