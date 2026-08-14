-- IDE-style intentions the LSPs do not provide, fed into the actions
-- menu's bottom section (util/actions.lua) next to the treesj entries.
-- Treesitter-based, so each entry only appears where it applies:
--
--   Invert 'if' statement — negate the condition and swap the branches.
--     Single comparisons flip their operator (x > 3 → x <= 3), an already
--     negated condition loses its `!`/`not`, anything else is wrapped in
--     one. Without an else branch the guard-clause transformation applies
--     instead, when provably equivalent: an if that is the last statement
--     of a function/loop body becomes an early return/continue with the
--     body dedented after it; an `if (c) return;` guard folds its trailing
--     statements back in as `if (!c) { … }`; and a body that always exits
--     (throw, return) swaps with the trailing code — `if (!ok) { throw }
--     work` ⇄ `if (ok) { work } throw`, with an else when the trailing
--     code can fall through. Chains (else if / elif) are skipped rather
--     than half-inverted.
--   Surround with try/catch — wrap the statement under the cursor (or the
--     whole if/for/… it belongs to) in the language's try construct. With
--     a visual selection, wraps the selected lines instead.
--   Convert to foreach / indexed for (PHP, JS/TS) — only the provably safe
--     subset: an indexed for converts when the counter runs 0 → length,
--     is used exclusively as a read-only index of that one array, and the
--     array appears nowhere else in the body. Anything fancier is silently
--     not offered — a wrong conversion is worse than none.
--
-- Java and C# get "Invert if" / "Convert to foreach" from jdtls and roslyn
-- already (cursor on the keyword); these fill the gap for the rest, and
-- try/catch everywhere.
local M = {}

-- ------------------------------------------------------------- languages

-- not_fmt wraps a condition; comparison operators flip via OPERATORS with
-- per-language overrides (Lua's ~=, PHP's ===).
local LANGS = {
    php = { not_fmt = "!(%s)", try = { "try {", "} catch (\\Throwable $th) {", "}" } },
    javascript = { not_fmt = "!(%s)", try = { "try {", "} catch (error) {", "}" } },
    typescript = { not_fmt = "!(%s)", try = { "try {", "} catch (error) {", "}" } },
    tsx = { not_fmt = "!(%s)", try = { "try {", "} catch (error) {", "}" } },
    java = { not_fmt = "!(%s)", try = { "try {", "} catch (Exception e) {", "}" } },
    c_sharp = { not_fmt = "!(%s)", try = { "try {", "} catch (Exception e) {", "}" } },
    python = { not_fmt = "not (%s)", try_label = "Surround with try/except" },
    lua = { not_fmt = "not (%s)" }, -- no try construct; invert only
}

local OPERATORS = {
    [">"] = "<=",
    ["<"] = ">=",
    [">="] = "<",
    ["<="] = ">",
    ["=="] = "!=",
    ["!="] = "==",
}
local OPERATOR_OVERRIDES = {
    lua = { ["=="] = "~=", ["~="] = "==", ["!="] = false },
    php = { ["==="] = "!==", ["!=="] = "===" },
}

local UNARY = { unary_expression = true, not_operator = true, unary_op_expression = true }

-- ----------------------------------------------------------------- edits

local function text_of(node, bufnr)
    return vim.treesitter.get_node_text(node, bufnr)
end

local function indent_unit(bufnr)
    local sw = vim.fn.shiftwidth()
    return vim.bo[bufnr].expandtab and string.rep(" ", sw) or "\t"
end

-- apply {node-or-range, lines} replacements bottom-up so earlier ranges
-- stay valid
local function apply_edits(bufnr, edits)
    table.sort(edits, function(a, b)
        if a.range[1] ~= b.range[1] then
            return a.range[1] > b.range[1]
        end
        return a.range[2] > b.range[2]
    end)
    for _, e in ipairs(edits) do
        local sr, sc, er, ec = unpack(e.range)
        vim.api.nvim_buf_set_text(bufnr, sr, sc, er, ec, e.lines)
    end
end

local function node_at_cursor(bufnr, lang)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok or not parser then
        return nil
    end
    local trees = parser:parse()
    if not trees or not trees[1] then
        return nil
    end
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    return trees[1]:root():named_descendant_for_range(row - 1, col, row - 1, col)
end

