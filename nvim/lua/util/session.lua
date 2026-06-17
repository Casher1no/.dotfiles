-- Remembers the last project (cwd) Neovim was in, so the dashboard can offer a
-- "Continue — <project>" entry that cd's back in and restores its session.

local M = {}

M.file = vim.fn.stdpath("state") .. "/last_project"

function M.save()
    local cwd = vim.fn.getcwd()
    local f = io.open(M.file, "w")
    if f then
        f:write(cwd)
        f:close()
    end
end

-- True if persistence.nvim has a saved session for `dir`. Session files live in
-- stdpath("state")/sessions/ named after the dir (path separators -> "%%"),
-- optionally with a "%%<branch>" suffix — so we glob with a trailing wildcard.
local function has_session(dir)
    local enc = dir:gsub("[\\/:]+", "%%")
    local sdir = vim.fn.stdpath("state") .. "/sessions/"
    return #vim.fn.glob(sdir .. enc .. "*.vim", true, true) > 0
end

-- The last project's directory, or nil if none recorded, it no longer exists,
-- or there's no saved session to restore.
function M.get()
    local f = io.open(M.file, "r")
    if not f then
        return nil
    end
    local dir = f:read("*l")
    f:close()
    if dir and dir ~= "" and vim.fn.isdirectory(dir) == 1 and has_session(dir) then
        return dir
    end
    return nil
end

-- cd into the last project and load its saved session.
function M.continue()
    local dir = M.get()
    if not dir then
        return
    end
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    require("persistence").load()
end

return M
