-- Telescope picker over the folders in the projects root (see util.projects).
-- Selecting one cd's into it and opens a file finder scoped to that project.
local function project_picker()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local root = require("util.projects").root()
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

-- Dashboard action keys. Prepends "Continue — <project>" when a previous
-- project was recorded, so it always sits at the top.
-- Passed below by reference, not called: snacks resolves function-valued
-- preset fields when the dashboard renders, so the session lookup (file read
-- + session-dir glob) never runs on startups that open a file directly.
local function dashboard_keys()
    local keys = {}
    local last = require("util.session").get()
    if last then
        table.insert(keys, {
            icon = " ",
            key = "s",
            desc = "Continue — " .. vim.fn.fnamemodify(last, ":t"),
            action = function()
                require("util.session").continue()
            end,
        })
    end
    vim.list_extend(keys, {
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
    })
    return keys
end

return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    keys = {
        { "<c-/>", function() Snacks.terminal.toggle() end, mode = { "n", "t" }, desc = "Toggle Terminal" },
        { "<c-_>", function() Snacks.terminal.toggle() end, mode = { "n", "t" }, desc = "which_key_ignore" },
    },
    opts = {
        terminal = {},
        -- Back vim.ui.select with a real picker (used by <leader>r project
        -- tasks). Without this Neovim falls back to inputlist(), whose typed
        -- digits noice's cmdline popup swallows — input works but is invisible.
        picker = { ui_select = true },
        -- Floating prompt for vim.ui.input (task name / shell command).
        input = {},
        dashboard = {
            preset = {
                header = [[
 ██████╗ █████╗ ███████╗██╗  ██╗███████╗██████╗  ██╗███╗   ██╗ ██████╗
██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝██╔══██╗███║████╗  ██║██╔═══██╗
██║     ███████║███████╗███████║█████╗  ██████╔╝╚██║██╔██╗ ██║██║   ██║
██║     ██╔══██║╚════██║██╔══██║██╔══╝  ██╔══██╗ ██║██║╚██╗██║██║   ██║
╚██████╗██║  ██║███████║██║  ██║███████╗██║  ██║ ██║██║ ╚████║╚██████╔╝
 ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝
                ]],
                keys = dashboard_keys,
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
