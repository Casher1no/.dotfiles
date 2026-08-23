-- The interactive half of the Unity C# namespace refactor (logic lives in
-- util/cs_namespace.lua):
--
--   * an intention in the <leader>ca menu — "Fix namespace → Inheritance.
--     _Core.Utility" — offered on the namespace declaration of a C# file whose
--     namespace disagrees with its folder, and anywhere in a file that
--     declares none at all
--   * F in the explorer (plugins/neo-tree.lua) on a file or a whole folder
--   * :UnityNamespace [path] for the same thing without the tree
--
-- All three funnel into refactor(): resolve the root namespace (prompting once
-- if the project doesn't declare one), plan the edits, show them, apply on
-- <CR>. Nothing is written before that keypress — a namespace rename touches
-- other people's files, so it gets the same "here is what I am about to do"
-- treatment a rename in an IDE gets.

local cs = require("util.cs_namespace")

local M = {}

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO, { title = "Namespace" })
end

-- --------------------------------------------------------- root namespace

-- What to prefill the prompt with: the project folder name, minus anything
-- that can't appear in an identifier ("The Inheritance" -> "TheInheritance").
local function guess_root_ns(root)
    local name = vim.fn.fnamemodify(root, ":t"):gsub("[^%w_]", "")
    return name ~= "" and name or "App"
end

-- Ask for the project's root namespace and remember it, then continue. Called
-- only when Unity's own EditorSettings.asset has nothing to read.
local function prompt_root_ns(root, cb)
    vim.ui.input({
        prompt = "Root namespace for " .. vim.fn.fnamemodify(root, ":t") .. ": ",
        default = cs.get_override(root) or guess_root_ns(root),
    }, function(input)
        local ns = input and vim.trim(input) or ""
        if ns == "" then
            return
        end
        if not ns:match("^[%a_][%w_]*(%.?[%w_]*)*$") or ns:match("%.$") then
            notify("'" .. ns .. "' is not a valid namespace", vim.log.levels.ERROR)
            return
        end
        cs.set_override(root, ns)
        notify("Root namespace set to " .. ns)
        if cb then
            cb(ns)
        end
    end)
end

-- Change the stored root namespace for the current project (palette entry /
-- :UnityNamespaceRoot), then offer to fix whatever no longer matches.
function M.set_root_ns()
    local root = cs.project_root(vim.api.nvim_buf_get_name(0) ~= "" and vim.api.nvim_buf_get_name(0) or vim.uv.cwd())
    if not root then
        notify("Not inside a Unity project", vim.log.levels.WARN)
        return
    end
    prompt_root_ns(root, function()
        M.refactor_path(root .. "/Assets")
    end)
end

-- ---------------------------------------------------------------- preview

