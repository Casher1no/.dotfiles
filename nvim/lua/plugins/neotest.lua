-- JetBrains-style test runner: run the test under the cursor or the whole
-- file, with pass/fail marks in the gutter and a summary tree. Adapters:
-- Python (pytest/unittest), C# (dotnet test), Java (JUnit), PHP (PHPUnit).
-- https://github.com/nvim-neotest/neotest
return {
    "nvim-neotest/neotest",
    dependencies = {
        "nvim-neotest/nvim-nio",
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
        "nvim-neotest/neotest-python",
        "Issafalcon/neotest-dotnet",
        "rcasia/neotest-java",
        "olimorris/neotest-phpunit",
    },
    keys = {
        { "<leader>tt", function() require("neotest").run.run() end, desc = "Test: run nearest" },
        { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Test: run current file" },
        { "<leader>tD", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Test: debug nearest" },
        { "<leader>tS", function() require("neotest").run.stop() end, desc = "Test: stop" },
        { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Test: toggle summary tree" },
        {
            "<leader>to",
            function() require("neotest").output.open({ enter = true, auto_close = true }) end,
            desc = "Test: show output",
        },
        { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Test: toggle output panel" },
        { "]f", function() require("neotest").jump.next({ status = "failed" }) end, desc = "Next failed test" },
        { "[f", function() require("neotest").jump.prev({ status = "failed" }) end, desc = "Previous failed test" },
    },
    config = function()
        require("neotest").setup({
            adapters = {
                -- justMyCode=false so <leader>tD can step into library code,
                -- matching how the plain DAP configs behave.
                require("neotest-python")({ dap = { justMyCode = false } }),
                require("neotest-dotnet"),
                require("neotest-java")({}),
                require("neotest-phpunit"),
            },
        })
    end,
}
