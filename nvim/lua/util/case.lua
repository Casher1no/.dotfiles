-- Shared name-casing helpers for file templates (util/templates/*).

local M = {}

function M.pascal_case(s)
    local out = s:gsub("[%-_%s]+(%w)", function(c)
        return c:upper()
    end)
    return out:sub(1, 1):upper() .. out:sub(2)
end

function M.kebab_case(s)
    s = s:gsub("(%l)(%u)", "%1-%2")
    s = s:gsub("[_%s]+", "-")
    return s:lower()
end

function M.snake_case(s)
    s = s:gsub("(%l)(%u)", "%1_%2")
    s = s:gsub("[%-%s]+", "_")
    return s:lower()
end

return M
