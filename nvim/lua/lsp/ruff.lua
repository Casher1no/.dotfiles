-- https://docs.astral.sh/ruff/editors/ — ruff's built-in language server:
-- lint diagnostics, code actions (fix all, organize imports) and
-- black-compatible formatting. Runs alongside pyright, which keeps
-- owning types, hover, and navigation.
---@type vim.lsp.Config
return {
    cmd = { "ruff", "server" },
    filetypes = { "python" },
    root_markers = {
        "pyproject.toml",
        "ruff.toml",
        ".ruff.toml",
        "requirements.txt",
        ".git",
    },
    on_attach = function(client)
        -- pyright's hover is the rich one; ruff's would race it for K
        client.server_capabilities.hoverProvider = false
    end,
}
