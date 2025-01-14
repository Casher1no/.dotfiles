return {
    {
        "neovim/nvim-lspconfig",
        lazy = false,
        config = function()
            local lspconfig = require("lspconfig")
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- lua
            lspconfig.lua_ls.setup({
                capabilities = capabilities
            })

            -- c#

            -- Path to Mason root
            local mason_root = vim.fn.stdpath("data") .. "\\mason\\packages\\"

            lspconfig.omnisharp.setup {
                cmd = { "dotnet", mason_root .. "omnisharp/libexec/omnisharp.dll" },
                capabilities = capabilities,
                settings = {
                    formattingoptions = {
                        organizeimports = true,
                    },
                },
            }

            -- keymaps for lsp
            vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, {})
            vim.keymap.set("n", "gd", vim.lsp.buf.declaration, {})
            vim.keymap.set("n", "gi", vim.lsp.buf.implementation, {})
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})
            vim.keymap.set("n", "gr", vim.lsp.buf.references, {})
        end,
    },
}
