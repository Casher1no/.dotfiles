-- A small centered command palette for the keymaps defined by plugins in this
-- config. A search bar on top of two panes: categories on the left, that
-- category's actions (with the keys to press) on the right. The search bar
-- has focus when the palette opens — typing live-filters every action across
-- all categories; ↑/↓ move (wrapping top ↔ bottom), <CR> runs the focused
-- action and closes, <Esc> clears the query and then closes.
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
        name = "Claude Code",
        icon = "",
        items = {
            {
                desc = "Toggle Claude Code (left panel)",
                keys = "<leader>cc",
                action = function()
                    require("util.ai.claude").toggle()
                end,
            },
            {
                desc = "Add current file to prompt",
                keys = "<leader>cf",
                action = function()
                    require("util.ai.claude").add_file()
                end,
            },
            { desc = "Add selection / line to prompt", keys = "<leader>cl" },
        },
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
            { desc = "Go to definition (on def: references)", keys = "gd" },
            { desc = "Class usages / definition (styles)", keys = "gd / gr" },
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
            {
                desc = "Format file",
                keys = "<leader>fc",
                action = function()
                    require("util.format").format()
                end,
            },
            { desc = "Hover docs / error (K again: docs)", keys = "K" },
            { desc = "Scroll docs popup (when open)", keys = "<S-Down> / <S-Up>" },
            { desc = "Scroll popup sideways", keys = "<S-Left> / <S-Right>" },
            { desc = "Code action", keys = "<leader>ca" },
            { desc = "Rename symbol", keys = "F2 / <leader>rn" },
        },
    },
    {
        name = "Diagnostics",
        icon = "",
        -- Trouble panels (see plugins/trouble.lua). Toggles close the panel
        -- if it's already open.
        items = {
            { desc = "Diagnostics (project)", keys = "<leader>xx", cmd = "Trouble diagnostics toggle" },
            { desc = "Diagnostics (this file)", keys = "<leader>xX", cmd = "Trouble diagnostics toggle filter.buf=0" },
            { desc = "Document symbols panel", keys = "<leader>xs", cmd = "Trouble symbols toggle focus=false" },
            {
                desc = "References / definitions panel",
                keys = "<leader>xr",
                cmd = "Trouble lsp toggle focus=false win.position=right",
            },
            { desc = "Quickfix list panel", keys = "<leader>xq", cmd = "Trouble qflist toggle" },
            { desc = "TODO comments panel", keys = "<leader>xt", cmd = "Trouble todo toggle" },
        },
    },
    {
        name = "Tests",
        icon = "",
        -- Neotest (see plugins/neotest.lua). "Nearest" = the test the cursor
        -- is in, so run those from the buffer rather than from here.
        items = {
            { desc = "Run nearest test", keys = "<leader>tt", action = function() require("neotest").run.run() end },
            {
                desc = "Run current file",
                keys = "<leader>tf",
                action = function()
                    require("neotest").run.run(vim.fn.expand("%"))
                end,
            },
            {
                desc = "Debug nearest test",
                keys = "<leader>tD",
                action = function()
                    require("neotest").run.run({ strategy = "dap" })
                end,
            },
            { desc = "Stop running tests", keys = "<leader>tS", action = function() require("neotest").run.stop() end },
            {
                desc = "Toggle summary tree",
                keys = "<leader>ts",
                action = function()
                    require("neotest").summary.toggle()
                end,
            },
            {
                desc = "Show test output",
                keys = "<leader>to",
                action = function()
                    require("neotest").output.open({ enter = true, auto_close = true })
                end,
            },
            {
                desc = "Toggle output panel",
                keys = "<leader>tO",
                action = function()
                    require("neotest").output_panel.toggle()
                end,
            },
            { desc = "Next failed test", keys = "]f" },
            { desc = "Previous failed test", keys = "[f" },
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
            { desc = "Clear search highlight", keys = "<Esc>" },
            { desc = "Hover docs / error on line", keys = "K" },
            { desc = "Scroll docs popup (when open)", keys = "<S-Down> / <S-Up>" },
            { desc = "Scroll popup sideways", keys = "<S-Left> / <S-Right>" },
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
    search_win = nil,
    search_buf = nil,
    query = "", -- current search bar text ("" = browse mode)
    results = {}, -- flattened { item = ..., ci = category index } matches
    result_idx = 1, -- selected entry in `results`
    orig_colorscheme = nil, -- restored if a theme preview isn't confirmed
    confirmed = false, -- set when an action is run via <CR>
}

local LEFT_W = 24
local RIGHT_W = 48
local GAP = 1
local SEARCH_NS = vim.api.nvim_create_namespace("palette_search")

local function close()
    -- Leave insert mode before the windows go away, so it doesn't leak into
    -- whatever buffer regains focus.
    vim.cmd("stopinsert")
    -- Undo a live theme preview unless the user actually selected one.
    if not state.confirmed and state.orig_colorscheme and vim.g.colors_name ~= state.orig_colorscheme then
        pcall(vim.cmd.colorscheme, state.orig_colorscheme)
    end
    for _, w in ipairs({ state.act_win, state.cat_win, state.search_win }) do
        if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
        end
    end
    state.cat_win, state.act_win, state.search_win = nil, nil, nil
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

-- Browse mode: the selected category's actions.
local function render_browse()
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
            -- a runnable item — no keys column, blank line above for spacing
            -- (skipped for the first section, which already sits under the
            -- header's blank line).
            if #lines > 2 then
                table.insert(lines, "")
            end
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

-- Recompute state.results for the current query. An item matches when every
-- whitespace-separated word of the query appears (case-insensitive) somewhere
-- in its description, keys or category name. Section titles are skipped.
local function update_search()
    local words = {}
    for w in state.query:lower():gmatch("%S+") do
        words[#words + 1] = w
    end
    state.results = {}
    for ci, cat in ipairs(M.categories) do
        for _, item in ipairs(cat.items) do
            if not item.section then
                local hay = (item.desc .. " " .. (item.keys or "") .. " " .. cat.name):lower()
                local ok = true
                for _, w in ipairs(words) do
                    if not hay:find(w, 1, true) then
                        ok = false
                        break
                    end
                end
                if ok then
                    state.results[#state.results + 1] = { item = item, ci = ci }
                end
            end
        end
    end
    state.result_idx = 1
end

-- Search mode: flattened matches across all categories. The left pane
-- follows along, marking the category the selected match comes from.
local function render_search()
    if #state.results > 0 then
        state.selected = state.results[state.result_idx].ci
    end
    render_left()
    local n = #state.results
    local lines = { "  " .. n .. (n == 1 and " match" or " matches"), "" }
    local line_map = {}
    for i, r in ipairs(state.results) do
        local marker = (i == state.result_idx) and "▶ " or "  "
        local keys = r.item.keys or ""
        local pad = RIGHT_W - 4 - #r.item.desc - #keys
        if pad < 1 then
            pad = 1
        end
        lines[#lines + 1] = marker .. r.item.desc .. string.rep(" ", pad) .. keys
        line_map[#lines] = r.item
    end
    if n == 0 then
        lines[#lines + 1] = "  (no matches)"
    end
    state.line_map = line_map
    vim.bo[state.act_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.act_buf, 0, -1, false, lines)
    vim.bo[state.act_buf].modifiable = false
end

local function render_right()
    if state.query ~= "" then
        render_search()
    else
        render_browse()
    end
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

-- Re-render the currently selected category in place (if the palette is
-- open) — used by async producers like the AI section's model fetch.
function M.refresh()
    if not (state.act_win and vim.api.nvim_win_is_valid(state.act_win)) then
        return
    end
    local cat = M.categories[state.selected]
    if cat.dynamic then
        cat.items = cat.dynamic()
    end
    if state.query ~= "" then
        update_search()
    end
    render_right()
end

function M.open(category)
    state.selected = 1
    if category then
        for i, cat in ipairs(M.categories) do
            if cat.name == category then
                state.selected = i
            end
        end
    end
    state.confirmed = false
    state.orig_colorscheme = vim.g.colors_name
    state.query = ""
    state.results = {}
    state.result_idx = 1

    -- Refresh any categories whose contents are computed at open time.
    for _, cat in ipairs(M.categories) do
        if cat.dynamic then
            cat.items = cat.dynamic()
        end
    end

    local total_w = LEFT_W + GAP + RIGHT_W
    local height = math.max(#M.categories, 12) + 2
    -- +3 rows for the search bar (1 content + 2 border) above the panes.
    local row = math.floor((vim.o.lines - height - 3) / 2 - 1)
    local col = math.floor((vim.o.columns - total_w) / 2)

    -- Left pane (categories)
    state.cat_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.cat_buf].bufhidden = "wipe"
    state.cat_win = vim.api.nvim_open_win(state.cat_buf, false, {
        relative = "editor",
        width = LEFT_W,
        height = height,
        row = row + 3,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Palette ",
        title_pos = "center",
    })

    -- Right pane (actions / search results)
    state.act_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.act_buf].bufhidden = "wipe"
    state.act_win = vim.api.nvim_open_win(state.act_buf, false, {
        relative = "editor",
        width = RIGHT_W,
        height = height,
        row = row + 3,
        col = col + LEFT_W + GAP + 1,
        style = "minimal",
        border = "rounded",
    })

    -- Search bar spanning both panes. It takes focus in insert mode, so
    -- typing starts filtering immediately.
    state.search_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.search_buf].bufhidden = "wipe"
    -- Keep blink.cmp's completion menu out of the search bar — its Enter/Esc
    -- mappings would swallow ours while the menu is open. blink's default
    -- `enabled` check respects this per-buffer flag.
    vim.b[state.search_buf].completion = false
    state.search_win = vim.api.nvim_open_win(state.search_buf, true, {
        relative = "editor",
        width = total_w + 1,
        height = 1,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Search ",
        title_pos = "center",
    })

    render_left()
    render_right()
    pcall(vim.api.nvim_win_set_cursor, state.cat_win, { state.selected, 0 })

    -- Grey hint text while the search bar is empty.
    local function update_hint()
        vim.api.nvim_buf_clear_namespace(state.search_buf, SEARCH_NS, 0, -1)
        if state.query == "" then
            vim.api.nvim_buf_set_extmark(state.search_buf, SEARCH_NS, 0, 0, {
                virt_text = { { "type to filter — ↑/↓ move, ⏎ run", "Comment" } },
                virt_text_pos = "overlay",
            })
        end
    end
    update_hint()
    vim.cmd("startinsert")

    -- Live filter: any edit to the search bar re-renders the right pane.
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = state.search_buf,
        callback = function()
            local text = vim.api.nvim_buf_get_lines(state.search_buf, 0, 1, false)[1] or ""
            local q = vim.trim(text)
            if q == state.query then
                return
            end
            state.query = q
            update_hint()
            if q ~= "" then
                update_search()
            end
            render_left()
            render_right()
        end,
    })

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
    local function imap(lhs, fn)
        vim.keymap.set("i", lhs, fn, { buffer = state.search_buf, nowait = true, silent = true })
    end

    -- Category selection with wrap-around: up on the first wraps to the last
    -- and down on the last wraps back to the first.
    local function select_category(delta)
        local n = #M.categories
        state.selected = ((state.selected - 1 + delta) % n) + 1
        pcall(vim.api.nvim_win_set_cursor, state.cat_win, { state.selected, 0 })
        render_left()
        render_right()
    end

    -- Left pane: j/k move category (wrapping), <CR>/l/<Right>/<Tab> jumps
    -- into actions.
    map(state.cat_buf, "j", function() select_category(1) end)
    map(state.cat_buf, "k", function() select_category(-1) end)
    map(state.cat_buf, "<Down>", function() select_category(1) end)
    map(state.cat_buf, "<Up>", function() select_category(-1) end)
    local function enter_actions()
        vim.cmd("stopinsert")
        vim.api.nvim_set_current_win(state.act_win)
        pcall(vim.api.nvim_win_set_cursor, state.act_win, { 3, 0 }) -- first action
    end
    for _, lhs in ipairs({ "<CR>", "l", "<Right>", "<Tab>" }) do
        map(state.cat_buf, lhs, enter_actions)
    end

    -- Right pane: line-wise movement with wrap-around. Lines 1-2 are the
    -- header, so wrapping lands on line 3 (the first entry).
    local function act_move(delta)
        return function()
            local last = vim.api.nvim_buf_line_count(state.act_buf)
            local cur = vim.api.nvim_win_get_cursor(state.act_win)[1]
            local nxt = cur + delta
            if nxt > last then
                nxt = 3
            elseif nxt < 3 then
                nxt = last
            end
            pcall(vim.api.nvim_win_set_cursor, state.act_win, { math.min(nxt, last), 0 })
        end
    end
    map(state.act_buf, "j", act_move(1))
    map(state.act_buf, "k", act_move(-1))
    map(state.act_buf, "<Down>", act_move(1))
    map(state.act_buf, "<Up>", act_move(-1))

    -- <CR> runs the focused action; h/<Left> goes back to categories.
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

    -- Search bar: ↑/↓ move through categories (empty query) or matches, both
    -- wrapping; <CR> runs the selected match; <Tab> moves focus to the panes;
    -- <Esc> clears the query first, then closes.
    local function search_nav(delta)
        if state.query == "" then
            select_category(delta)
        elseif #state.results > 0 then
            local n = #state.results
            state.result_idx = ((state.result_idx - 1 + delta) % n) + 1
            render_right()
        end
    end
    imap("<Down>", function() search_nav(1) end)
    imap("<Up>", function() search_nav(-1) end)
    imap("<CR>", function()
        if state.query == "" then
            enter_actions()
        elseif #state.results > 0 then
            run_action(state.result_idx + 2) -- +2: header rows in the results pane
        end
    end)
    imap("<Tab>", function()
        vim.cmd("stopinsert")
        if state.query == "" then
            vim.api.nvim_set_current_win(state.cat_win)
        else
            vim.api.nvim_set_current_win(state.act_win)
            pcall(vim.api.nvim_win_set_cursor, state.act_win, { state.result_idx + 2, 0 })
        end
    end)
    imap("<Esc>", function()
        if state.query == "" then
            close()
        else
            -- First <Esc> clears the query; the guard in the TextChanged
            -- autocmd keeps this from double-rendering.
            state.query = ""
            vim.api.nvim_buf_set_lines(state.search_buf, 0, -1, false, { "" })
            update_hint()
            render_left()
            render_right()
        end
    end)
    map(state.search_buf, "<Esc>", close)
    map(state.search_buf, "q", close)
    map(state.search_buf, "i", function()
        vim.cmd("startinsert!")
    end)

    -- From the panes, `/` or `i` returns to the search bar; <Esc>/q close.
    local function focus_search()
        vim.api.nvim_set_current_win(state.search_win)
        vim.cmd("startinsert!")
    end
    for _, buf in ipairs({ state.cat_buf, state.act_buf }) do
        map(buf, "/", focus_search)
        map(buf, "i", focus_search)
        map(buf, "<Esc>", close)
        map(buf, "q", close)
    end
end

return M
