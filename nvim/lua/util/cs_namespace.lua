-- Namespace correctness for C# in Unity projects — the "Adjust namespaces"
-- refactor Rider offers, minus Rider.
--
-- The expected namespace of a file is the project's root namespace plus the
-- folders below the source root:
--
--   Assets/Scripts/_Core/Utility/UuidUtility.cs  ->  Inheritance._Core.Utility
--
-- Root namespace comes from the same place Rider reads it — Unity's
-- ProjectSettings/EditorSettings.asset (m_ProjectGenerationRootNamespace) —
-- with a per-project override stored on this machine for projects that leave
-- it blank (util/cs_namespace_ui.lua prompts for it once).
--
-- Source root is the nearest .asmdef directory (an assembly definition is its
-- own namespace root, and .asmdef carries a rootNamespace field), else the
-- Scripts/ directory under Assets/, else Assets/ itself.
--
-- Renaming a namespace breaks every reference to the types inside it, so
-- M.plan() returns the namespace edit *and* the using/qualified-name edits
-- that keep the project compiling.
--
-- Everything here is pure: it reads files, computes edits, and returns them.
-- Prompting, previewing and applying live in util/cs_namespace_ui.lua so this
-- half can run headlessly.

local unity = require("util.unity")

local M = {}

-- Per-project root-namespace overrides, keyed by absolute Unity project root.
-- Only written when EditorSettings.asset has no root namespace to read (or you
-- deliberately override it) — same JSON-in-state pattern as util/tasks.lua.
M.store_file = vim.fn.stdpath("state") .. "/cs_namespaces.json"

-- ------------------------------------------------------------------ store

local function read_store()
    local f = io.open(M.store_file, "r")
    if not f then
        return {}
    end
    local content = f:read("*a")
    f:close()
    if content == "" then
        return {}
    end
    local ok, data = pcall(vim.json.decode, content)
    return (ok and type(data) == "table") and data or {}
end

