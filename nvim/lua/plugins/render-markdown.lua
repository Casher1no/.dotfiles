-- Pretty in-buffer markdown rendering: styled headings, tables, checkboxes,
-- code blocks and callouts via treesitter (parsers markdown/markdown_inline,
-- installed in plugins/treesitter.lua). Toggle from the palette (Markdown
-- category) or with :RenderMarkdown toggle.
-- https://github.com/MeanderingProgrammer/render-markdown.nvim
return {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.icons" },
    -- (Markdown buffers leave "E31: No such mapping" in v:errmsg via the
    -- stock ftplugin's silent!-guarded b:undo_ftplugin — never displayed,
    -- harmless; noted here so nobody chases it again.)
    ft = { "markdown" },
    cmd = "RenderMarkdown", -- also load when toggled from the palette
    opts = {},
}
