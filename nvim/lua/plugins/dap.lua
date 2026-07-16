-- Debugging via nvim-dap. C# (netcoredbg), PHP (Xdebug / vscode-php-debug)
-- and Python (debugpy) are auto-configured here; Java is wired through
-- nvim-jdtls (see plugins/jdtls.lua).
return {
    "mfussenegger/nvim-dap",
    dependencies = {
        { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
        "theHamsta/nvim-dap-virtual-text",
        "mfussenegger/nvim-dap-python",
        {
            "jay-babu/mason-nvim-dap.nvim",
            dependencies = "mason-org/mason.nvim",
            opts = {
                -- Adapter binaries installed automatically on first launch.
                ensure_installed = {
                    "netcoredbg", -- C#
                    "php", -- PHP (vscode-php-debug / Xdebug)
                    "javadbg", -- java-debug-adapter (bundle for jdtls)
                    "javatest", -- vscode-java-test (bundle for jdtls)
                    "python", -- debugpy
                },
                -- Let mason-nvim-dap auto-create adapters/configs for netcoredbg
                -- and php. Java is handled by nvim-jdtls, not here.
                automatic_installation = true,
                handlers = {
                    function(config)
                        require("mason-nvim-dap").default_setup(config)
                    end,
                    -- Python is set up by nvim-dap-python below instead: it
                    -- resolves the debugged program's interpreter from the
                    -- project's .venv / $VIRTUAL_ENV, which the default
                    -- handler doesn't.
                    python = function() end,
                },
            },
        },
    },
    keys = {
        { "<leader>b", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
        { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
        {
            "<leader>B",
            function()
                require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
            end,
            desc = "Debug: conditional breakpoint",
        },
        { "<leader>bc", function() require("dap").clear_breakpoints() end, desc = "Debug: clear all breakpoints" },
        { "<F5>", function() require("dap").continue() end, desc = "Debug: start/continue" },
        { "<S-F5>", function() require("dap").terminate() end, desc = "Debug: terminate" },
        { "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
        { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
        { "<S-F11>", function() require("dap").step_out() end, desc = "Debug: step out" },
        { "<F6>", function() require("dapui").toggle() end, desc = "Debug: toggle UI" },
        {
            "<leader>i",
            function() require("dapui").eval() end,
            mode = { "n", "v" },
            desc = "Debug: inspect / eval",
        },
    },
    config = function()
        local dap = require("dap")
        local dapui = require("dapui")

        dapui.setup()
        require("nvim-dap-virtual-text").setup({})

        -- Open the UI automatically on a session, close it when it ends.
        dap.listeners.before.attach.dapui_config = function() dapui.open() end
        dap.listeners.before.launch.dapui_config = function() dapui.open() end
        dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
        dap.listeners.before.event_exited.dapui_config = function() dapui.close() end

        -- Breakpoint / cursor gutter signs.
        vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", numhl = "" })
        vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", numhl = "" })
        vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticInfo", linehl = "Visual", numhl = "" })
        vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticHint", numhl = "" })

        -- C#: launch a built DLL (mason-nvim-dap provides the `coreclr` adapter).
        dap.configurations.cs = {
            {
                type = "coreclr",
                name = "Launch - netcoredbg",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
                end,
            },
        }

        -- Unity: attach to the Editor's Play Mode process via the Mono soft
        -- debugger, using the adapter bundled with the "Visual Studio Tools
        -- for Unity" VS Code extension (a separate debugger backend from
        -- coreclr/netcoredbg, which can't attach to Unity's Mono runtime).
        -- Only the adapter itself is registered here — the actual "Attach to
        -- Unity" configuration comes from the project's own
        -- .vscode/launch.json, which nvim-dap reads automatically; adding our
        -- own copy here would just duplicate that entry in the picker.
        if require("util.unity").is_unity_project() then
            local extension_dirs =
                vim.fn.glob(vim.fn.expand("~/.vscode/extensions/visualstudiotoolsforunity.vstuc-*"), false, true)
            table.sort(extension_dirs)
            local vstuc_dir = extension_dirs[#extension_dirs]

            if vstuc_dir then
                dap.adapters.vstuc = {
                    type = "executable",
                    command = "dotnet",
                    args = { "UnityDebugAdapter.dll" },
                    options = { cwd = vstuc_dir .. "/bin" },
                }
            else
                vim.notify(
                    "Unity project detected but no visualstudiotoolsforunity.vstuc-* extension found under "
                        .. "~/.vscode/extensions — install \"Visual Studio Tools for Unity\" in VS Code once to "
                        .. "get the debug adapter binary.",
                    vim.log.levels.WARN
                )
            end
        end

        -- Python: debugpy (installed by mason above) runs the adapter; the
        -- debugged program's interpreter comes from nvim-dap-python's
        -- resolver ($VIRTUAL_ENV, then <cwd>/.venv, then system python).
        require("dap-python").setup(vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python")

        -- PHP: listen for incoming Xdebug 3 connections (default port 9003).
        dap.configurations.php = {
            {
                type = "php",
                name = "Listen for Xdebug",
                request = "launch",
                port = 9003,
            },
        }
    end,
}
