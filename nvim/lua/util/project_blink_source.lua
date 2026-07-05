-- Custom blink.cmp source that serves the current project's custom
-- snippets (see util/project_snippets.lua) alongside LSP results. Each
-- snippet optionally restricts itself to one file extension; entries with
-- no extension show in every file for the project.

local source = {}

function source.new()
    return setmetatable({}, { __index = source })
end

function source:enabled()
    return true
end

function source:get_trigger_characters()
    return {}
end

local ok_types, types = pcall(require, "blink.cmp.types")
local SNIPPET_KIND = (ok_types and types.CompletionItemKind and types.CompletionItemKind.Snippet) or 15

function source:get_completions(ctx, callback)
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local ext = vim.fn.fnamemodify(bufname, ":e")

    local items = {}
    for _, entry in ipairs(require("util.project_snippets").list_for_ext(ext)) do
        local body = table.concat(entry.body, "\n")
        items[#items + 1] = {
            label = entry.prefix,
            kind = SNIPPET_KIND,
            insertText = body,
            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
            filterText = entry.prefix,
            sortText = entry.prefix,
            documentation = {
                kind = "markdown",
                value = "```\n" .. body .. "\n```",
            },
        }
    end
    callback({
        context = ctx,
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = items,
    })
end

return source
