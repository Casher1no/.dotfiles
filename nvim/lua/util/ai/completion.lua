-- Ghost-text autocompletion from the local LLM. Fires automatically while
-- typing (debounced); <Tab> accepts — chained ahead of blink's fallback in
-- plugins/blink-cmp.lua, and never competing with blink since the ghost is
-- cleared whenever blink's menu is visible.
--
-- When the server or a model is unavailable every path here fails silently
-- (with a 30s cooldown after a failed request) so coding is never disturbed.
local M = {}

local ns = vim.api.nvim_create_namespace("ai_ghost")
local timer = nil
local current = nil -- { buf, row, col, lines } of the rendered suggestion
local inflight = nil -- cancel handle of the request on the wire
local cooldown_until = 0
local request_seq = 0

local DEBOUNCE_MS = 500
local PREFIX_LINES = 100
local SUFFIX_LINES = 30
local MAX_GHOST_LINES = 10

local SYSTEM_PROMPT = table.concat({
    "You are a code completion engine. The user sends code with <CURSOR> marking the insertion point.",
    "Reply with ONLY the raw text to insert at <CURSOR>.",
    "Never repeat code that is already before the cursor. Never explain.",
    "No markdown fences, no prose. Stop at a natural boundary (end of the statement or block).",
}, " ")

local enabled = nil -- lazily read from config, kept in sync by toggle()

function M.is_enabled()
    if enabled == nil then
        enabled = require("util.ai.config").get().autocomplete
    end
    return enabled
end

function M.toggle()
    enabled = not M.is_enabled()
    require("util.ai.config").set("autocomplete", enabled)
    if not enabled then
        M.clear()
    end
    return enabled
end

function M.visible()
    return current ~= nil
end

function M.clear()
    if timer then
        timer:stop()
    end
    if inflight then
        inflight.cancel()
        inflight = nil
    end
    if current and vim.api.nvim_buf_is_valid(current.buf) then
        vim.api.nvim_buf_clear_namespace(current.buf, ns, 0, -1)
    end
    current = nil
end

local function blink_menu_visible()
    local ok, blink = pcall(require, "blink.cmp")
    return ok and blink.is_visible and blink.is_visible()
end

local function postprocess(text)
    -- Models occasionally fence the answer despite the prompt.
    text = text:gsub("^%s*```[%w%-]*\n", ""):gsub("\n```%s*$", "")
    text = text:gsub("%s+$", "")
    if text == "" then
        return nil
    end
    local lines = vim.split(text, "\n", { plain = true })
    if #lines > MAX_GHOST_LINES then
        lines = vim.list_slice(lines, 1, MAX_GHOST_LINES)
    end
    return lines
end

local function show(buf, row, col, lines)
    local virt_lines = {}
    for i = 2, #lines do
        virt_lines[#virt_lines + 1] = { { lines[i] == "" and " " or lines[i], "AiGhost" } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, col, {
        virt_text = { { lines[1] == "" and " " or lines[1], "AiGhost" } },
        virt_text_pos = "inline",
        virt_lines = #virt_lines > 0 and virt_lines or nil,
    })
    current = { buf = buf, row = row, col = col, lines = lines }
end

local function request()
    if not M.is_enabled() or vim.uv.now() < cooldown_until then
        return
    end
    -- Only complete in real file buffers, in insert mode, outside macros,
    -- and while blink's menu is closed.
    if vim.fn.mode():sub(1, 1) ~= "i" or vim.bo.buftype ~= "" then
        return
    end
    if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
        return
    end
    if blink_menu_visible() then
        return
    end

    local buf = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local row, col = pos[1], pos[2]
    local line = vim.api.nvim_get_current_line()
    local before = vim.api.nvim_buf_get_lines(buf, math.max(0, row - 1 - PREFIX_LINES), row - 1, false)
    local after = vim.api.nvim_buf_get_lines(buf, row, row + SUFFIX_LINES, false)
    local prefix = table.concat(before, "\n") .. (#before > 0 and "\n" or "") .. line:sub(1, col)
    local suffix = line:sub(col + 1) .. "\n" .. table.concat(after, "\n")

    local tick = vim.api.nvim_buf_get_changedtick(buf)
    request_seq = request_seq + 1
    local seq = request_seq

    inflight = require("util.ai.client").complete({
        temperature = 0.2,
        max_tokens = 128,
        timeout_ms = 10000,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            {
                role = "user",
                content = ("Language: %s\nFile: %s\n\n%s<CURSOR>%s"):format(
                    vim.bo[buf].filetype,
                    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
                    prefix,
                    suffix
                ),
            },
        },
    }, function(text, err)
        if seq ~= request_seq then
            return -- a newer request superseded this one
        end
        inflight = nil
        if err then
            -- Silent by design; just back off so a dead server isn't hit
            -- on every pause in typing.
            cooldown_until = vim.uv.now() + 30000
            return
        end
        -- Drop stale responses: anything moved or changed since we asked.
        if
            vim.api.nvim_get_current_buf() ~= buf
            or vim.fn.mode():sub(1, 1) ~= "i"
            or vim.api.nvim_buf_get_changedtick(buf) ~= tick
            or blink_menu_visible()
        then
            return
        end
        local now_pos = vim.api.nvim_win_get_cursor(0)
        if now_pos[1] ~= row or now_pos[2] ~= col then
            return
        end
        local lines = postprocess(text)
        if lines then
            show(buf, row, col, lines)
        end
    end)
end

-- The blink <Tab> chain contract: return true when the ghost text was
-- accepted (key consumed), false to fall through to blink's next handler.
function M.accept()
    if not current then
        return false
    end
    local c = current
    if vim.api.nvim_get_current_buf() ~= c.buf then
        M.clear()
        return false
    end
    vim.api.nvim_buf_set_text(c.buf, c.row - 1, c.col, c.row - 1, c.col, c.lines)
    local last = c.lines[#c.lines]
    local new_row = c.row + #c.lines - 1
    local new_col = (#c.lines == 1) and (c.col + #last) or #last
    M.clear()
    vim.api.nvim_win_set_cursor(0, { new_row, new_col })
    return true
end

function M.setup()
    timer = vim.uv.new_timer()
    local group = vim.api.nvim_create_augroup("AiGhost", { clear = true })

    vim.api.nvim_create_autocmd("TextChangedI", {
        group = group,
        callback = function()
            M.clear()
            if M.is_enabled() and vim.bo.buftype == "" then
                timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(request))
            end
        end,
    })
    vim.api.nvim_create_autocmd("CursorMovedI", {
        group = group,
        callback = function()
            -- Typing also fires TextChangedI (which restarts the cycle);
            -- pure movement away from the suggestion just clears it.
            if current then
                local pos = vim.api.nvim_win_get_cursor(0)
                if pos[1] ~= current.row or pos[2] ~= current.col then
                    M.clear()
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
        group = group,
        callback = function()
            M.clear()
        end,
    })
    -- blink's menu takes priority over ghost text.
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "BlinkCmpMenuOpen",
        callback = function()
            M.clear()
        end,
    })
end

return M
