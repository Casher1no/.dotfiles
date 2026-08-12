-- Tracks the order in which files were visited this session, most-recent first.
-- Used by the project recent-files picker so the list reflects live navigation
-- (current file on top, previously visited next, …).

local M = {}

-- The picker shows at most 12 entries per project; 100 leaves room for several
-- projects in one session while bounding the cost of every touch.
local MAX = 100

M.list = {} -- array of normalized absolute paths, index 1 = most recent

-- comparison key -> position in M.list, so touch needs no scan
local index = {}

local is_win = vim.fn.has("win32") == 1

-- Normalize so comparisons are stable: forward slashes, resolved ./.., and on
-- Windows the buffer-name/cwd separator mismatch (\ vs /) goes away.
local function norm(path)
    return vim.fs.normalize(path or "")
end

-- Case-insensitive on Windows.
local function to_key(path)
    return is_win and path:lower() or path
end

function M.touch(path)
    if path == nil or path == "" then
        return
    end
    path = norm(path)
    local key = to_key(path)
    local pos = index[key]
    if pos == 1 then
        M.list[1] = path -- keep the latest spelling (case can differ on Windows)
        return
    end
    if pos then
        table.remove(M.list, pos)
    elseif #M.list >= MAX then
        index[to_key(table.remove(M.list))] = nil -- evict the least recent
    end
    table.insert(M.list, 1, path)
    -- Entries up to the old position shifted down one; refresh their index.
    for i = 1, pos or #M.list do
        index[to_key(M.list[i])] = i
    end
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
        local cmp = to_key(path)
        -- fs_access and filereadable() only disagree on directories, and the
        -- list never holds one: the BufEnter hook checks filereadable before
        -- calling touch.
        if cmp:sub(1, #prefix) == prefix and vim.uv.fs_access(path, "R") then
            table.insert(out, path)
            if #out >= limit then
                break
            end
        end
    end
    return out
end

return M
