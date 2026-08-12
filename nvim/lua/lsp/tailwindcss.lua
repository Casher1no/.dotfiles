-- https://github.com/tailwindlabs/tailwindcss-intellisense
local util = require("lspconfig.util")

-- Tailwind v4 can run config-less ("CSS-first"): with the standalone CLI
-- there is no tailwind.config.* and no package.json dependency either — the
-- only on-disk evidence is an `@import "tailwindcss"` (or `@tailwind`
-- directive) line in a stylesheet. Probe only these conventional entry-point
-- locations; a recursive scan would run against every repo a matching
-- filetype opens in.
local css_entry_globs = {
    "*.css",
    "src/*.css",
    "src/css/*.css",
    "src/styles/*.css",
    "styles/*.css",
    "css/*.css",
    "app/*.css", -- Next.js app router
    "assets/css/*.css",
    "resources/css/*.css", -- Laravel
    "public/css/*.css",
}

-- root_dir runs for every matching buffer; cache the verdict so each
-- candidate root's stylesheets are read once per session.
local css_probe_cache = {}

-- A negative verdict must not outlive its evidence: adding
-- `@import "tailwindcss"` to a stylesheet (config-less v4 adoption) has to
-- be picked up by the next root_dir run, so any CSS write clears the cache
-- (a handful of entries at most — re-probing is cheap).
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("tailwindcss_css_probe", { clear = true }),
    pattern = { "*.css", "*.scss" },
    callback = function()
        css_probe_cache = {}
    end,
})

local function has_tailwind_css(root)
    if css_probe_cache[root] ~= nil then
        return css_probe_cache[root]
    end
    local found = false
    local budget = 20 -- files read at most, keeps a miss cheap in css-heavy roots
    for _, pat in ipairs(css_entry_globs) do
        for _, file in ipairs(vim.fn.glob(vim.fs.joinpath(root, pat), true, true)) do
            budget = budget - 1
            if budget < 0 or found then
                break
            end
            local f = io.open(file)
            if f then
                -- the import/directive sits at the top of the file; 4KB is plenty
                local head = f:read(4096) or ""
                f:close()
                found = head:find("@import%s+[\"']tailwindcss") ~= nil
                    or head:find("@tailwind%s") ~= nil
            end
        end
        if budget < 0 or found then
            break
        end
    end
    css_probe_cache[root] = found
    return found
end

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
    -- Not calling on_dir is what actually prevents a start (see angularls.lua):
    -- workspace_required only helps when root_dir yields nothing. Without real
    -- tailwind evidence the ~35-filetype list above would otherwise spawn a
    -- node server in every git repo, PHP/Python-only ones included.
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
        }
        local fname = vim.api.nvim_buf_get_name(bufnr)
        root_files = util.insert_package_json(root_files, "tailwindcss", fname)
        local marker = vim.fs.find(root_files, { path = fname, upward = true })[1]
        if marker then
            on_dir(vim.fs.dirname(marker))
            return
        end
        -- Config-less v4 fallback: only start when a conventional CSS entry
        -- point under the project root actually imports tailwind.
        local root = vim.fs.root(bufnr, { "package.json", ".git" })
        if root and has_tailwind_css(root) then
            on_dir(root)
        end
    end,
}
