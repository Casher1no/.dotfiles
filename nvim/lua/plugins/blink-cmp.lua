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
                    -- icon column + label, no plain "Field/Method" text
                    columns = {
                        { "kind_icon" },
                        { "label", "label_description", gap = 1 },
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
            default = { "lsp", "path", "snippets", "buffer" },
        },
        -- falls back to a Lua matcher if the prebuilt binary is unavailable
        fuzzy = { implementation = "prefer_rust_with_warning" },
    },
}
