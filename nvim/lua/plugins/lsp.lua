return {
    "neovim/nvim-lspconfig",
    -- BufReadPre fires before FileType, so vim.lsp.enable below registers its
    -- FileType autocmd in time for the first opened file; for buffers loaded
    -- before this plugin, vim.lsp.enable replays the event itself (doautoall
    -- in runtime vim/lsp.lua). StdinReadPre covers `nvim -` sessions. Known
    -- gap, accepted: a pure `:enew` + `:set ft=…` scratch buffer before any
    -- real file open gets no LSP (FileType can't join this list — the
    -- dashboard buffer sets a filetype and would defeat the gate).
    event = { "BufReadPre", "BufNewFile", "StdinReadPre" },
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
        -- (snippets, auto-import / additionalTextEdits, resolve support, ...)
        -- without loading blink at startup — see util/lsp_caps.lua for the
        -- hardcoded table and its drift guard.
        vim.lsp.config("*", { capabilities = require("util.lsp_caps")() })

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

                -- Load eagerly (not on first gd press) so its client start-time
                -- tracker sees every server from the moment it attaches — gd
                -- uses those ages to retry instead of reporting "not found"
                -- while a just-started server is still loading its index.
                require("util.goto")

                -- JS projects without a ts/jsconfig only get references for
                -- open files (tsserver inferred project); preload the rest
                -- into hidden buffers so navigation covers the whole project
                -- (util/tsproject.lua).
                if client.name == "vtsls" then
                    require("util.tsproject").preload(client, bufnr)
                end

                -- Everything below is per-buffer, not per-client; php buffers
                -- attach 3+ servers, so only register the maps on the first
                -- attach.
                if vim.b[bufnr].lsp_keymaps then
                    return
                end

                local opts = { buffer = bufnr, silent = true }

                -- Hover and signature help. K is diagnostics-aware: on a
                -- problem line it shows the error first, K again shows docs
                -- (see util/hover.lua).
                vim.keymap.set("n", "K", function()
                    require("util.hover").show()
                end, opts)
                vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, opts)

                -- Navigation (telescope pickers show a code preview alongside
                -- the list; telescope is required inside the closures so it
                -- isn't loaded on attach, only on first use)
                -- gd shows definition + usages in one picker (definition
                -- first, so <CR> is a plain jump) — gr is only a shortcut to
                -- the usages half. Also Inertia-aware in PHP and class-aware
                -- in templates/stylesheets. See util/goto.lua.
                vim.keymap.set("n", "gd", function()
                    require("util.goto").definition()
                end, opts)
                vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
                vim.keymap.set("n", "gi", function()
                    require("telescope.builtin").lsp_implementations()
                end, opts)
                vim.keymap.set("n", "go", function()
                    require("telescope.builtin").lsp_type_definitions()
                end, opts)
                -- gr in a stylesheet on .class/#id finds usages across
                -- templates (util/styleref.lua); otherwise the grouped
                -- references picker (util/references.lua).
                vim.keymap.set("n", "gr", function()
                    if require("util.styleref").references() then
                        return
                    end
                    require("util.references").open()
                end, opts)
                vim.keymap.set("n", "gs", function()
                    require("telescope.builtin").lsp_document_symbols()
                end, opts)

                -- Call hierarchy: who calls this (incoming) / what it calls
                -- (outgoing). Answers "what uses this method" as a navigable tree.
                vim.keymap.set("n", "<leader>ci", vim.lsp.buf.incoming_calls, opts)
                vim.keymap.set("n", "<leader>co", vim.lsp.buf.outgoing_calls, opts)

                -- Code actions and refactoring: JetBrains-style intentions
                -- dropdown at the cursor (LSP actions + treesj split/join),
                -- see util/actions.lua.
                vim.keymap.set({ "n", "v" }, "<leader>ca", function()
                    require("util.actions").open()
                end, opts)
                vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
                vim.keymap.set("n", "<F2>", vim.lsp.buf.rename, opts)

                -- Formatting: global <leader>fc → util/format.lua (works for
                -- every attached server, warns when none can format).

                -- Diagnostics
                vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
                vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
                vim.keymap.set("n", "<leader>of", vim.diagnostic.open_float, opts)
                vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)

                vim.b[bufnr].lsp_keymaps = true
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
