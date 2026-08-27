-- Keeps Unity's Assembly-CSharp.csproj in step with the files on disk.
--
-- Why this exists: Unity generates that csproj with <EnableDefaultItems>false,
-- so every source file is listed explicitly as <Compile Include="..." />. A
-- script created from Neovim is therefore invisible to Roslyn
-- (plugins/roslyn.lua) until Unity is refocused and regenerates the project --
-- no completion, no diagnostics, and "type or namespace could not be found"
-- from every file that references it. This closes that gap without leaving
-- Neovim.
--
-- The csproj XML surgery comes from apyra/nvim-unity-sync (plugins/unity.lua).
-- We deliberately require only its `unity.handler` module and never
-- `unity.plugin`, because plugin.lua:
--   * registers a VimLeave autocmd running os.execute("pkill -f unity2025") on
--     every exit, on every OS,
--   * subscribes its file events to nvim-tree, which this config doesn't use,
--   * uses `pattern = ".cs"` on its LSP autocmds, which never matches "Foo.cs",
--   * ships a :Uopen that shells `tasklist` (Windows-only) with a malformed
--     argv.
-- Its utils.normalizePath is unusable here for the same reason: it collapses
-- everything to forward slashes even on Windows, while Unity writes
-- "Assets\Scripts\Foo.cs". Writing the other spelling defeats the plugin's own
-- duplicate check and leaves two <Compile> items for one file, which the SDK
-- rejects (NETSDK1022). So: their XML editing, our paths and our events.
--
-- Coverage: neo-tree create/delete/rename/move (plugins/neo-tree.lua), plus
-- BufWritePost for a file first written from a buffer (:e Foo.cs, telescope, a
-- template). Anything else -- a file arriving via git, a bulk move from the
-- shell -- is caught by :Usync, which rewrites the whole list.
local unity = require("util.unity")

local M = {}

local is_win = vim.fn.has("win32") == 1

