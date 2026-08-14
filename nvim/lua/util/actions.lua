-- IDE-style intentions menu, replacing vim.lsp.buf.code_action for
-- <leader>ca (plugins/lsp.lua): a dropdown anchored at the cursor line —
-- not a centered picker — listing every code action from every attached
-- client, then non-LSP refactors that fit the cursor context: the
-- IDE-style intentions from util/intentions.lua (invert if, surround
-- with try/catch) and treesj ("Split …" when the node under the cursor is
-- on one line, "Join …" when it is already spread out). 1-9 pick directly,
-- j/k/arrows + <CR> navigate, <Esc>/q close.
local M = {}

-- Ordering: what fixes the code under the cursor comes first,
-- boilerplate generators last. LSP kinds map cleanly onto that — quickfix.*
-- addresses a diagnostic, refactor.* transforms what's there, source.*
-- (generate getters, organize imports, sort members …) adds new code.
local GROUPS = {
    { rank = 1, label = "Fix", match = "^quickfix" },
    { rank = 3, label = "Generate", match = "^source" },
}
local REFACTOR = { rank = 2, label = "Refactor" } -- refactor.* and kindless

local function group_for(kind)
    for _, g in ipairs(GROUPS) do
        if (kind or ""):find(g.match) then
            return g
        end
    end
    return REFACTOR
end

-- ---------------------------------------------------------------- treesj

-- Walk up from the cursor node to the first construct treesj can transform
-- in this language; already-multiline nodes offer Join, one-liners Split.
-- Everything pcall'd: no parser, no treesj, no matching node — no entries.
local function treesj_entries(bufnr)
    local entries = {}
    local ok, result = pcall(function()
        local ft = vim.bo[bufnr].filetype
        local lang = vim.treesitter.language.get_lang(ft) or ft
        local presets = require("treesj.langs").presets[lang]
        if not presets then
            return nil
        end
        local node = vim.treesitter.get_node({ bufnr = bufnr })
        if not node then
            -- no parser attached yet (fresh buffer, or highlighting skipped
            -- it) — attach and parse on demand, it's one small buffer
            local parser = vim.treesitter.get_parser(bufnr, lang)
            if parser then
                parser:parse()
                node = vim.treesitter.get_node({ bufnr = bufnr })
            end
        end
        while node do
            if presets[node:type()] then
                return node
            end
            node = node:parent()
        end
    end)
    if not (ok and result) then
        return entries
    end
    local node = result
    local srow, _, erow = node:range()
    local pretty = node:type():gsub("_", " ")
    if srow == erow then
        entries[#entries + 1] = {
            label = "Split " .. pretty,
            run = function()
                require("treesj").split()
            end,
        }
    else
        entries[#entries + 1] = {
            label = "Join " .. pretty,
            run = function()
                require("treesj").join()
            end,
        }
    end
    return entries
end

-- ------------------------------------------------------------------ menu

-- entries: { { label, run } | { header = "Refactor" } | { sep = true } }.
-- Opens at the cursor, picks call entry.run(). Headers and separators render
-- as dim rules; rows carry no icons — the grouping is the visual language.
local function show_menu(entries)
    -- first pass: row text and width, so headers can pad their rule to it
    local lines, selectable = {}, {}
    local n = 0
    for _, entry in ipairs(entries) do
        if entry.sep or entry.header then
            lines[#lines + 1] = entry -- placeholder, rendered after width is known
        else
            n = n + 1
            local num = n <= 9 and tostring(n) or " "
            lines[#lines + 1] = (" %s  %s "):format(num, entry.label)
            selectable[#lines] = entry
        end
    end
    local width = 16
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            width = math.max(width, vim.fn.strdisplaywidth(line))
        end
    end
    for i, line in ipairs(lines) do
        if type(line) ~= "string" then
            if line.header then
                local rule = "─ " .. line.header .. " "
                lines[i] = rule .. string.rep("─", math.max(1, width - vim.fn.strdisplaywidth(rule)))
            else
                lines[i] = string.rep("─", width)
            end
        end
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = width,
        height = #lines,
        style = "minimal",
        border = "rounded",
        title = " 󰌵 Actions ",
        title_pos = "left",
    })
    vim.wo[win].cursorline = true
    -- land on the first action, not a header rule
    for i = 1, #lines do
        if selectable[i] then
            vim.api.nvim_win_set_cursor(win, { i, 0 })
            break
        end
    end

    -- dim the separator rows and the number column
    local ns = vim.api.nvim_create_namespace("actions_menu")
    for i, line in ipairs(lines) do
        if not selectable[i] then
            vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_row = i, end_col = 0, hl_group = "Comment" })
        end
    end

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    local function pick(lnum)
        local entry = selectable[lnum]
        if not entry then
            return
        end
        close()
        -- run after the float is gone so edits land in the original window
        vim.schedule(entry.run)
    end
    -- move to the next selectable row in the given direction, wrapping
    local function move(delta)
        local cur = vim.api.nvim_win_get_cursor(win)[1]
        for _ = 1, #lines do
            cur = cur + delta
            if cur > #lines then
                cur = 1
            elseif cur < 1 then
                cur = #lines
            end
            if selectable[cur] then
                vim.api.nvim_win_set_cursor(win, { cur, 0 })
                return
            end
        end
    end

    local function map(lhs, fn)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
    map("<CR>", function()
        pick(vim.api.nvim_win_get_cursor(win)[1])
    end)
    for _, lhs in ipairs({ "j", "<Down>", "<Tab>" }) do
        map(lhs, function()
            move(1)
        end)
    end
    for _, lhs in ipairs({ "k", "<Up>", "<S-Tab>" }) do
        map(lhs, function()
            move(-1)
        end)
    end
    for _, lhs in ipairs({ "<Esc>", "q" }) do
        map(lhs, close)
    end
    local i = 0
    for lnum, _ in vim.spairs(selectable) do
        i = i + 1
        if i <= 9 then
            local num = i
            map(tostring(num), function()
                pick(lnum)
            end)
        end
    end
    -- leaving the menu (mouse click elsewhere) closes it
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = buf,
        once = true,
        callback = close,
    })
