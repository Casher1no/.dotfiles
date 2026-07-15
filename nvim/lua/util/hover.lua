-- Smart K (see plugins/lsp.lua): diagnostics under the cursor take priority
-- — pressing K on a problem line shows the full error(s) with their source;
-- pressing K again swaps the error float for the documentation. Lines
-- without diagnostics go straight to LSP hover, which noice renders as
-- highlighted markdown (see plugins/noice.lua).
local M = {}

function M.show()
    local diag_win = vim.b.diag_float_win
    if diag_win and vim.api.nvim_win_is_valid(diag_win) then
        -- Second K on the same spot: error is on screen, show the docs.
        vim.api.nvim_win_close(diag_win, true)
        vim.b.diag_float_win = nil
        vim.lsp.buf.hover()
        return
    end

    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    if #vim.diagnostic.get(0, { lnum = lnum }) > 0 then
        local _, win = vim.diagnostic.open_float({
            scope = "line",
            border = "rounded",
            source = true,
            header = "",
        })
        vim.b.diag_float_win = win
        return
    end

    vim.lsp.buf.hover()
end

-- The open K popup, if any: our diagnostic float or noice's docs/signature
-- float (found via noice's message registry — noice.lsp.docs).
local function popup_win()
    local win = vim.b.diag_float_win
    if win and vim.api.nvim_win_is_valid(win) then
        return win
    end
    local ok, docs = pcall(require, "noice.lsp.docs")
    if ok then
        for _, kind in ipairs({ "hover", "signature" }) do
            -- _messages directly: docs.get() would clear the message
            local msg = docs._messages[kind]
            local mwin = msg and msg:win()
            if mwin and vim.api.nvim_win_is_valid(mwin) then
                return mwin
            end
        end
    end
end

-- Scroll the open K popup without focusing it. Both return true when a
-- popup was scrolled — used by the smart <S-arrows> in plugins/neoscroll.lua,
-- which fall back to their normal behavior otherwise.
function M.scroll(lines)
    local win = popup_win()
    if not win then
        return false
    end
    vim.api.nvim_win_call(win, function()
        local key = lines > 0 and "\5" or "\25" -- <C-e> / <C-y>
        vim.cmd("normal! " .. math.abs(lines) .. key)
    end)
    return true
end

-- Close the open K popup (wired into the global <Esc> in vim-options.lua).
-- Returns true when something was closed.
function M.close()
    local win = vim.b.diag_float_win
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
        vim.b.diag_float_win = nil
        return true
    end
    local ok, docs = pcall(require, "noice.lsp.docs")
    if ok then
        for _, kind in ipairs({ "hover", "signature" }) do
            local msg = docs._messages[kind]
            if msg and msg:win() then
                docs.hide(msg) -- noice's own teardown, keeps its state sane
                return true
            end
        end
    end
    return false
end

function M.hscroll(cols)
    local win = popup_win()
    if not win then
        return false
    end
    -- zl/zh only move with 'wrap' off; sideways scrolling implies the user
    -- wants the unwrapped view.
    vim.wo[win].wrap = false
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! " .. math.abs(cols) .. (cols > 0 and "zl" or "zh"))
    end)
    return true
end

return M
