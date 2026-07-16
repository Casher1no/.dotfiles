-- Cross-referencing between stylesheets and templates — the piece no CSS
-- language server provides (JetBrains does it with its own indexer):
--
--   stylesheet, gr on `.card` / `#header`  → every usage across templates
--                                            (class="..."), Angular bindings
--                                            ([class.card]) and stylesheets
--   template,   gd on a name inside a      → the selector's definition in
--               class="..." attribute        css/scss/sass/less/vue files
--
-- Wired into the gd/gr LSP keymaps (plugins/lsp.lua): both functions return
-- false when the cursor isn't in their context, so normal LSP navigation
-- takes over. Searches run ripgrep (same binary telescope's live_grep uses)
-- from the current working directory.
local M = {}

local STYLESHEET_FT = { css = true, scss = true, sass = true, less = true }
local TEMPLATE_FT = {
    html = true,
    htmlangular = true,
    vue = true,
    php = true,
    blade = true,
    javascriptreact = true,
    typescriptreact = true,
}

-- Word under the cursor including `-` (iskeyword in templates splits on it,
-- which would break names like "btn-primary"). Returns word + start column.
local function word_at_cursor()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local s = col
    while s > 1 and line:sub(s - 1, s - 1):match("[%w_%-]") do
        s = s - 1
    end
    local e = col
    while e <= #line and line:sub(e, e):match("[%w_%-]") do
        e = e + 1
    end
    local word = line:sub(s, e - 1)
    if word == "" then
        return nil
    end
    return word, s, line
end

-- rg --vimgrep, results into the quickfix list: 0 hits → notify, 1 hit →
-- jump straight there, many → telescope quickfix picker (:copen fallback).
local function search(pattern, globs, title)
    local cmd = { "rg", "--vimgrep", pattern }
    for _, g in ipairs(globs or {}) do
        table.insert(cmd, "--glob")
        table.insert(cmd, g)
    end
    vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }, function(res)
        vim.schedule(function()
            local items = {}
            for _, l in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
                local file, lnum, col, text = l:match("^(.-):(%d+):(%d+):(.*)$")
                if file then
                    items[#items + 1] = { filename = file, lnum = tonumber(lnum), col = tonumber(col), text = text }
                end
            end
            if #items == 0 then
                vim.notify(title .. ": nothing found", vim.log.levels.INFO)
                return
            end
            if #items == 1 then
                vim.cmd("edit " .. vim.fn.fnameescape(items[1].filename))
                vim.api.nvim_win_set_cursor(0, { items[1].lnum, items[1].col - 1 })
                return
            end
            vim.fn.setqflist({}, " ", { title = title, items = items })
            local ok = pcall(function()
                require("telescope.builtin").quickfix({ prompt_title = title })
            end)
            if not ok then
                vim.cmd("copen")
            end
        end)
    end)
end

local function rg_escape(s)
    return s:gsub("([%.%[%]%(%)%{%}%*%+%?%^%$%|\\])", "\\%1")
end

-- In a stylesheet, on a class/id selector: find usages everywhere.
-- Returns false when not applicable (caller falls back to LSP references).
function M.references()
    if not STYLESHEET_FT[vim.bo.filetype] then
        return false
    end
    local word, s, line = word_at_cursor()
    if not word then
        return false
    end
    local sigil = line:sub(s - 1, s - 1)
    if sigil ~= "." and sigil ~= "#" then
        return false -- $variables, mixins etc. belong to the LSP
    end
    local name = rg_escape(word)
    -- \b would treat "-" as a boundary (.card matching .card-title), so the
    -- guards below require a real delimiter around the name instead.
    local tail = [[([^\w-]|$)]]
    local pattern = ("(class[A-Za-z]*\\s*=\\s*[\"']([^\"']*[\\s])?%s([^\\w-]|[\"']))|(\\[class\\.%s([^\\w-]|\\]))|([.#]%s%s)"):format(
        name,
        name,
        name,
        tail
    )
    -- Usages live in templates — other stylesheets would just echo
    -- definitions back, so they're excluded (the reverse direction,
    -- template → stylesheet, searches only style files).
    search(pattern, { "!*.css", "!*.scss", "!*.sass", "!*.less" }, "Usages of " .. sigil .. word)
    return true
end

-- In a template, on a name inside class="...": find the selector's
-- definition in stylesheet files. Returns false when not applicable.
function M.definition()
    if not TEMPLATE_FT[vim.bo.filetype] then
        return false
    end
    local word, s, line = word_at_cursor()
    if not word then
        return false
    end
    -- Cursor must sit inside an open class attribute: class="… <cursor>
    local before = line:sub(1, s - 1)
    if not (before:match([[class[%a]*%s*=%s*["'][^"']*$]]) or before:match([[%[class%.$]])) then
        return false
    end
    search("[.#]" .. rg_escape(word) .. "([^\\w-]|$)", {
        "*.css",
        "*.scss",
        "*.sass",
        "*.less",
        "*.vue",
    }, "Definition of ." .. word)
    return true
end

return M
