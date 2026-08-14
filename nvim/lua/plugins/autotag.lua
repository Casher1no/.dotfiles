-- IDE-style tag behavior, powered by treesitter:
--   - type `<div>` and the closing `</div>` appears with the cursor between
--   - edit the opening tag (`div` → `a`) and the closing tag renames along
-- Works in html, vue, php (blade/inertia templates), jsx/tsx, xml, markdown.
return {
    "windwp/nvim-ts-autotag",
    -- The plugin only acts while typing. Its setup registers a one-shot
    -- InsertEnter attach (lazy.nvim re-fires the event for autocmds created
    -- during load, so the triggering buffer is covered) plus a FileType
    -- attach for buffers opened afterwards.
    event = "InsertEnter",
    opts = {
        -- Angular templates parse with the angular grammar but behave like
        -- HTML for tag closing/renaming.
        aliases = { ["htmlangular"] = "html" },
    },
    config = function(_, opts)
        require("nvim-ts-autotag").setup(opts)
        -- Buffers whose FileType fired before the first InsertEnter (e.g. a
        -- restored session with several template files) are invisible to the
        -- plugin's own autocmds, so attach when typing starts in them.
        -- attach() ignores buffers that are already attached.
        vim.api.nvim_create_autocmd("InsertEnter", {
            group = vim.api.nvim_create_augroup("autotag_late_attach", { clear = true }),
            callback = function(args)
                require("nvim-ts-autotag.internal").attach(args.buf)
            end,
        })
    end,
}
