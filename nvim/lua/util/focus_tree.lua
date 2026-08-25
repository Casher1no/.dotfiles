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

local is_win = vim.fn.has("win32") == 1

-- Canonical form for comparing two paths. On Windows this matters twice over:
-- neo-tree normalizes its own paths to BACKslashes (neo-tree.utils
-- normalize_path) and so does nvim_buf_get_name, so a containment test written
-- with "/" separators answers false for every file in the project — which is
-- exactly what used to happen here, leaving reveal off on every <leader>e.
-- Drive-letter/segment case can differ between the two sources as well, and
-- NTFS does not care, so fold it.
local function canon(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    path = vim.fs.normalize(path) -- "\\" -> "/", resolves . and ..
    path = path:gsub("/+$", "") -- no trailing separator
    return is_win and path:lower() or path
end

local function inside(path, root)
    path, root = canon(path), canon(root)
    if path == "" or root == "" then
        return false
    end
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
