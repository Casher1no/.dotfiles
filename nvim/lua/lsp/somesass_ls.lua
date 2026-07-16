-- Some Sass language server (mason: somesass_ls) — the workspace-aware half
-- of SCSS support: go to definition and find references for variables,
-- mixins, functions and placeholder selectors across all project
-- stylesheets. Runs alongside cssls, which keeps validation/completion.
---@type vim.lsp.Config
return {
    cmd = { "some-sass-language-server", "--stdio" },
    filetypes = { "scss", "sass" },
    root_markers = { "package.json", ".git" },
}
