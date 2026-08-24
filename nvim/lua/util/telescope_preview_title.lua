-- Preview window title: the previewed FILE NAME, pinned to the top-left
-- corner (IDE-style — the tab above an editor names the file you're
-- looking at, nothing else).
--
-- Telescope's `dynamic_preview_title` already retitles the preview per
-- entry, but it hands plenary the whole relative path as a plain string,
-- and plenary centres a plain-string title on the top border. Two small
-- patches fix both without forking telescope:
--
--   * Previewer:title() — trim a path title to its last component. Only
--     titles that stat as a real file are trimmed, so free-text ones
--     (git_history previews "<sha>  <subject>", which can itself contain
--     a slash) come through untouched.
--   * get_initial_window_options() — pass the preview title as
--     { pos = "NW" } instead of a bare string. The corner then sticks for
--     the whole picker: plenary's Border:change_title() reuses the pos of
--     the title it replaces, and that's the call telescope makes on every
--     selection change.

local M = {}

local uv = vim.uv or vim.loop
local patched = false

-- Path titles become their file name; anything else is left alone.
local function file_name_only(title)
    if type(title) ~= "string" or not title:find("[/\\]") then
        return title
    end
    local path = title
    if not (path:sub(1, 1) == "/" or path:match("^%a:[/\\]")) then
        path = (uv.cwd() or "") .. "/" .. path
    end
    local stat = uv.fs_stat(path)
    if not stat or stat.type ~= "file" then
        return title
    end
    return vim.fn.fnamemodify(title, ":t")
end

function M.setup()
    if patched then
        return
    end
    patched = true

    local Previewer = require("telescope.previewers.previewer")
    local title = Previewer.title
    function Previewer:title(entry, dynamic)
        return file_name_only(title(self, entry, dynamic))
    end

    local p_window = require("telescope.pickers.window")
    local initial_window_options = p_window.get_initial_window_options
    function p_window.get_initial_window_options(picker)
        local opts = initial_window_options(picker)
        -- bottom_pane draws its titles along the *bottom* border and does
        -- the string -> { pos = "S" } conversion itself; leave it be.
        if picker.layout_strategy ~= "bottom_pane" and type(opts.preview.title) == "string" then
            opts.preview.title = { { pos = "NW", text = opts.preview.title } }
        end
        return opts
    end
end

return M
