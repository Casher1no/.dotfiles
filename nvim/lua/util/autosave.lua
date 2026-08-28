-- Save like an IDE: never stop to ask.
--
-- Two halves, because Neovim asks in two different places.
--
-- 1. Pause points. Modified, named, real-file buffers are written when you
--    leave insert, switch buffer or window, lose focus, or go idle — so
--    external tools never collide with unsaved edits. Deliberately NOT on
--    every keystroke: Unity would recompile mid-typing. CursorHoldI covers a
--    pause *inside* insert mode ('updatetime'); without it a long typing
--    session never reaches disk, and anything reading the file meanwhile (an
--    AI agent, a formatter, a test run) works from stale contents.
--
-- 2. Closing. The pause points always miss the last few seconds of typing in
--    the buffer you close from, and 'confirm' (vim-options.lua) turns that
--    into a "Save changes?" dialog on the way out. 'autowriteall' handles
--    most of it, but not all, so the gaps are covered here:
--      * QuitPre / ExitPre — :q, :qa, ZZ, closing a split. Every buffer is
--        still loaded at that point, so one that is only open in another
--        window or tab gets written too.
--      * CmdlineLeave — :bdelete / :bwipeout, which Neovim checks for
--        changes itself, before any autocommand of its own would run.
local M = {}

-- Anything that can be written back to a file it came from. Terminals,
-- prompts, help and read-only buffers can't; nor can [No Name], which has no
-- path to write to (that one still reaches the 'confirm' dialog, and should).
function M.has_unsaved_file(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return false
    end
    if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
        return false
    end
    return vim.bo[buf].modified and vim.api.nvim_buf_get_name(buf) ~= ""
end

-- `update` writes only if modified. `update!` additionally overrides the
-- "file changed since reading it" check, which otherwise stops to ask "Do you
-- really want to write to it (y/n)?" — another close-time prompt.
function M.write(buf, force)
    vim.api.nvim_buf_call(buf, function()
        vim.cmd(force and "silent! lockmarks update!" or "silent! lockmarks update")
    end)
end

function M.save(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not M.has_unsaved_file(buf) then
        return
    end
    if require("util.file_watch").conflicted(buf) then
        -- Something else rewrote this file while these edits were unsaved.
        -- Writing now would drop that change on the floor with no prompt —
        -- file_watch has already said so; leave the choice to :w! or :e!.
        -- Closing is the exception; see save_all.
        return
    end
    M.write(buf)
end

-- Every buffer, conflicts included. Mid-session, refusing to write a
-- conflicted buffer keeps both versions alive and lets you pick with :w! or
-- :e!. On the way out there is no such choice left: not writing doesn't
-- preserve the file on disk, it just throws away everything you typed.
-- Writing loses strictly less, and file_watch has already warned that the
-- file changed underneath you.
function M.save_all()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if M.has_unsaved_file(buf) then
            M.write(buf, true)
        end
    end
end

-- Does this command line close a buffer? Matched on the verb because :bd,
-- :bdel and :bdelete are all the same command, and a range or count can come
-- first (:%bd, :1,3bd, :.bd!).
--
-- Over-matching is harmless — the cost of a false positive is writing a
-- buffer that was already going to be written — so :bu is allowed to look
-- like :bunload when it is really :buffer. Under-matching is not, hence the
-- prefix test rather than a fixed list of spellings. A bare :b is excluded
-- because on its own it is :buffer, which 'autowrite' already covers.
local closing_commands = { "bdelete", "bwipeout", "bunload" }
function M.closes_a_buffer(cmdline)
    local verb = cmdline:match("^[%s:]*[%d,%%%.$'<>%+%-]*%s*(%a+)")
    if not verb or #verb < 2 then
        return false
    end
    for _, full in ipairs(closing_commands) do
        if full:sub(1, #verb) == verb then
            return true
        end
    end
    return false
end

function M.setup()
    local group = vim.api.nvim_create_augroup("auto_save", { clear = true })

    vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "FocusLost", "CursorHold", "CursorHoldI" }, {
        group = group,
        callback = function(args)
            M.save(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "QuitPre", "ExitPre" }, {
        group = group,
        callback = function()
            M.save_all()
        end,
    })

    -- CmdlineLeave fires while the command is still just text, which is early
    -- enough to write. Only typed commands come through here; a plugin
    -- invoking :bdelete straight from a mapping would still get the dialog.
    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        pattern = ":",
        callback = function()
            if M.closes_a_buffer(vim.fn.getcmdline()) then
                M.save_all()
            end
        end,
    })
end

return M