-- Canonical form for *comparison only*: forward slashes, no trailing slash,
-- case-folded on Windows (NTFS is case-insensitive, so F:\Projects and
-- f:\projects are one directory). Never write this back out -- it destroys the
-- casing Unity put in the csproj.
local function canon(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    path = vim.fs.normalize(path):gsub("/+$", "")
    return is_win and path:lower() or path
end

-- The separator Unity used in *this* csproj. MSBuild accepts either, but the
-- add/remove patterns are literal matches: write "Assets/Foo.cs" into a file
-- that already says "Assets\Foo.cs" and the duplicate check misses.
function M._detect_sep(content)
    if type(content) ~= "string" then
        return is_win and "\\" or "/"
    end
    if content:match('<Compile%s+Include%s*=%s*"[^"]*\\') then
        return "\\"
    end
    if content:match('<Compile%s+Include%s*=%s*"[^"]*/') then
        return "/"
    end
    return is_win and "\\" or "/"
end

-- Line ending already in the file. This repo is checked out CRLF on Windows and
-- so are Unity's generated projects; splicing "\n" into a CRLF file leaves a
-- mixed-ending csproj that git then reports as rewritten end to end.
function M._detect_nl(content)
    return (type(content) == "string" and content:find("\r\n", 1, true)) and "\r\n" or "\n"
end

-- Project-relative include value for `path`, in `sep` style, or nil when the
-- file is not a source of Assembly-CSharp (outside the root, or outside
-- Assets/). `path` may use either separator and any casing.
function M._include_path(root, path, sep)
    if type(root) ~= "string" or type(path) ~= "string" or root == "" or path == "" then
        return nil
    end

    local nroot = vim.fs.normalize(root):gsub("/+$", "")
    local npath = vim.fs.normalize(path):gsub("/+$", "")
    local croot, cpath = canon(nroot), canon(npath)

    -- Compare against root .. "/" so a sibling whose name is a prefix of the
    -- root (".../The Inheritance Extra" vs ".../The Inheritance") is excluded.
    if cpath:sub(1, #croot + 1) ~= croot .. "/" then
        return nil
    end

    local rel = npath:sub(#nroot + 2)
    if not rel:match("^Assets/") then
        return nil
    end

    if sep == "\\" then
        rel = rel:gsub("/", "\\")
    end
    return rel
end

-- A folder holding an .asmdef starts its own assembly, so its scripts belong to
-- <Name>.csproj, not Assembly-CSharp.csproj. Listing them here compiles them
-- twice -- CS0101 on every type in the folder. Walk up to Assets/ and bail if
-- any parent claims one.
function M._owned_by_asmdef(root, path)
    local stop = canon(vim.fs.normalize(root) .. "/Assets")
    local dir = vim.fs.dirname(vim.fs.normalize(path))

    while dir and dir ~= "" do
        for name, type in vim.fs.dir(dir) do
            if type ~= "directory" and name:match("%.asmdef$") then
                return true
            end
        end
        if canon(dir) == stop then
            return false
        end
        local parent = vim.fs.dirname(dir)
        if parent == dir then
            return false
        end
        dir = parent
    end
    return false
end

-- Every .cs under `dir` that Assembly-CSharp actually compiles, as paths
-- relative to `dir` with forward slashes. Subtrees claimed by an .asmdef are
-- pruned whole. Symlinks count as files, so a loop cannot hang the walk.
function M._scan_cs(dir)
    local out = {}

    local function walk(abs, rel)
        local files, subdirs, claimed = {}, {}, false
        for name, type in vim.fs.dir(abs) do
            if type == "directory" then
                subdirs[#subdirs + 1] = name
            else
                if name:match("%.asmdef$") then
                    claimed = true
                end
                if name:match("%.cs$") then
                    files[#files + 1] = name
                end
            end
        end
        if claimed then
            return
        end
        for _, name in ipairs(files) do
            out[#out + 1] = rel == "" and name or (rel .. "/" .. name)
        end
        for _, name in ipairs(subdirs) do
            walk(abs .. "/" .. name, rel == "" and name or (rel .. "/" .. name))
        end
    end

    walk(vim.fs.normalize(dir), "")
    table.sort(out)
    return out
end

-- Load Assembly-CSharp.csproj for `root`. Returns a handler holding .content,
-- or nil plus the reason. hasCSProjectUnityCapability is reset every time on
-- purpose: Unity rewrites this file behind our back whenever it regenerates,
-- so a cached parse goes stale inside a single session.
local function open_project(root)
    local ok, Handler = pcall(require, "unity.handler")
    if not ok then
        return nil, "apyra/nvim-unity-sync is not installed"
    end

    local h = Handler:new()
    h.rootFolder = vim.fs.normalize(root):gsub("/+$", "")
    h.hasCSProjectUnityCapability = false

    local valid, msg = h:validateProject()
    if not valid then
        return nil, msg
    end
    return h
end

-- Run `fn(handler, root, sep)` against the project owning `path`, and save if
-- it reports a change. Silent when there is no Unity project or no csproj yet:
-- those are the normal states in every other repo, and a notify would fire on
-- every write.
local function edit(path, fn)
    local root = unity.root(vim.fs.dirname(vim.fs.normalize(path)))
    if not root then
        return false
    end

    local h, why = open_project(root)
    if not h then
        return false, why
    end

    if not fn(h, root, M._detect_sep(h.content)) then
        return false
    end

    local saved, err = h:save()
    if not saved then
        vim.notify("[unity-sync] " .. (err or "could not write Assembly-CSharp.csproj"), vim.log.levels.ERROR)
        return false
    end
    return true
end

function M.on_added(path)
    if type(path) ~= "string" or not path:match("%.cs$") then
        return
    end
    edit(path, function(h, root, sep)
        if M._owned_by_asmdef(root, path) then
            return false
        end
        local inc = M._include_path(root, path, sep)
        return inc ~= nil and (h:addCompileTag(inc)) == true
    end)
end

-- neo-tree fires file_deleted for directories too, and the path is gone by the
-- time we see it -- so the ".cs" suffix, not a stat, decides which it was.
function M.on_deleted(path)
    if type(path) ~= "string" then
        return
    end
    edit(path, function(h, root, sep)
        local inc = M._include_path(root, path, sep)
        if not inc then
            return false
        end
        if path:match("%.cs$") then
            return h:removeCompileTag(inc)
        end
        -- Trailing separator, or deleting "Assets\Enemy" also strips
        -- "Assets\EnemySpawner.cs".
        return h:removeCompileTagsByFolder(inc .. sep)
    end)
end

function M.on_renamed(old, new)
    if type(old) ~= "string" or type(new) ~= "string" then
        return
    end

    edit(new, function(h, root, sep)
        local changes = {}

        if new:match("%.cs$") then
            local from = M._include_path(root, old, sep)
            local to = M._include_path(root, new, sep)
            if not from then
                return false
            end
            -- Moved into an .asmdef's territory: it leaves this csproj rather
            -- than being renamed inside it.
            if not to or M._owned_by_asmdef(root, new) then
                return h:removeCompileTag(from)
            end
            changes[1] = { old = from, new = to }
        else
            for _, rel in ipairs(M._scan_cs(new)) do
                local from = M._include_path(root, old .. "/" .. rel, sep)
                local to = M._include_path(root, new .. "/" .. rel, sep)
                if from and to then
                    changes[#changes + 1] = { old = from, new = to }
                end
            end
        end

        if #changes == 0 then
            return false
        end
        local updated = h:updateCompileTags(changes)
        return type(updated) == "table" and #updated > 0
    end)
end

local COMPILE_LINE = '[ \t]*<Compile%s+Include%s*=%s*"[^"]*"%s*/>[ \t]*\r?\n?'
local PLACEHOLDER = "<!%-%- {{COMPILE_INCLUDES}} %-%->"

-- Rewrite the whole <Compile> list from what is on disk. This is the recovery
-- path: a bulk move, a git checkout, or a stretch of editing with Neovim closed
-- all leave the csproj wrong in ways the incremental hooks never see.
function M.rebuild(root, content)
    local sep, nl = M._detect_sep(content), M._detect_nl(content)
    local files = M._scan_cs(root .. "/Assets")

    local lines = {}
    for _, rel in ipairs(files) do
        local inc = "Assets/" .. rel
        if sep == "\\" then
            inc = inc:gsub("/", "\\")
        end
        lines[#lines + 1] = '    <Compile Include="' .. inc .. '" />'
    end
    local block = table.concat(lines, nl)

    content = content:gsub(COMPILE_LINE, "")

    if content:match(PLACEHOLDER) then
        -- Function replacement, not a string: an include containing "%" would
        -- otherwise be read as a capture reference.
        content = content:gsub(PLACEHOLDER, function(marker)
            return #block > 0 and (marker .. nl .. block) or marker
        end, 1)
    else
        local at = content:find("</Project>", 1, true)
        if not at then
            return nil, "Assembly-CSharp.csproj has no </Project>"
        end
        content = content:sub(1, at - 1)
            .. table.concat({
                "  <ItemGroup>",
                "    <!-- Auto-generated block: do not modify manually or remove these commented lines -->",
                "    <!-- {{COMPILE_INCLUDES}} -->",
                block,
                "  </ItemGroup>",
                "",
            }, nl)
            .. content:sub(at)
    end

    return content, #files
end

-- Root for the current buffer, falling back to the cwd (the buffer may be a
-- dashboard, a terminal or neo-tree itself when :Usync is invoked).
local function current_root()
    local name = vim.api.nvim_buf_get_name(0)
    if name ~= "" then
        local root = unity.root(vim.fs.dirname(vim.fs.normalize(name)))
        if root then
            return root
        end
    end
    return unity.root()
end

-- opts.root overrides the buffer/cwd lookup (headless tests), opts.quiet
-- suppresses the summary notify.
function M.sync(opts)
    opts = opts or {}

    local root = opts.root or current_root()
    if not root then
        vim.notify("[unity-sync] not inside a Unity project", vim.log.levels.WARN)
        return
    end

    local h, why = open_project(root)
    if not h then
        vim.notify("[unity-sync] " .. (why or "no Assembly-CSharp.csproj"), vim.log.levels.WARN)
        return
    end

    local content, count = M.rebuild(root, h.content)
    if not content then
        vim.notify("[unity-sync] " .. count, vim.log.levels.ERROR)
        return
    end

    h.content = content
    local saved, err = h:save()
    if not saved then
        vim.notify("[unity-sync] " .. (err or "could not write Assembly-CSharp.csproj"), vim.log.levels.ERROR)
        return
    end

    if not opts.quiet then
        vim.notify(("[unity-sync] %d script%s listed in Assembly-CSharp.csproj"):format(count, count == 1 and "" or "s"))
    end
end

function M.status()
    local root = current_root()
    if not root then
        vim.notify("[unity-sync] not inside a Unity project", vim.log.levels.WARN)
        return
    end

    local h, why = open_project(root)
    if not h then
        vim.notify(("[unity-sync] root: %s\n%s"):format(root, why or "unknown"), vim.log.levels.WARN)
        return
    end

    local listed = select(2, h.content:gsub('<Compile%s+Include%s*=%s*"', ""))
    vim.notify(table.concat({
        "[unity-sync]",
        "root:      " .. root,
        "separator: " .. M._detect_sep(h.content),
        "listed:    " .. listed .. " <Compile> entries",
        "on disk:   " .. #M._scan_cs(root .. "/Assets") .. " .cs files (Assembly-CSharp only)",
    }, "\n"))
end

function M.setup()
    local group = vim.api.nvim_create_augroup("UnitySync", { clear = true })

    -- A file that did not exist when the buffer opened, and does once written:
    -- the non-neo-tree creation path (:e Foo.cs, a telescope "create", a
    -- template). Flagged on BufNewFile so BufWritePost stays free on every
    -- other save -- an existing file is already listed, and re-reading a
    -- ~200KB csproj on each :w does not belong on the write path.
    vim.api.nvim_create_autocmd("BufNewFile", {
        group = group,
        pattern = "*.cs",
        callback = function(args)
            vim.b[args.buf].unity_sync_new = true
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = "*.cs",
        callback = function(args)
            if not vim.b[args.buf].unity_sync_new then
                return
            end
            vim.b[args.buf].unity_sync_new = nil
            M.on_added(vim.api.nvim_buf_get_name(args.buf))
        end,
    })

    vim.api.nvim_create_user_command("Usync", function()
        M.sync()
    end, { desc = "Unity: rebuild the <Compile> list in Assembly-CSharp.csproj" })

    vim.api.nvim_create_user_command("Ustatus", function()
        M.status()
    end, { desc = "Unity: csproj sync status for this project" })
end

return M
