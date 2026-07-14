-- Claude Code in a left split, plus helpers that reference the current
-- file / selected lines in its prompt (as @path and @path#L10-20 mentions).
local M = {}

-- Pinned at first open: snacks keys terminals by cmd+cwd, so a later :cd
-- must not silently spawn a second claude.
local cwd = nil

local function term_opts()
    cwd = cwd or vim.fn.getcwd()
    return {
        cwd = cwd,
        win = { position = "left", width = 0.35 },
        interactive = true,
    }
end

function M.toggle()
    require("snacks").terminal.toggle("claude", term_opts())
end

-- Type text into Claude Code's prompt, opening the terminal if needed.
function M.send(text)
    local term, created = require("snacks").terminal.get("claude", term_opts())
    if not term then
        return
    end
    local function push()
        if not (term.buf and vim.api.nvim_buf_is_valid(term.buf)) then
            return
        end
        local chan = vim.bo[term.buf].channel
        if chan and chan > 0 then
            vim.api.nvim_chan_send(chan, text)
        end
        pcall(function()
            term:show()
            term:focus()
            vim.cmd.startinsert()
        end)
    end
    if created then
        -- Give claude's TUI a moment to boot before feeding it input.
        vim.defer_fn(push, 1500)
    else
        push()
    end
end

local function relpath(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" or vim.bo[buf].buftype ~= "" then
        return nil
    end
    return vim.fn.fnamemodify(name, ":.")
end

-- @-mention the current file in the Claude Code prompt.
function M.add_file()
    local path = relpath(vim.api.nvim_get_current_buf())
    if not path then
        vim.notify("Current buffer has no file to add to Claude Code", vim.log.levels.WARN)
        return
    end
    M.send("@" .. path .. " ")
end

-- Reference the visually selected lines — or the current line in normal
-- mode — in the Claude Code prompt.
function M.add_lines()
    local path = relpath(vim.api.nvim_get_current_buf())
    if not path then
        vim.notify("Current buffer has no file to add to Claude Code", vim.log.levels.WARN)
        return
    end
    local srow, erow = vim.fn.line("v"), vim.fn.line(".")
    if srow > erow then
        srow, erow = erow, srow
    end
    if vim.fn.mode():match("[vV\22]") then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end
    local ref = (srow == erow) and ("#L" .. srow) or ("#L" .. srow .. "-" .. erow)
    M.send("@" .. path .. ref .. " ")
end

return M
