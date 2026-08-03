-- Custom LSP references picker, replacing telescope's lsp_references for
-- gr and gd-on-definition (util/goto.lua). Differences from stock:
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

-- Fetch, dedup and order reference items; cb(items, current_file).
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
        if #items == 0 then
            vim.notify("No references found", vim.log.levels.INFO)
            return
        end
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

function M.open()
    M._gather(function(items, current)
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values

        local function entry_maker(item)
            local in_current = vim.fn.fnamemodify(item.filename, ":p") == current
            local text = vim.trim(item.text or "")
            -- ·grep = found by text search, not confirmed by the LSP
            -- (util/grepref.lua) — could be a same-named method elsewhere.
            local suffix = item.via_grep and "  ·grep" or ""
            local display
            if in_current then
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

        pickers
            .new({}, {
                -- Never censor LSP results with the search-noise ignore
                -- patterns: a reference inside vendor/node_modules is still
                -- a reference (telescope filters picker entries through
                -- file_ignore_patterns by default).
                file_ignore_patterns = {},
                prompt_title = "References — current file first",
                finder = finders.new_table({ results = items, entry_maker = entry_maker }),
                sorter = conf.generic_sorter({}),
                previewer = conf.qflist_previewer({}),
            })
            :find()
    end)
end

return M
