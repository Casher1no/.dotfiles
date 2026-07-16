return {
    "neovim/nvim-lspconfig",
    config = function()
        local servers = {
            "lua_ls",
            "intelephense",
            "laravel_ls",
            "tailwindcss",
            "vue_ls",
            "vtsls",
            "angularls",
            "pyright",
            "ruff",
            "html",
            "cssls",
            "somesass_ls",
            -- jdtls is started by nvim-jdtls (see plugins/jdtls.lua), not here.
        }

        -- Advertise blink.cmp's richer completion capabilities to every server
        -- (snippets, auto-import / additionalTextEdits, resolve support, ...).
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        local ok_blink, blink = pcall(require, "blink.cmp")
        if ok_blink then
            capabilities = blink.get_lsp_capabilities(capabilities)
        end
        vim.lsp.config("*", { capabilities = capabilities })

        for _, server in ipairs(servers) do
            local config = require("lsp." .. server)
            vim.lsp.config[server] = config
        end

        vim.lsp.enable(servers)

        vim.api.nvim_create_autocmd("LspAttach", {
            callback = function(args)
                local bufnr = args.buf
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                if not client then
                    return
                end

                -- Completion is handled by blink.cmp (see plugins/blink-cmp.lua)

                local opts = { buffer = bufnr, silent = true }

                -- Hover and signature help. K is diagnostics-aware: on a
                -- problem line it shows the error first, K again shows docs
                -- (see util/hover.lua).
                vim.keymap.set("n", "K", function()
                    require("util.hover").show()
                end, opts)
                vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, opts)

                -- Navigation (telescope pickers show a code preview alongside the list)
                local tb = require("telescope.builtin")
                -- gd is JetBrains-style: usage → definition, definition →
                -- references. Also Inertia-aware in PHP and class-aware in
                -- templates/stylesheets. See util/goto.lua.
                vim.keymap.set("n", "gd", function()
                    require("util.goto").definition()
                end, opts)
                vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
                vim.keymap.set("n", "gi", tb.lsp_implementations, opts)
                vim.keymap.set("n", "go", tb.lsp_type_definitions, opts)
                -- gr in a stylesheet on .class/#id finds usages across
                -- templates (util/styleref.lua); otherwise the grouped
                -- references picker (util/references.lua).
                vim.keymap.set("n", "gr", function()
                    if require("util.styleref").references() then
                        return
                    end
                    require("util.references").open()
                end, opts)
                vim.keymap.set("n", "gs", tb.lsp_document_symbols, opts)

                -- Call hierarchy: who calls this (incoming) / what it calls
                -- (outgoing). Answers "what uses this method" as a navigable tree.
                vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls, opts)
                vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls, opts)

                -- Code actions and refactoring
                vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
                vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
                vim.keymap.set("n", "<F2>", vim.lsp.buf.rename, opts)

                -- Formatting: global <leader>fc → util/format.lua (works for
                -- every attached server, warns when none can format).

                -- Diagnostics
                vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
                vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
                vim.keymap.set("n", "<leader>of", vim.diagnostic.open_float, opts)
                vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)
            end,
        })

        vim.diagnostic.config({
            -- Hints ("context is not accessed") stay out of the inline
            -- virtual text — they still dim the symbol and show on K.
            virtual_text = { severity = { min = vim.diagnostic.severity.WARN } },
            severity_sort = true,
        })
    end,
}
