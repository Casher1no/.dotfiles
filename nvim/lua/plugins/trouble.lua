-- IDE-style "Problems" panel: diagnostics, references, symbols, quickfix
-- and TODOs (via todo-comments) in one togglable list.
-- https://github.com/folke/trouble.nvim
return {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
    keys = {
        { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (project)" },
        { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Diagnostics (this file)" },
        { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Document symbols panel" },
        { "<leader>xr", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP references / definitions" },
        { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list panel" },
        {
            "<leader>xt",
            function()
                -- todo-comments lazy-loads on BufReadPost; straight from the
                -- dashboard its trouble source is not registered yet
                require("lazy").load({ plugins = { "todo-comments.nvim" } })
                vim.cmd("Trouble todo toggle")
            end,
            desc = "TODO comments panel",
        },
    },
}
