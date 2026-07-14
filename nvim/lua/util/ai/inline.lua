-- Inline edit assistant: <leader>cp on a visual selection opens a prompt
-- float next to the selected lines; the local LLM rewrites the selection.
--
-- Flow:   prompting ──<CR>──▶ generating ──▶ reviewing ──<CR>──▶ applied
--                    └<C-y>─▶ generating ──────────────────────▶ applied
-- <Esc> cancels at every stage. While generating, an animated
-- "✻ Tinkering…" indicator sits at the end of the first selected line.
local M = {}

local ns = vim.api.nvim_create_namespace("ai_inline")
local session = nil

local SPINNER_FRAMES = { "✻ Tinkering", "✻ Tinkering ·", "✻ Tinkering ··", "✻ Tinkering ···" }

local SYSTEM_PROMPT = table.concat({
    "You are a precise code editing assistant.",
    "The user sends a file excerpt with a SELECTED region and an instruction.",
    "Reply with ONLY the replacement text for the SELECTED region — raw code,",
    "no markdown fences, no commentary. Preserve the file's indentation style",
    "and make the result fit its surrounding context.",
}, " ")

local function mark_row(s, id)
    local pos = vim.api.nvim_buf_get_extmark_by_id(s.buf, ns, id, {})
    return pos[1] -- 0-based; falls back to 0 if the mark vanished
end

-- Idempotent single cleanup path for every way a session can end.
local function teardown(msg)
    local s = session
    if not s then
        return
    end
    session = nil
    if s.handle then
        s.handle.cancel()
    end
    if s.spinner_timer then
        s.spinner_timer:stop()
        s.spinner_timer:close()
    end
    if s.prompt_win and vim.api.nvim_win_is_valid(s.prompt_win) then
        vim.api.nvim_win_close(s.prompt_win, true)
    end
    if vim.api.nvim_buf_is_valid(s.buf) then
        vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
        for _, lhs in ipairs(s.buf_keys or {}) do
            pcall(vim.keymap.del, "n", lhs, { buffer = s.buf })
        end
    end
    if s.augroup then
        pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
    end
    if msg then
        vim.notify(msg, vim.log.levels.INFO)
    end
end

M.cancel = teardown

local function postprocess(text)
    if not text then
        return nil
    end
    text = text:gsub("^%s*```[%w%-]*\n", ""):gsub("\n```%s*$", "")
    text = text:gsub("%s+$", "")
    if vim.trim(text) == "" then
        return nil
    end
    return vim.split(text, "\n", { plain = true })
end

