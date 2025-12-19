return {
    "nvimtools/none-ls.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        local null_ls = require("null-ls")

        null_ls.setup({
            sources = {
                -- Lua
                null_ls.builtins.formatting.stylua,

                -- PHP & Laravel
                null_ls.builtins.formatting.phpcsfixer,
                -- or null_ls.builtins.formatting.pint,

                -- Vue/JS/TS
                null_ls.builtins.formatting.prettier.with({
                    filetypes = {
                        "vue",
                        "javascript",
                        "typescript",
                        "css",
                        "scss",
                        "html",
                        "json",
                        "yaml",
                        "markdown"
                    },
                }),

                -- Python
                null_ls.builtins.formatting.black,
                null_ls.builtins.formatting.isort,

                -- Java
                null_ls.builtins.formatting.google_java_format,
            },
        })

        vim.keymap.set("n", "<leader>gf", vim.lsp.buf.format, { desc = "Format" })
    end,
}
