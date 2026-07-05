-- Smooth (animated) scrolling. <S-Up>/<S-Down> scroll half a page with an
-- easing animation instead of jumping instantly.
return {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    config = function()
        local neoscroll = require("neoscroll")
        neoscroll.setup({
            mappings = {}, -- only bind the keys we want, not neoscroll's full default set
        })

        local keymap = {
            ["<S-Up>"] = function()
                neoscroll.ctrl_u({ duration = 30 })
            end,
            ["<S-Down>"] = function()
                neoscroll.ctrl_d({ duration = 30 })
            end,
        }
        for lhs, action in pairs(keymap) do
            vim.keymap.set({ "n", "v", "x" }, lhs, action)
        end
    end,
}