local function spinner_start(s)
    s.spinner_timer = vim.uv.new_timer()
    local i = 0
    s.spinner_timer:start(
        0,
        200,
        vim.schedule_wrap(function()
            if session ~= s or not vim.api.nvim_buf_is_valid(s.buf) then
                return
            end
            i = i + 1
            s.spinner_id = vim.api.nvim_buf_set_extmark(s.buf, ns, mark_row(s, s.mark_start), 0, {
                id = s.spinner_id,
                virt_text = { { "  " .. SPINNER_FRAMES[(i % #SPINNER_FRAMES) + 1], "AiProgress" } },
                virt_text_pos = "eol",
            })
        end)
    )
end

local function spinner_stop(s)
    if s.spinner_timer then
        s.spinner_timer:stop()
        s.spinner_timer:close()
        s.spinner_timer = nil
    end
    if s.spinner_id and vim.api.nvim_buf_is_valid(s.buf) then
        pcall(vim.api.nvim_buf_del_extmark, s.buf, ns, s.spinner_id)
        s.spinner_id = nil
    end
end

-- Replace the (extmark-tracked) selection with the generated lines.
local function apply(new_lines)
    local s = session
    if not s then
        return
    end
    local start_row, end_row = mark_row(s, s.mark_start), mark_row(s, s.mark_end)
    teardown() -- removes review autocmds first so set_lines doesn't self-dismiss
    if vim.api.nvim_buf_is_valid(s.buf) then
        vim.api.nvim_buf_set_lines(s.buf, start_row, end_row + 1, false, new_lines)
    end
end

local function show_review(s, new_lines)
    s.state = "reviewing"
    local start_row, end_row = mark_row(s, s.mark_start), mark_row(s, s.mark_end)

    for r = start_row, end_row do
        vim.api.nvim_buf_set_extmark(s.buf, ns, r, 0, { line_hl_group = "AiReviewOld" })
    end
    local virt = {}
    for _, l in ipairs(new_lines) do
        virt[#virt + 1] = { { l == "" and " " or l, "AiReviewNew" } }
    end
    vim.api.nvim_buf_set_extmark(s.buf, ns, end_row, 0, {
        virt_lines = virt,
        virt_text = { { "  <CR> accept · <Esc> decline ", "AiHint" } },
        virt_text_pos = "eol",
    })

    s.buf_keys = { "<CR>", "<Esc>" }
    vim.keymap.set("n", "<CR>", function()
        apply(new_lines)
    end, { buffer = s.buf, nowait = true, desc = "AI: accept change" })
    vim.keymap.set("n", "<Esc>", function()
        teardown("AI edit declined")
    end, { buffer = s.buf, nowait = true, desc = "AI: decline change" })

    -- Any modification or external reload of the buffer invalidates the
    -- proposal (the config auto-reloads files via checktime).
    s.augroup = vim.api.nvim_create_augroup("AiInlineReview", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost", "BufUnload" }, {
        group = s.augroup,
        buffer = s.buf,
        callback = function()
            teardown("AI review dismissed — buffer changed")
        end,
    })
end

local function generate(s, instruction, auto_apply)
    s.state = "generating"
    s.gen_tick = vim.api.nvim_buf_get_changedtick(s.buf)

    local start_row, end_row = mark_row(s, s.mark_start), mark_row(s, s.mark_end)
    local ctx_before = vim.api.nvim_buf_get_lines(s.buf, math.max(0, start_row - 40), start_row, false)
    local ctx_after = vim.api.nvim_buf_get_lines(s.buf, end_row + 1, end_row + 41, false)

    spinner_start(s)
    s.buf_keys = { "<Esc>" }
    vim.keymap.set("n", "<Esc>", function()
        teardown("AI edit cancelled")
    end, { buffer = s.buf, nowait = true, desc = "AI: cancel generation" })

    s.handle = require("util.ai.client").chat({
        temperature = 0.3,
        max_tokens = 2048,
        timeout_ms = 120000, -- LM Studio may JIT-load the model on first use
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            {
                role = "user",
                content = table.concat({
                    "Language: " .. vim.bo[s.buf].filetype,
                    "",
                    "Context before:",
                    table.concat(ctx_before, "\n"),
                    "",
                    "SELECTED (reply with the replacement for exactly this region):",
                    table.concat(s.original, "\n"),
                    "",
                    "Context after:",
                    table.concat(ctx_after, "\n"),
                    "",
                    "Instruction: " .. instruction,
                }, "\n"),
            },
        },
        on_done = function(text, err)
            if session ~= s then
                return
            end
            spinner_stop(s)
            pcall(vim.keymap.del, "n", "<Esc>", { buffer = s.buf })
            s.buf_keys = nil
            s.handle = nil
            if err then
                if err == "offline" or err == "no model" then
                    vim.notify(
                        "AI edit failed — LM Studio server unreachable (palette → AI)",
                        vim.log.levels.WARN
                    )
                    teardown()
                else
                    teardown("AI edit failed: " .. err)
                end
                return
            end
            -- Discard if the selected region itself changed while generating
            -- (edits elsewhere are fine — the extmarks track the region).
            local cur_start, cur_end = mark_row(s, s.mark_start), mark_row(s, s.mark_end)
            local now_lines = vim.api.nvim_buf_get_lines(s.buf, cur_start, cur_end + 1, false)
            if vim.api.nvim_buf_get_changedtick(s.buf) ~= s.gen_tick and not vim.deep_equal(now_lines, s.original) then
                teardown("AI edit discarded — selection changed while generating")
                return
            end
            local new_lines = postprocess(text)
            if not new_lines then
                teardown("AI returned an empty edit")
                return
            end
            if auto_apply then
                apply(new_lines)
            else
                show_review(s, new_lines)
            end
        end,
    })
end

local function open_prompt(s, srow)
    local pbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[pbuf].bufhidden = "wipe"
    s.prompt_buf = pbuf
    s.prompt_win = vim.api.nvim_open_win(pbuf, true, {
        relative = "win",
        win = s.win,
        bufpos = { srow - 1, 0 }, -- anchored to the selection, tracks scrolling
        row = 0,
        col = 4,
        width = math.min(64, math.max(40, vim.api.nvim_win_get_width(s.win) - 8)),
        height = 1,
        style = "minimal",
        border = "rounded",
        title = " AI edit — <CR> review · <C-y> apply · <Esc> cancel ",
        title_pos = "left",
    })
    vim.cmd.startinsert()

    local function submit(auto_apply)
        return function()
            if session ~= s then
                return
            end
            local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), "\n"))
            vim.cmd.stopinsert()
            local win = s.prompt_win
            s.prompt_win = nil -- cleared first so WinClosed doesn't cancel us
            if win and vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
            if text == "" then
                teardown()
                return
            end
            generate(s, text, auto_apply)
        end
    end
    -- <C-y> instead of <C-CR>: most terminals can't distinguish <C-CR> from
    -- <CR>, and the global insert <C-S> mapping would interfere.
    for _, mode in ipairs({ "i", "n" }) do
        vim.keymap.set(mode, "<CR>", submit(false), { buffer = pbuf, nowait = true })
        vim.keymap.set(mode, "<C-y>", submit(true), { buffer = pbuf, nowait = true })
    end
    vim.keymap.set("n", "<Esc>", function()
        teardown()
    end, { buffer = pbuf, nowait = true })
    -- Closing the float any other way (:q, focus tricks) cancels too.
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(s.prompt_win),
        once = true,
        callback = function()
            if session == s and s.prompt_win then
                vim.cmd.stopinsert()
                teardown()
            end
        end,
    })
