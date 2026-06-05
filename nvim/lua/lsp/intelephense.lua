-- https://intelephense.com/ (PHP language server)
---@type vim.lsp.Config
return {
    cmd = { "intelephense", "--stdio" },
    filetypes = { "php", "blade" },
    root_markers = { "composer.json", ".git" },
    settings = {
        intelephense = {
            files = {
                maxSize = 1000000,
            },
        },
    },
}
