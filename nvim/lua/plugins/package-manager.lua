return {
    {
        "mason-org/mason.nvim",
        -- Stays eager: setup() prepends mason/bin to PATH
        -- (mason-core/installer/InstallLocation.lua set_env), which spawned
        -- language servers must inherit.
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
        -- With automatic_enable = false (below) its only job is the
        -- ensure_installed check, which needn't block startup — and it never
        -- requires nvim-lspconfig, so that isn't a dependency (depending on it
        -- would force-load lspconfig past its BufReadPre gate).
        event = "VeryLazy",
        dependencies = {
            "mason-org/mason.nvim",
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
                "html",          -- HTML (tags, attributes, formatting)
                "cssls",         -- CSS / SCSS / LESS (completion, validation)
                "somesass_ls",   -- SCSS workspace defs/references
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
