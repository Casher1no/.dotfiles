return {
    "neovim/nvim-lspconfig",
    config = function()
        local servers = {
            "intelephense",
            "lua_ls",
            "ts_ls",
            "vue_ls",
            "pyright",
            "tailwindcss",
            "laravel_ls",
            "angularls"
        }

        -- Register each server config with the new vim.lsp.config API
        for _, server in ipairs(servers) do
            local config = require("lsp." .. server)
            vim.lsp.config[server] = config
        end

        -- Enable all configured servers
        vim.lsp.enable(servers)

        vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(args)
                local bufnr = args.buf
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                -- Enable completion if supported
                if client:supports_method("textDocument/completion") then
                    vim.opt.completeopt = { "menu", "menuone", "noinsert", "fuzzy", "popup" }
                    vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
                    vim.keymap.set("i", "<C-m>", function()
                        vim.lsp.completion.get()
                    end)
                end

                local opts = { buffer = bufnr, silent = true }

                -- Hover and signature help
                vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
                vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, opts)

                -- Navigation
                vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
                vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
                vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
                vim.keymap.set("n", "go", vim.lsp.buf.type_definition, opts)
                vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
                vim.keymap.set("n", "gs", vim.lsp.buf.document_symbol, opts)

                -- Code actions and refactoring
                vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
                vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

                -- Formatting
                if client:supports_method("textDocument/formatting") then
                    vim.keymap.set("n", "<leader>f", function()
                        vim.lsp.buf.format({ async = true })
                    end, opts)
                end

                -- Diagnostics
                vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
                vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
                vim.keymap.set("n", "<leader>of", vim.diagnostic.open_float, opts)
                vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)
            end,
        })
        vim.diagnostic.config({
            -- virtual_lines = {
            -- 	current_line = true,
            -- },
        })
    end,
}
