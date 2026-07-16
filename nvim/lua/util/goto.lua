-- JetBrains-style gd (bound in plugins/lsp.lua): on a usage it jumps to the
-- definition; pressed again on the definition itself it lists references —
-- so gr is never required. Folds in the special cases first: Inertia page
-- strings in PHP, template class names → stylesheet selector, and
-- stylesheet selectors → their usages (util/styleref.lua).
local M = {}

function M.definition()
    if vim.bo.filetype == "php" then
        local page = require("util.inertia").page_file_under_cursor()
        if page then
            vim.cmd("edit " .. vim.fn.fnameescape(page))
            return
        end
    end
    local styleref = require("util.styleref")
    if styleref.definition() then
        return
    end
    if styleref.references() then
        return -- a selector IS its definition: gd on it = show usages
    end

    local tb = require("telescope.builtin")
    vim.lsp.buf_request_all(0, "textDocument/definition", function(client, _)
        return vim.lsp.util.make_position_params(0, client.offset_encoding)
    end, function(results)
        local locs = {}
        for _, res in pairs(results or {}) do
            local r = res.result
            if r and (r.uri or r.targetUri) then
                r = { r } -- single Location → list
            end
            for _, loc in ipairs(r or {}) do
                locs[#locs + 1] = loc
            end
        end
        if #locs == 0 then
            tb.lsp_definitions() -- let telescope surface "no definitions"
            return
        end
        local cur_uri = vim.uri_from_bufnr(0)
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        for _, loc in ipairs(locs) do
            local uri = loc.uri or loc.targetUri
            local range = loc.range or loc.targetSelectionRange
            if uri == cur_uri and range and row >= range.start.line and row <= range["end"].line then
                -- Already at the definition — show where it's used instead
                -- (grouped picker: current file first, deduped).
                require("util.references").open()
                return
            end
        end
        tb.lsp_definitions()
    end)
end

return M
