-- A small centered command palette for the keymaps defined by plugins in this
-- config. Two panes: categories on the left, that category's actions (with the
-- keys to press) on the right. <CR> runs the focused action and closes; the
-- left pane just selects which category the right pane shows.
--
-- This list is curated by hand — keep it in sync with the keymaps in
-- lua/plugins/*. It intentionally shows only *our* mappings, not Neovim's
-- built-in or plugin-default ones.

local M = {}

M.categories = {
    {
        name = "Projects",
        icon = "",
        -- Rebuilt each time the palette opens (see M.open). Lists folders in
        -- the projects root (see util.projects); selecting one cd's in and
        -- opens a file finder there. Favorited projects (see util.favorites)
        -- are shown first, marked with ★. Press `f` on a project to toggle its
        -- favorite state.
        dynamic = function()
            local root = require("util.projects").root()
            local favorites = require("util.favorites")
            local favs, rest = {}, {}
            for name, type in vim.fs.dir(root) do
                if type == "directory" and not name:match("^%.") then
                    local path = root .. "/" .. name
                    local is_fav = favorites.is_favorite(name)
                    local item = {
                        desc = (is_fav and "★ " or "") .. name,
                        keys = "f",
                        project = name, -- used by the `f` toggle in M.open
                        action = function()
                            -- Avoid landing in a no-neck-pain padding window
                            -- when centered view is on (see util.projects).
                            require("util.projects").focus_content_window()
                            vim.cmd("cd " .. vim.fn.fnameescape(path))
                            require("telescope.builtin").find_files({ cwd = path })
                        end,
                    }
                    table.insert(is_fav and favs or rest, item)
                end
            end
            local function by_project(a, b)
                return a.project < b.project
            end
            table.sort(favs, by_project)
            table.sort(rest, by_project)

            local items = {}
            if #favs > 0 then
                items[#items + 1] = { desc = "Favorites  (f: toggle)", section = true }
                for _, it in ipairs(favs) do
                    items[#items + 1] = it
                end
                items[#items + 1] = { desc = "All Projects", section = true }
            else
                items[#items + 1] = { desc = "All Projects  (f: favorite)", section = true }
            end
            for _, it in ipairs(rest) do
                items[#items + 1] = it
            end
            return items
        end,
        items = {},
    },
    {
        name = "Project Commands",
        icon = "",
        -- Saved per-project tasks (see util/tasks.lua). Run on <CR>; the last
        -- two entries add / remove tasks for the current project.
        dynamic = function()
            local tasks = require("util.tasks")
            local reopen = function()
                vim.schedule(function()
                    require("util.palette").open()
                end)
            end
            local items = {}
            for _, t in ipairs(tasks.list()) do
                items[#items + 1] = {
                    desc = t.name,
                    keys = t.cmd,
                    action = function()
                        tasks.run(t)
                    end,
                }
            end
            items[#items + 1] = {
                desc = "＋ Add task…",
                action = function()
                    tasks.add_interactive(reopen)
                end,
            }
            items[#items + 1] = {
                desc = "－ Remove task…",
                action = function()
                    tasks.remove_interactive(reopen)
                end,
            }
            return items
        end,
        items = {},
    },
    {
        name = "Snippets",
        icon = "",
        -- Custom per-project snippets (see util/project_snippets.lua), keyed
        -- by project folder name so they persist across a `git pull` of this
        -- repo on any machine. Not tied to any language — each snippet has
        -- an optional file extension filter (blank = shows in every file).
        dynamic = function()
            local snippets = require("util.project_snippets")
            local reopen = function()
                vim.schedule(function()
                    require("util.palette").open()
                end)
            end
            local items = {}
            items[#items + 1] = {
                desc = "＋ Add project snippet…",
                action = function()
                    snippets.add_project_interactive(reopen)
                end,
            }
            items[#items + 1] = {
                desc = "＋ Add global snippet…",
                action = function()
                    snippets.add_global_interactive(reopen)
                end,
            }
            items[#items + 1] = {
                desc = "✎ Edit snippet…",
                action = function()
                    snippets.edit_interactive(reopen)
                end,
            }
            items[#items + 1] = {
                desc = "－ Remove snippet…",
                action = function()
                    snippets.remove_interactive(reopen)
                end,
            }

            local project_entries, global_entries = {}, {}
            for _, e in ipairs(snippets.list()) do
                table.insert(e.scope == snippets.GLOBAL_KEY and global_entries or project_entries, e)
            end
            local function entry_item(e)
                return { desc = e.name, keys = e.prefix .. (e.ext ~= "" and (" (." .. e.ext .. ")") or "") }
            end

            items[#items + 1] = { desc = "Project Snippets", section = true }
            if #project_entries == 0 then
                items[#items + 1] = { desc = "(none)" }
            else
                for _, e in ipairs(project_entries) do
                    items[#items + 1] = entry_item(e)
                end
            end

            items[#items + 1] = { desc = "Global Snippets", section = true }
            if #global_entries == 0 then
                items[#items + 1] = { desc = "(none)" }
            else
                for _, e in ipairs(global_entries) do
                    items[#items + 1] = entry_item(e)
                end
            end

            return items
        end,
        items = {},
    },
    {
        name = "Explorer",
        icon = "",
        items = {
            { desc = "Toggle / focus explorer", keys = "<leader>e", cmd = "Neotree focus right" },
            { desc = "Focus explorer", keys = "<leader>o", cmd = "Neotree focus right" },
            {
                desc = "New file from template (current buffer's folder)",
                keys = "A (in explorer)",
                action = function()
                    local dir = vim.fn.expand("%:p:h")
                    require("util.templates").create_interactive(dir)
                end,
            },
        },
    },
    {
        name = "Find (Telescope)",
        icon = "",
        items = {
            { desc = "Find files", keys = "<C-p> / <leader>ff", cmd = "Telescope find_files" },
            { desc = "Live grep", keys = "<leader>fg", cmd = "Telescope live_grep" },
            { desc = "Open buffers", keys = "<leader>fb", cmd = "Telescope buffers" },
            { desc = "Recent files (all)", keys = "<leader>fr", cmd = "Telescope oldfiles" },
            { desc = "Recent files (this project)", keys = "<leader>fp" },
            { desc = "Help tags", keys = "<leader>fh", cmd = "Telescope help_tags" },
            { desc = "Search word under cursor", keys = "<leader>fw", cmd = "Telescope grep_string" },
            { desc = "Find TODOs", keys = "<leader>ft", cmd = "TodoTelescope" },
        },
    },
    {
        name = "Git",
        icon = "",
        items = {
            { desc = "Changed files + diff", keys = "<leader>gs", cmd = "Telescope git_status" },
            { desc = "Next hunk", keys = "]h" },
            { desc = "Previous hunk", keys = "[h" },
            { desc = "Preview hunk", keys = "<leader>hp" },
            { desc = "Diff this file", keys = "<leader>hd" },
            { desc = "Stage hunk", keys = "<leader>hs" },
            { desc = "Reset hunk", keys = "<leader>hr" },
            { desc = "Blame line (full)", keys = "<leader>hb" },
            { desc = "Toggle line blame", keys = "<leader>tb" },
            { desc = "Toggle word diff", keys = "<leader>tw" },
            { desc = "Toggle line highlight", keys = "<leader>tl" },
            { desc = "Toggle deleted lines", keys = "<leader>td" },
        },
    },
    {
        name = "Window",
        icon = "",
        items = {
            { desc = "Cycle next window", keys = "<leader>ww", cmd = "wincmd w" },
            { desc = "Go to left window", keys = "<leader>wh", cmd = "wincmd h" },
            { desc = "Go to lower window", keys = "<leader>wj", cmd = "wincmd j" },
            { desc = "Go to upper window", keys = "<leader>wk", cmd = "wincmd k" },
            { desc = "Go to right window", keys = "<leader>wl", cmd = "wincmd l" },
            { desc = "Focus next window", keys = "<leader>nb", cmd = "wincmd w" },
            { desc = "Focus previous window", keys = "<leader>pb", cmd = "wincmd W" },
            { desc = "Toggle centered view", keys = "<leader>zz" },
            { desc = "Smooth scroll up half page", keys = "<S-Up>" },
            { desc = "Smooth scroll down half page", keys = "<S-Down>" },
        },
    },
    {
        name = "Themes",
        icon = "",
        -- on_focus previews the theme as you move through the list; <CR> applies
        -- and persists it via themery (closing without selecting reverts).
        on_focus = function(item)
            if item.theme then
                pcall(vim.cmd.colorscheme, item.theme)
            end
        end,
        items = (function()
            local names = {
                "catppuccin",
                "kanagawa-wave",
                "gruvbox",
                "oxocarbon",
                "onedark",
                "rose-pine",
                "everforest",
                "cyberdream",
                "vscode",
                "dracula",
                "nord",
            }
            local items = {}
            for _, name in ipairs(names) do
                items[#items + 1] = {
                    desc = name,
                    theme = name,
                    action = function()
                        require("themery").setThemeByName(name, true)
                    end,
                }
            end
            return items
        end)(),
    },
    {
        name = "LSP / Code",
        icon = "",
        items = {
            { desc = "Go to definition", keys = "gd" },
            { desc = "Go to declaration", keys = "gD" },
            { desc = "Go to implementations", keys = "gi" },
            { desc = "Go to type definition", keys = "go" },
            { desc = "Find references / usages", keys = "gr" },
            { desc = "Incoming calls (who calls this)", keys = "<leader>ci" },
            { desc = "Outgoing calls (what this calls)", keys = "<leader>co" },
            {
                desc = "Document symbols (methods, vars, …)",
                keys = "gs",
                action = function()
                    require("telescope.builtin").lsp_document_symbols()
                end,
            },
            {
                -- `:lsp restart` with no args only restarts clients attached
                -- to the *current* buffer, and errors if there are none. We
                -- want a global "fix everything" restart regardless of which
                -- buffer/client the cursor happens to be on.
                desc = "Restart LSP (fix stale/wrong diagnostics)",
                action = function()
                    local names = {}
                    local seen = {}
                    for _, client in ipairs(vim.lsp.get_clients()) do
                        if not seen[client.name] then
                            seen[client.name] = true
                            table.insert(names, client.name)
                        end
                    end
                    if #names == 0 then
                        vim.notify("No active LSP clients to restart", vim.log.levels.INFO)
                        return
                    end
                    vim.cmd("lsp restart " .. table.concat(names, " "))
                end,
            },
            { desc = "Hover docs", keys = "K" },
            { desc = "Code action", keys = "<leader>ca" },
            { desc = "Rename symbol", keys = "<leader>rn" },
        },
    },
    {
        name = "Debug",
        icon = "",
        items = {
            { desc = "Toggle breakpoint", keys = "<leader>b / <F9>", action = function() require("dap").toggle_breakpoint() end },
            { desc = "Conditional breakpoint", keys = "<leader>B" },
            { desc = "Clear all breakpoints", keys = "<leader>bc", action = function() require("dap").clear_breakpoints() end },
            { desc = "Start / Continue", keys = "<F5>", action = function() require("dap").continue() end },
            { desc = "Step over", keys = "<F10>", action = function() require("dap").step_over() end },
            { desc = "Step into", keys = "<F11>", action = function() require("dap").step_into() end },
            { desc = "Step out", keys = "<S-F11>", action = function() require("dap").step_out() end },
            { desc = "Terminate", keys = "<S-F5>", action = function() require("dap").terminate() end },
            { desc = "Toggle debug UI", keys = "<F6>", action = function() require("dapui").toggle() end },
            { desc = "Inspect / eval", keys = "<leader>i" },
        },
    },
    {
        name = "Help",
        icon = "",
        items = {
            { desc = "Buffer-local keymaps (which-key)", keys = "<leader>?" },
            { desc = "This palette", keys = "<leader><space>" },
            { desc = "Clear search highlight", keys = "<Esc>u" },
            { desc = "Run project task", keys = "<leader>r" },
            { desc = "Comment line", keys = "gcc" },
            { desc = "Comment selection (visual)", keys = "gc" },
            { desc = "Comment a motion (e.g. gcap)", keys = "gc{motion}" },
            { desc = "Move selection down", keys = "J / <A-Down> (visual)" },
            { desc = "Move selection up", keys = "K / <A-Up> (visual)" },
        },
    },
}

-- ---------------------------------------------------------------------------

local state = {
    selected = 1, -- which category the right pane is showing
    cat_win = nil,
    cat_buf = nil,
    act_win = nil,
    act_buf = nil,
    orig_colorscheme = nil, -- restored if a theme preview isn't confirmed
    confirmed = false, -- set when an action is run via <CR>
}

local LEFT_W = 24
local RIGHT_W = 48
local GAP = 1

local function close()
    -- Undo a live theme preview unless the user actually selected one.
    if not state.confirmed and state.orig_colorscheme and vim.g.colors_name ~= state.orig_colorscheme then
        pcall(vim.cmd.colorscheme, state.orig_colorscheme)
    end
    for _, w in ipairs({ state.act_win, state.cat_win }) do
        if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end
    state.cat_win, state.act_win = nil, nil
end

local function render_right()
    local cat = M.categories[state.selected]
    local lines, width = {}, RIGHT_W
    table.insert(lines, "  " .. (cat.icon or "") .. " " .. cat.name)
    table.insert(lines, "")
    -- Maps a rendered line number to the item that produced it (nil for
    -- header/blank/section lines) — needed because section titles take a
    -- variable number of lines, so line number no longer maps to
    -- cat.items[line - 2] by fixed arithmetic.
    local line_map = {}
    for _, item in ipairs(cat.items) do
        if item.section then
            -- A non-actionable section title (e.g. "Project Snippets"), not
            -- a runnable item — no keys column, blank line above for spacing.
            table.insert(lines, "")
            table.insert(lines, "  " .. item.desc)
        else
            local keys = item.keys or ""
            local pad = width - 4 - #item.desc - #keys
            if pad < 1 then
                pad = 1
            end
            table.insert(lines, "  " .. item.desc .. string.rep(" ", pad) .. keys)
            line_map[#lines] = item
        end
    end
    state.line_map = line_map
    vim.bo[state.act_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.act_buf, 0, -1, false, lines)
    vim.bo[state.act_buf].modifiable = false
end

local function render_left()
    local lines = {}
    for i, cat in ipairs(M.categories) do
        local marker = (i == state.selected) and "▶ " or "  "
        table.insert(lines, marker .. (cat.icon or "") .. " " .. cat.name)
    end
    vim.bo[state.cat_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.cat_buf, 0, -1, false, lines)
    vim.bo[state.cat_buf].modifiable = false
end

-- Run the action on the given right-pane line (1-based, including header rows).
local function run_action(line)
    local item = state.line_map[line]
    -- Mark confirmed so close() keeps a previewed theme instead of reverting.
    if item then
        state.confirmed = true
    end
    close()
    if item and item.action then
        vim.schedule(item.action)
    elseif item and item.cmd then
        vim.schedule(function()
            vim.cmd(item.cmd)
        end)
    elseif item then
        vim.notify(item.desc .. "  →  press " .. (item.keys or "?"), vim.log.levels.INFO)
    end
end

function M.open()
    state.selected = 1
    state.confirmed = false
    state.orig_colorscheme = vim.g.colors_name

    -- Refresh any categories whose contents are computed at open time.
    for _, cat in ipairs(M.categories) do
        if cat.dynamic then
            cat.items = cat.dynamic()
        end
    end

    local total_w = LEFT_W + GAP + RIGHT_W
    local height = math.max(#M.categories, 12) + 2
    local row = math.floor((vim.o.lines - height) / 2 - 1)
    local col = math.floor((vim.o.columns - total_w) / 2)

    -- Left pane (categories)
    state.cat_buf = vim.api.nvim_create_buf(false, true)
    state.cat_win = vim.api.nvim_open_win(state.cat_buf, true, {
        relative = "editor",
        width = LEFT_W,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Palette ",
        title_pos = "center",
    })

    vim.bo[state.cat_buf].bufhidden = "wipe"

    -- Right pane (actions)
    state.act_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.act_buf].bufhidden = "wipe"
    state.act_win = vim.api.nvim_open_win(state.act_buf, false, {
        relative = "editor",
        width = RIGHT_W,
        height = height,
        row = row,
        col = col + LEFT_W + GAP + 1,
        style = "minimal",
        border = "rounded",
    })

    render_left()
    render_right()

    -- Fire the focused category's on_focus as the cursor moves in the right
    -- pane (used for live theme preview).
    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = state.act_buf,
        callback = function()
            local cat = M.categories[state.selected]
            if not cat.on_focus then
                return
            end
            local line = vim.api.nvim_win_get_cursor(state.act_win)[1]
            local item = state.line_map[line]
            if item then
                cat.on_focus(item)
            end
        end,
    })

    local function map(buf, lhs, fn)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
    end

    -- Left pane: j/k move category, <CR>/l/<Right>/<Tab> jumps into actions.
    local function sync_from_cursor()
        local l = vim.api.nvim_win_get_cursor(state.cat_win)[1]
        state.selected = math.min(math.max(l, 1), #M.categories)
        render_left()
        render_right()
    end
    local function move(dir)
        return function()
            vim.cmd("normal! " .. dir)
            sync_from_cursor()
        end
    end
    map(state.cat_buf, "j", move("j"))
    map(state.cat_buf, "k", move("k"))
    map(state.cat_buf, "<Down>", move("j"))
    map(state.cat_buf, "<Up>", move("k"))
    local function enter_actions()
        vim.api.nvim_set_current_win(state.act_win)
        vim.api.nvim_win_set_cursor(state.act_win, { 3, 0 }) -- first action
    end
    for _, lhs in ipairs({ "<CR>", "l", "<Right>", "<Tab>" }) do
        map(state.cat_buf, lhs, enter_actions)
    end

    -- Right pane: <CR> runs the focused action; h/<Left> goes back to categories.
    map(state.act_buf, "<CR>", function()
        run_action(vim.api.nvim_win_get_cursor(state.act_win)[1])
    end)

    -- `f` toggles the focused project as a favorite (Projects category only),
    -- then rebuilds the list in place so favorites re-sort to the top.
    map(state.act_buf, "f", function()
        local line = vim.api.nvim_win_get_cursor(state.act_win)[1]
        local item = state.line_map[line]
        if not (item and item.project) then
            return
        end
        require("util.favorites").toggle(item.project)
        local cat = M.categories[state.selected]
        if cat.dynamic then
            cat.items = cat.dynamic()
        end
        render_right()
    end)
    for _, lhs in ipairs({ "h", "<Left>", "<S-Tab>" }) do
        map(state.act_buf, lhs, function()
            vim.api.nvim_set_current_win(state.cat_win)
        end)
    end

    -- Close from either pane.
    for _, buf in ipairs({ state.cat_buf, state.act_buf }) do
        map(buf, "<Esc>", close)
        map(buf, "q", close)
    end
end

return M
