-- Resolve Inertia page strings (Inertia::render('Campaigns', ...)) to the
-- corresponding front-end page file, so `gd` can jump to Campaigns.vue.
local M = {}

-- Return the quoted-string contents the cursor is currently inside, or nil.
local function string_under_cursor()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local idx = 1
    while true do
        local s, e, content = line:find("['\"]([^'\"]*)['\"]", idx)
        if not s then
            return nil, line
        end
        if col >= s and col <= e then
            return content, line
        end
        idx = e + 1
    end
end

local function project_root()
    return vim.fs.root(0, { "artisan", "composer.json", ".git" }) or vim.fn.getcwd()
end

-- Resolve a page name ("Campaigns", "Campaigns/Index") to an existing file path.
function M.resolve(page)
    if not page or page == "" then
        return nil
    end
    page = page:gsub("%.", "/") -- support dot notation too

    local root = project_root()
    local dirs = { "resources/js/Pages", "resources/js/pages" }
    local exts = { ".vue", ".tsx", ".jsx" }
    for _, dir in ipairs(dirs) do
        for _, ext in ipairs(exts) do
            local path = root .. "/" .. dir .. "/" .. page .. ext
            if vim.uv.fs_stat(path) then
                return path
            end
        end
    end
    return nil
end

-- If the cursor sits on an Inertia render page string, return its file path.
function M.page_file_under_cursor()
    local str, line = string_under_cursor()
    if not str then
        return nil
    end
    -- Only treat it as a page when the line is an Inertia render call.
    if not (line:match("[Ii]nertia::render") or line:match("inertia%s*%(") or line:match("->render%s*%(")) then
        return nil
    end
    return M.resolve(str)
end

return M