end

-- Entry point for the x-mode <leader>cp mapping; runs while the visual
-- selection is still active.
function M.edit()
    teardown()
    -- Explicit invocation deserves a loud answer (unlike autocomplete,
    -- which must stay silent): refuse up front when AI can't respond.
    local client = require("util.ai.client")
    if not require("util.ai.config").model() then
        vim.notify(
            "AI edit unavailable — no model configured. Palette → AI to start LM Studio and pick a model.",
            vim.log.levels.WARN
        )
        client.models() -- refresh status + model list in the background
        return
    end
    if client.status.online == false then
        vim.notify(
            "AI edit unavailable — LM Studio server is offline. Palette → AI → Start server.",
            vim.log.levels.WARN
        )
        client.models() -- so a just-started server unblocks the next attempt
        return
    end
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "" then
        return
    end
    local srow, erow = vim.fn.line("v"), vim.fn.line(".")
    if srow > erow then
        srow, erow = erow, srow
    end

    session = {
        state = "prompting",
        buf = buf,
        win = vim.api.nvim_get_current_win(),
        original = vim.api.nvim_buf_get_lines(buf, srow - 1, erow, false),
        -- Gravity-pinned range markers: later row math derives from these,
        -- so edits above the selection can't corrupt positions.
        mark_start = vim.api.nvim_buf_set_extmark(buf, ns, srow - 1, 0, { right_gravity = false }),
        mark_end = vim.api.nvim_buf_set_extmark(buf, ns, erow - 1, 0, {}),
    }
    local s = session
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    vim.schedule(function()
        if session == s then
            open_prompt(s, srow)
        end
    end)
end

return M
