-- Open + focus the neo-tree explorer, surviving no-neck-pain's centered
-- view: when the tree window first opens, no-neck-pain rebuilds its padding
-- layout and steals focus back to the code window — so on the first
-- <leader>e the tree appeared unfocused. After opening, re-assert focus once
-- the layout has settled.
return function()
    vim.cmd("Neotree focus right")
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
