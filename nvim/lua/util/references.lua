-- Custom LSP references picker, replacing telescope's lsp_references for
-- gr and for gd pressed on a definition (util/goto.lua). Differences from
-- stock:
--   - deduplicates locations when several servers answer the request
--     (angularls + vtsls both cover .ts files and doubled every hit)
--   - groups results: current file first, as compact "  123: code" rows,
--     then other files as "path:123: code"
--   - in PHP, merges ripgrep call-site hits (util/grepref.lua) the LSP
--     missed — Eloquent's magic methods hide receiver types from
--     intelephense, so e.g. `$link->registerClick()` after a dynamic
--     `::where(...)->first()` is invisible to textDocument/references
-- The telescope default sorting_strategy is "ascending" (see
-- plugins/telescope.lua), so finder order is display order.
local M = {}

-- Fetch, dedup and order reference items; cb(items, current_file). Called
-- with an empty list when there are none — the picker reports that case.
-- Separate from the picker so it can be tested headlessly.
function M._gather(cb)
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local word = vim.fn.expand("<cword>")
    local is_php = vim.bo[buf].filetype == "php"
    local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/references" })
    if #clients == 0 then
        vim.notify("No attached LSP supports references here", vim.log.levels.WARN)
        return
    end
    local encoding = clients[1].offset_encoding or "utf-16"

    local function finish(items)
        local current = vim.api.nvim_buf_get_name(buf)
        local here, elsewhere = {}, {}
        for _, it in ipairs(items) do
            local target = (vim.fn.fnamemodify(it.filename, ":p") == current) and here or elsewhere
            table.insert(target, it)
        end
        local by_pos = function(a, b)
            if a.filename ~= b.filename then
                return a.filename < b.filename
            end
            return a.lnum < b.lnum
        end
        table.sort(here, by_pos)
        table.sort(elsewhere, by_pos)
        local ordered = {}
        vim.list_extend(ordered, here)
        vim.list_extend(ordered, elsewhere)
        cb(ordered, current)
    end

    vim.lsp.buf_request_all(buf, "textDocument/references", function(client)
        local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
        params.context = { includeDeclaration = true }
        return params
    end, function(results)
        local seen, locations = {}, {}
        for _, res in pairs(results or {}) do
            for _, loc in ipairs(res.result or {}) do
                local uri = loc.uri or loc.targetUri
                local range = loc.range or loc.targetSelectionRange
                local key = ("%s:%d:%d"):format(uri, range.start.line, range.start.character)
                if not seen[key] then
                    seen[key] = true
                    locations[#locations + 1] = loc
                end
            end
        end
        local items = vim.lsp.util.locations_to_items(locations, encoding)

        if not is_php then
            finish(items)
            return
        end
        local root = vim.fs.root(buf, { "composer.json", ".git" }) or vim.fn.getcwd()
        require("util.grepref").method_calls(word, root, function(grep_items)
            -- LSP hits win; grep only fills lines the LSP didn't report.
            local have = {}
            for _, it in ipairs(items) do
                have[vim.fn.fnamemodify(it.filename, ":p") .. ":" .. it.lnum] = true
            end
            for _, it in ipairs(grep_items) do
                local key = vim.fn.fnamemodify(it.filename, ":p") .. ":" .. it.lnum
                if not have[key] then
                    have[key] = true
                    items[#items + 1] = it
                end
            end
            finish(items)
        end)
    end)
end

local badge_ns = vim.api.nvim_create_namespace("references_tests_badge")

-- Right-aligned badge in the prompt line showing the test-filter state,
-- same style as the Aa badge in util/telescope_case.lua.
local function place_badge(prompt_bufnr, hide_tests)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        vim.api.nvim_buf_set_extmark(prompt_bufnr, badge_ns, 0, 0, {
            -- Same label in both states, only the highlight changes.
            virt_text = { { " tests ⟨C-t⟩ ", hide_tests and "DiagnosticWarn" or "Comment" } },
            virt_text_pos = "right_align",
        })
    end)
end

-- References inside test folders / colocated test files, per the shared
-- classification in util/tree_tints. Definitions (·def) never count:
-- hiding the definition itself would be worse than showing a test row.
local function is_test_item(item)
    if item.is_def then
        return false
    end
    return require("util.tree_tints").classify(vim.fn.fnamemodify(item.filename, ":p"), vim.loop.cwd()) == "test"
end

-- Show a list of locations in the picker. Shared by gr (usages) and gd
-- (definitions, util/goto.lua) so both look and filter the same.
-- opts.title: picker title. opts.current: the file whose hits are shown as
--   compact "  123: code" rows (defaults to the current buffer).
-- opts.empty: what to say when there is nothing to show.
-- opts.jump_if_single: skip the picker and jump when there is one location.
function M.pick(items, opts)
    opts = opts or {}
    local current = opts.current or vim.api.nvim_buf_get_name(0)
    if #items == 0 then
        vim.notify(opts.empty or "Nothing to show", vim.log.levels.INFO)
        return
    end
    if opts.jump_if_single and #items == 1 then
        local it = items[1]
        vim.cmd("normal! m'") -- jumplist entry, so <C-o> comes back here
        vim.cmd("edit " .. vim.fn.fnameescape(it.filename))
        pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum, math.max(0, (it.col or 1) - 1) })
        vim.cmd("normal! zz")
        return
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values

    local function entry_maker(item)
        local in_current = vim.fn.fnamemodify(item.filename, ":p") == current
        local text = vim.trim(item.text or "")
        -- ·grep = found by text search, not confirmed by the LSP
        -- (util/grepref.lua) — could be a same-named method elsewhere.
        -- ·def = a definition, from the gd picker.
        local suffix = item.is_def and "  ·def" or (item.via_grep and "  ·grep" or "")
        local display
        if in_current and not item.is_def then
            display = ("  %4d: %s%s"):format(item.lnum, text, suffix)
        else
            display = ("%s:%d: %s%s"):format(vim.fn.fnamemodify(item.filename, ":."), item.lnum, text, suffix)
        end
        return {
            value = item,
            display = display,
            ordinal = display,
            filename = item.filename,
            lnum = item.lnum,
            col = item.col,
        }
    end

    -- hide_tests drops usages in test folders/files (<C-t> toggles it,
    -- like the filter buttons on an IDE usages panel). The full
    -- item list stays in this closure, so toggling just rebuilds the
    -- picker from it with the typed query kept.
    local function show(hide_tests, text)
        local shown = items
        if hide_tests then
            shown = vim.tbl_filter(function(it)
                return not is_test_item(it)
            end, items)
        end
        pickers
            .new({}, {
                -- Never censor LSP results with the search-noise ignore
                -- patterns: a reference inside vendor/node_modules is still
                -- a reference (telescope filters picker entries through
                -- file_ignore_patterns by default).
                file_ignore_patterns = {},
                prompt_title = (opts.title or "References — current file first")
                    .. (hide_tests and " — tests hidden" or ""),
                default_text = text,
                finder = finders.new_table({ results = shown, entry_maker = entry_maker }),
                sorter = conf.generic_sorter({}),
                previewer = conf.qflist_previewer({}),
                attach_mappings = function(prompt_bufnr, map)
                    place_badge(prompt_bufnr, hide_tests)
                    map({ "i", "n" }, "<C-t>", function()
                        local line = require("telescope.actions.state").get_current_line()
                        require("telescope.actions").close(prompt_bufnr)
                        show(not hide_tests, line)
                    end, { desc = "Toggle hide tests" })
                    return true
                end,
            })
            :find()
    end
    show(false)
end

-- gr, and gd pressed on the definition itself: every usage of the symbol
-- under the cursor, current file first.
function M.open(opts)
    opts = opts or {}
    M._gather(function(refs, current)
        M.pick(refs, {
            current = current,
            title = opts.title,
            empty = "No usages found",
        })
    end)
end

return M
