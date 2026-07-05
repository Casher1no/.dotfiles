local M = {}

local function is_unity_root(dir)
    return vim.fn.isdirectory(dir .. "/Assets") == 1 and vim.fn.isdirectory(dir .. "/ProjectSettings") == 1
end

function M.root(start)
    local dir = start or vim.uv.cwd()
    while dir do
        if is_unity_root(dir) then
            return dir
        end
        local parent = vim.fs.dirname(dir)
        if parent == dir then
            return nil
        end
        dir = parent
    end
end

function M.is_unity_project(start)
    return M.root(start) ~= nil
end

return M
