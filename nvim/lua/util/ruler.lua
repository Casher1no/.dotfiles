-- Thin right-margin ruler. 'colorcolumn' paints a whole cell with ColorColumn,
-- which reads as a thick band down the file; this draws a single │ in the same
-- grey instead, so it looks like the window separators do.
--
-- The glyph is virtual text pinned to a window column, produced by a
-- decoration provider (the mechanism util/tree_tints.lua uses for its row
-- tints): nothing is stored in the buffer and nothing has to be cleaned up.
--
-- Lines that reach past the ruler keep their text — virtual text at a fixed
-- window column paints over whatever character sits there, so those lines are
-- skipped rather than corrupted.
local M = {}

M.column = 120

local ns = vim.api.nvim_create_namespace("ruler")

-- Same grey as the window separators. Re-applied on ColorScheme because
-- themes clear groups they don't know about.
local function pin_highlight()
    local separator = vim.api.nvim_get_hl(0, { name = "WinSeparator", link = false })
    local column = vim.api.nvim_get_hl(0, { name = "ColorColumn", link = false })
    vim.api.nvim_set_hl(0, "Ruler", { fg = separator.fg or column.bg })
end

-- Normal file windows only: no explorer, terminal, dashboard, help or floats.
local function eligible(win, buf)
    return vim.bo[buf].buftype == ""
        and vim.api.nvim_win_get_config(win).relative == ""
        and vim.wo[win].number -- the same windows that used to show the column
end

-- Horizontal scrolling moves the text under the ruler. leftcol can only be
-- read from the window it belongs to, and a decoration provider must not
-- switch windows — doing that mid-redraw corrupts the screen — so it is
-- recorded per window from an autocmd instead and read back during the draw.
local leftcol = 0

local function record_leftcol()
    local ok, view = pcall(vim.fn.winsaveview)
    if ok then
        vim.w.ruler_leftcol = view.leftcol
    end
end

-- Display width of a buffer line, safe on binary content.
--
-- A buffer line can hold NUL bytes, and every stack this config is used on
-- has binaries sitting in a directory you might open a file from: a .pyc
-- under __pycache__, a compiled extension in .venv, a phar or a platform
-- binary in Laravel's vendor/, an esbuild/sharp/node-sass .node in
-- node_modules, a .pack under .git. Vimscript strings cannot carry NUL, so
-- such a line crosses the vim.fn bridge as a *Blob* and strdisplaywidth()
-- raises E976 "Using a Blob as a String". Raised from inside a decoration
-- provider, Neovim prints it and disables the provider — so opening one
-- binary file killed the ruler for the rest of the session, with a
-- "Press ENTER" prompt on the way out.
--
-- Neovim renders a NUL as ^@, two cells (virtcol on "hello<NUL>world" is
-- 12, not 11), so substituting that keeps the width exact and keeps the
-- value a String. Two things that don't work here: nvim_strwidth(), which
-- takes NUL-bearing strings but stops at the first one and counts a tab as
-- a single cell — tabs being the whole reason strdisplaywidth() is used;
-- and gsub("\0", ...), where LuaJIT reads the NUL as the end of the
-- pattern and so matches the empty string at every position. It has to be
-- the %z class.
--
-- Public so the binary case can be tested without a binary file.
function M.display_width(line)
    if line:find("%z") then
        line = line:gsub("%z", "^@")
    end
    return vim.fn.strdisplaywidth(line)
end

function M.setup(column)
    M.column = column or M.column
    -- The built-in column is what's being replaced.
    vim.opt.colorcolumn = ""
    pin_highlight()
    local group = vim.api.nvim_create_augroup("ruler", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = pin_highlight })
    vim.api.nvim_create_autocmd({ "WinScrolled", "WinEnter", "BufWinEnter" }, {
        group = group,
        callback = record_leftcol,
    })
    vim.api.nvim_set_decoration_provider(ns, {
        on_win = function(_, win, buf)
            if not eligible(win, buf) then
                return false
            end
            leftcol = vim.w[win].ruler_leftcol or 0
            return true
        end,
        on_line = function(_, _, buf, row)
            local screen_col = M.column - 1 - leftcol
            if screen_col < 0 then
                return
            end
            local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
            if not line then
                return
            end
            -- #line is a cheap lower bound on the display width for the
            -- common (ASCII, no tabs, no NUL) case; only then is the real
            -- width worth computing. A tab or a ^@ is wider than its one
            -- byte, so a line under the threshold can still reach the
            -- ruler — that is the pre-existing trade for not calling
            -- strdisplaywidth on every line of every redraw.
            if #line >= M.column and M.display_width(line) > screen_col + leftcol then
                return
            end
            vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
                ephemeral = true,
                virt_text = { { "│", "Ruler" } },
                virt_text_win_col = screen_col,
                hl_mode = "combine",
            })
        end,
    })
end

return M
