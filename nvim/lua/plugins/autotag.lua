-- JetBrains-style tag behavior, powered by treesitter:
--   - type `<div>` and the closing `</div>` appears with the cursor between
--   - edit the opening tag (`div` → `a`) and the closing tag renames along
-- Works in html, vue, php (blade/inertia templates), jsx/tsx, xml, markdown.
return {
    "windwp/nvim-ts-autotag",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
        -- Angular templates parse with the angular grammar but behave like
        -- HTML for tag closing/renaming.
        aliases = { ["htmlangular"] = "html" },
    },
}
