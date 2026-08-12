-- Favorite projects. A simple global list of project folder names (matching the
-- folders under the projects root, see util.projects) stored as a JSON array.
-- Favorites are surfaced at the top of the "Projects" palette category.

local M = {}

M.file = vim.fn.stdpath("state") .. "/project_favorites.json"

-- is_favorite runs once per project directory every time the "Projects"
-- palette category is built, so it can't afford a disk read + JSON decode
-- per call. Keyed on mtime rather than a one-shot load so edits made
-- outside this process (another nvim instance) are still picked up.
local cache -- { data, sec, nsec }

local function read_all()
    local stat = vim.uv.fs_stat(M.file)
    if not stat then
        return {}
    end
    if cache and cache.sec == stat.mtime.sec and cache.nsec == stat.mtime.nsec then
        return cache.data
    end
    local f = io.open(M.file, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    local data = {}
    if content ~= "" then
        local ok, decoded = pcall(vim.json.decode, content)
        if ok and type(decoded) == "table" then
            data = decoded
        end
    end
    cache = { data = data, sec = stat.mtime.sec, nsec = stat.mtime.nsec }
    return data
end

local function write_all(list)
    -- Callers mutate the table read_all handed out — possibly the cached
    -- one — before writing, so drop the cache unconditionally: the next
    -- read must reflect whatever actually landed on disk.
    cache = nil
    local f = io.open(M.file, "w")
    if f then
        f:write(vim.json.encode(list))
        f:close()
    end
end

-- List of favorited project names.
function M.list()
    return read_all()
end

function M.is_favorite(name)
    for _, n in ipairs(read_all()) do
        if n == name then
            return true
        end
    end
    return false
end

function M.add(name)
    local list = read_all()
    if not M.is_favorite(name) then
        table.insert(list, name)
        write_all(list)
    end
end

function M.remove(name)
    local list = read_all()
    for i, n in ipairs(list) do
        if n == name then
            table.remove(list, i)
            break
        end
    end
    write_all(list)
end

-- Toggle favorite state for a project name; returns the new state (true = now a
-- favorite).
function M.toggle(name)
    if M.is_favorite(name) then
        M.remove(name)
        return false
    end
    M.add(name)
    return true
end

return M
