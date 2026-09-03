-- gs (bound in plugins/lsp.lua) — the *structure* of the file, the way an
-- IDE's structure pane shows it: classes, interfaces, enums, their members,
-- and the top-level functions/constants around them.
--
-- Telescope's stock lsp_document_symbols flattens the server's whole tree, so
-- every temporary inside every method body is a row. On one small Angular
-- component a single `load()` contributed url / attempts / onDone / r / first
-- — rows that only mean anything while you are already reading that method,
-- and that push the class's actual members off the screen. lua_ls is worse
-- again: it reports the *contents* of every table literal, so a config table
-- of fifteen booleans is fifteen rows.
--
-- Two rules, both positional rather than a kind blacklist (a blacklist would
-- have to drop Variable, and a top-level `const PAGE_SIZE = 25` or an
-- interface's fields are variables that belong in an outline):
--
--   1. Anything inside something with a *body* is a local. Method, Function
--      and Constructor are the obvious ones; the test is on ancestors, so a
--      named closure nested in a method goes too.
--   2. Anything inside a *value* — a table/object/array literal, a variable,
--      a property — is the shape of that literal, not structure. Unless it
--      contains a function or a type, in which case it is exactly what you
--      opened the outline for: `export default { methods: { save() {} } }`
--      keeps save(), and lua's `nvim_create_autocmd { callback = function`
--      keeps the callback.
--
-- Rule 2 is what covers the accessor and the arrow-function class field —
-- tsserver reports both `get count()` and `onSave = () => {…}` as Property,
-- with the body's locals as children.
--
-- Rule 2 applies only to files that contain some code structure to begin
-- with. In a *document* — an Angular template, an HTML page, a JSON file —
-- the nested literals are the content, and the DOM/object tree is the whole
-- point of asking for an outline; there is nothing to demote them in favour
-- of. A .ts file holding nothing but `export const environment = {…}` is a
-- document by that test too, which is the right answer for it.
--
-- Locals are filtered, not discarded: <C-l> brings them back without a second
-- request, the way the test/dependency toggles work in util/references.lua.
local M = {}

local KIND = vim.lsp.protocol.SymbolKind

-- Rule 1: kinds that own a body. Anything nested inside one is a local.
local BODY = {
    [KIND.Method] = true,
    [KIND.Constructor] = true,
    [KIND.Function] = true,
}

-- Rule 2: kinds whose members describe a value rather than a scope.
local VALUE = {
    [KIND.Variable] = true,
    [KIND.Constant] = true,
    [KIND.Property] = true,
    [KIND.Field] = true,
    [KIND.Object] = true,
    [KIND.Array] = true,
    [KIND.Key] = true,
    [KIND.String] = true,
    [KIND.Number] = true,
    [KIND.Boolean] = true,
    [KIND.Null] = true,
}

-- …and what rescues a member of one: something you would navigate *to*.
local STRUCTURE = {
    [KIND.Method] = true,
    [KIND.Constructor] = true,
    [KIND.Function] = true,
    [KIND.Class] = true,
    [KIND.Interface] = true,
    [KIND.Enum] = true,
    [KIND.Struct] = true,
    [KIND.Module] = true,
    [KIND.Namespace] = true,
    [KIND.Package] = true,
}

-- True when the node is, or contains, something from STRUCTURE.
local function holds_structure(node)
    if node._holds == nil then
        node._holds = STRUCTURE[node.kind] or false
        for _, child in ipairs(node.children or {}) do
            if holds_structure(child) then
                node._holds = true
            end
        end
    end
    return node._holds
end

local function range_of(sym)
    return sym.range or (sym.location and sym.location.range)
end

-- Both documentSymbol replies, normalised: DocumentSymbol (hierarchical,
-- `children`) and SymbolInformation (flat, `location`). Anything without a
-- range is dropped — it can't be navigated to or nested.
local function to_nodes(result)
    local nodes, flat = {}, false
    for _, sym in ipairs(result or {}) do
        local range = range_of(sym)
        if range and sym.name then
            local children, child_flat
            if sym.children then
                children, child_flat = to_nodes(sym.children)
            end
            flat = flat or sym.location ~= nil or child_flat
            nodes[#nodes + 1] = {
                name = sym.name,
                kind = sym.kind or KIND.Variable,
                detail = sym.detail,
                range = range,
                sel = sym.selectionRange or range,
                children = children,
            }
        end
    end
    return nodes, flat
end

local function contains(outer, inner)
    local os_, oe = outer.start, outer["end"]
    local is_, ie = inner.start, inner["end"]
    local after_start = is_.line > os_.line or (is_.line == os_.line and is_.character >= os_.character)
    local before_end = ie.line < oe.line or (ie.line == oe.line and ie.character <= oe.character)
    return after_start and before_end
end

-- Containment order: by where the symbol *starts*, widest first, so an
-- enclosing symbol always precedes what it encloses.
local function by_extent(a, b)
    local x, y = a.range.start, b.range.start
    if x.line ~= y.line then
        return x.line < y.line
    end
    if x.character ~= y.character then
        return x.character < y.character
    end
    return a.range["end"].line > b.range["end"].line
end

-- Display order: by where the symbol's *name* is. A decorated symbol's range
-- starts at its decorator, so ordering an Angular component's members by
-- range puts `@Component({…})`'s class ahead of things written above it and
-- the line numbers in the list read backwards.
local function by_name_position(a, b)
    local x, y = a.sel.start, b.sel.start
    if x.line ~= y.line then
        return x.line < y.line
    end
    if x.character ~= y.character then
        return x.character < y.character
    end
    return by_extent(a, b)
end

local function node_key(node)
    return ("%d|%d|%d|%d|%d|%s"):format(node.kind, node.range.start.line,
        node.range.start.character, node.range["end"].line, node.range["end"].character, node.name)
end

-- Two servers answer for the same .ts file in an Angular project, and they
-- describe the *same* symbol differently: both report the component class
-- over the same range, but vtsls fills it with the class's members while
-- angularls fills it with the inline template's DOM. Dropping the duplicate
-- loses whichever half arrived second — it silently emptied every Angular
-- component of its members — and keeping both lists the class twice. So
-- merge them: one node, children unioned, recursively. It runs before the
-- range nesting below, not after: with a flat reply the containment test
-- reads an identical range as "inside", so a duplicate class would nest
-- under itself rather than merely repeat.
local function merge(list)
    local out, by_key = {}, {}
    for _, node in ipairs(list) do
        local key = node_key(node)
        local kept = by_key[key]
        if kept then
            if node.children then
                kept.children = merge(vim.list_extend(kept.children or {}, node.children))
            end
        else
            by_key[key] = node
            out[#out + 1] = node
            if node.children then
                node.children = merge(node.children)
            end
        end
    end
    return out
end

-- SymbolInformation carries no hierarchy — only a `containerName`, which is
-- a name and not an identity (two `handle()` methods in two classes are
-- indistinguishable by it). Ranges are an identity, so nest by containment.
local function nest_by_range(nodes)
    table.sort(nodes, by_extent)
    local roots, stack = {}, {}
    for _, node in ipairs(nodes) do
        while #stack > 0 and not contains(stack[#stack].range, node.range) do
            table.remove(stack)
        end
        local parent = stack[#stack]
        if parent then
            parent.children = parent.children or {}
            table.insert(parent.children, node)
        else
            roots[#roots + 1] = node
        end
        stack[#stack + 1] = node
    end
    return roots
end

-- Flatten to display rows in document order. Servers are free to answer in
-- any order and vtsls answers *alphabetically*, which is not how you read a
-- file — an outline that doesn't match the buffer is a worse map than none.
--
-- `hidden` marks a row that lives inside a body: kept in the list so the
-- <C-l> toggle costs no second request. Exposed for headless tests.
function M._flatten(nodes, flat)
    nodes = merge(nodes)
    if flat then
        nodes = nest_by_range(nodes)
    end
    -- Rule 2 only bites in files that have code in them (see the header).
    local value_rule = false
    for _, node in ipairs(nodes) do
        value_rule = value_rule or holds_structure(node)
    end
    local rows = {}
    local function walk(list, depth, in_body, in_value, path)
        table.sort(list, by_name_position)
        for _, node in ipairs(list) do
            local hidden = in_body or (in_value and value_rule and not holds_structure(node))
            rows[#rows + 1] = {
                name = node.name,
                kind = node.kind,
                detail = node.detail,
                depth = depth,
                hidden = hidden or false,
                path = path,
                lnum = node.sel.start.line + 1,
                col = node.sel.start.character + 1,
            }
            if node.children and #node.children > 0 then
                walk(
                    node.children,
                    depth + 1,
                    in_body or BODY[node.kind] or false,
                    VALUE[node.kind] or false,
                    path == "" and node.name or (path .. " " .. node.name)
                )
            end
        end
    end
    walk(nodes, 0, false, false, "")
    return rows
end

-- Ask every attached server, merge, flatten. cb(rows) — never called when no
-- server can answer (that case notifies instead). Separate from the picker so
-- it can be driven headlessly.
function M._gather(cb)
    local buf = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
    if #clients == 0 then
        vim.notify("No attached LSP provides document symbols here", vim.log.levels.WARN)
        return
    end
    vim.lsp.buf_request_all(buf, "textDocument/documentSymbol", function()
        return { textDocument = vim.lsp.util.make_text_document_params(buf) }
    end, function(results)
        local nodes, flat = {}, false
        for _, res in pairs(results or {}) do
            local part, part_flat = to_nodes(res.result)
            flat = flat or part_flat
            vim.list_extend(nodes, part)
        end
        cb(M._flatten(nodes, flat))
    end)
end

local function icon_for(kind)
    local name = (KIND[kind] or "Variable"):lower()
    local ok, mini = pcall(require, "mini.icons")
    if ok then
        local glyph, hl = mini.get("lsp", name)
        if glyph then
            return glyph, hl or "Comment"
        end
    end
    return "•", "Comment"
end

local badge_ns = vim.api.nvim_create_namespace("symbols_locals_badge")

-- Right-aligned filter badge in the prompt line, same style as the usages
-- picker's tests/deps badges (util/references.lua) and the Aa badge in
-- util/telescope_case.lua. The label never changes, only its highlight, so
-- the prompt doesn't reflow as you toggle.
local function place_badge(prompt_bufnr, state)
    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
            return
        end
        vim.api.nvim_buf_set_extmark(prompt_bufnr, badge_ns, 0, 0, {
            virt_text = { { " locals ⟨C-l⟩ ", state.hide_locals and "DiagnosticWarn" or "Comment" } },
            virt_text_pos = "right_align",
        })
    end)
end

function M.open()
    M._gather(function(rows)
        if #rows == 0 then
            vim.notify("No symbols in this file", vim.log.levels.INFO)
            return
        end

        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local filename = vim.api.nvim_buf_get_name(0)

        local locals = 0
        for _, row in ipairs(rows) do
            if row.hidden then
                locals = locals + 1
            end
        end

        -- Locals start hidden. They are never hidden past the point where
        -- nothing is left: a file whose symbols are *all* body-locals (a
        -- script with one top-level function's worth of code) would
        -- otherwise answer an empty picker, which is worse than a noisy one.
        local state = { hide_locals = locals > 0 and locals < #rows }

        local function entry_maker(row)
            local kind = (KIND[row.kind] or "Variable"):lower()
            return {
                value = row,
                ordinal = (row.path ~= "" and (row.path .. " ") or "") .. row.name .. " " .. kind,
                filename = filename,
                lnum = row.lnum,
                col = row.col,
                display = function(entry)
                    local it = entry.value
                    local pad = ("  "):rep(it.depth)
                    local icon, hl = icon_for(it.kind)
                    local head = pad .. icon
                    local text = head .. " " .. it.name
                    local tail = "  " .. kind .. (it.hidden and "  ·local" or "")
                    return text .. tail, {
                        { { #pad, #head }, hl },
                        { { #text, #text + #tail }, "Comment" },
                    }
                end,
            }
        end

        local function show(default_text)
            local shown = state.hide_locals
                and vim.tbl_filter(function(row)
                    return not row.hidden
                end, rows)
                or rows
            pickers
                .new({}, {
                    -- Never censor the outline of the file that is open:
                    -- telescope filters entries through file_ignore_patterns
                    -- by default, which would empty this picker outright for
                    -- a file opened inside node_modules/ or vendor/.
                    file_ignore_patterns = {},
                    prompt_title = "Symbols — "
                        .. vim.fn.fnamemodify(filename, ":t")
                        .. (state.hide_locals and (" — %d locals hidden"):format(locals) or ""),
                    default_text = default_text,
                    finder = finders.new_table({ results = shown, entry_maker = entry_maker }),
                    sorter = conf.generic_sorter({}),
                    previewer = conf.qflist_previewer({}),
                    attach_mappings = function(prompt_bufnr, map)
                        place_badge(prompt_bufnr, state)
                        map({ "i", "n" }, "<C-l>", function()
                            local line = require("telescope.actions.state").get_current_line()
                            require("telescope.actions").close(prompt_bufnr)
                            state.hide_locals = not state.hide_locals
                            show(line)
                        end, { desc = "Toggle locals inside method bodies" })
                        return true
                    end,
                })
                :find()
        end
        show()
    end)
end

return M
