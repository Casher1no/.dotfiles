return {
    {
        "mason-org/mason.nvim",
        opts = {
            ui = {
                icons = {
                    package_installed = "✓",
                    package_pending = "➜",
                    package_uninstalled = "✗",
                },
            },
        },
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = {
            "mason-org/mason.nvim",
            "neovim/nvim-lspconfig",
        },
        opts = {
            -- Servers installed automatically on first launch.
            ensure_installed = {
                "lua_ls",        -- editing this config
                "intelephense",  -- PHP / Laravel
                "laravel_ls",    -- Laravel-aware features
                "tailwindcss",   -- Tailwind in blade / vue / etc.
                "vue_ls",        -- Vue SFC (Inertia)
                "vtsls",         -- TypeScript/JS (Vue + Angular)
                "angularls",     -- Angular templates
                "pyright",       -- Python (types, hover, navigation)
                "ruff",          -- Python lint + formatting
                "jdtls",         -- Java
                "roslyn_ls",     -- C# (installs the `roslyn-language-server` package; started by roslyn.nvim)
            },
            -- We register and enable the servers ourselves in plugins/lsp.lua
            -- (with our custom configs in lua/lsp/), so don't let
            -- mason-lspconfig auto-enable them with default settings.
            automatic_enable = false,
        },
    },
}
