-- Telescope picker over the folders in ~/Projects. Selecting one cd's into it
-- and opens a file finder scoped to that project.
local function project_picker()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local root = vim.fn.expand("~/Projects")
    local dirs = {}
    for name, type in vim.fs.dir(root) do
        if type == "directory" and not name:match("^%.") then
            table.insert(dirs, name)
        end
    end
    table.sort(dirs)

    pickers
        .new({}, {
            prompt_title = "Projects",
            finder = finders.new_table({ results = dirs }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local entry = action_state.get_selected_entry()
                    if not entry then
                        return
                    end
                    local path = root .. "/" .. entry[1]
                    vim.cmd("cd " .. vim.fn.fnameescape(path))
                    require("telescope.builtin").find_files({ cwd = path })
                end)
                return true
            end,
        })
        :find()
end

return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
        dashboard = {
            preset = {
                header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝
                ]],
                keys = {
                    { icon = " ", key = "f", desc = "Find File", action = ":Telescope find_files" },
                    { icon = " ", key = "p", desc = "Projects", action = project_picker },
                    { icon = " ", key = "r", desc = "Recent Files", action = ":Telescope oldfiles" },
                    { icon = " ", key = "g", desc = "Find Text", action = ":Telescope live_grep" },
                    { icon = " ", key = "e", desc = "File Explorer", action = ":Neotree toggle right" },
                    {
                        icon = " ",
                        key = "c",
                        desc = "Config",
                        action = function()
                            require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config") })
                        end,
                    },
                    { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy" },
                    { icon = " ", key = "m", desc = "Mason", action = ":Mason" },
                    { icon = " ", key = "q", desc = "Quit", action = ":qa" },
                },
            },
            sections = {
                { section = "header" },
                { section = "keys", gap = 1, padding = 1 },
                { section = "recent_files", icon = " ", title = "Recent Files", indent = 2, padding = 1 },
                { section = "startup" },
            },
        },
    },
}
