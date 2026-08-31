-- Recoverable file deletion, the way an IDE's "Delete" is recoverable:
-- deleting from the tree moves the file into a trash directory and records
-- it, and `u` in the tree puts it back.
--
-- Neo-tree's own delete is permanent — `rm -Rf` / `rmdir /s /q` and the node
-- is gone — so an accidental `d` on the wrong row could not be taken back.
-- plugins/neo-tree.lua hooks `before_file_delete` and hands the path here
-- instead; returning { handled = true } is what makes neo-tree skip its own
-- unlink while still firing `file_deleted`, so util/unity_sync still gets to
-- take the file out of Assembly-CSharp.csproj.
--
-- The manifest is on disk rather than in memory so the undo survives
-- restarting Neovim: noticing tomorrow that a file went missing is the case
-- this is actually for.
local M = {}

local uv = vim.uv or vim.loop
local os_files = require("util.os_files")

-- Bounded so the trash cannot grow forever on a machine that never restarts.
-- Pruned oldest-first on every stash, by both count and age.
local MAX_ENTRIES = 100
local MAX_AGE_SECS = 30 * 24 * 60 * 60

function M.root()
    return vim.fs.joinpath(vim.fn.stdpath("state"), "trash")
end

local function manifest_path()
    return vim.fs.joinpath(M.root(), "manifest.json")
end

-- Basename without vim.fs.basename: that runs the path through normalize,
-- which does not fold backslashes off Windows, so a path produced on Windows
-- (or by a test exercising that arm) would come back whole. See CLAUDE.md.
local function basename(path)
    return path:match("[^/\\]+$") or path
end

---@return table[] entries oldest first
function M.read_manifest()
    local fd = io.open(manifest_path(), "r")
    if not fd then
        return {}
    end
    local raw = fd:read("*a")
    fd:close()
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        -- A truncated manifest must not take the whole feature down with it.
        return {}
    end
    return decoded
end

local function write_manifest(entries)
    vim.fn.mkdir(M.root(), "p")
    local fd, err = io.open(manifest_path(), "w")
    if not fd then
        return false, err
    end
    fd:write(vim.json.encode(entries))
    fd:close()
    return true
end

-- Moves `src` to `dst`, across filesystems if it has to. fs_rename is one
-- syscall and keeps inodes, but fails with EXDEV whenever the two are on
-- different volumes — which is the normal case here, not the exotic one: the
-- trash lives under stdpath("state") on the system drive while projects sit
-- on F:\ (Windows) or an external volume (mac). Falling back to copy+delete
-- is what makes deleting from those work at all.
local function move(src, dst)
    if uv.fs_rename(src, dst) then
        return true
    end
    local ok, err = os_files.copy(src, dst)
    if not ok then
        return false, err
    end
    local removed, rerr = os_files.remove_tree(src)
    if not removed then
        -- The copy landed, so undo still works; leaving the original in place
        -- is the safe half of a bad outcome, but say so rather than
        -- reporting a delete that did not happen.
        return false, rerr
    end
    return true
end

local function prune(entries)
    local now = os.time()
    local kept = {}
    for _, entry in ipairs(entries) do
        local too_old = (now - (entry.at or 0)) > MAX_AGE_SECS
        local gone = not uv.fs_lstat(entry.stored)
        if gone then
            -- already removed from under us; drop the record silently
        elseif too_old then
            os_files.remove_tree(entry.stored)
        else
            kept[#kept + 1] = entry
        end
    end
    while #kept > MAX_ENTRIES do
        local oldest = table.remove(kept, 1)
        os_files.remove_tree(oldest.stored)
    end
    return kept
end

-- Moves `path` into the trash and records it for undo.
---@return boolean ok, string? err
function M.stash(path)
    local st = uv.fs_lstat(path)
    if not st then
        return false, path .. ": not found"
    end
    local root = M.root()
    if vim.fn.mkdir(root, "p") == 0 then
        return false, "could not create " .. root
    end

    -- Unique per stash: two deletes of the same basename, even in the same
    -- second, must not land on each other.
    local stored
    local n = 0
    repeat
        stored = vim.fs.joinpath(root, ("%d-%d-%s"):format(os.time(), n, basename(path)))
        n = n + 1
    until not uv.fs_lstat(stored)

    local ok, err = move(path, stored)
    if not ok then
        return false, err
    end

    local entries = prune(M.read_manifest())
    entries[#entries + 1] = {
        original = path,
        stored = stored,
        at = os.time(),
        type = st.type,
    }
    write_manifest(entries)
    return true
end

-- Restores the most recent stash.
---@return boolean ok, string restored_or_err
function M.undo()
    local entries = prune(M.read_manifest())
    local entry = entries[#entries]
    if not entry then
        return false, "nothing to restore"
    end
    if uv.fs_lstat(entry.original) then
        -- Something occupies the path again; clobbering it would turn one
        -- lost file into two.
        return false, entry.original .. " already exists"
    end
    -- The parent may have been deleted too (or the whole directory was what
    -- got deleted), so recreate it before moving back.
    vim.fn.mkdir(vim.fs.dirname(entry.original), "p")
    local ok, err = move(entry.stored, entry.original)
    if not ok then
        return false, err or "could not restore"
    end
    table.remove(entries)
    write_manifest(entries)
    return true, entry.original
end

-- Newest first, for a picker or a status readout.
function M.list()
    local entries = M.read_manifest()
    local out = {}
    for i = #entries, 1, -1 do
        out[#out + 1] = entries[i]
    end
    return out
end

return M
