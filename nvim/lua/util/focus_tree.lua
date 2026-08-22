-- Open + focus the neo-tree explorer.
--
-- Reveal — jumping the tree to the file being edited — only happens when that
-- file lives inside the tree's root. Neo-tree's own answer for a file outside
-- it is to stop and ask "File not in cwd. Change cwd to …?" in a popup, so
-- <leader>e while editing a file from another project put a prompt on screen
-- and never opened the explorer.
--
-- The tree also opens asynchronously and the layout it lands in is rebuilt a
-- tick later, which can drop focus back on the code window — so on the first
-- <leader>e the tree appeared unfocused. Re-assert focus once it has settled.
local function inside(path, root)
    if path == "" or root == nil or root == "" then
        return false
    end
    root = root:gsub("/$", "")
    return path == root or vim.startswith(path, root .. "/")
end

local function tree_root()
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
        local state = manager.get_state("filesystem")
        if state and state.path then
            return state.path
        end
    end
    return vim.fn.getcwd()
end

return function()
    require("neo-tree.command").execute({
        action = "focus",
        source = "filesystem",
        position = "right",
        reveal = inside(vim.api.nvim_buf_get_name(0), tree_root()),
    })
    vim.defer_fn(function()
        if vim.bo.filetype == "neo-tree" then
            return -- focus survived, nothing to fix
        end
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
                vim.api.nvim_set_current_win(win)
                return
            end
        end
    end, 80)
end
