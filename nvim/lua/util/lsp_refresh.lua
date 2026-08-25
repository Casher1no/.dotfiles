-- External-change bridge for language servers. Buffers already auto-reload
-- from disk (see config/autocmds.lua), but servers keep their own in-memory
-- project model: when an outside tool (AI agent, git checkout, a generator)
-- rewrites files that aren't open in a buffer, vtsls/angularls/jdtls/… can
-- miss it and report phantom "cannot find X" errors until you visit the file
-- by hand — visiting works because it sends the server a fresh didOpen.
-- This automates that, two ways:
--   1. Watch bridge — on focus/terminal/idle events, diff the project files
--      (git-aware, async) against the last snapshot and push
--      workspace/didChangeWatchedFiles to every client with that root.
--   2. Diagnostic heal — when an unresolved-symbol diagnostic shows up,
--      locate the file that defines it (relative module path,
--      workspace/symbol, or Angular selector grep) and silently
--      didOpen/didClose it into the server.
-- :LspRefresh runs a forced pass of both.
local M = {}

local uv = vim.uv

local Created, Changed, Deleted = 1, 2, 3

local SCAN_GAP_MS = 5000 -- min time between snapshot scans per root
local IDLE_GAP_MS = 30000 -- wider gap for passive idle (CursorHold) scans
local HEAL_COOLDOWN_MS = 30000 -- min time between heals of the same file/client

local snapshots = {} -- root -> { relpath -> mtime }
local scanning = {} -- root -> true while a scan is in flight
local last_scan = {} -- root -> uv.now() of last started scan
local healed = {} -- client_id .. ":" .. uri -> uv.now() of last heal
local attempts = {} -- client_id .. ":" .. kind .. ":" .. name -> uv.now() of last lookup

-- ---------------------------------------------------------------- watch bridge

-- List tracked + untracked (non-ignored) files with their mtimes, async.
--
-- git is the only external tool involved, and it is a core dependency on all
-- three platforms (both bootstrap scripts install it). This used to pipe git
-- through `xargs stat` inside `sh -c`, which needs sh, xargs and stat — none
-- of which exist on Windows, so the entire watch bridge was silently dead
-- there. libuv stats the files instead: same code, same behaviour, every OS.
--
-- The stat loop is the one part that runs on the main loop. Measured at ~24ms
-- for ~1700 files, and it runs at most once per SCAN_GAP_MS per root, so it
-- stays well under a frame's worth of work at the rate this actually fires.
local function scan_root(root, cb)
    vim.system(
        { "git", "ls-files", "-co", "--exclude-standard", "-z" },
        { cwd = root, text = true },
        function(out)
            if out.code ~= 0 then
                return cb(nil) -- not a git repo, or git unavailable
            end
            local snap = {}
            for rel in (out.stdout or ""):gmatch("[^%z]+") do
                -- Forward slashes from git join fine on Windows too, and
                -- keeping git's own spelling makes the snapshot keys stable.
                local st = uv.fs_stat(root .. "/" .. rel)
                if st then
                    snap[rel] = st.mtime.sec .. "." .. st.mtime.nsec
                end
            end
            cb(snap)
        end
    )
end

local function notify_clients(root, changes)
    for _, client in ipairs(vim.lsp.get_clients()) do
        if client.root_dir == root then
            client:notify("workspace/didChangeWatchedFiles", { changes = changes })
        end
    end
end

local function diff_and_notify(root, snap)
    local old = snapshots[root]
    snapshots[root] = snap
    if not old then
        return -- first scan is just the baseline
    end

    local changes = {}
    for path, mtime in pairs(snap) do
        if not old[path] then
            table.insert(changes, { uri = vim.uri_from_fname(root .. "/" .. path), type = Created })
        elseif old[path] ~= mtime then
            table.insert(changes, { uri = vim.uri_from_fname(root .. "/" .. path), type = Changed })
        end
    end
    for path in pairs(old) do
        if not snap[path] then
            table.insert(changes, { uri = vim.uri_from_fname(root .. "/" .. path), type = Deleted })
        end
    end
    if #changes > 0 then
        notify_clients(root, changes)
    end
end

