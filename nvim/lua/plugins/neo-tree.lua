-- Files that nvim can't render; open these in the macOS default app instead.
local image_extensions = {
    png = true,
    jpg = true,
    jpeg = true,
    gif = true,
    bmp = true,
    webp = true,
    svg = true,
    ico = true,
    icns = true,
    tif = true,
    tiff = true,
    heic = true,
    avif = true,
}

-- True for dependency/package folders (util/tree_tints.lua owns the list)
-- and anything inside them; their text renders grayed-out (same look as
-- gitignored files), even in projects without git.
local function in_package_dir(node)
    local package_dirs = require("util.tree_tints").package_dirs
    if package_dirs[node.name] then
        return true
    end
    local path = node.path or ""
    for dir in pairs(package_dirs) do
        if path:find("/" .. dir .. "/", 1, true) then
            return true
        end
    end
    return false
end

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree", -- also load when invoked as :Neotree (e.g. from the dashboard)
    keys = {
        {
            "<leader>e",
            function()
                -- Smart toggle:
                --   closed            -> open + focus
                --   open, not focused -> focus it
                --   open + focused    -> close it
                if vim.bo.filetype == "neo-tree" then
                    vim.cmd("Neotree close")
                else
                    require("util.focus_tree")()
                end
            end,
            desc = "Toggle/focus file explorer",
        },
        {
            "<leader>o",
            function()
                require("util.focus_tree")()
            end,
            desc = "Focus file explorer",
        },
    },
    opts = {
        close_if_last_window = true,
        -- Defaults plus centered_pad: without it neo-tree picks the centered
        -- view's left margin (util/centered.lua) as the window to open a file
        -- in — <CR> on a file appeared to do nothing, because the file opened
        -- out in the margin.
        open_files_do_not_replace_types = { "terminal", "Trouble", "qf", "edgy", "centered_pad" },
        enable_git_status = true,
        enable_diagnostics = true,
        event_handlers = {
            -- Full-width background tints for package/test folder rows.
            -- Registers the tree state; the actual painting happens in
            -- util/tree_tints.lua via a decoration provider on redraw.
            {
                event = "after_render",
                handler = function(state)
                    require("util.tree_tints").register(state)
                end,
            },
        },
        default_component_configs = {
            icon = {
                -- Neo-tree draws its own single-color folder glyph and only
                -- asks the icon plugin about files. Route both through
                -- mini.icons so folders get per-name icons and colors too
                -- (src, test, .git, node_modules, …).
                provider = function(icon, node)
                    local ok, mini_icons = pcall(require, "mini.icons")
                    if not ok then
                        return
                    end
                    if node.type == "file" then
                        local text, hl = mini_icons.get("file", node.name)
                        icon.text = text
                        icon.highlight = hl
                    elseif node.type == "directory" then
                        local text, hl = mini_icons.get("directory", node.name)
                        icon.highlight = hl
                        -- Keep neo-tree's open-folder glyph on expanded dirs
                        -- so the open/closed state stays visible.
                        if not node:is_expanded() then
                            icon.text = text
                        end
                    end
                end,
            },
        },
        commands = {
            -- Open files / expand folders, but when collapsing an already-expanded
            -- folder, recursively collapse everything inside it too. That way the
            -- next time you expand it, its child folders start collapsed.
            toggle_or_recursive_collapse = function(state)
                local cc = require("neo-tree.sources.filesystem.commands")
                local node = state.tree:get_node()
                if node and node.type == "directory" and node:is_expanded() then
                    cc.close_all_subnodes(state)
                elseif node and node.type == "file" and image_extensions[(node.path:match("%.([^%.]+)$") or ""):lower()] then
                    -- Images open in the default viewer (Preview, browser, ...)
                    -- instead of as a binary buffer.
                    local _, err = vim.ui.open(node.path)
                    if err then
                        vim.notify("Failed to open " .. node.path .. ": " .. err, vim.log.levels.ERROR)
                    end
                else
                    cc.open(state)
                end
            end,
            -- Return focus to the previously focused (code) window, leaving the
            -- explorer open.
            focus_previous_window = function()
                vim.cmd("wincmd p")
            end,
            -- Reveal the file in the OS file manager (Explorer / Finder /
            -- whatever the desktop provides), or open the folder for a
            -- directory node. Was macOS-only (`open -R`) until util/os_files
            -- grew the Windows and Linux arms.
            open_in_file_manager = function(state)
                local node = state.tree:get_node()
                if not node then
                    return
                end
                if node.type == "directory" then
                    vim.ui.open(node.path)
                elseif not require("util.os_files").reveal(node.path) then
                    -- Nothing on this desktop can highlight the file itself;
                    -- settle for opening the folder that contains it.
                    vim.ui.open(vim.fs.dirname(node.path))
                end
            end,
            -- Create a new file from a template. Offers only the templates
            -- for whatever stack the project is (Unity C#, Laravel/PHP,
            -- Angular, Vue, Python, ...) — see util/templates/init.lua.
            add_template = function(state)
                local node = state.tree:get_node()
                local dir = (node.type == "directory") and node.path or vim.fn.fnamemodify(node.path, ":h")
                require("util.templates").create_interactive(dir, function()
                    require("neo-tree.sources.manager").refresh(state.name)
                end)
            end,
            -- Fix C# namespaces to match the folder layout, for the file or the
            -- whole folder under the cursor — util/cs_namespace_ui.lua shows
            -- every edit (including the references it has to update) before
            -- anything is written.
            refactor_namespace = function(state)
                local node = state.tree:get_node()
                if node then
                    require("util.cs_namespace_ui").refactor_path(node.path)
                end
            end,
        },
        window = {
            position = "right",
            -- Columns, not pixels — Neovim sizes windows in cells. 46 is 40
            -- plus ~50px at a typical ~8-9px monospace cell width; adjust the
            -- number directly if your font makes that come out wrong.
            width = 46,
            mappings = {
                ["<esc>"] = "focus_previous_window",
                ["<cr>"] = "toggle_or_recursive_collapse",
                ["<2-LeftMouse>"] = "toggle_or_recursive_collapse", -- double-click
                ["o"] = "toggle_or_recursive_collapse",
                ["<right>"] = "open", -- expand folder / open file
                ["<left>"] = "close_node", -- collapse folder
                ["s"] = "open_vsplit",
                ["S"] = "open_split",
                ["P"] = { "toggle_preview", config = { use_float = true } },
                ["a"] = "add",
                ["A"] = "add_template",
                ["d"] = "delete",
                ["r"] = "rename",
                ["y"] = "copy_to_clipboard",
                ["x"] = "cut_to_clipboard",
                ["p"] = "paste_from_clipboard",
                ["R"] = "refresh",
                ["H"] = "toggle_hidden",
                ["O"] = "open_in_file_manager",
                ["F"] = "refactor_namespace",
            },
        },
        filesystem = {
            follow_current_file = { enabled = true }, -- highlight the file you're editing
            use_libuv_file_watcher = true, -- auto-refresh on external changes
            components = {
                name = function(config, node, state)
                    local result = require("neo-tree.sources.filesystem.components").name(config, node, state)
                    if in_package_dir(node) then
                        result.highlight = require("neo-tree.ui.highlights").GIT_IGNORED
                    end
                    return result
                end,
            },
            filtered_items = {
                hide_dotfiles = false,
                hide_gitignored = false,
                -- Hide Unity's .meta sidecar files. Still revealable with "H"
                -- (toggle_hidden) since they're hidden, not never_show.
                hide_by_pattern = { "*.meta" },
            },
        },
    },
    config = function(_, opts)
        if require("util.unity").is_unity_project() then
            opts.filesystem.filtered_items = vim.tbl_deep_extend("force", opts.filesystem.filtered_items, {
                never_show = {
                    ".vs",
                    "Library",
                    "library",
                    "Obj",
                    "obj",
                    "Logs",
                    "logs",
                    "ProjectSettings",
                    "UserSettings",
                    "Temp",
                    "temp",
                    "build",
                    "Build",
                },
                never_show_by_pattern = {
                    "*.booproj",
                    "*.pidb",
                    "*.suo",
                    "*.user",
                    "*.userprefs",
                    "*.unityproj",
                    "*.vsconfig",
                    "*.dll",
                    "*.pdf",
                },
            })
        end

        require("neo-tree").setup(opts)
        -- Mouse must be on for clicking the tree
        vim.opt.mouse = "a"

        -- Dropping a file from the OS file manager onto the explorer arrives
        -- as a pasted (shell-escaped) path in iTerm2, Windows Terminal and
        -- WezTerm alike. Intercept pastes in the neo-tree buffer and copy
        -- those files into the folder under the cursor.
        local orig_paste = vim.paste
        local drop_chunks = {}
        vim.paste = function(lines, phase)
            if vim.bo.filetype ~= "neo-tree" then
                return orig_paste(lines, phase)
            end
            if phase == -1 or phase == 1 then
                drop_chunks = {}
            end
            vim.list_extend(drop_chunks, lines)
            if phase ~= -1 and phase ~= 3 then
                return true -- more chunks of this paste still coming
            end

            local paths = {}
            for _, line in ipairs(drop_chunks) do
                -- Multiple dropped files are space-separated; keep escaped
                -- spaces ("\ ") inside a single path while splitting.
                line = line:gsub("\\ ", "\1")
                for token in line:gmatch("%S+") do
                    token = token:gsub("\1", " "):gsub("\\(.)", "%1")
                    if vim.uv.fs_stat(token) then
                        table.insert(paths, token)
                    end
                end
            end
            if #paths == 0 then
                vim.notify("Pasted text is not an existing file path", vim.log.levels.WARN)
                return true
            end

            local manager = require("neo-tree.sources.manager")
            local state = manager.get_state("filesystem")
            local node = state and state.tree and state.tree:get_node()
            local dir = state and state.path or vim.uv.cwd()
            if node then
                dir = (node.type == "directory") and node.path or vim.fn.fnamemodify(node.path, ":h")
            end

            local copied = 0
            for _, src in ipairs(paths) do
                local dst = vim.fs.joinpath(dir, vim.fn.fnamemodify(src, ":t"))
                if vim.uv.fs_stat(dst) then
                    vim.notify("Already exists: " .. dst, vim.log.levels.WARN)
                else
                    local ok, err = require("util.os_files").copy(src, dst)
                    if ok then
                        copied = copied + 1
                    else
                        vim.notify("Copy failed: " .. (err or src), vim.log.levels.ERROR)
                    end
                end
            end
            if copied > 0 then
                manager.refresh("filesystem")
                vim.notify(("Copied %d file(s) to %s"):format(copied, dir))
            end
            return true
        end
    end,
}
