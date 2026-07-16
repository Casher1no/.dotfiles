-- vscode-css-language-server (mason: cssls) — completion, hover and
-- diagnostics for css/scss/less. Workspace-wide go-to-definition /
-- references for SCSS symbols come from somesass_ls (see
-- lua/lsp/somesass_ls.lua).
---@type vim.lsp.Config
return {
    cmd = { "vscode-css-language-server", "--stdio" },
    filetypes = { "css", "scss", "less" },
    root_markers = { "package.json", ".git" },
    settings = {
        css = { validate = true },
        scss = { validate = true },
        less = { validate = true },
    },
}
