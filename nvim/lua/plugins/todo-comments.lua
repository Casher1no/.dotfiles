-- Highlight, list, and navigate TODO/FIX/HACK/NOTE/etc. comments.
-- https://github.com/folke/todo-comments.nvim
return {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TodoTelescope", "TodoQuickFix", "TodoLocList" },
    opts = {
        keywords = {
            TODO = { icon = " ", color = "yellow" },
        },
        colors = {
            yellow = { "#FFDD33" },
        },
    },
    keys = {
        { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
        {
            "]t",
            function() require("todo-comments").jump_next() end,
            desc = "Next TODO comment",
        },
        {
            "[t",
            function() require("todo-comments").jump_prev() end,
            desc = "Previous TODO comment",
        },
    },
}
