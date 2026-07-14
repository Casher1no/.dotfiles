-- Side-panel chat with the local LLM. One markdown conversation buffer kept
-- for the whole session; the window is a plain right split. Ask with `i` or
-- <CR> inside the panel (input via vim.ui.input → snacks float), `q` closes,
-- `R` resets the conversation, <Esc> stops a running response.
local M = {}

local state = { buf = nil, win = nil, messages = {}, handle = nil }

local SYSTEM_PROMPT = "You are a concise programming assistant inside Neovim. "
    .. "Answer in markdown; keep code in fenced blocks."

local function buf_valid()
    return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function win_valid()
    return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function writable(fn)
    vim.bo[state.buf].modifiable = true
    fn()
    vim.bo[state.buf].modifiable = false
end

local function line_count()
    return vim.api.nvim_buf_line_count(state.buf)
end

-- Append whole lines at the end of the buffer, following with the cursor
-- only when it was already at the bottom (so scrolling back stays put).
local function append_lines(lines)
    local follow = win_valid() and vim.api.nvim_win_get_cursor(state.win)[1] == line_count()
    writable(function()
        vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, lines)
    end)
    if follow and win_valid() then
        vim.api.nvim_win_set_cursor(state.win, { line_count(), 0 })
    end
end

-- Append streamed text to the end of the last line (may contain newlines).
local function append_text(text)
    local follow = win_valid() and vim.api.nvim_win_get_cursor(state.win)[1] == line_count()
    local last = line_count() - 1
    local last_line = vim.api.nvim_buf_get_lines(state.buf, last, last + 1, false)[1] or ""
    writable(function()
        vim.api.nvim_buf_set_text(state.buf, last, #last_line, last, #last_line, vim.split(text, "\n", { plain = true }))
    end)
    if follow and win_valid() then
        vim.api.nvim_win_set_cursor(state.win, { line_count(), 0 })
    end
end

local function stop_stream()
    if state.handle then
        state.handle.cancel()
        state.handle = nil
        append_lines({ "", "_(stopped)_", "", "---", "" })
    end
end

local function ensure_buf()
    if buf_valid() then
        return
    end
    state.buf = vim.api.nvim_create_buf(false, true)
    local buf = state.buf
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false
    pcall(vim.api.nvim_buf_set_name, buf, "AI Chat")
    writable(function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# AI Chat", "" })
    end)

    local function map(lhs, fn, desc)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
    map("q", M.close, "Close AI chat")
    map("i", M.ask, "Ask AI")
    map("<CR>", M.ask, "Ask AI")
    map("R", M.reset, "Reset AI conversation")
    map("<Esc>", function()
        stop_stream()
        vim.cmd.nohlsearch() -- keep the global Esc muscle memory working
    end, "Stop AI response")
end

function M.open()
    ensure_buf()
    if win_valid() then
        vim.api.nvim_set_current_win(state.win)
        return
    end
    state.win = vim.api.nvim_open_win(state.buf, true, {
        split = "right",
        width = math.max(40, math.floor(vim.o.columns * 0.38)),
    })
    vim.wo[state.win].wrap = true
    vim.wo[state.win].linebreak = true
    vim.wo[state.win].number = false
    vim.wo[state.win].relativenumber = false
    vim.wo[state.win].signcolumn = "no"
    vim.api.nvim_win_set_cursor(state.win, { line_count(), 0 })
end

function M.close()
    if win_valid() then
        vim.api.nvim_win_close(state.win, true)
    end
    state.win = nil
end

function M.toggle()
    if win_valid() then
        M.close()
    else
        M.open()
    end
end

function M.reset()
    stop_stream()
    state.messages = {}
    if buf_valid() then
        writable(function()
            vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "# AI Chat", "" })
        end)
    end
end

function M.ask()
    M.open()
    if state.handle then
        vim.notify("AI is still responding — <Esc> stops it", vim.log.levels.INFO)
        return
    end
    vim.ui.input({ prompt = "Ask AI: " }, function(input)
        input = input and vim.trim(input) or ""
        if input == "" then
            return
        end
        local client = require("util.ai.client")
        if not require("util.ai.config").model() then
            vim.notify("No AI model configured — palette → AI", vim.log.levels.WARN)
            return
        end

        table.insert(state.messages, { role = "user", content = input })
        append_lines({ "## You", "", input, "", "## Assistant", "", "" })

        local msgs = { { role = "system", content = SYSTEM_PROMPT } }
        vim.list_extend(msgs, state.messages)
        state.handle = client.chat({
            messages = msgs,
            temperature = 0.4,
            max_tokens = 2048,
            timeout_ms = 300000,
            on_delta = append_text,
            on_done = function(full, err)
                state.handle = nil
                if err then
                    if err == "offline" then
                        client.notify_offline()
                    else
                        vim.notify("AI chat failed: " .. err, vim.log.levels.WARN)
                    end
                    append_text("_(no response — server unavailable)_")
                elseif full and full ~= "" then
                    table.insert(state.messages, { role = "assistant", content = full })
                end
                append_lines({ "", "---", "" })
            end,
        })
    end)
end

return M
