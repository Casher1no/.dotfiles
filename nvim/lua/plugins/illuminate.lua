-- Automatically highlight other occurrences of the symbol under the cursor
-- (LSP first, then treesitter, then plain text) — like an IDE's
-- identifier highlighting. <A-n> / <A-p> jump between the occurrences.
-- https://github.com/RRethy/vim-illuminate
return {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
        delay = 150,
        -- On very large files, regex/treesitter scanning gets slow — restrict
        -- to the LSP provider there.
        large_file_cutoff = 3000,
        large_file_overrides = { providers = { "lsp" } },
        -- No occurrence scans per keystroke in Telescope's prompt buffer.
        -- configure() replaces the default denylist instead of merging, so
        -- the plugin's defaults (dirbuf, dirvish, fugitive) are repeated.
        filetypes_denylist = { "dirbuf", "dirvish", "fugitive", "TelescopePrompt" },
    },
    config = function(_, opts)
        -- vim-illuminate uses configure(), not setup(), so `opts` alone
        -- wouldn't be applied.
        require("illuminate").configure(opts)
    end,
}