-- ------------------------------------------------------------- invert if

-- the actual branch node inside an else clause, or nil for else-if chains
local function else_block(alt)
    if alt:type() == "if_statement" then
        return nil -- java/c_sharp: `else if` puts the if directly in the field
    end
    if alt:type():find("else") then
        local inner = alt:named_child(alt:named_child_count() - 1)
        if not inner or inner:type() == "if_statement" then
            return nil
        end
        return inner
    end
    return alt -- java/c_sharp: the field is the block itself
end

-- new condition text: strip an existing negation, else flip a lone
-- comparison operator (returned as a range edit), else wrap in not
local function negate(cond, bufnr, lang)
    local inner = cond
    if inner:type() == "parenthesized_expression" then
        inner = inner:named_child(0)
    end
    if not inner then
        return nil
    end

    if UNARY[inner:type()] then
        local txt = text_of(inner, bufnr)
        if txt:match("^!") or txt:match("^not[%s(]") then
            local arg = inner:named_child(inner:named_child_count() - 1)
            if arg and arg:type() == "parenthesized_expression" and arg:named_child_count() == 1 then
                arg = arg:named_child(0)
            end
            if arg then
                return { range = { inner:range() }, lines = { text_of(arg, bufnr) } }
            end
        end
    end

    local ops = vim.tbl_extend("force", OPERATORS, OPERATOR_OVERRIDES[lang] or {})
    local op = inner:field("operator")[1] or inner:field("operators")[1]
    if op then
        local flipped = ops[text_of(op, bufnr)]
        if flipped then
            return { range = { op:range() }, lines = { flipped } }
        end
    end

    local fmt = LANGS[lang].not_fmt
    return { range = { inner:range() }, lines = { fmt:format(text_of(inner, bufnr)) } }
end

-- the if_statement at the cursor, unless it is an elif/elseif chain
local function find_if(bufnr, lang)
    local node = node_at_cursor(bufnr, lang)
    while node and node:type() ~= "if_statement" do
        node = node:parent()
    end
    if not node then
        return nil
    end
    for child in node:iter_children() do
        if child:type():find("elif") or child:type():find("elseif") then
            return nil
        end
    end
    return node
end

local function invert_if_edits(bufnr, lang, node)
    local cons = node:field("consequence")[1] or node:field("body")[1]
    local alt = node:field("alternative")[1]
    local cond = node:field("condition")[1]
    if not (cons and alt and cond) then
        return nil
    end
    local other = else_block(alt)
    if not other then
        return nil
    end
    local cond_edit = negate(cond, bufnr, lang)
    if not cond_edit then
        return nil
    end
    return {
        cond_edit,
        { range = { cons:range() }, lines = vim.split(text_of(other, bufnr), "\n") },
        { range = { other:range() }, lines = vim.split(text_of(cons, bufnr), "\n") },
    }
end

-- ---------------------------------------------------- guard-clause invert

-- The no-else cases, applied only where the rewrite is provably
-- equivalent. `return` semantics demand the if's block be the direct body
-- of a function (a guard in a nested block would skip code outside it);
-- `continue` likewise a direct loop body. `break` never qualifies — it
-- ends the whole loop, which `if (!c)` around the rest would not.
local FUNCTION_OWNERS = {
    function_declaration = true,
    function_definition = true,
    function_expression = true,
    arrow_function = true,
    method_declaration = true,
    method_definition = true,
    constructor_declaration = true,
    local_function = true,
    local_function_statement = true,
    lambda_expression = true,
    anonymous_function = true,
    anonymous_function_creation_expression = true,
}
local LOOP_OWNERS = {
    for_statement = true,
    while_statement = true,
    foreach_statement = true,
    for_in_statement = true,
    do_statement = true,
}
local BLOCKS = { block = true, statement_block = true, compound_statement = true }

