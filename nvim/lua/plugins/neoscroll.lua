-- Smooth (animated) scrolling. <S-Up>/<S-Down> scroll half a page with an
-- easing animation instead of jumping instantly — unless a K popup (docs or
-- error float, see util/hover.lua) is open, in which case they scroll the
-- popup's content and leave the code untouched.
return {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    config = function()
        local neoscroll = require("neoscroll")
        neoscroll.setup({
            mappings = {}, -- only bind the keys we want, not neoscroll's full default set
        })

        local function smart_scroll(dir) -- 1 = down, -1 = up
            return function()
                -- An open K popup (docs or error) captures the scroll.
                if require("util.hover").scroll(dir * 4) then
                    return
                end
                if dir > 0 then
                    neoscroll.ctrl_d({ duration = 30 })
                else
                    neoscroll.ctrl_u({ duration = 30 })
                end
            end
        end
        local function smart_hscroll(dir) -- 1 = right, -1 = left
            return function()
                if require("util.hover").hscroll(dir * 8) then
                    return
                end
                -- No popup: keep the default <S-Left>/<S-Right> word motion.
                vim.cmd("normal! " .. (dir > 0 and "w" or "b"))
            end
        end
        vim.keymap.set({ "n", "v", "x" }, "<S-Up>", smart_scroll(-1))
        vim.keymap.set({ "n", "v", "x" }, "<S-Down>", smart_scroll(1))
        vim.keymap.set({ "n", "v", "x" }, "<S-Left>", smart_hscroll(-1))
        vim.keymap.set({ "n", "v", "x" }, "<S-Right>", smart_hscroll(1))
    end,
}
