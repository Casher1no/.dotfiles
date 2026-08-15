-- Per-project saved shell commands ("tasks"). Stored as JSON keyed by project
-- directory (cwd), so each project has its own set — e.g. a Java project can
-- have "./gradlew spotlessApply", an Angular one "npm run format".
--
-- Commands run in a Snacks terminal scoped to the project directory.

local M = {}

M.file = vim.fn.stdpath("state") .. "/project_tasks.json"

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
    local f = io.open(M.file, "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

-- The project a task belongs to (current working directory).
function M.key()
    return vim.fn.getcwd()
end

-- List of { name, cmd } tasks for the current project.
function M.list()
    return read_all()[M.key()] or {}
end

function M.add(name, cmd)
    local data = read_all()
    local key = M.key()
    data[key] = data[key] or {}
    table.insert(data[key], { name = name, cmd = cmd })
    write_all(data)
end

function M.remove(index)
    local data = read_all()
    local key = M.key()
    if data[key] then
        table.remove(data[key], index)
        if #data[key] == 0 then
            data[key] = nil
        end
        write_all(data)
    end
end

-- `{}` in a command is a placeholder you fill in at run time, so one saved
-- task covers a whole family of runs:
--
--   g++ -std=c++17 -O2 -Wall -Wextra -g {}.cpp -o sol.exe
--
-- asks for a value once, drops it in, and runs. Several `{}` are asked for in
-- order, and each prompt previews the whole command with the answers so far
-- filled in and the one being typed marked ‹?›, so you can see what you're
-- building.

-- Preview of `cmd` with `values` substituted; the placeholder at index
-- `current` shows as ‹?› and later ones stay literal.
local function preview(cmd, values, current)
    local i = 0
    -- A replacement *function* (not a string) so a value containing % or \
    -- lands verbatim instead of being read as a gsub capture reference.
    return (cmd:gsub("{}", function()
        i = i + 1
        return values[i] or (i == current and "‹?›" or "{}")
    end))
end

local function count_placeholders(cmd)
    local n = 0
    for _ in cmd:gmatch("{}") do
        n = n + 1
    end
    return n
end

-- Ask for each `{}` in turn, then hand the finished command to `done`.
-- Cancelling any prompt (Esc) abandons the whole run.
function M.expand(cmd, done)
    local total = count_placeholders(cmd)
    if total == 0 then
        return done(cmd)
    end

    local values = {}
    local function ask(idx)
        if idx > total then
            return done(preview(cmd, values))
        end
        local label = total == 1 and "Value" or ("Value " .. idx .. "/" .. total)
        vim.ui.input({
            prompt = label .. " — " .. preview(cmd, values, idx) .. ": ",
        }, function(answer)
            if answer == nil then
                return -- Esc: cancel the run, don't half-execute
            end
            values[idx] = answer
            ask(idx + 1)
        end)
    end
    ask(1)
end

-- Recently run commands, per project, newest first. Kept in their *expanded*
-- form — the whole point is re-running the exact thing you ran, placeholder
-- answers included, without being asked again.
--
-- Separate file from the tasks themselves: history churns on every run and
-- tasks are hand-curated, so a corrupt/rolled-back one shouldn't take the
-- other with it.
M.history_file = vim.fn.stdpath("state") .. "/project_task_history.json"
M.history_limit = 5

local function read_history()
    local f = io.open(M.history_file, "r")
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

local function write_history(data)
    local f = io.open(M.history_file, "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

-- Last M.history_limit commands run in this project, newest first.
function M.history()
    return read_history()[M.key()] or {}
end

-- Push a run to the front. Re-running something already in the list moves it
-- up rather than adding a duplicate, so five slots stay five distinct things.
function M.record(name, cmd)
    local data = read_history()
    local key = M.key()
    local list = data[key] or {}
    for i, entry in ipairs(list) do
        if entry.cmd == cmd and entry.name == name then
            table.remove(list, i)
            break
        end
    end
    table.insert(list, 1, { name = name, cmd = cmd })
    while #list > M.history_limit do
        table.remove(list)
    end
    data[key] = list
    write_history(data)
end

-- auto_close=false: snacks otherwise closes the window the moment the command
-- exits 0, so anything a short run printed is gone before you can read it.
-- util/terminal.lua turns the finished terminal into one you dismiss with
-- Enter (or q / Esc).
local function launch(cmd)
    require("snacks").terminal(cmd, { cwd = M.key(), auto_close = false })
end

-- Run a task in a Snacks terminal opened in the project directory, asking for
-- any `{}` placeholders first.
function M.run(task)
    M.expand(task.cmd, function(cmd)
        M.record(task.name, cmd)
        launch(cmd)
    end)
end

-- Re-run a history entry verbatim — it's already expanded, so no prompting.
function M.run_recent(entry)
    M.record(entry.name, entry.cmd)
    launch(entry.cmd)
end

-- Prompt for a name + command and save it to the current project.
function M.add_interactive(on_done)
    vim.ui.input({ prompt = "Task name: " }, function(name)
        if not name or name == "" then
            return
        end
        vim.ui.input({ prompt = "Shell command: " }, function(cmd)
            if not cmd or cmd == "" then
                return
            end
            M.add(name, cmd)
            vim.notify("Added task: " .. name, vim.log.levels.INFO)
            if on_done then
                on_done()
            end
        end)
    end)
end

-- Pick a saved task and remove it.
function M.remove_interactive(on_done)
    local list = M.list()
    if #list == 0 then
        vim.notify("No tasks for this project", vim.log.levels.WARN)
        return
    end
    vim.ui.select(list, {
        prompt = "Remove which task?",
        format_item = function(t)
            return t.name .. "  —  " .. t.cmd
        end,
    }, function(choice, idx)
        if idx then
            M.remove(idx)
            vim.notify("Removed task: " .. choice.name, vim.log.levels.INFO)
            if on_done then
                on_done()
            end
        end
    end)
end

-- Pick a saved task and run it. Saved tasks first, then the recent runs under
-- a "History" divider — those are already expanded, so picking one re-runs it
-- verbatim instead of asking for its `{}` values again.
function M.run_interactive()
    local list = M.list()
    local recent = M.history()
    if #list == 0 and #recent == 0 then
        vim.notify("No tasks for this project — add one via the palette", vim.log.levels.WARN)
        return
    end

    local entries = {}
    for _, t in ipairs(list) do
        entries[#entries + 1] = { kind = "task", task = t }
    end
    if #recent > 0 then
        entries[#entries + 1] = { kind = "divider" }
        for _, e in ipairs(recent) do
            entries[#entries + 1] = { kind = "recent", task = e }
        end
    end

    vim.ui.select(entries, {
        prompt = "Run task:",
        format_item = function(entry)
            if entry.kind == "divider" then
                return "───────────────  History  ───────────────"
            end
            return entry.task.name .. "  —  " .. entry.task.cmd
        end,
    }, function(choice)
        -- vim.ui.select has no notion of an unselectable row, so the divider
        -- is a real item that simply does nothing when picked.
        if not choice or choice.kind == "divider" then
            return
        end
        if choice.kind == "recent" then
            M.run_recent(choice.task)
        else
            M.run(choice.task)
        end
    end)
end

return M
