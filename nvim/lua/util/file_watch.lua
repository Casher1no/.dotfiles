-- Live file sync: reload an open buffer as soon as its file changes on disk.
--
-- The checktime autocmds in config/autocmds.lua cover the obvious moments
-- (focus, buffer switch, leaving a terminal, idle), but CursorHold fires
-- exactly once per idle period — nvim never repeats it until a key is
-- pressed. So a file rewritten by an outside tool (an AI agent writing in the
-- background, a git checkout, a generator) while you sit reading stays stale
-- on screen until you happen to move the cursor. This watches the files
-- themselves, so the reload lands about a second after the write.
--
-- uv.new_fs_poll, not fs_event: editors and agents write through a temp file
-- plus rename, which leaves an fs_event handle bound to the replaced inode
-- and silently stops reporting. A poll re-stats the path by name, so it
-- survives renames — and one stat a second per open buffer costs nothing.
local M = {}

local uv = vim.uv or vim.loop

local INTERVAL = 1000 -- ms between stats, per buffer

local watchers = {} -- bufnr -> { handle = uv_fs_poll, path = string }

local function stop(buf)
    local w = watchers[buf]
    if not w then
        return
    end
    watchers[buf] = nil
    if not w.handle:is_closing() then
        w.handle:stop()
        w.handle:close()
    end
end

-- True while this buffer has unsaved edits *and* its file has moved
-- underneath — the one case nothing here can resolve on its own. Neovim does
-- not merge; both versions just stay alive until you pick one. util/autosave
-- skips a conflicted buffer at its pause points, so a background write never
-- gets silently overwritten by an idle save — but it does force-write on the
-- way out, where there is no "leave it for later" left. See there.
function M.conflicted(buf)
    local w = watchers[buf]
    return w ~= nil and w.conflict == true
end

-- checktime is what actually swaps the new contents in (autoread is on).
local function check(buf)
    if not vim.api.nvim_buf_is_loaded(buf) then
        return stop(buf)
    end
    -- A file that vanished (branch switch, rm) would make checktime shout
    -- E211; leave that buffer alone until the path exists again.
    local w = watchers[buf]
    if not w or vim.fn.filereadable(w.path) ~= 1 then
        return
    end
    -- Not from the cmdline window, and not mid-command — same guard the
    -- checktime autocmds use.
    if vim.fn.getcmdwintype() ~= "" or vim.fn.mode() == "c" then
        return
    end
    if vim.bo[buf].modified then
        -- Both sides changed, and nvim can't merge them. checktime would put
        -- the W12 prompt on screen once a second for as long as the buffer
        -- stays dirty, so raise it once as a message instead and let the
        -- reader pick a side.
        if not w.conflict then
            w.conflict = true
            local name = vim.fn.fnamemodify(w.path, ":t")
            vim.notify(
                name .. " changed on disk while you have unsaved edits — :e! takes the disk version, :w! keeps yours",
                vim.log.levels.WARN
            )
        end
        return
    end
    w.conflict = false
    vim.cmd("silent! checktime " .. buf)
end

local function watch(buf)
    if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
        return -- terminals, help, prompts, quickfix
    end
    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" or vim.fn.filereadable(path) ~= 1 then
        return
    end
    local existing = watchers[buf]
    if existing then
        if existing.path == path then
            -- Re-armed from a write or a re-read, so whatever the two sides
            -- disagreed about has been resolved one way or the other.
            existing.conflict = false
            return
        end
        stop(buf) -- renamed (:saveas, BufFilePost): re-arm on the new path
    end

    local handle = uv.new_fs_poll()
    if not handle then
        return
    end
    watchers[buf] = { handle = handle, path = path }
    handle:start(path, INTERVAL, function()
        -- Poll callbacks run on the loop thread, where the editor API is off
        -- limits; hop back to the main loop before touching the buffer.
        vim.schedule(function()
            check(buf)
        end)
    end)
end

function M.setup()
    local group = vim.api.nvim_create_augroup("file_watch", { clear = true })

    -- BufWritePost re-arms after a write-through-rename of our own, and
    -- BufFilePost after the buffer is renamed onto a different path.
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost", "BufWritePost" }, {
        group = group,
        callback = function(args)
            watch(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
            stop(args.buf)
        end,
    })

    -- Say what happened, since the text changing under the cursor with no
    -- explanation is worse than the stale buffer was. FileChangedShellPost
    -- fires only when nvim actually took the new contents, so our own writes
    -- (which trip the poll too, but reload nothing) stay silent.
    vim.api.nvim_create_autocmd("FileChangedShellPost", {
        group = group,
        callback = function(args)
            local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t")
            vim.notify("Reloaded " .. name .. " — changed on disk", vim.log.levels.INFO)
        end,
    })

    -- Buffers already open when this runs (session restore, `nvim file`).
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            watch(buf)
        end
    end
end

return M
