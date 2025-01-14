return {
    "ThePrimeagen/harpoon",
    opts = {
        menu = {
            width = vim.api.nvim_win_get_width(0) - 4,
        }
    },
    config = function()
        local harpoon_ui = require("harpoon.ui")
        local harpoon_mark = require("harpoon.mark")

        vim.keymap.set("n", "<leader>ha", harpoon_mark.add_file, { desc = "Harpoon: Add file" })
        vim.keymap.set("n", "<leader>hm", harpoon_ui.toggle_quick_menu, { desc = "Harpoon: Toggle menu" })
    end,
}
