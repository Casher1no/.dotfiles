-- Client capabilities advertised to every LSP server (plugins/lsp.lua):
-- nvim's defaults plus blink.cmp's completion additions. The blink part is a
-- HARDCODED copy of what get_lsp_capabilities({}, true) adds over the nvim
-- 0.12.4 defaults (generated from blink.cmp main@78336bc) — requiring blink
-- here just for its static capability table loaded all of it at startup,
-- defeating its InsertEnter gate. The rest of blink's table (snippetSupport,
-- labelDetailsSupport, contextSupport, ...) already matches the defaults.
--
-- Drift guard: when blink actually loads, plugins/blink-cmp.lua compares
-- this table against the live get_lsp_capabilities() and warns if an update
-- changed it. Blink's own plugin/blink-cmp.lua also re-merges its caps into
-- vim.lsp.config("*") on load, so servers started after that get the fresh
-- table either way — this copy covers the ones started before insert mode.
return function()
    return vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
        textDocument = {
            completion = {
                completionItem = {
                    insertTextModeSupport = { valueSet = { 1 } }, -- asIs
                    resolveSupport = {
                        properties = { "documentation", "detail", "additionalTextEdits", "command", "data" },
                    },
                },
                completionList = {
                    itemDefaults = { "commitCharacters", "editRange", "insertTextFormat", "insertTextMode", "data" },
                },
                insertTextMode = 1, -- asIs
            },
        },
    })
end
