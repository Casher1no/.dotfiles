-- Filesystem operations that every OS spells differently, in one place so the
-- callers (currently plugins/neo-tree.lua) stay platform-agnostic — and so
-- they can be tested headlessly, which a local inside a plugin spec cannot.
--
-- See CLAUDE.md: the rule is that a feature works on Windows, macOS and Linux
-- or it isn't finished. Both functions here replaced macOS-only code that did
-- nothing at all on the other two.
local M = {}

local uv = vim.uv or vim.loop

local is_win = vim.fn.has("win32") == 1
local is_mac = vim.fn.has("mac") == 1

-- The argv for revealing `path` in the OS file manager, or nil when this
-- platform has no way to highlight a specific file. Split out from reveal()
-- so the command construction is testable without spawning a file manager.
---@return string[]|nil
function M.reveal_cmd(path)
    if is_win then
        -- explorer.exe wants backslashes, and /select, takes its argument
        -- glued straight onto the comma (no space, no second argument).
        return { "explorer.exe", "/select," .. path:gsub("/", "\\") }
    end
    if is_mac then
        return { "open", "-R", path }
    end
    -- Linux/BSD have no single answer. This is the freedesktop interface that
    -- Nautilus, Dolphin, Nemo and Thunar all implement; --reply-timeout keeps
    -- a desktop without it from sitting out dbus-send's 25s default.
    if vim.fn.executable("dbus-send") == 1 then
        return {
            "dbus-send",
            "--session",
            "--type=method_call",
            "--reply-timeout=1000",
            "--dest=org.freedesktop.FileManager1",
            "/org/freedesktop/FileManager1",
            "org.freedesktop.FileManager1.ShowItems",
            "array:string:" .. vim.uri_from_fname(path),
            "string:",
        }
    end
    return nil
end

-- Reveal `path` in the OS file manager with the file itself selected.
-- Returns false when this platform can't, so the caller can fall back to
-- opening the containing folder.
function M.reveal(path)
    local cmd = M.reveal_cmd(path)
    if not cmd then
        return false
    end
    if cmd[1] == "dbus-send" then
        -- Only this one reports whether it worked; a desktop with no
        -- FileManager1 on the bus should fall back to opening the folder.
        local ok, res = pcall(function()
            return vim.system(cmd):wait(2000)
        end)
        return ok and res ~= nil and res.code == 0
    end
    -- explorer.exe exits 1 even on success, and `open -R` is fire-and-forget,
    -- so neither exit code carries information worth waiting for.
    pcall(vim.system, cmd)
    return true
end

-- Recursive copy through libuv. cp(1) does not exist on Windows and the
-- native equivalents (robocopy, xcopy) disagree on argument shape and return
-- non-zero on success, so there is no portable command to shell out to.
---@return boolean ok, string? err
function M.copy(src, dst)
    -- lstat, not stat: a symlink should be recreated as a link rather than
    -- silently expanded into a copy of whatever it points at.
    local st = uv.fs_lstat(src)
    if not st then
        return false, src .. ": not found"
    end

    if st.type == "link" then
        local target = uv.fs_readlink(src)
        if not target then
            return false, src .. ": unreadable link"
        end
        local ok, err = uv.fs_symlink(target, dst)
        return ok == true, err
    end

    if st.type ~= "directory" then
        local ok, err = uv.fs_copyfile(src, dst)
        return ok == true, err
    end

    if not uv.fs_stat(dst) then
        local ok, err = uv.fs_mkdir(dst, st.mode)
        if not ok then
            return false, err
        end
    end

    local dir, oerr = uv.fs_opendir(src, nil, 64)
    if not dir then
        return false, oerr or (src .. ": cannot read")
    end
    while true do
        local entries = uv.fs_readdir(dir)
        if not entries or #entries == 0 then
            break
        end
        for _, e in ipairs(entries) do
            -- joinpath, not "src .. '/' .. name": see CLAUDE.md on paths.
            local ok, err = M.copy(vim.fs.joinpath(src, e.name), vim.fs.joinpath(dst, e.name))
            if not ok then
                uv.fs_closedir(dir)
                return false, err
            end
        end
    end
    uv.fs_closedir(dir)
    return true
end

return M
