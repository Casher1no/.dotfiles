-- JetBrains-style gd (bound in plugins/lsp.lua): on a usage it jumps to the
-- definition; pressed again on the definition itself it lists references —
-- so gr is never required. Folds in the special cases first: Inertia page
-- strings in PHP, template class names → stylesheet selector, and
-- stylesheet selectors → their usages (util/styleref.lua).
local M = {}

-- Client start times, for the young-server retry below. Backfilled at module
-- load (plugins/lsp.lua requires this module on the first LspAttach of the
-- session, so every client alive then really is young) and maintained by the
-- autocmd for servers that start later.
local first_seen = {}
do
    local now = vim.uv.now()
    for _, client in ipairs(vim.lsp.get_clients()) do
        first_seen[client.id] = now
    end
end
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("goto_first_seen", { clear = true }),
    callback = function(args)
        local id = args.data and args.data.client_id
        if id and not first_seen[id] then
            first_seen[id] = vim.uv.now()
        end
    end,
})

local WARMUP_MS = 15000

-- A server that is still loading its index answers definition requests with
-- an empty result — which used to surface as a misleading "No LSP
-- Definitions found". Some of that work shows up in progress.pending
-- (tsserver project loads, intelephense cold indexing), but a warm-cache
-- intelephense load reports NO progress at all while still answering empty
-- for the first seconds. So treat a server as warming up while it either
-- has pending progress or simply started recently.
local function warming_up(bufnr)
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        local seen = first_seen[client.id]
        if (seen and vim.uv.now() - seen < WARMUP_MS)
            or (client.progress and next(client.progress.pending or {}))
        then
            return client.name
        end
    end
end

function M.definition()
    if vim.bo.filetype == "php" then
        local page = require("util.inertia").page_file_under_cursor()
        if page then
            vim.cmd("edit " .. vim.fn.fnameescape(page))
            return
        end
    end
    local styleref = require("util.styleref")
    if styleref.css_var() then
        return -- var(--x) → definition; on the definition → usages
    end
    if styleref.definition() then
        return
    end
    if styleref.references() then
        return -- a selector IS its definition: gd on it = show usages
    end

    local tb = require("telescope.builtin")
    local buf = vim.api.nvim_get_current_buf()
    local start_pos = vim.api.nvim_win_get_cursor(0)

    local RETRY_MS, MAX_RETRIES = 500, 30 -- retry warming servers up to ~15s
    local notified = false

    local function attempt(retries_left)
        vim.lsp.buf_request_all(buf, "textDocument/definition", function(client, _)
            return vim.lsp.util.make_position_params(0, client.offset_encoding)
        end, function(results)
            local locs = {}
            for cid, res in pairs(results or {}) do
                local client = vim.lsp.get_client_by_id(cid)
                local enc = client and client.offset_encoding or "utf-16"
                local r = res.result
                if r and (r.uri or r.targetUri) then
                    r = { r } -- single Location → list
                end
                for _, loc in ipairs(r or {}) do
                    locs[#locs + 1] = { loc = loc, enc = enc }
                end
            end
            if #locs == 0 then
                local busy = warming_up(buf)
                local cur = vim.api.nvim_win_get_cursor(0)
                local here = vim.api.nvim_get_current_buf() == buf
                    and cur[1] == start_pos[1]
                    and cur[2] == start_pos[2]
                if busy and here and retries_left > 0 then
                    if not notified then
                        notified = true
                        vim.notify(busy .. " is still indexing — waiting for it…", vim.log.levels.INFO)
                    end
                    vim.defer_fn(function()
                        attempt(retries_left - 1)
                    end, RETRY_MS)
                    return
                end
                tb.lsp_definitions() -- let telescope surface "no definitions"
                return
            end
            local cur_uri = vim.uri_from_bufnr(0)
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            for _, it in ipairs(locs) do
                local uri = it.loc.uri or it.loc.targetUri
                local range = it.loc.range or it.loc.targetSelectionRange
                if uri == cur_uri and range and row >= range.start.line and row <= range["end"].line then
                    -- Already at the definition — show where it's used instead
                    -- (grouped picker: current file first, deduped).
                    require("util.references").open()
                    return
                end
            end
            -- Jump ourselves rather than via telescope's lsp_definitions:
            -- telescope filters LSP results through file_ignore_patterns
            -- (vendor/, node_modules/, …), silently discarding definitions
            -- that live inside dependencies. The patterns are for search
            -- noise, not for explicit navigation.
            if #locs == 1 then
                vim.lsp.util.show_document(locs[1].loc, locs[1].enc, { focus = true })
                return
            end
            tb.lsp_definitions({ file_ignore_patterns = {} })
        end)
    end
    attempt(MAX_RETRIES)
end

return M
