-- https://github.com/laravel-ls/laravel-ls
---@type vim.lsp.Config
return {
    cmd = { "laravel-ls" },
    filetypes = { "php", "blade" },
    root_markers = { "artisan" },
    -- An unmatched marker still starts the client in single-file mode on every
    -- php buffer (see lua/lsp/angularls.lua); no artisan means no laravel-ls.
    workspace_required = true,
}
