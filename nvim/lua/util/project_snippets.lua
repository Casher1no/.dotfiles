-- Custom snippets — not tied to any one language or framework (Unity C#,
-- Angular, Laravel, whatever). Stored inside this dotfiles repo (not
-- stdpath("state")) so they travel with `git pull` on any machine.
--
-- Two scopes:
--   - project snippets: keyed by the project's folder name (not absolute
--     path, since that differs per machine), only show up in that project.
--   - global snippets: stored under GLOBAL_KEY, show up in every project.
--
-- Each snippet also has an optional `ext` (file extension without the dot,
-- e.g. "cs", "ts", "php"). Blank/omitted means it shows in every file
-- (within whichever scope it belongs to) — e.g. a global "td" -> "TODO: "
-- snippet with no ext at all.
--
-- Surfaced in completion via util/project_blink_source.lua, and managed
-- (add/edit/remove) from the command palette — see util/palette.lua.

local M = {}

M.file = vim.fn.stdpath("config") .. "/data/project-snippets.json"
M.GLOBAL_KEY = "*"

local function read_all()
    local f = io.open(M.file, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    if content == "" then
        return {}
    end
    local ok, data = pcall(vim.json.decode, content)
    return (ok and type(data) == "table") and data or {}
end

local function write_all(data)
    vim.fn.mkdir(vim.fs.dirname(M.file), "p")
    -- Hand-rolled pretty printer (vim.json.encode is single-line) so the
    -- saved file stays readable and diffs cleanly in git.
    local out = { "{" }
    local scope_names = {}
    for name in pairs(data) do
        table.insert(scope_names, name)
    end
    table.sort(scope_names)
    for pi, scope in ipairs(scope_names) do
        table.insert(out, ('  %s: ['):format(vim.json.encode(scope)))
        local entries = data[scope]
        for ei, entry in ipairs(entries) do
            table.insert(out, "    {")
            table.insert(out, ('      "name": %s,'):format(vim.json.encode(entry.name)))
            table.insert(out, ('      "prefix": %s,'):format(vim.json.encode(entry.prefix)))
            table.insert(out, ('      "ext": %s,'):format(vim.json.encode(entry.ext or "")))
            local body_json = {}
            for _, line in ipairs(entry.body) do
                table.insert(body_json, vim.json.encode(line))
            end
            table.insert(out, ('      "body": [%s]'):format(table.concat(body_json, ", ")))
            table.insert(out, "    }" .. (ei < #entries and "," or ""))
        end
        table.insert(out, "  ]" .. (pi < #scope_names and "," or ""))
    end
    table.insert(out, "}")

    local f = io.open(M.file, "w")
    if f then
        f:write(table.concat(out, "\n") .. "\n")
        f:close()
    end
end

-- The project scope for the current buffer: the current working directory's
-- folder name (whatever kind of project it is).
function M.key()
    local cwd = vim.fn.getcwd()
    if cwd == "" then
        return nil
    end
    return vim.fs.basename(cwd)
end

-- Merged array of { name, prefix, ext, body, scope, index } — global
-- snippets first, then this project's. scope/index identify where an entry
-- lives so edit/remove can write back to the right place.
function M.list()
    local data = read_all()
    local items = {}
    for i, e in ipairs(data[M.GLOBAL_KEY] or {}) do
        items[#items + 1] = vim.tbl_extend("force", {}, e, { scope = M.GLOBAL_KEY, index = i })
    end
    local key = M.key()
    if key then
        for i, e in ipairs(data[key] or {}) do
            items[#items + 1] = vim.tbl_extend("force", {}, e, { scope = key, index = i })
        end
    end
    return items
end

-- M.list(), filtered to entries with no ext (shown everywhere) or matching
-- the given extension.
function M.list_for_ext(ext)
    local items = {}
    for _, entry in ipairs(M.list()) do
        if not entry.ext or entry.ext == "" or entry.ext == ext then
            items[#items + 1] = entry
        end
    end
    return items
end

function M.add(scope, name, prefix, ext, body)
    local data = read_all()
    data[scope] = data[scope] or {}
    table.insert(data[scope], { name = name, prefix = prefix, ext = ext, body = body })
    write_all(data)
end

function M.update(scope, index, name, prefix, ext, body)
    local data = read_all()
    if data[scope] and data[scope][index] then
        data[scope][index] = { name = name, prefix = prefix, ext = ext, body = body }
        write_all(data)
    end
end

function M.remove(scope, index)
    local data = read_all()
    if data[scope] then
        table.remove(data[scope], index)
        if #data[scope] == 0 then
            data[scope] = nil
        end
        write_all(data)
    end
end

-- Open a scratch floating buffer to edit a snippet body (multi-line).
-- Saving with <C-S> calls on_save(lines) with the edited body and closes
-- the window; <Esc> cancels without saving.
local function edit_body_buffer(title, initial_lines, filetype, on_save)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    if filetype and filetype ~= "" then
        vim.bo[buf].filetype = filetype
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)

    local width = math.floor(vim.o.columns * 0.5)
    local height = math.max(#initial_lines + 2, 8)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2 - 1),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " " .. title .. " — save with <C-S>, cancel with <Esc> ",
        title_pos = "center",
    })

    -- Bound directly (not via :w/BufWriteCmd): the global <C-S> insert-mode
    -- mapping expands to "<Esc>:w<CR>", and a plain buffer-local <Esc> cancel
    -- keymap would intercept that synthesized <Esc> and close the window
    -- before ":w" ever ran. Handling the save inline sidesteps that clash.
    local function save()
        if vim.fn.mode() == "i" then
            vim.cmd("stopinsert")
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        on_save(lines)
    end
    vim.keymap.set({ "n", "i" }, "<C-S>", save, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
end

-- Prompt for a name, optional distinct trigger prefix, and optional file
-- extension (blank = all files), then open the body editor, then save as a
-- new snippet under the given scope (a project key or M.GLOBAL_KEY).
local function add_interactive(scope, label, on_done)
    vim.ui.input({ prompt = "Snippet name: " }, function(name)
        if not name or name == "" then
            return
        end
        vim.ui.input({ prompt = "Trigger prefix (blank = " .. name .. "): " }, function(prefix)
            prefix = (prefix and prefix ~= "") and prefix or name
            vim.ui.input({ prompt = "File extension, no dot (blank = all files): " }, function(ext)
                ext = ext or ""
                edit_body_buffer("New " .. label .. ": " .. name, { "" }, ext, function(lines)
                    M.add(scope, name, prefix, ext, lines)
                    vim.notify("Added " .. label .. " snippet: " .. name, vim.log.levels.INFO)
                    if on_done then
                        on_done()
                    end
                end)
            end)
        end)
    end)
end

function M.add_project_interactive(on_done)
    local key = M.key()
    if not key then
        vim.notify("No project (empty cwd)", vim.log.levels.WARN)
        return
    end
    add_interactive(key, "project", on_done)
end

function M.add_global_interactive(on_done)
    add_interactive(M.GLOBAL_KEY, "global", on_done)
end

local function format_entry(e)
    local scope_label = (e.scope == M.GLOBAL_KEY) and "global" or e.scope
    return e.name .. "  (" .. e.prefix .. (e.ext ~= "" and (", ." .. e.ext) or ", all files") .. ", " .. scope_label .. ")"
end

function M.edit_interactive(on_done)
    local list = M.list()
    if #list == 0 then
        vim.notify("No custom snippets (project or global)", vim.log.levels.WARN)
        return
    end
    vim.ui.select(list, {
        prompt = "Edit which snippet?",
        format_item = format_entry,
    }, function(choice)
        if not choice then
            return
        end
        edit_body_buffer("Edit: " .. choice.name, choice.body, choice.ext, function(lines)
            M.update(choice.scope, choice.index, choice.name, choice.prefix, choice.ext, lines)
            vim.notify("Updated snippet: " .. choice.name, vim.log.levels.INFO)
            if on_done then
                on_done()
            end
        end)
    end)
end

function M.remove_interactive(on_done)
    local list = M.list()
    if #list == 0 then
        vim.notify("No custom snippets (project or global)", vim.log.levels.WARN)
        return
    end
    vim.ui.select(list, {
        prompt = "Remove which snippet?",
        format_item = format_entry,
    }, function(choice)
        if choice then
            M.remove(choice.scope, choice.index)
            vim.notify("Removed snippet: " .. choice.name, vim.log.levels.INFO)
            if on_done then
                on_done()
            end
        end
    end)
end

return M
