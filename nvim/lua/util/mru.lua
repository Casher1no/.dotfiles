-- Tracks the order in which files were visited this session, most-recent first.
-- Used by the project recent-files picker so the list reflects live navigation
-- (current file on top, previously visited next, …).

local M = {}

M.list = {} -- array of absolute paths, index 1 = most recent

function M.touch(path)
    if path == nil or path == "" then
        return
    end
    -- Drop any existing entry, then push to the front.
    for i, p in ipairs(M.list) do
        if p == path then
            table.remove(M.list, i)
            break
        end
    end
    table.insert(M.list, 1, path)
end

-- Most-recent files under `cwd` that still exist on disk, capped at `limit`.
function M.for_cwd(cwd, limit)
    local out = {}
    for _, path in ipairs(M.list) do
        if path:sub(1, #cwd) == cwd and vim.fn.filereadable(path) == 1 then
            table.insert(out, path)
            if #out >= limit then
                break
            end
        end
    end
    return out
end

return M
