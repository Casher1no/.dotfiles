-- Detects which language/framework stack(s) the current project is, so
-- util/templates/init.lua only offers relevant file templates (e.g. Unity
-- C# in a Unity project, Laravel + PHP in a Laravel project).
--
-- Walks upward from a starting directory; the nearest directory where ANY
-- stack matches wins (mirrors how LSP root_markers resolve nested projects
-- in a monorepo — e.g. a Vue frontend/ inside a Laravel repo).

local M = {}

local function has(dir, name)
    local path = dir .. "/" .. name
    return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

local function read_json(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end
    local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    return ok2 and data or nil
end

local function package_json_has_dep(dir, dep_name)
    local data = read_json(dir .. "/package.json")
    if not data then
        return false
    end
    local deps = data.dependencies or {}
    local dev_deps = data.devDependencies or {}
    return deps[dep_name] ~= nil or dev_deps[dep_name] ~= nil
end

local function is_unity_root(dir)
    return vim.fn.isdirectory(dir .. "/Assets") == 1 and vim.fn.isdirectory(dir .. "/ProjectSettings") == 1
end

M.STACKS = {
    {
        key = "unity",
        matches = is_unity_root,
    },
    {
        key = "laravel",
        matches = function(dir)
            return has(dir, "artisan")
        end,
    },
    {
        key = "php",
        matches = function(dir)
            return has(dir, "composer.json")
        end,
    },
    {
        key = "angular",
        matches = function(dir)
            return has(dir, "angular.json")
        end,
    },
    {
        key = "vue",
        matches = function(dir)
            return has(dir, "vue.config.js") or package_json_has_dep(dir, "vue")
        end,
    },
    {
        key = "python",
        matches = function(dir)
            return has(dir, "pyproject.toml") or has(dir, "setup.py") or has(dir, "requirements.txt")
        end,
    },
    {
        key = "csharp",
        matches = function(dir)
            if is_unity_root(dir) then
                return false -- Unity owns its own C# templates
            end
            return #vim.fn.glob(dir .. "/*.csproj", false, true) > 0 or #vim.fn.glob(dir .. "/*.sln", false, true) > 0
        end,
    },
}

-- Returns (stack_keys, root_dir) for the nearest directory (walking upward
-- from `start`) where at least one stack matches. Empty table if none found.
function M.detect(start)
    local dir = start or vim.uv.cwd()
    if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
        dir = vim.fs.dirname(dir)
    end

    while dir and dir ~= "" do
        local found = {}
        for _, stack in ipairs(M.STACKS) do
            if stack.matches(dir) then
                found[#found + 1] = stack.key
            end
        end
        if #found > 0 then
            return found, dir
        end
        local parent = vim.fs.dirname(dir)
        if parent == dir then
            break
        end
        dir = parent
    end
    return {}, nil
end

return M
