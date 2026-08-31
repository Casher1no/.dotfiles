-- gd (bound in plugins/lsp.lua) is a toggle, IDE-style: on a usage it jumps
-- straight to the definition, and pressed again on the definition itself it
-- lists the usages (util/references.lua) instead of navigating nowhere.
-- Folds in the special cases first: Inertia page strings in PHP, template
-- class names → stylesheet selector, and stylesheet selectors → their usages
-- (util/styleref.lua), each of which toggles the same way.
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

local function same_file(a, b)
    a, b = vim.fs.normalize(a), vim.fs.normalize(b)
    if vim.fn.has("win32") == 1 then
        a, b = a:lower(), b:lower()
    end
    return a == b
end

-- True when the cursor was already sitting on one of the definitions the
-- server returned — servers answer a definition request made on a
-- declaration with that declaration itself. That is the toggle: there is
-- nowhere to navigate, so the useful answer is "who uses this".
-- Exposed (like references._gather) so it can be tested headlessly.
function M._at_definition(buf, row, locs)
    local file = vim.api.nvim_buf_get_name(buf)
    for _, it in ipairs(locs) do
        local uri = it.loc.uri or it.loc.targetUri
        -- targetSelectionRange is just the name; targetRange/range can span
        -- the whole declaration, which is still "on the definition".
        local range = it.loc.targetSelectionRange or it.loc.range or it.loc.targetRange
        if uri and range
            and same_file(vim.uri_to_fname(uri), file)
            and row >= range.start.line
            and row <= range["end"].line
        then
            return true
        end
    end
    return false
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
                -- No definition anywhere: either a symbol the server can't
                -- resolve, or the declaration itself (some servers answer
                -- empty there rather than pointing at themselves). Either
                -- way the usages are the useful answer.
                require("util.references").open()
                return
            end

            -- Second press, on the definition → the other half of the toggle.
            if M._at_definition(buf, start_pos[1] - 1, locs) then
                require("util.references").open()
                return
            end

            -- Items are built here rather than via telescope's
            -- lsp_definitions: that filters LSP results through
            -- file_ignore_patterns (vendor/, node_modules/, …), silently
            -- discarding definitions inside dependencies — including the
            -- case where the only definition is in one. Dependency hits are
            -- demoted below (and in the references picker they go behind the
            -- <C-l> toggle), never dropped without a fallback.
            local by_enc = {}
            for _, it in ipairs(locs) do
                by_enc[it.enc] = by_enc[it.enc] or {}
                table.insert(by_enc[it.enc], it.loc)
            end
            -- Dedup: on files two servers both claim (vtsls + angularls in
            -- Angular projects) the same definition comes back twice, which
            -- would turn a plain jump into a two-row picker.
            local def_items, seen = {}, {}
            for enc, list in pairs(by_enc) do
                for _, item in ipairs(vim.lsp.util.locations_to_items(list, enc)) do
                    local key = ("%s:%d:%d"):format(
                        vim.fn.fnamemodify(item.filename, ":p"), item.lnum, item.col or 0)
                    if not seen[key] then
                        seen[key] = true
                        item.is_def = true
                        def_items[#def_items + 1] = item
                    end
                end
            end
            -- A method that implements a library interface (Angular's
            -- PipeTransform.transform, an RxJS operator, …) comes back as
            -- *both* your implementation and the .d.ts declaration inside
            -- node_modules, which turned a plain jump into a two-row picker
            -- whose second row is a dependency. Your own code wins when it
            -- has an answer; when the only definition is in a package, gd
            -- still goes there — navigating into a library must keep working.
            local project = vim.tbl_filter(function(item)
                return require("util.tree_tints").classify(
                    vim.fn.fnamemodify(item.filename, ":p"), vim.uv.cwd()) ~= "package"
            end, def_items)
            if #project > 0 then
                def_items = project
            end

            -- One definition (the normal case) → jump. Several (interface +
            -- implementation, overloads, a symbol two servers both claim) →
            -- pick one.
            require("util.references").pick(def_items, {
                title = "Definitions",
                jump_if_single = true,
            })
        end)
    end
    attempt(MAX_RETRIES)
end

return M
