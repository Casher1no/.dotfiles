-- Tracks the order in which files were visited this session, most-recent first.
-- Used by the project recent-files picker so the list reflects live navigation
-- (current file on top, previously visited next, …).

local M = {}

M.list = {} -- array of normalized absolute paths, index 1 = most recent

local is_win = vim.fn.has("win32") == 1

-- Normalize so comparisons are stable: forward slashes, resolved ./.., and on
-- Windows the buffer-name/cwd separator mismatch (\ vs /) goes away.
local function norm(path)
    return vim.fs.normalize(path or "")
end

function M.touch(path)
    if path == nil or path == "" then
        return
    end
    path = norm(path)
    -- Drop any existing entry (case-insensitive on Windows), then push to front.
    local key = is_win and path:lower() or path
    for i, p in ipairs(M.list) do
        if (is_win and p:lower() or p) == key then
            table.remove(M.list, i)
            break
        end
    end
    table.insert(M.list, 1, path)
end

-- Most-recent files under `cwd` that still exist on disk, capped at `limit`.
function M.for_cwd(cwd, limit)
    cwd = norm(cwd)
    local prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
    if is_win then
        prefix = prefix:lower()
    end
    local out = {}
    for _, path in ipairs(M.list) do
        local cmp = is_win and path:lower() or path
        if cmp:sub(1, #prefix) == prefix and vim.fn.filereadable(path) == 1 then
            table.insert(out, path)
            if #out >= limit then
                break
            end
        end
    end
    return out
end

return M
