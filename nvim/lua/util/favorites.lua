-- Favorite projects. A simple global list of project folder names (matching the
-- folders under the projects root, see util.projects) stored as a JSON array.
-- Favorites are surfaced at the top of the "Projects" palette category.

local M = {}

M.file = vim.fn.stdpath("state") .. "/project_favorites.json"

local function read_all()
    local f = io.open(M.file, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    if content == "" then
        return {}
    end
    local ok, data = pcall(vim.json.decode, content)
    return (ok and type(data) == "table") and data or {}
end

local function write_all(list)
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