-- Absolute on every platform: "/..." on unix, "F:\..." or "F:/..." on
-- Windows. The old test was `root:sub(1, 1) == "/"`, which is false for every
-- Windows path — so no root ever qualified and the bridge never ran there.
local function is_absolute(path)
    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function refresh(force, gap)
    local roots = {}
    for _, client in ipairs(vim.lsp.get_clients()) do
        local root = client.root_dir
        -- Absolute existing dirs only: a client started with a cwd-relative
        -- root would make vim.system resolve it against nvim's current cwd
        -- and blow up with ENOENT once the cwd moves.
        if root and is_absolute(root) and uv.fs_stat(root) then
            roots[root] = true
        end
    end
    -- Drop caches for roots whose last client is gone, so project-hopping in
    -- one session doesn't accumulate snapshots forever.
    for _, cache in ipairs({ snapshots, last_scan }) do
        for root in pairs(cache) do
            if not roots[root] and not scanning[root] then
                cache[root] = nil
            end
        end
    end
    for root in pairs(roots) do
        local now = uv.now()
        if not scanning[root] and (force or not last_scan[root] or now - last_scan[root] > gap) then
            scanning[root] = true
            last_scan[root] = now
            scan_root(root, function(snap)
                vim.schedule(function()
                    scanning[root] = nil
                    -- nil = output identical to last scan; empty = git failed.
                    -- Keep the old baseline either way.
                    if snap and next(snap) then
                        diff_and_notify(root, snap)
                    end
                end)
            end)
        end
    end
end

--- Rescan every active client root and tell servers what changed on disk.
---@param force boolean|nil skip the per-root throttle
function M.refresh(force)
    refresh(force, SCAN_GAP_MS)
end

-- ------------------------------------------------------------- diagnostic heal

-- Unresolved-reference shapes worth healing. kind decides how the capture is
-- turned into a file: "module" resolves a relative import path, "symbol" asks
-- the server via workspace/symbol, "selector" greps Angular selectors,
-- "java_import" is a symbol keyed by the last dotted segment.
local PATTERNS = {
    { pat = "Cannot find module '([^']+)'", kind = "module" }, -- TS2307
    { pat = "Module '\"([^\"]+)\"' has no exported member", kind = "module" }, -- TS2305
    { pat = "Cannot find name '([^']+)'", kind = "symbol" }, -- TS2304
    { pat = "'([%w%-]+)' is not a known element", kind = "selector" }, -- Angular NG8001
    { pat = "The import ([%w_%.]+) cannot be resolved", kind = "java_import" },
    { pat = "([%w_]+) cannot be resolved to a type", kind = "symbol" },
}

-- Feed a file to the server as if it were opened in a window, then close it
-- again — forces the server to (re)read it without touching the UI.
-- attempt_key: the caller's `attempts` stamp, re-stamped here so both
-- cooldown clocks tick from the same instant — stamped only at dispatch,
-- they drift apart by the lookup's latency, and a retry landing in that
-- drift window passes the attempts gate only to have the still-fresh healed
-- stamp drop its didOpen.
local function phantom_open(client, path, attempt_key)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        return -- a real buffer exists; autoread/checktime keeps that fresh
    end
    if attempt_key then
        attempts[attempt_key] = uv.now()
    end
    local uri = vim.uri_from_fname(path)
    local key = client.id .. ":" .. uri
    if healed[key] and uv.now() - healed[key] < HEAL_COOLDOWN_MS then
        return
    end
    healed[key] = uv.now()

    local f = io.open(path, "r")
    if not f then
        return
    end
    local text = f:read("*a")
    f:close()
    if #text > 1024 * 1024 then
        return
    end

    local ft = vim.filetype.match({ filename = path }) or "plaintext"
    local lang = ({ cs = "csharp" })[ft] or ft
    client:notify("textDocument/didOpen", {
        textDocument = { uri = uri, languageId = lang, version = 0, text = text },
    })
    vim.defer_fn(function()
        client:notify("textDocument/didClose", { textDocument = { uri = uri } })
    end, 300)
end

-- Resolve a relative import spec ("./user/user.component") against the
-- importing file. Non-relative specs (packages, tsconfig path aliases) are
-- left to the watch bridge.
local function resolve_module(spec, from_file)
    if spec:sub(1, 1) ~= "." then
        return nil
    end
    local base = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(from_file), spec))
    for _, candidate in ipairs({ base, base .. ".ts", base .. ".tsx", base .. ".d.ts", base .. "/index.ts" }) do
        local stat = uv.fs_stat(candidate)
        if stat and stat.type == "file" then
            return candidate
        end
    end
end

