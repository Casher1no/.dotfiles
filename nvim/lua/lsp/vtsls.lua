-- https://github.com/yioneko/vtsls (TypeScript/JS server)
--
-- Hosts the @vue/typescript-plugin so it can power TypeScript inside .vue
-- single-file components (Vue 3 hybrid mode). Also serves Angular/plain TS.
-- Use stdpath rather than $MASON: the env var is only set after mason.nvim
-- setup runs, which may be later than this config is evaluated.
local vue_language_server_path = vim.fn.stdpath("data")
    .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

local vue_plugin = {
    name = "@vue/typescript-plugin",
    location = vue_language_server_path,
    languages = { "vue" },
    configNamespace = "typescript",
}

---@type vim.lsp.Config
return {
    cmd = { "vtsls", "--stdio" },
    init_options = {
        hostInfo = "neovim",
    },
    filetypes = {
        "javascript",
        "javascriptreact",
        "javascript.jsx",
        "typescript",
        "typescriptreact",
        "typescript.tsx",
        "vue",
    },
    settings = {
        vtsls = {
            tsserver = {
                globalPlugins = {
                    vue_plugin,
                },
            },
        },
    },
    root_dir = function(bufnr, on_dir)
        local root_markers = { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }
        root_markers = vim.fn.has("nvim-0.11.3") == 1 and { root_markers, { ".git" } }
            or vim.list_extend(root_markers, { ".git" })

        -- exclude deno projects
        if vim.fs.root(bufnr, { "deno.json", "deno.jsonc", "deno.lock" }) then
            return
        end

        local project_root = vim.fs.root(bufnr, root_markers) or vim.fn.getcwd()
        on_dir(project_root)
    end,
}