-- the negated condition as bare text (no outer parens), or nil when the
-- condition spans lines — the guard paths rebuild the header from scratch
local function negated_condition_text(cond, bufnr, lang)
    local inner = cond
    if inner:type() == "parenthesized_expression" then
        inner = inner:named_child(0)
    end
    if not inner then
        return nil
    end
    local isr, isc, ier = inner:range()
    if isr ~= ier then
        return nil
    end
    local edit = negate(cond, bufnr, lang)
    if not edit then
        return nil
    end
    local esr, esc, eer, eec = unpack(edit.range)
    if esr ~= isr or eer ~= isr then
        return nil
    end
    local itext = text_of(inner, bufnr)
    return itext:sub(1, esc - isc) .. edit.lines[1] .. itext:sub(eec - isc + 1)
end

local EXITS = { return_statement = "return", continue_statement = "continue" }

-- statements that unconditionally leave the function
local HARD_EXITS = { return_statement = true, throw_statement = true, raise_statement = true }

-- does this block (or single statement) always exit at its end?
local function always_exits(node)
    local last = node
    if BLOCKS[node:type()] then
        if node:named_child_count() == 0 then
            return false
        end
        last = node:named_child(node:named_child_count() - 1)
    end
    if HARD_EXITS[last:type()] then
        return true
    end
    -- php: throw is an expression (throw_expression in a statement)
    local inner = last:type() == "expression_statement" and last:named_child(0)
    return (inner and inner:type() == "throw_expression") or false
end

-- body that is exactly a bare exit statement (no value), possibly braced
local function lone_exit(body)
    if EXITS[body:type()] and body:named_child_count() == 0 then
        return EXITS[body:type()]
    end
    if BLOCKS[body:type()] and body:named_child_count() == 1 then
        local only = body:named_child(0)
        if EXITS[only:type()] and only:named_child_count() == 0 then
            return EXITS[only:type()]
        end
    end
end

