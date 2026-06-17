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

-- Run a task in a Snacks terminal opened in the project directory.
function M.run(task)
    require("snacks").terminal(task.cmd, { cwd = M.key() })
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

-- Pick a saved task and run it.
function M.run_interactive()
    local list = M.list()
    if #list == 0 then
        vim.notify("No tasks for this project — add one via the palette", vim.log.levels.WARN)
        return
    end
    vim.ui.select(list, {
        prompt = "Run task:",
        format_item = function(t)
            return t.name .. "  —  " .. t.cmd
        end,
    }, function(choice)
        if choice then
            M.run(choice)
        end
    end)
end

return M
