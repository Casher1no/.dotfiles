-- Resolves the directory that holds your projects. It differs per machine:
-- on Windows they live in F:/Projects, elsewhere in ~/Projects. Picks the
-- first candidate that actually exists so the project pickers find them.
local M = {}

local function exists(path)
    return vim.fn.isdirectory(vim.fn.expand(path)) == 1
end

-- Ordered list of candidate roots; first existing one wins.
local candidates = vim.fn.has("win32") == 1
        and { "F:/Projects", "~/Projects" }
    or { "~/Projects" }

-- Absolute path to the projects root (expanded), falling back to the first
-- candidate even if missing so callers always get a usable string.
function M.root()
    for _, dir in ipairs(candidates) do
        if exists(dir) then
            return vim.fn.expand(dir)
        end
    end
    return vim.fn.expand(candidates[1])
end

-- When the centered view (no-neck-pain) is active, the focused window may be
-- one of its empty padding windows. Opening a file/picker from there would put
-- the buffer in the padding column instead of the centered content window. If
-- we're in a padding window, jump to no-neck-pain's main content window first.
-- No-ops (guarded) when the plugin isn't loaded or centered view is off.
function M.focus_content_window()
    local ok, state = pcall(require, "no-neck-pain.state")
    if not ok then
        return
    end
    local tab = state.tabs and state.active_tab and state.tabs[state.active_tab]
    local main = tab and tab.wins and tab.wins.main
    if not main then
        return
    end
    local cur = vim.api.nvim_get_current_win()
    if (cur == main.left or cur == main.right) and main.curr and vim.api.nvim_win_is_valid(main.curr) then
        vim.api.nvim_set_current_win(main.curr)
    end
end

return M