local function relative(path, root)
    if root and path:sub(1, #root + 1) == root .. "/" then
        return path:sub(#root + 2)
    end
    return path
end

-- Render the plan as removed/added line pairs grouped by file, and apply it on
-- <CR>. Returns without opening anything when there is nothing to show.
local function preview(plan, on_apply)
    local grouped, order = cs.by_file(plan.edits)
    local lines, highlights = {}, {}
    local function add(text, hl)
        lines[#lines + 1] = text
        if hl then
            highlights[#highlights + 1] = { #lines - 1, hl }
        end
    end
    for i, path in ipairs(order) do
        if i > 1 then
            add("", nil)
        end
        add(" " .. relative(path, plan.root), "Directory")
        for _, e in ipairs(grouped[path]) do
            local at = ("%5d "):format(e.lnum)
            if e.before ~= "" then
                add(at .. "- " .. vim.trim(e.before), "Removed")
                at = ("%5s "):format("")
            end
            add(at .. "+ " .. vim.trim(e.after), "Added")
        end
    end

    local width = 40
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
    end
    width = math.min(width, vim.o.columns - 8)
    local height = math.min(#lines, math.max(6, vim.o.lines - 10))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local ns_id = vim.api.nvim_create_namespace("cs_namespace_preview")
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(buf, ns_id, hl[1], 0, { end_row = hl[1] + 1, hl_group = hl[2] })
    end
    vim.bo[buf].modifiable = false

    local ref_files = #order - #plan.targets
    local title = (" %d file%s, %d edit%s "):format(
        #order,
        #order == 1 and "" or "s",
        #plan.edits,
        #plan.edits == 1 and "" or "s"
    )
    if ref_files > 0 then
        title = (" %d namespace%s + %d referencing file%s, %d edits "):format(
            #plan.targets,
            #plan.targets == 1 and "" or "s",
            ref_files,
            ref_files == 1 and "" or "s",
            #plan.edits
        )
    end

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = title,
        title_pos = "center",
        footer = " ⏎ apply   q cancel ",
        footer_pos = "center",
    })
    vim.wo[win].cursorline = false
    vim.wo[win].wrap = false

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    for _, lhs in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", lhs, close, { buffer = buf, nowait = true, silent = true })
    end
    vim.keymap.set("n", "<CR>", function()
        close()
        on_apply()
    end, { buffer = buf, nowait = true, silent = true })
end

-- ---------------------------------------------------------------- applying

local function apply(plan)
    local files, reformat = cs.apply(plan)
    -- Wrapping a file in a namespace re-indents its whole body; let the server
    -- settle the result where one is attached. Line-level edits keep the
    -- original indentation and need no such pass.
    for _, bufnr in ipairs(reformat) do
        if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/formatting" }) > 0 then
            pcall(vim.lsp.buf.format, { bufnr = bufnr, async = false, timeout_ms = 2000 })
        end
    end
    -- Most of these buffers are not on screen, so the auto-save in
    -- config/autocmds.lua (which follows the cursor) would never reach them.
    for _, path in ipairs(files) do
        local bufnr = vim.fn.bufnr(path)
        if bufnr ~= -1 and vim.bo[bufnr].modified then
            vim.api.nvim_buf_call(bufnr, function()
                vim.cmd("silent! write")
            end)
        end
    end
    local ref_files = #files - #plan.targets
    notify(
        ("Renamed %d namespace%s%s"):format(
            #plan.targets,
            #plan.targets == 1 and "" or "s",
            ref_files > 0 and (", updated references in %d file%s"):format(ref_files, ref_files == 1 and "" or "s")
                or ""
        )
    )
end

-- ----------------------------------------------------------- entry points

-- Fix the namespaces of `paths` (already-correct ones drop out) plus every
-- reference to them. Prompts for the root namespace first when the project
-- doesn't declare one.
function M.refactor(paths)
    if #paths == 0 then
        notify("No C# files to check", vim.log.levels.WARN)
        return
    end
    local root = cs.project_root(paths[1])
    if not root then
        notify("Not inside a Unity project", vim.log.levels.WARN)
        return
    end
    local function proceed()
        local plan, err = cs.plan(paths)
        if not plan then
            notify(err, vim.log.levels.INFO)
            return
        end
        preview(plan, function()
            apply(plan)
        end)
    end
    if cs.root_ns(paths[1]) then
        proceed()
    else
        prompt_root_ns(root, proceed)
    end
end

-- A file or a whole folder, from the explorer or :UnityNamespace.
function M.refactor_path(path)
    path = cs.normalize(vim.fn.fnamemodify(path, ":p"))
    if vim.fn.isdirectory(path) == 1 then
        local found = cs.mismatches_under(path)
        if #found == 0 then
            notify("Every namespace under " .. vim.fn.fnamemodify(path, ":t") .. " already matches its folder")
            return
        end
        M.refactor(found)
    else
        M.refactor({ path })
    end
end

-- --------------------------------------------------- <leader>ca intention

-- Ranked entries for util/actions.lua: they sort into the "Fix" group at the
-- top of the menu, next to the LSP's own quickfixes, rather than into the
-- bottom section with the treesitter intentions.
function M.entries(bufnr)
    if vim.bo[bufnr].filetype ~= "cs" then
        return {}
    end
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == "" or not cs.project_root(path) then
        return {}
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local info = cs.parse(lines)
    -- On the declaration is where Rider offers this; a file with no namespace
    -- has no such line, so there it is offered anywhere.
    if info.ns_lnum and vim.api.nvim_win_get_cursor(0)[1] ~= info.ns_lnum then
        return {}
    end

    local entry = { rank = 1, group_label = "Fix" }
    local want = cs.expected(path)
    if not want then
        -- Root namespace still unknown: offer to set it, then fix.
        entry.label = "Set root namespace…"
        entry.run = M.set_root_ns
        return { entry }
    end
    if info.namespace == want then
        return {}
    end
    entry.label = "Fix namespace → " .. want
    entry.run = function()
        M.refactor({ path })
    end
    return { entry }
end

function M.setup()
    vim.api.nvim_create_user_command("UnityNamespace", function(opts)
        local target = opts.args ~= "" and opts.args or vim.api.nvim_buf_get_name(0)
        if target == "" then
            notify("No file or folder given", vim.log.levels.WARN)
            return
        end
        M.refactor_path(target)
    end, { nargs = "?", complete = "file", desc = "Fix C# namespaces to match folders (file or folder)" })

    vim.api.nvim_create_user_command("UnityNamespaceRoot", function()
        M.set_root_ns()
    end, { desc = "Set this Unity project's root namespace" })
end

return M
