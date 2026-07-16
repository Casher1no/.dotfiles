-- Format the current buffer with whatever attached LSP client supports it
-- (ruff for Python, intelephense for PHP, lua_ls for Lua, ...). Bound to
-- <leader>f in vim-options.lua and runnable from the palette (LSP / Code →
-- Format file).
local M = {}

function M.format()
    local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/formatting" })
    if #clients == 0 then
        vim.notify("No attached LSP can format this buffer", vim.log.levels.WARN)
        return
    end
    vim.lsp.buf.format({ async = true })
end

return M