local function dedent(line, unit)
    if line == "" then
        return line
    end
    return line:sub(1, #unit) == unit and line:sub(#unit + 1) or line:gsub("^%s?%s?%s?%s?", "", 1)
end

-- if (c) { A }  as the LAST statement of a function/loop body
--   → if (!c) exit; A   (A dedented one level)
-- if (c) exit;  with trailing statements B in a function/loop body
--   → if (!c) { B }
local function guard_invert(bufnr, lang, node)
    local cfg = LANGS[lang]
    local body = node:field("consequence")[1] or node:field("body")[1]
    local cond = node:field("condition")[1]
    local block = node:parent()
    if node:field("alternative")[1] then
        return nil -- an else/else-if belongs to the branch-swap path only
    end
    if not (body and cond and block and (BLOCKS[block:type()] or (lang == "lua" and block:type() == "block"))) then
        return nil
    end
    local owner = block:parent()
    local exit_kw -- nil when the block is not a direct function/loop body;
    -- only the fold/flip cases need it, the exit-swap works in any block
    if owner and FUNCTION_OWNERS[owner:type()] then
        exit_kw = "return"
    elseif owner and LOOP_OWNERS[owner:type()] and lang ~= "lua" then
        exit_kw = "continue" -- lua has no continue; loops stay untouched
    end
    local neg = negated_condition_text(cond, bufnr, lang)
    if not neg then
        return nil
    end

    local srow, _, erow = node:range()
    local first = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, false)[1]
    local indent = first:match("^%s*")
    local unit = indent_unit(bufnr)
    local semi = (lang == "python" or lang == "lua") and "" or ";"
    local function header(t)
        if lang == "python" then
            return indent .. "if " .. t .. ":"
        elseif lang == "lua" then
            return indent .. "if " .. t .. " then"
        end
        return indent .. "if (" .. t .. ") {"
    end
    local footer -- python blocks close by dedent alone
    if lang == "lua" then
        footer = indent .. "end"
    elseif lang ~= "python" then
        footer = indent .. "}"
    end

    local is_last = block:named_child(block:named_child_count() - 1) == node
    local exit_body = lone_exit(body)

    -- trailing region: statements after the if, to the end of the block
    local block_erow = select(3, block:range())
    local inner_end = (lang == "python" or lang == "lua") and block_erow or block_erow - 1

    if exit_body and exit_body == exit_kw and inner_end > erow then
        -- bare-exit guard → fold the trailing statements into the if
        return function()
            local trailing = vim.api.nvim_buf_get_lines(bufnr, erow + 1, inner_end + 1, false)
            local new = { header(neg) }
            for _, l in ipairs(trailing) do
                new[#new + 1] = l == "" and l or unit .. l
            end
            if footer then
                new[#new + 1] = footer
            end
            vim.api.nvim_buf_set_lines(bufnr, srow, inner_end + 1, false, new)
        end
    end

    if not is_last and BLOCKS[body:type()] and always_exits(body) and inner_end > erow then
        -- exit-swap: the body always leaves the function (throw, return),
        -- so the trailing code becomes the body and the old body moves
        -- after the if — or into an else when the trailing code can fall
        -- through. Valid in any block, no owner constraint needed.
        local bsr, _, ber = body:range()
        local bfrom, bto
        if lang == "python" or lang == "lua" then
            bfrom, bto = bsr, ber
        else
            if ber <= bsr then
                return nil -- one-line { … } body
            end
            bfrom, bto = bsr + 1, ber - 1
        end
        local t_exits = always_exits(block:named_child(block:named_child_count() - 1))
        return function()
            local trailing = vim.api.nvim_buf_get_lines(bufnr, erow + 1, inner_end + 1, false)
            while trailing[1] == "" do
                table.remove(trailing, 1)
            end
            local a_lines = vim.api.nvim_buf_get_lines(bufnr, bfrom, bto + 1, false)
            local new = { header(neg) }
            for _, l in ipairs(trailing) do
                new[#new + 1] = l == "" and l or unit .. l
            end
            if t_exits then
                if footer then
                    new[#new + 1] = footer
                end
                for _, l in ipairs(a_lines) do
                    new[#new + 1] = dedent(l, unit)
                end
            else
                if lang == "python" then
                    new[#new + 1] = indent .. "else:"
                elseif lang == "lua" then
                    new[#new + 1] = indent .. "else"
                else
                    new[#new + 1] = indent .. "} else {"
                end
                vim.list_extend(new, a_lines)
                if lang == "lua" then
                    new[#new + 1] = indent .. "end"
                elseif lang ~= "python" then
                    new[#new + 1] = indent .. "}"
                end
            end
            vim.api.nvim_buf_set_lines(bufnr, srow, inner_end + 1, false, new)
        end
    end

    if is_last and BLOCKS[body:type()] and exit_kw and not exit_body then
        -- last statement → guard-flip; body must span its own lines
        local bsr, _, ber = body:range()
        local inner_from, inner_to
        if lang == "python" or lang == "lua" then
            inner_from, inner_to = bsr, ber
        else
            if ber <= bsr then
                return nil -- one-line { … } body: nothing to dedent cleanly
            end
            inner_from, inner_to = bsr + 1, ber - 1
        end
        if inner_to < inner_from then
            return nil
        end
        return function()
            local inner = vim.api.nvim_buf_get_lines(bufnr, inner_from, inner_to + 1, false)
            local new = { header(neg), indent .. unit .. exit_kw .. semi }
            if footer then
                new[#new + 1] = footer
            end
            for _, l in ipairs(inner) do
                new[#new + 1] = dedent(l, unit)
            end
            vim.api.nvim_buf_set_lines(bufnr, srow, erow + 1, false, new)
        end
    end
end

-- ------------------------------------------------------------- try/catch

-- the innermost statement containing the cursor: on a
-- line inside a for body it wraps that line's statement; on the for
-- keyword itself it wraps the whole loop
local CONTAINERS = {
    block = true,
    statement_block = true,
    compound_statement = true,
    program = true,
    source_file = true,
    chunk = true,
    module = true,
}

local function statement_at_cursor(bufnr, lang)
    local node = node_at_cursor(bufnr, lang)
    while node and node:parent() and not CONTAINERS[node:parent():type()] do
        node = node:parent()
    end
    return node and node:parent() and node or nil
end

local function wrap_try(bufnr, lang, srow, erow)
    local lines = vim.api.nvim_buf_get_lines(bufnr, srow, erow + 1, false)
    local base = lines[1]:match("^%s*") or ""
    local unit = indent_unit(bufnr)
    local wrapped = {}
    local function add(l)
        wrapped[#wrapped + 1] = l
    end
    if lang == "python" then
        add(base .. "try:")
        for _, l in ipairs(lines) do
            add(l == "" and l or unit .. l)
        end
        add(base .. "except Exception:")
        add(base .. unit .. "raise")
    else
        local t = LANGS[lang].try
        add(base .. t[1])
        for _, l in ipairs(lines) do
            add(l == "" and l or unit .. l)
        end
        add(base .. t[2])
        add(base .. t[3])
    end
    vim.api.nvim_buf_set_lines(bufnr, srow, erow + 1, false, wrapped)
    -- cursor onto the catch/except line, ready to type the handler
    pcall(vim.api.nvim_win_set_cursor, 0, { srow + #lines + 2, 0 })
end

-- --------------------------------------------------------- for ⇄ foreach

-- a variable use that is written to (or referenced) can't be converted away
local function is_write_target(node)
    local parent = node:parent()
    if not parent then
        return false
    end
    local t = parent:type()
    if t == "update_expression" or t:find("by_ref") or t:find("reference") then
        return true
    end
    if t:find("assignment") then
        return parent:field("left")[1] == node
    end
    return false
end

-- Verify the safe subset inside the loop body: every use of ivar is the
-- index of xvar[ivar] and read-only, and xvar never appears outside those
-- subscripts (no xs.push, no xs = …, no aliasing). Returns the subscript
-- nodes to substitute, or nil when anything else is going on.
local function index_uses(body, bufnr, ivar, xvar)
    local subscripts = {}
    local function fail()
        subscripts = nil
    end
    local function walk(node)
        for child in node:iter_children() do
            if not subscripts then
                return
            end
            local t = child:type()
            local txt = (t == "identifier" or t == "variable_name") and text_of(child, bufnr) or nil
            if txt == ivar or txt == xvar then
                local sub = child:parent()
                if not sub or sub:type() ~= "subscript_expression" or is_write_target(sub) then
                    fail()
                    return
                end
                local object = sub:named_child(0)
                local index = sub:named_child(sub:named_child_count() - 1)
                if txt == ivar and (index ~= child or text_of(object, bufnr) ~= xvar) then
                    fail()
                    return
                end
                if txt == xvar and (object ~= child or text_of(index, bufnr) ~= ivar) then
                    fail()
                    return
                end
                subscripts[sub:id()] = sub
            end
            if t ~= "variable_name" then -- php: $i nests an identifier; count once
                walk(child)
            end
        end
    end
    walk(body)
    return subscripts
end

-- first of the candidates not occurring anywhere in the loop text
local function free_name(candidates, loop_text)
    for _, name in ipairs(candidates) do
        if not loop_text:find("%f[%w_$]" .. vim.pesc(name) .. "%f[^%w_]") then
            return name
        end
    end
end

local function element_candidates(xs, lang)
    local bare = xs:gsub("^%$", "")
    local names = {}
    if bare:match("s$") and #bare > 3 then
        names[#names + 1] = bare:sub(1, -2) -- items → item
    end
    vim.list_extend(names, { "item", "value", "entry" })
    if lang == "php" then
        for i, n in ipairs(names) do
            names[i] = "$" .. n
        end
    end
    return names
end

-- for (i = 0; i < <xs.length|count($xs)>; i++) → ivar, xvar, body
local function indexed_for_pieces(node, bufnr, lang)
    local body = node:field("body")[1]
    local cond = node:field("condition")[1]
    if not (body and cond and cond:type() == "binary_expression") then
        return nil
    end

    local ivar
    if lang == "php" then
        local init = node:field("initialize")[1]
        if not init or init:type() ~= "assignment_expression" then
            return nil
        end
        local left, right = init:field("left")[1], init:field("right")[1]
        if not (left and right) or left:type() ~= "variable_name" or text_of(right, bufnr) ~= "0" then
            return nil
        end
        ivar = text_of(left, bufnr)
    else
        local init = node:field("initializer")[1]
        if not init or not init:type():find("declaration") or init:named_child_count() ~= 1 then
            return nil
        end
        local decl = init:named_child(0)
        local name, value = decl:field("name")[1], decl:field("value")[1]
        if not (name and value) or name:type() ~= "identifier" or text_of(value, bufnr) ~= "0" then
            return nil
        end
        ivar = text_of(name, bufnr)
    end

    local op = cond:field("operator")[1]
    local left, right = cond:field("left")[1], cond:field("right")[1]
    if not (op and left and right) or text_of(op, bufnr) ~= "<" or text_of(left, bufnr) ~= ivar then
        return nil
    end
    local xvar
    if lang == "php" then
        -- $i < count($xs) / sizeof($xs)
        if right:type() ~= "function_call_expression" then
            return nil
        end
        local fn = right:field("function")[1]
        local args = right:field("arguments")[1]
        if not (fn and args) or not vim.tbl_contains({ "count", "sizeof" }, text_of(fn, bufnr)) then
            return nil
        end
        if args:named_child_count() ~= 1 then
            return nil
        end
        local arg = text_of(args:named_child(0), bufnr)
        if not arg:match("^%$[%w_]+$") then
            return nil
        end
        xvar = arg
    else
        -- i < xs.length
        if right:type() ~= "member_expression" then
            return nil
        end
        local obj, prop = right:field("object")[1], right:field("property")[1]
        if not (obj and prop) or obj:type() ~= "identifier" or text_of(prop, bufnr) ~= "length" then
            return nil
        end
        xvar = text_of(obj, bufnr)
    end

    local inc = node:field(lang == "php" and "update" or "increment")[1]
    if not inc then
        return nil
    end
    local itxt = text_of(inc, bufnr):gsub("%s", "")
    if itxt ~= ivar .. "++" and itxt ~= "++" .. ivar and itxt ~= ivar .. "+=1" then
        return nil
    end

    return ivar, xvar, body
end

local function to_foreach_edits(bufnr, lang, node)
    local ivar, xvar, body = indexed_for_pieces(node, bufnr, lang)
    if not ivar then
        return nil
    end
    local subscripts = index_uses(body, bufnr, ivar, xvar)
    if not subscripts then
        return nil
    end
    local elem = free_name(element_candidates(xvar, lang), text_of(node, bufnr))
    if not elem then
        return nil
    end
    local header
    if lang == "php" then
        header = ("foreach (%s as %s) "):format(xvar, elem)
    else
        header = ("for (const %s of %s) "):format(elem, xvar)
    end
    local sr, sc = node:range()
    local br, bc = body:range()
    local edits = { { range = { sr, sc, br, bc }, lines = { header } } }
    for _, sub in pairs(subscripts) do
        edits[#edits + 1] = { range = { sub:range() }, lines = { elem } }
    end
    return edits
end

-- foreach ($xs as $x) / for (const x of xs) → indexed for. The element
-- var becomes the body's first line, so the body must be a multi-line
-- block with nothing on the brace line.
local function to_indexed_for(bufnr, lang, node)
    local xvar, evar, kind, body
    if lang == "php" then
        if node:named_child_count() ~= 3 then
            return nil -- $k => $v or &$v forms
        end
        local coll, val = node:named_child(0), node:named_child(1)
        body = node:field("body")[1]
        if coll:type() ~= "variable_name" or val:type() ~= "variable_name" then
            return nil
        end
        xvar, evar = text_of(coll, bufnr), text_of(val, bufnr)
    else
        local op = node:field("operator")[1]
        local right = node:field("right")[1]
        body = node:field("body")[1]
        if not (op and right and body) or text_of(op, bufnr) ~= "of" or right:type() ~= "identifier" then
            return nil
        end
        xvar = text_of(right, bufnr)
        evar = text_of(node:field("left")[1], bufnr)
        kind = text_of(node:field("kind")[1], bufnr)
    end
    local br = body:range()
    local first = body:named_child(0)
    if not first or select(1, first:range()) == br then
        return nil -- single-line body: nowhere to put the element line
    end
    local idx = free_name(
        lang == "php" and { "$i", "$j", "$k", "$index" } or { "i", "j", "k", "index" },
        text_of(node, bufnr)
    )
    if not idx then
        return nil
    end
    return function()
        local frow, fcol = first:range()
        local indent = string.rep(" ", fcol)
        if not vim.bo[bufnr].expandtab then
            indent = vim.api.nvim_buf_get_lines(bufnr, frow, frow + 1, false)[1]:match("^%s*")
        end
        local assign, header
        if lang == "php" then
            assign = ("%s%s = %s[%s];"):format(indent, evar, xvar, idx)
            header = ("for (%s = 0; %s < count(%s); %s++) "):format(idx, idx, xvar, idx)
        else
            assign = ("%s%s %s = %s[%s];"):format(indent, kind, evar, xvar, idx)
            header = ("for (let %s = 0; %s < %s.length; %s++) "):format(idx, idx, xvar, idx)
        end
        local sr, sc = node:range()
        local brow, bcol = body:range()
        vim.api.nvim_buf_set_lines(bufnr, brow + 1, brow + 1, false, { assign })
        vim.api.nvim_buf_set_text(bufnr, sr, sc, brow, bcol, { header })
    end
end

local CONVERT_LANGS = { php = true, javascript = true, typescript = true, tsx = true }
local FOR_NODES = { for_statement = true, for_in_statement = true, foreach_statement = true }

local function loop_conversion(bufnr, lang)
    if not CONVERT_LANGS[lang] then
        return nil
    end
    local node = node_at_cursor(bufnr, lang)
    while node and not FOR_NODES[node:type()] do
        node = node:parent()
    end
    if not node then
        return nil
    end
    if node:type() == "for_statement" then
        local edits = to_foreach_edits(bufnr, lang, node)
        if edits then
            return {
                label = lang == "php" and "Convert to 'foreach'" or "Convert to 'for…of' loop",
                run = function()
                    local e = to_foreach_edits(bufnr, lang, node)
                    if e then
                        apply_edits(bufnr, e)
                    end
                end,
            }
        end
    else
        local run = to_indexed_for(bufnr, lang, node)
        if run then
            return { label = "Convert to indexed 'for' loop", run = run }
        end
    end
end

-- ------------------------------------------------------------------ menu

-- Entries that apply at the cursor right now, for util/actions.lua.
-- lang is derived from the buffer unless given (tests pass it directly).
-- sel = { start_line, end_line } (1-based) when invoked on a visual
-- selection: the menu then offers wrapping those exact lines and skips the
-- cursor-based intentions.
function M.entries(bufnr, lang, sel)
    lang = lang or vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
    local cfg = lang and LANGS[lang]
    if not cfg then
        return {}
    end

    if sel then
        if not (cfg.try or lang == "python") then
            return {}
        end
        local srow, erow = sel[1] - 1, sel[2] - 1
        return {
            {
                label = cfg.try_label or "Surround with try/catch",
                run = function()
                    wrap_try(bufnr, lang, srow, erow)
                end,
            },
        }
    end

    local entries = {}

    local iok, ifnode = pcall(find_if, bufnr, lang)
    if iok and ifnode then
        local eok, edits = pcall(invert_if_edits, bufnr, lang, ifnode)
        if eok and edits then
            entries[#entries + 1] = {
                label = "Invert 'if' statement",
                run = function()
                    local n = find_if(bufnr, lang)
                    local e = n and invert_if_edits(bufnr, lang, n)
                    if e then
                        apply_edits(bufnr, e)
                    end
                end,
            }
        else
            -- no else branch: guard-clause transformation where provable
            local gok, guard = pcall(guard_invert, bufnr, lang, ifnode)
            if gok and guard then
                entries[#entries + 1] = { label = "Invert 'if' statement", run = guard }
            end
        end
    end

    local cok, convert = pcall(loop_conversion, bufnr, lang)
    if cok and convert then
        entries[#entries + 1] = convert
    end

    if cfg.try or lang == "python" then
        local sok, stmt = pcall(statement_at_cursor, bufnr, lang)
        if sok and stmt then
            entries[#entries + 1] = {
                label = cfg.try_label or "Surround with try/catch",
                run = function()
                    local s = statement_at_cursor(bufnr, lang)
                    if s then
                        local srow, _, erow = s:range()
                        wrap_try(bufnr, lang, srow, erow)
                    end
                end,
            }
        end
    end

    return entries
end

return M