end

-- ------------------------------------------------------- gather and apply

-- Extract refactors insert a server-chosen placeholder name (tsserver:
-- newFunction/newLocal, jdtls: extracted, roslyn: NewMethod) and expect the
-- editor to start a rename — VS Code does, stock Neovim does not. Our
-- flow instead: the name is asked for up front (see apply_action), and once
-- the server's edit lands (watched via changedtick — jdtls applies its
-- asynchronously), the placeholder nearest the cursor is LSP-renamed to it.
local EXTRACT_PLACEHOLDERS =
    { "newFunction", "newMethod", "newLocal", "newVariable", "NewMethod", "extracted" }

-- After an extract, vtsls asks the client to start a rename at the inserted
-- name via the VS Code command editor.action.rename([uri, position]) —
-- unimplemented in stock Neovim, which errors "does not support command".
-- Move the cursor there instead: rename_extracted then renames exactly it.
vim.lsp.commands["editor.action.rename"] = function(cmd)
    local uri, pos = cmd.arguments and cmd.arguments[1], cmd.arguments and cmd.arguments[2]
    if type(uri) == "string" and type(pos) == "table" then
        local win = vim.fn.bufwinid(vim.uri_to_bufnr(uri))
        if win ~= -1 then
            pcall(vim.api.nvim_win_set_cursor, win, { (pos.line or 0) + 1, pos.character or 0 })
        end
    end
end

local function rename_extracted(bufnr, name)
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    local tries = 0
    local function poll()
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        if vim.api.nvim_buf_get_changedtick(bufnr) == tick then
            tries = tries + 1
            if tries < 30 then
                vim.defer_fn(poll, 100)
            end
            return
        end
        -- small settle delay: multi-part edits, jdtls's own cursor move
        vim.defer_fn(function()
            local cur = vim.api.nvim_win_get_cursor(0)[1]
            local best, best_d
            for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
                for _, ph in ipairs(EXTRACT_PLACEHOLDERS) do
                    local col = line:find("%f[%w_]" .. ph .. "%f[^%w_]")
                    if col and (not best or math.abs(i - cur) < best_d) then
                        best, best_d = { i, col - 1 }, math.abs(i - cur)
                    end
                end
            end
            if not best then
                vim.notify("Extracted — rename the placeholder manually", vim.log.levels.INFO)
                return
            end
            pcall(vim.api.nvim_win_set_cursor, 0, best)
            vim.lsp.buf.rename(name)
        end, 200)
    end
    poll()
end

-- Resolve-then-apply, mirroring what vim.lsp.buf.code_action does after its
-- picker: result items are Command | CodeAction, and CodeActions may need a
-- codeAction/resolve round-trip to fill in their edit. The exec_cmd context
-- must carry the ORIGINAL codeAction request params — client-side command
-- handlers read them (nvim-jdtls feeds ctx.params straight into java/move &
-- friends, and a nil there comes back as a server "Internal error").
local function apply_action(item, bufnr)
    local client = vim.lsp.get_client_by_id(item.client_id)
    if not client then
        return
    end
    local ctx = { bufnr = bufnr, method = "textDocument/codeAction", params = item.request_params }
    local function run(action)
        if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
        end
        if type(action.command) == "string" then
            -- the item itself is a bare Command
            client:exec_cmd({ title = action.title, command = action.command, arguments = action.arguments }, ctx)
        elseif type(action.command) == "table" then
            client:exec_cmd(action.command, ctx)
        end
    end
    local action = item.action
    local function proceed()
        if type(action.command) ~= "string" and not action.edit and client:supports_method("codeAction/resolve") then
            client:request("codeAction/resolve", action, function(err, resolved)
                run(resolved or action) -- unresolvable: try what the server sent
            end, bufnr)
        else
            run(action)
        end
    end

    -- Extract flow: name first, then apply + rename placeholder.
    -- Cancelling the prompt cancels the whole extraction.
    if (action.kind or ""):find("^refactor%.extract") then
        vim.ui.input({ prompt = "Extract as: " }, function(name)
            if not name or name == "" then
                return
            end
            rename_extracted(bufnr, name)
            proceed()
        end)
        return
    end
    proceed()
