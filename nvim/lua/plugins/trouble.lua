-- JetBrains-style "Problems" panel: diagnostics, references, symbols, quickfix
-- and TODOs (via todo-comments) in one togglable list.
-- https://github.com/folke/trouble.nvim
return {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "Trouble",
    opts = {},
    keys = {
        { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (project)" },
        { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Diagnostics (this file)" },
        { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Document symbols panel" },
        { "<leader>xr", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP references / definitions" },
        { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list panel" },
        { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "TODO comments panel" },
    },
}
