-- Angular-specific narrowing for "find usages" (util/references.lua).
--
-- A pipe's transform() is not really a symbol of its own: it implements
-- PipeTransform.transform, and tsserver answers a references request on an
-- interface member with the whole family — every transform() in the project
-- and in node_modules. angularls then maps each of those to the template
-- usages of *that* pipe, so gd on DistancePipe.transform came back with
-- everyone else's pipes.
--
-- Measured on ramble-application (2026-08-31), cursor on
-- DistancePipe.transform: angularls 279 hits + vtsls 67, of which
--   184 `| transloco`, 134 `transform`, 13 `| truncate`, 5 `| date`, …
--   and exactly 1 `| distance` — the one usage that was being asked for.
--
-- The mapping we want is known, though: a pipe class's transform() is spelled
-- in a template as `| <the @Pipe name>`. So when the cursor sits on such a
-- transform, keep only the hits that can belong to *this* pipe:
--   - anything in the file itself (the declaration and its neighbours),
--   - a template hit whose token is one of the file's @Pipe names,
--   - a `.transform(` call site, wherever it is — a direct call is a real
--     use, and unlike the bare declarations it is not the interface family.
-- Everything else is a usage of a different symbol that only came back
-- because the interface member is shared, so it is dropped rather than
-- hidden behind a toggle. The picker title names the pipe it narrowed to,
-- so the narrowing is never silent.
local M = {}

local is_win = vim.fn.has("win32") == 1

-- Comparable form of a path. Backslashes are folded on every OS: the LSP
-- items and the buffer name can be spelled differently, and
-- vim.fs.normalize only rewrites separators when running on Windows.
local function canon(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    path = (vim.fs.normalize((path:gsub("\\", "/"))):gsub("/+$", ""))
    return is_win and path:lower() or path
end

-- Names declared by @Pipe({ ..., name: 'x' }) decorators in `lines`. A file
-- normally declares one; several is legal and all of them are kept.
function M.pipe_names(lines)
    local names, in_decorator = {}, false
    for _, line in ipairs(lines) do
        if line:find("@Pipe%s*%(") then
            in_decorator = true
        end
        if in_decorator then
            local name = line:match("name%s*:%s*['\"]([%w_%$%-]+)['\"]")
            if name then
                names[#names + 1] = name
                in_decorator = false
            elseif line:match("^%s*export%s") or line:match("^%s*class%s") then
                in_decorator = false -- decorator ended without a name field
            end
        end
    end
    return names
end

-- The identifier a reference points at, plus the character in front of it.
-- vim.lsp.util.locations_to_items gives the whole line in .text and a
-- 1-based byte column, so the token is readable without touching the file.
function M.token_at(item)
    local text = item.text or ""
    local col = math.max(1, item.col or 1)
    return text:sub(col):match("^[%w_%$]+"), text:sub(col - 1, col - 1)
end

-- Is the cursor on the *declaration* of a pipe's transform()? Returns the
-- pipe names when it is. A call site (`this.other.transform(x)`) is a use of
-- somebody else's method, so it is left alone.
-- `row`/`col` are 0-based, as nvim_win_get_cursor reports them.
function M.transform_pipe(lines, row, col, word)
    if word ~= "transform" then
        return nil
    end
    local line = lines[row + 1] or ""
    -- Walk left to the start of the identifier: the cursor can be anywhere
    -- inside it, and only the character before it says call vs declaration.
    local start = math.min(col + 1, #line + 1)
    while start > 1 and line:sub(start - 1, start - 1):match("[%w_%$]") do
        start = start - 1
    end
    if line:sub(start - 1, start - 1) == "." then
        return nil
    end
    local implements = false
    for _, l in ipairs(lines) do
        if l:find("PipeTransform", 1, true) then
            implements = true
            break
        end
    end
    if not implements then
        return nil
    end
    local names = M.pipe_names(lines)
    return #names > 0 and names or nil
end

-- Keep only the reference items that can belong to the pipe named by
-- `names`. Pure, so it can be tested without an LSP.
function M.scope(items, names, current)
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[name] = true
    end
    current = canon(current)
    local kept = {}
    for _, item in ipairs(items) do
        local token, before = M.token_at(item)
        local keep = canon(item.filename) == current
            or (token and wanted[token]) -- `| distance` in a template
            or (token == "transform" and before == ".") -- a direct call
        if keep then
            kept[#kept + 1] = item
        end
    end
    return kept
end

-- Entry point for util/references.lua. Returns the (possibly narrowed) item
-- list and the pipe name it narrowed to, or the list unchanged and nil.
function M.narrow(bufnr, row, col, word, items, current)
    local ft = vim.bo[bufnr].filetype
    if ft ~= "typescript" and ft ~= "typescriptreact" then
        return items, nil
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local names = M.transform_pipe(lines, row, col, word)
    if not names then
        return items, nil
    end
    return M.scope(items, names, current), table.concat(names, ", ")
end

return M
