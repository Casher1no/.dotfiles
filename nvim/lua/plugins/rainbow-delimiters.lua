-- Rainbow brackets: nested (), [], {} get alternating colors so matching
-- pairs are easy to spot. Powered by the treesitter parse tree (see
-- plugins/treesitter.lua) — languages without a parser just keep plain
-- bracket colors.
return {
    "HiPhish/rainbow-delimiters.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
        require("rainbow-delimiters.setup").setup({
            strategy = {
                -- The global strategy runs whole-buffer queries, which
                -- stalls redraws on huge files; a strategy function that
                -- returns nil disables the plugin for that buffer
                -- (:h rb-delimiters-strategy).
                [""] = function(bufnr)
                    if vim.api.nvim_buf_line_count(bufnr) > 10000 then
                        return nil
                    end
                    return "rainbow-delimiters.strategy.global"
                end,
            },
        })
    end,
}
