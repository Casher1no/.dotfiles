-- Rainbow brackets: nested (), [], {} get alternating colors so matching
-- pairs are easy to spot. Powered by the treesitter parse tree (see
-- plugins/treesitter.lua) — languages without a parser just keep plain
-- bracket colors.
return {
    "HiPhish/rainbow-delimiters.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
        -- Defaults cover everything; submodule setup keeps lazy happy.
        require("rainbow-delimiters.setup").setup({})
    end,
}
