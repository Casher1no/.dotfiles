-- C# language server via the Roslyn-based server (the one VS / VS Code use),
-- driven by seblyng/roslyn.nvim. Unlike the servers in lua/lsp/, Roslyn isn't
-- enabled through plugins/lsp.lua's generic loop: roslyn.nvim starts the server
-- itself once it locates a .sln / .csproj, and picks up the Roslyn binary that
-- mason installs (see plugins/package-manager.lua → "roslyn").
--
-- Buffer keymaps (gd, gr, K, <leader>f, …) still come from the shared LspAttach
-- handler in plugins/lsp.lua, which fires for every client including this one.
return {
    "seblyng/roslyn.nvim",
    ft = "cs",
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {
        -- Defaults are fine; server-level settings go through vim.lsp.config
        -- below so blink.cmp's capabilities (set on "*" in plugins/lsp.lua)
        -- still apply.
    },
    config = function(_, opts)
        -- Upstream bug (roslyn.nvim @ 7d8c166): the code action pickers assume a
        -- selection was made. Pressing <Esc> passes nil to the callback, so the
        -- nested picker throws "attempt to index local 'action' (a nil value)"
        -- and the fix-all picker fires a resolveFixAll request with a nil scope.
        --
        -- Rather than copy the handlers, run upstream's implementation with
        -- vim.ui.select swapped for a version that drops cancelled selections.
        -- Each handler opens exactly one picker, so the stub restores itself on
        -- first use; if upstream ever fixes this, the wrapper becomes a no-op.
        local function cancellable(handler)
            return function(data, ctx)
                local select = vim.ui.select
                vim.ui.select = function(items, select_opts, on_choice)
                    vim.ui.select = select
                    select(items, select_opts, function(choice, idx)
                        if choice ~= nil then
                            on_choice(choice, idx)
                        end
                    end)
                end

                local ok, err = pcall(handler, data, ctx)
                vim.ui.select = select
                if not ok then
                    error(err)
                end
            end
        end

        local roslyn_commands = require("roslyn.lsp.commands")

        vim.lsp.config("roslyn", {
            commands = {
                ["roslyn.client.nestedCodeAction"] = cancellable(roslyn_commands["roslyn.client.nestedCodeAction"]),
                ["roslyn.client.fixAllCodeAction"] = cancellable(roslyn_commands["roslyn.client.fixAllCodeAction"]),
            },
            settings = {
                ["csharp|inlay_hints"] = {
                    csharp_enable_inlay_hints_for_implicit_object_creation = true,
                    csharp_enable_inlay_hints_for_implicit_variable_types = true,
                },
                ["csharp|code_lens"] = {
                    -- Off on purpose. Reference counts are recomputed for every
                    -- symbol in the buffer as you type, and on a Unity solution
                    -- (Assembly-CSharp plus a dozen package assemblies) that is
                    -- a steady source of input lag. Flip to true if the counts
                    -- are worth it on a smaller solution.
                    dotnet_enable_references_code_lens = false,
                },
            },
        })
        require("roslyn").setup(opts)
    end,
}
