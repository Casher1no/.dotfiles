-- C# language server via the Roslyn-based server (the one VS / VS Code use),
-- driven by seblyng/roslyn.nvim. Unlike the servers in lua/lsp/, Roslyn isn't
-- enabled through plugins/lsp.lua's generic loop: roslyn.nvim starts the server
-- itself once it locates a .sln / .csproj, and picks up the Roslyn binary that
-- mason installs (see plugins/package-manager.lua → "roslyn").
--
-- Buffer keymaps (gd, gr, K, <leader>f, …) still come from the shared LspAttach
-- handler in plugins/lsp.lua, which fires for every client including this one.
return {
    "seblyng/roslyn.nvim",
    ft = "cs",
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {
        -- Defaults are fine; server-level settings go through vim.lsp.config
        -- below so blink.cmp's capabilities (set on "*" in plugins/lsp.lua)
        -- still apply.
    },
    config = function(_, opts)
        vim.lsp.config("roslyn", {
            settings = {
                ["csharp|inlay_hints"] = {
                    csharp_enable_inlay_hints_for_implicit_object_creation = true,
                    csharp_enable_inlay_hints_for_implicit_variable_types = true,
                },
                ["csharp|code_lens"] = {
                    dotnet_enable_references_code_lens = true,
                },
            },
        })
        require("roslyn").setup(opts)
    end,
}
