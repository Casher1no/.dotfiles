-- https://github.com/tailwindlabs/tailwindcss-intellisense
local util = require("lspconfig.util")

---@type vim.lsp.Config
return {
    cmd = { "tailwindcss-language-server", "--stdio" },
    filetypes = {
        -- html / templating
        "aspnetcorerazor",
        "astro",
        "blade",
        "django-html",
        "htmldjango",
        "edge",
        "ejs",
        "erb",
        "eruby",
        "gohtml",
        "gohtmltmpl",
        "haml",
        "handlebars",
        "hbs",
        "html",
        "htmlangular",
        "html-eex",
        "heex",
        "jade",
        "leaf",
        "liquid",
        "markdown",
        "mdx",
        "mustache",
        "njk",
        "nunjucks",
        "php",
        "razor",
        "slim",
        "twig",
        -- css
        "css",
        "less",
        "postcss",
        "sass",
        "scss",
        "stylus",
        "sugarss",
        -- js / ts
        "javascript",
        "javascriptreact",
        "typescript",
        "typescriptreact",
        -- mixed
        "vue",
        "svelte",
    },
    capabilities = {
        workspace = {
            didChangeWatchedFiles = {
                dynamicRegistration = true,
            },
        },
    },
    settings = {
        tailwindCSS = {
            validate = true,
            lint = {
                cssConflict = "warning",
                invalidApply = "error",
                invalidScreen = "error",
                invalidVariant = "error",
                invalidConfigPath = "error",
                invalidTailwindDirective = "error",
                recommendedVariantOrder = "warning",
            },
            classAttributes = {
                "class",
                "className",
                "class:list",
                "classList",
                "ngClass",
            },
            includeLanguages = {
                eruby = "erb",
                htmlangular = "html",
            },
        },
    },
    before_init = function(_, config)
        config.settings = config.settings or {}
        config.settings.editor = config.settings.editor or {}
        if not config.settings.editor.tabSize then
            config.settings.editor.tabSize = vim.lsp.util.get_effective_tabstop()
        end
    end,
    workspace_required = true,
    root_dir = function(bufnr, on_dir)
        local root_files = {
            "tailwind.config.js",
            "tailwind.config.cjs",
            "tailwind.config.mjs",
            "tailwind.config.ts",
            "postcss.config.js",
            "postcss.config.cjs",
            "postcss.config.mjs",
            "postcss.config.ts",
            -- Tailwind v4 no longer requires a config file
            ".git",
        }
        local fname = vim.api.nvim_buf_get_name(bufnr)
        root_files = util.insert_package_json(root_files, "tailwindcss", fname)
        on_dir(vim.fs.dirname(vim.fs.find(root_files, { path = fname, upward = true })[1]))
    end,
}