end

-- Collect entries (LSP + treesj) and hand them to cb — separated from the
-- menu so it can be tested headlessly.
function M._entries(cb)
    local bufnr = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    local mode = vim.api.nvim_get_mode().mode

    -- Selection range while still in visual mode ('< '> only update on exit).
    -- Linewise V spans whole lines — getpos cols are cursor cols, and a
    -- range cut mid-statement makes servers refuse refactors ("Cannot
    -- extract range") that the full lines would support.
    local range
    if mode:find("[vV\22]") then
        local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
        if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then
            s, e = e, s
        end
        if mode == "V" then
            range = { start_pos = { s[2], 0 }, end_pos = { e[2], #vim.fn.getline(e[2]) } }
        else
            range = { start_pos = { s[2], s[3] - 1 }, end_pos = { e[2], e[3] - 1 } }
        end
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end

    -- bottom section: IDE-style intentions (invert if, loop
    -- conversions, surround with try/catch — util/intentions.lua), then the
    -- treesj split/join. A visual selection narrows this to wrapping the
    -- selected lines; cursor intentions and treesj don't apply to a range.
    local sel = range and { range.start_pos[1], range.end_pos[1] }
    local extras = require("util.intentions").entries(bufnr, nil, sel)
    if not sel then
        vim.list_extend(extras, treesj_entries(bufnr))
    end
    local lnum = vim.api.nvim_win_get_cursor(win)[1] - 1

    local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
    if #clients == 0 then
        return cb(extras, bufnr)
    end

    -- kept per client (offset encodings differ) for exec_cmd's context
    local params_by_client = {}
    vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", function(client)
        local params
        if range then
            params = vim.lsp.util.make_given_range_params(range.start_pos, range.end_pos, bufnr, client.offset_encoding)
        else
            params = vim.lsp.util.make_range_params(win, client.offset_encoding)
        end
        params.context = {
            triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
            diagnostics = vim.lsp.diagnostic.from(vim.diagnostic.get(bufnr, { lnum = lnum })),
        }
        params_by_client[client.id] = params
        return params
    end, function(results)
        local collected = {}
        for _, item in ipairs(M._dedupe(results)) do
            local action, client_id = item.action, item.client_id
            local group = group_for(action.kind)
            -- a selection menu is about the selection: file/class-scoped
            -- generators (organize imports, generate getters, …) drop out
            if range and group.rank == 3 then
                goto continue
            end
            collected[#collected + 1] = {
                label = action.title,
                rank = group.rank,
                group_label = group.label,
                -- servers mark the fix they'd apply themselves; it leads
                preferred = action.isPreferred and 0 or 1,
                order = #collected,
                run = function()
                    apply_action({
                        action = action,
                        client_id = client_id,
                        request_params = params_by_client[client_id],
                    }, bufnr)
                end,
            }
            ::continue::
        end
        table.sort(collected, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            if a.preferred ~= b.preferred then
                return a.preferred < b.preferred
            end
            return a.order < b.order -- otherwise keep server order
        end)
        -- labeled rule between groups; skipped when everything is one group,
        -- so small menus stay a plain list
        local ranks = {}
        for _, item in ipairs(collected) do
            ranks[item.rank] = true
        end
        local multi_group = vim.tbl_count(ranks) > 1
        local entries, last_rank = {}, nil
        for _, item in ipairs(collected) do
            if multi_group and item.rank ~= last_rank then
                entries[#entries + 1] = { header = item.group_label }
                last_rank = item.rank
            end
            entries[#entries + 1] = item
        end
        if #entries > 0 and #extras > 0 then
            entries[#entries + 1] = { sep = true }
        end
        vim.list_extend(entries, extras)
        cb(entries, bufnr)
    end)
end

-- One row per title: jdtls sends its generators twice — a kindless quick
-- assist and a source.generate.* action with the same title. The kinded
-- copy wins, it is the one that knows which group it belongs to.
-- results: client_id -> { result = CodeAction[] }, as buf_request_all
-- hands them over; returns { { action, client_id } } in arrival order.
local function dedupe_results(results)
    local picked, by_title = {}, {}
    for client_id, res in pairs(results or {}) do
        for _, action in ipairs(res.result or {}) do
            -- category placeholders the server itself marks unrunnable
            -- (vtsls: "Extract function" with "Cannot extract range")
            if action.disabled then
                goto continue
            end
            local prev = by_title[action.title]
            if not prev then
                picked[#picked + 1] = { action = action, client_id = client_id }
                by_title[action.title] = picked[#picked]
            elseif (prev.action.kind or "") == "" and (action.kind or "") ~= "" then
                prev.action, prev.client_id = action, client_id
            end
            ::continue::
        end
    end
    return picked
end

-- Exposed for headless tests.
M._show_menu = show_menu
M._dedupe = dedupe_results

function M.open()
    M._entries(function(entries)
        if #entries == 0 then
            vim.notify("No code actions here", vim.log.levels.INFO)
            return
        end
        show_menu(entries)
    end)
end

return M
