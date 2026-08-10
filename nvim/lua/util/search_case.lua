-- Match-case state badge for / and ? search, right-aligned in the noice
-- cmdline popup — same look as the Telescope one in util/telescope_case.lua:
-- a dim "Aa ⟨C-s⟩" hint while case-insensitive, a highlighted "Aa ✓" while
-- the pattern starts with \C. The <C-s> toggle itself is mapped in
-- vim-options.lua and calls M.toggle().
local M = {}

local ns = vim.api.nvim_create_namespace("search_case_badge")
local active = false
local attached = {} ---@type table<number, boolean>

-- The buffer noice renders the cmdline into, plus the 0-indexed row of the
-- cmdline text within it. Nil before noice has rendered anything (or when
-- noice isn't loaded — the native bottom cmdline can't show virtual text).
local function badge_target()
    local ok, cmdline = pcall(require, "noice.ui.cmdline")
    if not ok or not cmdline.position then
        return
    end
    local buf = cmdline.position.buf
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
    end
    return buf, math.max(0, (cmdline.position.bufpos.row or 1) - 1)
end

local function place()
    if not active then
        return
    end
    local buf, row = badge_target()
    if not buf then
        return
    end
    local sensitive = vim.fn.getcmdline():sub(1, 2) == [[\C]]
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
        virt_text = sensitive and { { " Aa ✓ ", "DiagnosticOk" } }
            or { { " Aa ⟨C-s⟩ ", "Comment" } },
        virt_text_pos = "right_align",
    })
    -- noice rewrites this buffer on every render, wiping the extmark —
    -- re-place the badge whenever the buffer content changes.
    if not attached[buf] then
        attached[buf] = true
        vim.api.nvim_buf_attach(buf, false, {
            on_lines = function()
                if not attached[buf] then
                    return true -- detach
                end
                vim.schedule(place)
            end,
            on_detach = function()
                attached[buf] = nil
            end,
        })
    end
end

-- <C-s> while typing a search: add/remove the \C prefix that forces
-- case-sensitivity (see vim-options.lua for why \C rather than an option:
-- it's visible, previews live, and sticks for n/N).
function M.toggle()
    local cmdtype = vim.fn.getcmdtype()
    if cmdtype ~= "/" and cmdtype ~= "?" then
        return
    end
    local line = vim.fn.getcmdline()
    if line:sub(1, 2) == [[\C]] then
        vim.fn.setcmdline(line:sub(3))
    else
        vim.fn.setcmdline([[\C]] .. line)
    end
    vim.schedule(place)
end

function M.setup()
    local group = vim.api.nvim_create_augroup("SearchCaseBadge", { clear = true })
    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        pattern = { "/", "\\?" },
        callback = function()
            active = true
            vim.schedule(place)
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineChanged", {
        group = group,
        pattern = { "/", "\\?" },
        callback = function()
            vim.schedule(place)
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function()
            active = false
            local buf = badge_target()
            if buf then
                vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
            end
        end,
    })
end

return M
