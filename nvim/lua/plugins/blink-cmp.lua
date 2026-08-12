return {
    "saghen/blink.cmp",
    version = "1.*", -- use a release with prebuilt fuzzy-matching binaries
    event = "InsertEnter",
    opts = {
        keymap = {
            -- JetBrains-like: Enter and Tab accept, arrows / C-n / C-p navigate
            preset = "enter",
            ["<Tab>"] = { "accept", "fallback" },
        },
        appearance = {
            nerd_font_variant = "mono", -- match most Nerd Fonts
        },
        completion = {
            menu = {
                auto_show = true, -- pop up automatically as you type
                draw = {
                    -- icon + label, with the kind name ("Method", "Field", …) on the right
                    columns = {
                        { "kind_icon" },
                        { "label", "label_description", gap = 1 },
                        { "kind", gap = 1 },
                    },
                },
            },
            -- show docs/preview for the highlighted item
            documentation = { auto_show = true, auto_show_delay_ms = 200 },
            -- preselect the top match so Enter/Tab accepts it immediately
            list = { selection = { preselect = true, auto_insert = false } },
            -- trigger on every keyword char, even the first letter
            trigger = { show_on_keyword = true },
        },
        sources = {
            -- "project_snippets" serves this project's custom snippets (see
            -- util/project_snippets.lua), filtered by file extension.
            --
            -- C# drops "buffer": Unity method names like OnDrawGizmos are
            -- real overrides in plenty of other scripts, so blink's buffer
            -- source (which scans all loaded buffers, not just this one)
            -- kept surfacing them a second time as a plain-word match
            -- alongside the actual snippet entry.
            default = function(ctx)
                -- blink calls this without a ctx from some internal paths
                -- (e.g. computing trigger characters) — fall back to the
                -- current buffer rather than indexing a nil ctx.
                local bufnr = (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
                if vim.bo[bufnr].filetype == "cs" then
                    return { "lsp", "path", "snippets", "project_snippets" }
                end
                return { "lsp", "path", "snippets", "buffer", "project_snippets" }
            end,
            providers = {
                project_snippets = {
                    name = "Project",
                    module = "util.project_blink_source",
                },
            },
        },
        -- falls back to a Lua matcher if the prebuilt binary is unavailable
        fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    config = function(_, opts)
        require("blink.cmp").setup(opts)
        -- Drift guard for the capability copy hardcoded in util/lsp_caps.lua
        -- (advertised to servers without loading blink at startup): if a
        -- blink update changes get_lsp_capabilities, warn that the copy is
        -- stale. Compared against the copy itself, not vim.lsp.config["*"] —
        -- blink's own plugin file (and potentially other plugins) merge into
        -- that table on load, which would false-positive the check.
        vim.schedule(function()
            pcall(function()
                local want = require("blink.cmp").get_lsp_capabilities({}, true).textDocument.completion
                local have = require("util.lsp_caps")().textDocument.completion
                if not vim.deep_equal(want, have) then
                    vim.notify(
                        "blink.cmp's LSP capabilities changed upstream — update the hardcoded table in util/lsp_caps.lua",
                        vim.log.levels.WARN
                    )
                end
            end)
        end)
    end,
}
