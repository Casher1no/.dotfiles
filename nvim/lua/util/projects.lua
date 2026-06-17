-- Resolves the directory that holds your projects. It differs per machine:
-- on Windows they live in F:/Projects, elsewhere in ~/Projects. Picks the
-- first candidate that actually exists so the project pickers find them.
local M = {}

local function exists(path)
    return vim.fn.isdirectory(vim.fn.expand(path)) == 1
end

-- Ordered list of candidate roots; first existing one wins.
local candidates = vim.fn.has("win32") == 1
        and { "F:/Projects", "~/Projects" }
    or { "~/Projects" }

-- Absolute path to the projects root (expanded), falling back to the first
-- candidate even if missing so callers always get a usable string.
function M.root()
    for _, dir in ipairs(candidates) do
        if exists(dir) then
            return vim.fn.expand(dir)
        end
    end
    return vim.fn.expand(candidates[1])
end

return M