local function write_store(data)
    local f = io.open(M.store_file, "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

local function normalize(path)
    return (vim.fs.normalize(((path or ""):gsub("\\", "/"))))
end
M.normalize = normalize

function M.get_override(root)
    local ns = read_store()[normalize(root)]
    return (type(ns) == "string" and ns ~= "") and ns or nil
end

function M.set_override(root, ns)
    local data = read_store()
    data[normalize(root)] = ns
    write_store(data)
end

-- --------------------------------------------------------- root namespace

local function read_lines(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    return ok and lines or nil
end

-- m_ProjectGenerationRootNamespace in EditorSettings.asset is the value Unity
-- stamps into generated .csproj files and Rider derives namespaces from, so
-- reading it means a correctly configured project never has to be told twice.
local function editor_settings_ns(root)
    local lines = read_lines(root .. "/ProjectSettings/EditorSettings.asset")
    if not lines then
        return nil
    end
    for _, line in ipairs(lines) do
        local ns = line:match("^%s*m_ProjectGenerationRootNamespace:%s*(%S+)%s*$")
        if ns then
            return ns
        end
    end
    return nil
end

-- Nearest enclosing .asmdef: its directory is a namespace root of its own, and
-- since Unity 2020.2 it can name that namespace itself.
local function nearest_asmdef(path)
    local found = vim.fs.find(function(name)
        return name:match("%.asmdef$") ~= nil
    end, { path = vim.fs.dirname(normalize(path)), upward = true, limit = 1 })
    if not found[1] then
        return nil, nil
    end
    local dir = normalize(vim.fs.dirname(found[1]))
    local lines = read_lines(found[1])
    local ns
    if lines then
        local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        if ok and type(data) == "table" and type(data.rootNamespace) == "string" and data.rootNamespace ~= "" then
            ns = data.rootNamespace
        end
    end
    return dir, ns
end

function M.project_root(path)
    return unity.root(vim.fs.dirname(normalize(path)))
end

-- The project's root namespace, or nil when nothing declares one (the UI
-- prompts and stores it in that case).
function M.root_ns(path)
    local root = M.project_root(path)
    if not root then
        return nil
    end
    local _, asmdef_ns = nearest_asmdef(path)
    return M.get_override(root) or asmdef_ns or editor_settings_ns(root)
end

-- ----------------------------------------------------------- source root

-- Directory the namespace path is measured from. An .asmdef wins (it is a
-- separate assembly), then Assets/Scripts, then Assets.
function M.source_root(path)
    local root = M.project_root(path)
    if not root then
        return nil
    end
    local asmdef_dir = nearest_asmdef(path)
    if asmdef_dir then
        return asmdef_dir
    end
    local scripts = normalize(root) .. "/Assets/Scripts"
    local file = normalize(path)
    if vim.fn.isdirectory(scripts) == 1 and file:sub(1, #scripts + 1) == scripts .. "/" then
        return scripts
    end
    return normalize(root) .. "/Assets"
end

-- The namespace `path` should declare, or nil when this isn't a Unity C# file
-- or the root namespace is still unknown.
function M.expected(path)
    local file = normalize(path)
    if not file:match("%.cs$") then
        return nil
    end
    local root_ns = M.root_ns(file)
    local src = M.source_root(file)
    if not root_ns or not src then
        return nil
    end
    local dir = vim.fs.dirname(file)
    if dir ~= src and dir:sub(1, #src + 1) ~= src .. "/" then
        return root_ns -- outside the source root; nothing to append
    end
    local relative = dir:sub(#src + 2)
    if relative == "" then
        return root_ns
    end
    -- Unity allows spaces and dashes in folder names ("UI Toolkit"); those
    -- can't appear in an identifier, so strip them the way Rider does.
    local segments = { root_ns }
    for segment in relative:gmatch("[^/]+") do
        segments[#segments + 1] = (segment:gsub("[^%w_]", ""))
    end
    return table.concat(segments, ".")
end

-- ------------------------------------------------------------- C# parsing

-- Blank out comments, strings and char literals so brace counting and word
-- matching can't be thrown off by text inside them. Positions are preserved
-- (every removed character becomes a space) so a column found in the sanitized
-- copy still points at the same column of the real line.
local function sanitize(lines)
    local out, in_block = {}, false
    for index, line in ipairs(lines) do
        if index == 1 then
            -- Unity writes some scripts UTF-8 with a BOM, and readfile hands
            -- those three bytes over as part of line 1 — without stripping
            -- them "namespace" no longer starts the line.
            line = line:gsub("^\239\187\191", "")
        end
        local buf, i, n = {}, 1, #line
        while i <= n do
            local c = line:sub(i, i)
            if in_block then
                if line:sub(i, i + 1) == "*/" then
                    in_block, buf[#buf + 1], i = false, "  ", i + 2
                else
                    buf[#buf + 1], i = " ", i + 1
                end
            elseif line:sub(i, i + 1) == "//" then
                buf[#buf + 1] = string.rep(" ", n - i + 1)
                break
            elseif line:sub(i, i + 1) == "/*" then
                in_block, buf[#buf + 1], i = true, "  ", i + 2
            elseif c == '"' or c == "'" then
                local quote, j = c, i + 1
                buf[#buf + 1] = " "
                while j <= n do
                    local d = line:sub(j, j)
                    if d == "\\" then
                        buf[#buf + 1], j = "  ", j + 2
                    elseif d == quote then
                        buf[#buf + 1], j = " ", j + 1
                        break
                    else
                        buf[#buf + 1], j = " ", j + 1
                    end
                end
                i = j
            else
                buf[#buf + 1], i = c, i + 1
            end
        end
        out[#out + 1] = table.concat(buf)
    end
    return out
end
M._sanitize = sanitize

local TYPE_KEYWORDS = { "class", "struct", "interface", "enum", "record" }

-- Name of the type declared on this line, or nil. `record struct Foo` /
-- `record class Foo` would otherwise capture the second keyword, and a
-- delegate's name comes after its return type rather than after the keyword.
local function declared_type(line)
    line = line:gsub("%f[%w_]record%s+[%w_]*struct%f[^%w_]", "record"):gsub("%f[%w_]record%s+[%w_]*class%f[^%w_]", "record")
    for _, kw in ipairs(TYPE_KEYWORDS) do
        local name = line:match("%f[%w_]" .. kw .. "%s+([%w_]+)")
        if name then
            return name
        end
    end
    -- delegate <return type> Name(...) — the return type can itself be
    -- generic or an array, so take the identifier right before the ( or <.
    return line:match("%f[%w_]delegate%s+.-%s+([%w_]+)%s*[<(]")
end

-- What this file declares: its namespace (with the line it sits on), the
-- top-level type names inside it, and its `using` block. `lines` may come from
-- a buffer or from disk. Line numbers are 1-based.
function M.parse(lines)
    local clean = sanitize(lines)
    local info = {
        namespace = nil,
        ns_lnum = nil,
        file_scoped = false,
        types = {},
        usings = {},
        last_using = nil,
        first_code = nil,
    }
    local depth, ns_depth = 0, nil
    for i, line in ipairs(clean) do
        if not info.namespace then
            local ns, tail = line:match("^%s*namespace%s+([%w_.]+)%s*(.*)$")
            if ns then
                info.namespace, info.ns_lnum = ns, i
                info.file_scoped = tail:sub(1, 1) == ";"
                ns_depth = info.file_scoped and 0 or depth + 1
            end
        end
        local using = line:match("^%s*using%s+([%w_.]+)%s*;")
        if using and depth == 0 then
            info.usings[#info.usings + 1] = { name = using, lnum = i }
            info.last_using = i
        end
        -- Top-level types are the ones sitting directly in the namespace body
        -- (or at depth 0 in a file-scoped file); nested types keep their outer
        -- type's name and never move on their own.
        if depth == (ns_depth or 0) then
            local name = declared_type(line)
            if name then
                info.types[#info.types + 1] = name
            end
        end
        if not info.first_code and line:match("%S") then
            info.first_code = i
        end
        local _, opens = line:gsub("{", "")
        local _, closes = line:gsub("}", "")
        depth = depth + opens - closes
    end
    return info
end

-- Lines of `path`, from the loaded buffer when there is one so unsaved edits
-- are respected. Returns lines, bufnr (bufnr nil when read from disk).
function M.lines_of(path)
    local bufnr = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr
    end
    return read_lines(path), nil
end

-- The namespace `path` currently declares (nil when it declares none).
function M.current(path)
    local lines = M.lines_of(path)
    return lines and M.parse(lines).namespace or nil
end

-- nil when the file is fine; a descriptor when it isn't. `from` is nil for a
-- file that declares no namespace at all.
function M.mismatch(path)
    local file = normalize(path)
    local want = M.expected(file)
    if not want then
        return nil
    end
    local lines = M.lines_of(file)
    if not lines then
        return nil
    end
    local info = M.parse(lines)
    if info.namespace == want then
        return nil
    end
    return { path = file, from = info.namespace, to = want, info = info, lines = lines }
end

-- ------------------------------------------------------------ edit model
--
-- An edit is one line-level change with everything the preview needs:
--
--   { path, lnum, kind, before, after }
--
-- kind "namespace" rewrites the declaration, "wrap" wraps a namespace-less
-- file (handled whole-file, see apply_file), "using" retargets an existing
-- using, "add-using" inserts one, "qualified" rewrites an A.B.Type reference.
-- Edits carry original 1-based line numbers and are applied bottom-up, so
-- they never invalidate each other.

local function word_pattern(name)
    return "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
end

local function rg_escape(s)
    return (s:gsub("[%.%[%]%(%)%*%+%-%?%^%$|\\{}]", "\\%0"))
end

-- Does a file in namespace `from` see namespace `target` without a using?
-- C# resolves outward through the enclosing namespaces, so A.B.Sub sees A.B
-- and A, but never A.C.
local function sees(from, target)
    if not from then
        return false -- global namespace sees only what is global
    end
    return from == target or from:sub(1, #target + 1) == target .. "."
end

-- Where a new `using name;` goes: alphabetical position when the existing
-- block is sorted (Roslyn's own convention, and what this project does),
-- otherwise after the last using, otherwise above the namespace.
local function using_insert_lnum(info, name)
    if #info.usings == 0 then
        return info.ns_lnum or info.first_code or 1, true
    end
    local sorted = true
    for i = 2, #info.usings do
        if info.usings[i].name < info.usings[i - 1].name then
            sorted = false
            break
        end
    end
    if sorted then
        for _, u in ipairs(info.usings) do
            if name < u.name then
                return u.lnum, false
            end
        end
    end
    return info.last_using + 1, false
end

-- Files still declaring `ns` once `moved` (a set of paths) has moved out.
local function namespace_survives(root, ns, moved)
    local out = vim.system({
        "rg",
        "--files-with-matches",
        "--glob",
        "*.cs",
        "--glob",
        "!Library/**",
        "--glob",
        "!Temp/**",
        "--glob",
        "!obj/**",
        "^\\s*namespace\\s+" .. rg_escape(ns) .. "\\s*[;{]?\\s*$",
        root,
    }, { text = true }):wait()
    for _, line in ipairs(vim.split(out.stdout or "", "\n", { trimempty = true })) do
        if not moved[normalize(line)] then
            return true
        end
    end
    return false
end

-- Every .cs file under `root` mentioning any of `terms`.
local function candidate_files(root, terms)
    local pattern = {}
    for _, t in ipairs(terms) do
        pattern[#pattern + 1] = "\\b" .. rg_escape(t) .. "\\b"
    end
    local out = vim.system({
        "rg",
        "--files-with-matches",
        "--glob",
        "*.cs",
        "--glob",
        "!Library/**",
        "--glob",
        "!Temp/**",
        "--glob",
        "!obj/**",
        table.concat(pattern, "|"),
        root,
    }, { text = true }):wait()
    local files = {}
    for _, line in ipairs(vim.split(out.stdout or "", "\n", { trimempty = true })) do
        files[#files + 1] = normalize(line)
    end
    return files
end

-- Namespace edit for one mismatched file. A file that already declares a
-- namespace only needs its declaration line rewritten; one that declares none
-- has to be wrapped, which apply_file does whole-file.
local function target_edit(m)
    if m.info.namespace then
        local line = m.lines[m.info.ns_lnum]
        return {
            path = m.path,
            lnum = m.info.ns_lnum,
            kind = "namespace",
            before = line,
            after = (line:gsub(vim.pesc(m.from), (m.to:gsub("%%", "%%%%")), 1)),
        }
    end
    return {
        path = m.path,
        lnum = m.info.first_code or 1,
        kind = "wrap",
        before = "(no namespace)",
        after = "namespace " .. m.to .. " { … }",
        namespace = m.to,
    }
end

-- Build every edit needed to move `paths` to their expected namespaces and
-- keep the rest of the project referring to them correctly. Synchronous:
-- it shells out to ripgrep, which is a few tens of milliseconds even on a
-- full Assets tree.
--
-- Returns nil, reason when nothing can be planned.
function M.plan(paths)
    if vim.fn.executable("rg") ~= 1 then
        return nil, "ripgrep (rg) is required to find references"
    end
    local root
    local targets, edits = {}, {}
    for _, path in ipairs(paths) do
        local m = M.mismatch(path)
        if m then
            root = root or M.project_root(m.path)
            targets[#targets + 1] = m
            edits[#edits + 1] = target_edit(m)
        end
    end
    if #targets == 0 then
        return nil, "every namespace already matches its folder"
    end
    if not root then
        return nil, "not a Unity project"
    end
    root = normalize(root)

    -- One move per (old namespace -> new namespace) pair; several files in the
    -- same wrong namespace share a move, and their type names pool together.
    local moves, moved_paths = {}, {}
    for _, m in ipairs(targets) do
        local key = (m.from or "") .. "\0" .. m.to
        local move = moves[key]
        if not move then
            move = { old = m.from, new = m.to, types = {}, type_list = {}, files = {} }
            moves[key] = move
            moves[#moves + 1] = move
        end
        move.files[m.path] = true
        moved_paths[m.path] = true
        for _, t in ipairs(m.info.types) do
            if not move.types[t] then
                move.types[t] = true
                move.type_list[#move.type_list + 1] = t
            end
        end
    end

    -- An old namespace nobody lives in any more can have its usings retargeted;
    -- one that still has residents must keep them.
    local terms = {}
    for _, move in ipairs(moves) do
        if move.old then
            move.survives = namespace_survives(root, move.old, moved_paths)
            terms[#terms + 1] = move.old
        end
        vim.list_extend(terms, move.type_list)
    end
    if #terms == 0 then
        return { root = root, targets = targets, moves = moves, edits = edits }
    end

    for _, file in ipairs(candidate_files(root, terms)) do
        local lines = M.lines_of(file)
        if lines then
            local info = M.parse(lines)
            local clean = sanitize(lines)
            local wanted = {} -- usings to add, deduped across moves
            for _, move in ipairs(moves) do
                -- The declaring files are the ones being moved; they refer to
                -- their own types by name and need nothing.
                if not move.files[file] then
                    local refs = false
                    for _, t in ipairs(move.type_list) do
                        for _, line in ipairs(clean) do
                            if line:find(word_pattern(t)) then
                                refs = true
                                break
                            end
                        end
                        if refs then
                            break
                        end
                    end
                    if refs then
                        local has_new = false
                        for _, u in ipairs(info.usings) do
                            if u.name == move.new then
                                has_new = true
                            end
                        end
                        local retargeted = false
                        if move.old then
                            -- Fully-qualified A.B.Type references, and a
                            -- `using A.B;` this file no longer needs.
                            for i, line in ipairs(clean) do
                                for _, t in ipairs(move.type_list) do
                                    local qualified = vim.pesc(move.old .. "." .. t) .. "%f[^%w_]"
                                    if line:find("%f[%w_]" .. qualified) then
                                        edits[#edits + 1] = {
                                            path = file,
                                            lnum = i,
                                            kind = "qualified",
                                            before = lines[i],
                                            after = (
                                                lines[i]:gsub(
                                                    vim.pesc(move.old .. "." .. t) .. "%f[^%w_]",
                                                    ((move.new .. "." .. t):gsub("%%", "%%%%"))
                                                )
                                            ),
                                        }
                                        break
                                    end
                                end
                            end
                            for _, u in ipairs(info.usings) do
                                if u.name == move.old and not move.survives then
                                    edits[#edits + 1] = {
                                        path = file,
                                        lnum = u.lnum,
                                        kind = "using",
                                        before = lines[u.lnum],
                                        after = (lines[u.lnum]:gsub(vim.pesc(move.old), move.new, 1)),
                                    }
                                    retargeted = true
                                end
                            end
                        end
                        -- Still needs an import when it neither had one it kept
                        -- nor sees the new namespace from its own.
                        local had_old = false
                        for _, u in ipairs(info.usings) do
                            if u.name == move.old then
                                had_old = true
                            end
                        end
                        local covered = has_new or retargeted or sees(info.namespace, move.new)
                        if not covered and (had_old or sees(info.namespace, move.old)) then
                            wanted[move.new] = true
                        end
                    end
                end
            end
            for name in pairs(wanted) do
                local lnum, standalone = using_insert_lnum(info, name)
                edits[#edits + 1] = {
                    path = file,
                    lnum = lnum,
                    kind = "add-using",
                    before = "",
                    after = "using " .. name .. ";",
                    standalone = standalone, -- no using block yet: pad with a blank line
                }
            end
        end
    end

    return { root = root, targets = targets, moves = moves, edits = edits }
end

-- --------------------------------------------------------------- applying

local function by_file(edits)
    local grouped, order = {}, {}
    for _, e in ipairs(edits) do
        if not grouped[e.path] then
            grouped[e.path] = {}
            order[#order + 1] = e.path
        end
        table.insert(grouped[e.path], e)
    end
    return grouped, order
end
M.by_file = by_file

-- Transform one file's lines. Line-level edits go bottom-up so earlier line
-- numbers stay valid; the whole-file wrap runs last, on the already-edited
-- result.
local function apply_file(lines, edits)
    local wrap
    local ordered = {}
    for _, e in ipairs(edits) do
        if e.kind == "wrap" then
            wrap = e
        else
            ordered[#ordered + 1] = e
        end
    end
    table.sort(ordered, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum > b.lnum
        end
        return a.kind < b.kind
    end)
    for _, e in ipairs(ordered) do
        if e.kind == "add-using" then
            local block = { e.after }
            if e.standalone then
                block[#block + 1] = ""
            end
            for i = #block, 1, -1 do
                table.insert(lines, e.lnum, block[i])
            end
        else
            lines[e.lnum] = e.after
        end
    end
    if wrap then
        local indent = vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or "\t"
        local info = M.parse(lines)
        local body_start = info.last_using and (info.last_using + 1) or 1
        -- The blank line separating the using block from the body belongs
        -- above the namespace, not indented inside it.
        while body_start < #lines and not lines[body_start]:match("%S") do
            body_start = body_start + 1
        end
        local out = {}
        for i = 1, body_start - 1 do
            out[#out + 1] = lines[i]
        end
        if #out > 0 and out[#out]:match("%S") then
            out[#out + 1] = ""
        end
        out[#out + 1] = "namespace " .. wrap.namespace
        out[#out + 1] = "{"
        for i = body_start, #lines do
            out[#out + 1] = lines[i]:match("%S") and (indent .. lines[i]) or lines[i]
        end
        while #out > 0 and not out[#out]:match("%S") do
            out[#out] = nil
        end
        out[#out + 1] = "}"
        lines = out
    end
    return lines, wrap ~= nil
end
M._apply_file = apply_file

-- Apply a plan through buffers rather than by writing files directly: open
-- buffers pick the change up immediately, each file keeps a single undo step,
-- and autosave (config/autocmds.lua) puts them on disk. Returns the list of
-- buffers that were structurally rewritten (wrapped), which is all the caller
-- needs to re-format.
function M.apply(plan)
    local grouped, order = by_file(plan.edits)
    local reformat = {}
    for _, path in ipairs(order) do
        local bufnr = vim.fn.bufadd(path)
        vim.fn.bufload(bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local new_lines, wrapped = apply_file(lines, grouped[path])
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
        vim.bo[bufnr].buflisted = true
        if wrapped then
            reformat[#reformat + 1] = bufnr
        end
    end
    return order, reformat
end

-- Every mismatched .cs file under `dir`, recursively.
function M.mismatches_under(dir)
    local found = {}
    for _, file in ipairs(vim.fn.globpath(dir, "**/*.cs", false, true)) do
        local path = normalize(file)
        -- Vendored code (Plugins/, Packages/) follows its own conventions and
        -- is not ours to renumber.
        if not path:match("/Plugins/") and not path:match("/Packages/") then
            if M.mismatch(path) then
                found[#found + 1] = path
            end
        end
    end
    return found
end

return M