local function heal_symbol(client, name, attempt_key)
    if not client:supports_method("workspace/symbol") then
        return
    end
    client:request("workspace/symbol", { query = name }, function(err, result)
        if err or not result then
            return
        end
        for _, sym in ipairs(result) do
            local uri = sym.location and sym.location.uri
            if sym.name == name and uri and uri:sub(1, 7) == "file://" then
                phantom_open(client, vim.uri_to_fname(uri), attempt_key)
                return
            end
        end
    end)
end

-- Angular: "'app-user-card' is not a known element" — grep the project for
-- the component that declares that selector and feed it to the server.
local function heal_selector(client, selector, attempt_key)
    if not client.root_dir then
        return
    end
    vim.system({
        "rg",
        "--files-with-matches",
        "--no-messages",
        "--glob",
        "*.ts",
        "selector:\\s*['\"]" .. selector .. "['\"]",
        client.root_dir,
    }, { text = true }, function(out)
        vim.schedule(function()
            for path in (out.stdout or ""):gmatch("[^\n]+") do
                phantom_open(client, path, attempt_key)
            end
        end)
    end)
end

-- Drop stamps past their cooldown: they block nothing anymore, and the tables
-- otherwise keep one entry per client × name for the whole session.
local function prune_heal_stamps()
    local now = uv.now()
    for _, stamps in ipairs({ healed, attempts }) do
        for key, ts in pairs(stamps) do
            if now - ts >= HEAL_COOLDOWN_MS then
                stamps[key] = nil
            end
        end
    end
end

-- force (the :LspRefresh path) bypasses the attempts cooldown: the user is
-- explicitly saying "things changed, look again" — e.g. the missing module
-- was just created and its failed lookup is still inside the cooldown.
local function heal_buffer(bufnr, force)
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
        return
    end
    prune_heal_stamps()
    local from_file = vim.api.nvim_buf_get_name(bufnr)
    for _, diag in ipairs(vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })) do
        for _, rule in ipairs(PATTERNS) do
            local capture = diag.message:match(rule.pat)
            if capture then
                for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                    -- Stamped before the lookup runs, so a name the search
                    -- can't resolve (typo'd selector, deleted module) isn't
                    -- re-searched on every diagnostic burst while it lingers.
                    local key = client.id .. ":" .. rule.kind .. ":" .. capture
                    if rule.kind == "module" then
                        -- Module specs are relative to the importing file:
                        -- "./util" in src/a and in src/b are different lookups.
                        key = key .. ":" .. vim.fs.dirname(from_file)
                    end
                    if force or not attempts[key] or uv.now() - attempts[key] >= HEAL_COOLDOWN_MS then
                        attempts[key] = uv.now()
                        if rule.kind == "module" then
                            local path = resolve_module(capture, from_file)
                            if path then
                                phantom_open(client, path, key)
                            end
                        elseif rule.kind == "selector" then
                            heal_selector(client, capture, key)
                        else
                            local name = rule.kind == "java_import" and capture:match("([%w_]+)$") or capture
                            heal_symbol(client, name, key)
                        end
                    end
                end
                break -- first matching pattern wins for this diagnostic
            end
        end
    end
end

-- ---------------------------------------------------------------------- setup

function M.setup()
    local group = vim.api.nvim_create_augroup("lsp_refresh", { clear = true })

    -- Same moments checktime runs at (config/autocmds.lua): coming back from
    -- another app or a terminal, or pausing — all the points where an
    -- external tool may just have rewritten files.
    vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "TermClose" }, {
        group = group,
        callback = function()
            M.refresh()
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        group = group,
        callback = function()
            -- Idle polling only backstops the focus/terminal events above, so
            -- it runs at the wider IDLE_GAP_MS.
            refresh(nil, IDLE_GAP_MS)
        end,
    })

    -- New unresolved-reference errors trigger a heal pass, debounced so a
    -- burst of publishDiagnostics only runs it once.
    local pending = {}
    vim.api.nvim_create_autocmd("DiagnosticChanged", {
        group = group,
        callback = function(args)
            local bufnr = args.buf
            if pending[bufnr] then
                return
            end
            pending[bufnr] = true
            vim.defer_fn(function()
                pending[bufnr] = nil
                -- Heal only: diagnostics raised by in-editor edits say
                -- nothing about external file changes, so no rescan here.
                heal_buffer(bufnr)
            end, 800)
        end,
    })

    vim.api.nvim_create_user_command("LspRefresh", function()
        M.refresh(true)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
                heal_buffer(bufnr, true)
            end
        end
        vim.notify("LSP: rescanned project files and healed stale references", vim.log.levels.INFO)
    end, { desc = "Push external file changes to language servers" })
end

return M
