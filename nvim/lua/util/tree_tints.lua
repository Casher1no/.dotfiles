-- Full-width row tints for special folders in neo-tree (JetBrains style):
-- package/library roots and everything inside them get a gray background,
-- test roots and their contents a light green one.
--
-- Why a decoration provider: neo-tree components can only highlight the
-- label text, and persistent extmarks are destroyed by neo-tree rewriting
-- the buffer on every re-render — many of which (expand/collapse of loaded
-- dirs, git/diagnostic updates, window resize) fire no event to repaint
-- from. Ephemeral marks recomputed at redraw time can't be wiped.
--
-- Why hl_group ranges and not line_hl_group: the renderer silently ignores
-- ephemeral line_hl_group marks (neovim/neovim#32936), so each row is
-- painted as a (row,0)..(row+1,0) range with hl_eol=true, which covers the
-- indent, the text, and the blank space out to the window edge.
local M = {}

local ns = vim.api.nvim_create_namespace("tree_tints")

-- Dependency/package folders (also used by neo-tree.lua to gray out their
-- contents' text, matching gitignored files).
M.package_dirs = {
    node_modules = true,
    vendor = true,
    [".venv"] = true,
    venv = true,
    __pycache__ = true,
}

-- Test folders ("test source roots").
M.test_dirs = {
    test = true,
    tests = true,
    Test = true,
    Tests = true,
    spec = true,
    specs = true,
    __tests__ = true,
}

-- Colocated test files. React (and Go, and pytest) put the test next to the
-- code it covers — Button.tsx / Button.test.tsx — so no path segment is ever
-- a test folder and the folder rules above can't see them. Lua patterns,
-- matched against the file name only.
M.test_file_patterns = {
    "%.test%.%w+$", -- Button.test.tsx, api.test.js
    "%.spec%.%w+$", -- Button.spec.ts, app.component.spec.ts
    "%.cy%.%w+$", -- Button.cy.tsx (cypress)
    "%.e2e%-spec%.%w+$", -- app.e2e-spec.ts (nest)
    "^test_.+%.py$", -- test_user.py (pytest default)
    "_test%.py$",
    "_test%.go$", -- user_test.go
    "Test%.php$", -- UserTest.php (phpunit)
    "Tests?%.cs$", -- UserTests.cs
}

-- Public: exposed so the patterns above can be reused/tested directly.
function M.is_test_file(name)
    for _, pattern in ipairs(M.test_file_patterns) do
        if name:match(pattern) then
            return true
        end
    end
    return false
end

local tint_groups = {
    package = "NeoTreePackageTint",
    test = "NeoTreeTestTint",
}

-- bg-only so icon/name colors and the dimmed package text show through the
-- tint. Re-applied on ColorScheme since themes clear unknown groups (same
-- as the pinned mini.icons colors).
local highlights = {
    NeoTreePackageTint = { bg = "#313244" },
    NeoTreeTestTint = { bg = "#2e3d32" },
}
local function pin_highlights()
    for group, hl in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, hl)
    end
end
pin_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("tree_tints", { clear = true }),
    callback = pin_highlights,
})

-- Which tint (if any) applies to a path. Only segments below the tree root
-- count, so a project itself named "tests" doesn't tint everything. The
-- outermost matching folder wins (a vendor dir inside tests stays gray).
-- Public: util/telescope_tints.lua reuses it for picker rows.
function M.classify(path, root)
    if root and path:sub(1, #root) == root then
        path = path:sub(#root + 1)
    end
    local name
    for segment in path:gmatch("[^/\\]+") do
        if M.package_dirs[segment] then
            return "package"
        end
        if M.test_dirs[segment] then
            return "test"
        end
        name = segment
    end
    -- Only after the loop, so a colocated test inside node_modules stays
    -- gray rather than flipping to green.
    if name and M.is_test_file(name) then
        return "test"
    end
end

-- Neo-tree state per tree buffer, so rows can be mapped to nodes.
local states = {}
-- Per-buffer { tick = changedtick, [lnum] = hl group } cache. Rebuilt only
-- when the buffer content changes (every neo-tree render rewrites the
-- buffer, bumping the tick — including the render paths that fire no
-- event). Keeps the per-frame callbacks cheap and deterministic; plugins
-- like noice and smear-cursor force full redraws constantly.
local tints = {}
-- Cursor line per window, so the tint can yield to CursorLine (a bg-only
-- CursorLine loses to any extmark range bg regardless of priority).
local cursor_row = {}

-- after_render handler: remember (or refresh) the state for this buffer.
-- after_render is fired via vim.schedule, one tick AFTER the buffer was
-- written — the first frame may already be on screen untinted, and Neovim
-- never repaints lines it considers unchanged. Force one full repaint.
function M.register(state)
    if not state.bufnr then
        return
    end
    states[state.bufnr] = state
    pcall(vim.api.nvim__redraw, { buf = state.bufnr, valid = false, flush = false })
end

vim.api.nvim_set_decoration_provider(ns, {
    on_win = function(_, winid, bufnr)
        local state = states[bufnr]
        if not state then
            return false
        end
        -- Neo-tree deletes its buffer on close and Neovim can reuse the
        -- number; a state whose bufnr moved on is dead — drop it.
        if state.bufnr ~= bufnr or not state.tree then
            states[bufnr] = nil
            tints[bufnr] = nil
            return false
        end
        local tick = vim.api.nvim_buf_get_changedtick(bufnr)
        local rows = tints[bufnr]
        if not rows or rows.tick ~= tick then
            rows = { tick = tick }
            for lnum = 1, vim.api.nvim_buf_line_count(bufnr) do
                local ok, node = pcall(state.tree.get_node, state.tree, lnum)
                if ok and node and node.path then
                    local kind = M.classify(node.path, state.path)
                    if kind then
                        rows[lnum] = tint_groups[kind]
                    end
                end
            end
            tints[bufnr] = rows
        end
        -- Skipping the cursor row keeps CursorLine visible there; moving
        -- the cursor redraws both the old and new cursor lines, so the
        -- tint reappears as soon as the cursor leaves. Only needed (and
        -- only safe) when cursorline is actually drawn in this window.
        cursor_row[winid] = vim.wo[winid].cursorline and vim.api.nvim_win_get_cursor(winid)[1] or nil
        return true
    end,
    on_line = function(_, winid, bufnr, row)
        local rows = tints[bufnr]
        local group = rows and rows[row + 1]
        if group and row + 1 ~= cursor_row[winid] then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                ephemeral = true,
                end_row = row + 1,
                end_col = 0,
                hl_group = group,
                hl_eol = true,
                priority = 10,
            })
        end
    end,
})

return M
