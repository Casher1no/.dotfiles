-- Resolves the PSR-4 namespace for a target PHP file path, based on the
-- nearest composer.json's autoload.psr-4 (and autoload-dev.psr-4) map. Used
-- by both util/templates/laravel.lua and util/templates/php.lua — Laravel's
-- "App\..." namespacing is just the project's ordinary PSR-4 map, so one
-- resolver covers both.

local M = {}

local function read_json(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil
    end
    local ok2, data = pcall(vim.json.decode, table.concat(lines, "\n"))
    return ok2 and data or nil
end

local function find_composer(dir)
    local matches = vim.fs.find("composer.json", { path = dir, upward = true })
    if not matches[1] then
        return nil, nil
    end
    return read_json(matches[1]), vim.fs.dirname(matches[1])
end

function M.resolve(path)
    local dir = vim.fs.dirname((path:gsub("\\", "/")))
    local composer, root = find_composer(dir)
    if not composer or not root then
        return nil
    end

    local maps = {}
    for _, key in ipairs({ "autoload", "autoload-dev" }) do
        local psr4 = (composer[key] or {})["psr-4"]
        if psr4 then
            for ns, mapped_dir in pairs(psr4) do
                maps[#maps + 1] = { ns = ns, dir = mapped_dir }
            end
        end
    end

    local target_dir = vim.fs.normalize(dir)
    local best = nil
    for _, m in ipairs(maps) do
        local mapped_dir = vim.fs.normalize(root .. "/" .. (m.dir:gsub("/$", "")))
        if target_dir == mapped_dir or target_dir:sub(1, #mapped_dir + 1) == mapped_dir .. "/" then
            if not best or #mapped_dir > #best.mapped_dir then
                best = { ns = m.ns, mapped_dir = mapped_dir }
            end
        end
    end
    if not best then
        return nil
    end

    local relative = target_dir:sub(#best.mapped_dir + 2)
    local ns = best.ns:gsub("\\+$", "")
    if relative ~= "" then
        ns = ns .. "\\" .. relative:gsub("/", "\\")
    end
    return ns
end

return M
