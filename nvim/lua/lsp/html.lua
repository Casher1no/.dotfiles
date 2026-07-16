-- vscode-html-language-server (mason: html) — tag/attribute completion,
-- hover, formatting. Tag *closing* and paired *renaming* are handled by
-- nvim-ts-autotag (see plugins/autotag.lua), JetBrains-style.
---@type vim.lsp.Config
return {
    cmd = { "vscode-html-language-server", "--stdio" },
    -- htmlangular: Angular component templates get their own filetype since
    -- nvim 0.11 — without it listed here, plain-HTML completion (<d → div)
    -- never attaches in Angular projects.
    filetypes = { "html", "htmlangular" },
    root_markers = { "package.json", ".git" },
    init_options = {
        provideFormatter = true,
        embeddedLanguages = { css = true, javascript = true },
        configurationSection = { "html", "css", "javascript" },
    },
}
