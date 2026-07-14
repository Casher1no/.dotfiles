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

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
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
                    vim.cmd("Neotree focus right")
                end
            end,
            desc = "Toggle/focus file explorer",
        },
        { "<leader>o", "<cmd>Neotree focus right<cr>", desc = "Focus file explorer" },
    },
    opts = {
        close_if_last_window = true,
        enable_git_status = true,
        enable_diagnostics = true,
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
            -- Reveal the file (or open the folder) in Finder.
            open_in_finder = function(state)
                local node = state.tree:get_node()
                if not node then
                    return
                end
                if node.type == "directory" then
                    vim.ui.open(node.path)
                else
                    vim.system({ "open", "-R", node.path })
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
        },
        window = {
            position = "right",
            width = 35,
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
                ["O"] = "open_in_finder",
            },
        },
        filesystem = {
            follow_current_file = { enabled = true }, -- highlight the file you're editing
            use_libuv_file_watcher = true, -- auto-refresh on external changes
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

        -- Dropping a file from Finder onto the explorer arrives as a pasted
        -- (shell-escaped) path in iTerm2. Intercept pastes in the neo-tree
        -- buffer and copy those files into the folder under the cursor.
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
                local dst = dir .. "/" .. vim.fn.fnamemodify(src, ":t")
                if vim.uv.fs_stat(dst) then
                    vim.notify("Already exists: " .. dst, vim.log.levels.WARN)
                else
                    local res = vim.system({ "cp", "-R", src, dst }):wait()
                    if res.code == 0 then
                        copied = copied + 1
                    else
                        vim.notify("Copy failed: " .. (res.stderr or src), vim.log.levels.ERROR)
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
