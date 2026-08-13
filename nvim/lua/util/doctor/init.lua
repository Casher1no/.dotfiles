-- Doctor: probes every dependency in util/doctor/registry.lua, shows the
-- machine's state and installs/updates what it can. Three frontends share
-- this engine: the palette's Doctor category (live rows + actions), the
-- :Doctor command (including `nvim --headless "+Doctor sync"`, which
-- bootstrap.sh runs on a fresh clone) and `:checkhealth doctor`.
--
-- All probes are asynchronous where they shell out; results land in M.state
-- and the palette repaints via util.palette.refresh() as they arrive, so
-- opening the panel never blocks.
local M = {}

local registry = require("util.doctor.registry")
local uv = vim.uv or vim.loop

-- results[id] = { status, detail, version, latest }
-- status: ok | missing | outdated (below required min) | warn | manual
--         | checking | unknown.  latest ~= nil marks an available update.
M.state = {
    results = {},
    probed_at = 0,
    pending = 0, -- async probes in flight
    busy = nil, -- label of a running install/update batch
    checking_updates = false,
    note = nil, -- persistent one-line outcome shown in the panel ("no updates found", …)
    log = {},
}

local GLYPH = { ok = "✓", missing = "✗", outdated = "↑", warn = "!", manual = "·", checking = "…", unknown = "?" }
local HL = {
    ok = "DiagnosticOk",
    missing = "DiagnosticError",
    outdated = "DiagnosticWarn",
    warn = "DiagnosticWarn",
    manual = "Comment",
    checking = "Comment",
    unknown = "Comment",
}

local function log(line)
    -- one table entry per screen line: stderr from failed commands is
    -- multi-line, and nvim_buf_set_lines (open_log) rejects embedded \n
    local stamp = os.date("%H:%M:%S") .. "  "
    local first = true
    for piece in tostring(line):gmatch("[^\r\n]+") do
        table.insert(M.state.log, (first and stamp or "          ") .. piece)
        first = false
    end
end

-- The panel's persistent status line: vim.notify alone is easy to miss (it
-- fades, and the palette holds focus), so every action also leaves its
-- outcome here until the next action replaces it.
local function set_note(msg)
    M.state.note = msg
    if msg then
        log(msg)
    end
end

-- One system package manager per OS: brew (mac), choco (windows),
-- apt-get/dnf/pacman (linux, first found). false = detection ran, none found.
local pm_cache
local function package_manager()
    if pm_cache == nil then
        pm_cache = false
        local candidates = ({
            mac = { "brew" },
            windows = { "choco" },
            linux = { "apt-get", "dnf", "pacman" },
        })[registry.os]
        for _, bin in ipairs(candidates) do
            if vim.fn.executable(bin) == 1 then
                pm_cache = bin
                break
            end
        end
    end
    return pm_cache or nil
end

-- Resolve an entry's package name for the detected manager.
-- Returns manager, name, is_cask (brew only).
local function pkg_for(entry)
    local ins = entry.install
    local pm = package_manager()
    if not (ins and pm) then
        return nil
    end
    if pm == "brew" then
        if ins.brew then
            return pm, ins.brew, false
        elseif ins.cask then
            return pm, ins.cask, true
        end
    elseif pm == "choco" then
        if ins.choco then
            return pm, ins.choco, false
        end
    else -- linux managers fall back to the apt name unless overridden
        local name = (pm == "dnf" and (ins.dnf or ins.apt)) or (pm == "pacman" and (ins.pacman or ins.apt)) or ins.apt
        if name then
            return pm, name, false
        end
    end
end

-- Repaint the palette's Doctor rows if it is open. package.loaded (not
-- require) so a headless `Doctor sync` never drags the palette in.
local function notify_change()
    vim.schedule(function()
        local palette = package.loaded["util.palette"]
        if palette then
            pcall(palette.refresh)
        end
    end)
end

local function parse_version(s)
    local maj, min, pat = s:match("(%d+)%.(%d+)%.?(%d*)")
    if not maj then
        return nil
    end
    return { tonumber(maj), tonumber(min), tonumber(pat) or 0 }
end

local function version_lt(a, b)
    for i = 1, 3 do
        if a[i] ~= b[i] then
            return a[i] < b[i]
        end
    end
    return false
end

local function set_result(entry, status, detail, version)
    local prev = M.state.results[entry.id] or {}
    M.state.results[entry.id] = { status = status, detail = detail, version = version, latest = prev.latest }
end

local function probe_entry(entry, done)
    local check = entry.check
    if check.mason then
        local ok, mr = pcall(require, "mason-registry")
        if not ok then
            set_result(entry, "unknown", "mason not loaded")
        else
            set_result(entry, mr.is_installed(check.mason) and "ok" or "missing")
        end
        return done()
    end
    if check.fn then
        local ok, status, detail = pcall(check.fn)
        if ok then
            set_result(entry, status, detail)
        else
            set_result(entry, "unknown", tostring(status))
        end
        return done()
    end
    if check.bin then
        -- a list means "any of these counts" (python3 vs python on windows)
        local bins = type(check.bin) == "table" and check.bin or { check.bin }
        local have
        for _, bin in ipairs(bins) do
            if vim.fn.executable(bin) == 1 then
                have = bin
                break
            end
        end
        if not have then
            set_result(entry, "missing")
            return done()
        end
        if not entry.version then
            set_result(entry, "ok")
            return done()
        end
        -- java prints its version to stderr, so read both streams. The
        -- timeout guarantees done() fires even for a hung shim — otherwise
        -- one stuck probe would pin state.pending > 0 for the session.
        local ok = pcall(vim.system, entry.version.cmd, { text = true, timeout = 10000 }, function(out)
            local text = (out.stdout or "") .. (out.stderr or "")
            local v = text:match("(%d+%.%d+%.?%d*)")
            local status, detail = "ok", nil
            if out.code ~= 0 then
                -- an executable that can't report its version is broken, not
                -- installed — macOS ships a /usr/bin/java stub that passes
                -- the executable() check but exits 1 with "Unable to locate
                -- a Java Runtime"
                status, detail, v = "missing", vim.trim(text:match("[^\r\n]*") or ""), nil
            elseif not v then
                status, detail = "warn", "could not parse version output"
            elseif entry.version.min then
                local have, want = parse_version(v), parse_version(entry.version.min)
                if have and want and version_lt(have, want) then
                    status, detail = "outdated", v .. " < required " .. entry.version.min
                end
            end
            vim.schedule(function()
                set_result(entry, status, detail, v)
                done()
            end)
        end)
        if not ok then
            set_result(entry, "unknown", "version probe failed")
            done()
        end
        return
    end
    set_result(entry, "unknown")
    done()
end

-- Full probe pass. Cheap checks land synchronously; version probes finish
-- async and repaint the palette one by one.
function M.probe(force)
    if M.state.pending > 0 then
        return
    end
    if not force and next(M.state.results) and (uv.now() - M.state.probed_at) < 30000 then
        return
    end
    M.state.probed_at = uv.now()
    M.state.pending = #registry.entries
    for _, entry in ipairs(registry.entries) do
        M.state.results[entry.id] = M.state.results[entry.id] or { status = "checking" }
        probe_entry(entry, function()
            M.state.pending = M.state.pending - 1
            if M.state.pending % 5 == 0 or M.state.pending == 0 then
                notify_change()
            end
        end)
    end
    notify_change()
end

-- ── update detection ───────────────────────────────────────────────────

-- One package-manager query marks every system entry (`brew outdated` on
-- mac, `choco outdated` on windows; apt/dnf have no cheap per-package query,
-- so linux system updates are left to the distro and only logged); mason
-- packages are asked individually (a network hit per package, so on demand).
-- cb (optional) fires once, when every started check has resolved or after
-- a 60s safety timeout — `:Doctor update` chains the apply step off it.
function M.check_updates(cb)
    if M.state.checking_updates then
        return
    end
    M.state.checking_updates = true
    local pending = 0
    local fired = false
    local function finish_all()
        if fired then
            return
        end
        fired = true
        M.state.checking_updates = false
        local n = 0
        for _, res in pairs(M.state.results) do
            if res.latest then
                n = n + 1
            end
        end
        set_note(n == 0 and "no updates found" or n .. " update(s) available — ↑ rows, or “Update all outdated”")
        notify_change()
        if cb then
            cb()
        end
    end
    local function finish_one()
        pending = pending - 1
        if pending == 0 then
            finish_all()
        end
    end
    -- system-manager sweep: name -> newest version
    local function apply_latest(latest, key)
        for _, entry in ipairs(registry.entries) do
            local ins = entry.install
            local name = ins and (key == "brew" and (ins.brew or ins.cask) or ins[key])
            local res = M.state.results[entry.id]
            if name and res then
                res.latest = latest[name]
            end
        end
        notify_change()
    end
    local pm = package_manager()
    if pm == "brew" then
        pending = pending + 1
        vim.system({ "brew", "outdated", "--json=v2" }, { text = true, timeout = 60000 }, function(out)
            vim.schedule(function()
                local ok, data = pcall(vim.json.decode, out.stdout or "")
                if ok and type(data) == "table" then
                    local latest = {}
                    for _, f in ipairs(data.formulae or {}) do
                        latest[f.name] = (f.current_version or "new version")
                    end
                    for _, c in ipairs(data.casks or {}) do
                        latest[c.name] = (c.current_version or "new version")
                    end
                    apply_latest(latest, "brew")
                end
                finish_one()
            end)
        end)
    elseif pm == "choco" then
        pending = pending + 1
        -- -r: machine-readable "name|current|available|pinned" lines
        vim.system({ "choco", "outdated", "-r" }, { text = true, timeout = 60000 }, function(out)
            vim.schedule(function()
                local latest = {}
                for line in (out.stdout or ""):gmatch("[^\r\n]+") do
                    local name, _, available = line:match("^([^|]+)|([^|]*)|([^|]*)|")
                    if name and available and available ~= "" then
                        latest[name] = available
                    end
                end
                apply_latest(latest, "choco")
                finish_one()
            end)
        end)
    elseif pm then
        log("system updates on linux are the distro's job — check e.g. `apt list --upgradable`")
    end
    local ok, mr = pcall(require, "mason-registry")
    if ok then
        for _, entry in ipairs(registry.entries) do
            local res = M.state.results[entry.id]
            if entry.check.mason and res and res.status == "ok" then
                local okp, pkg = pcall(mr.get_package, entry.check.mason)
                -- mason's update API has changed across majors; degrade to
                -- "no update info" rather than erroring on either version.
                if okp and type(pkg.check_new_version) == "function" then
                    pending = pending + 1
                    local started = pcall(pkg.check_new_version, pkg, function(success, result)
                        vim.schedule(function()
                            if success and result and result.latest_version then
                                -- look the table up at write time: a re-probe
                                -- may have replaced it while the HTTP check ran
                                local live = M.state.results[entry.id]
                                if live then
                                    live.latest = result.latest_version
                                end
                                notify_change()
                            end
                            finish_one()
                        end)
                    end)
                    if not started then
                        pending = pending - 1
                    end
                end
            end
        end
    end
    set_note("checking for updates…")
    log("update check started (" .. (package_manager() or "no system manager") .. " + mason registry)")
    notify_change()
    if pending == 0 then
        finish_all()
    else
        -- safety net for callbacks mason never delivers
        vim.defer_fn(finish_all, 60000)
    end
end

-- ── install / update runners ───────────────────────────────────────────

-- Poll a main-loop predicate once a second until true or timeout.
local function poll(pred, timeout_ms, cb)
    if pred() then
        return cb(true)
    end
    if timeout_ms <= 0 then
        return cb(false)
    end
    vim.defer_fn(function()
        poll(pred, timeout_ms - 1000, cb)
    end, 1000)
end

local function run_queue(jobs, done)
    local i = 0
    local function next_job()
        i = i + 1
        local job = jobs[i]
        if not job then
            return done()
        end
        log(job.desc)
        notify_change()
        job.run(next_job)
    end
    next_job()
end

local function shell_job(desc, cmd)
    return {
        desc = desc,
        run = function(next_job)
            local ok = pcall(vim.system, cmd, { text = true }, function(out)
                vim.schedule(function()
                    if out.code == 0 then
                        log("done: " .. desc)
                    else
                        log("FAILED (" .. out.code .. "): " .. desc .. " — " .. vim.trim(out.stderr or ""))
                    end
                    next_job()
                end)
            end)
            if not ok then
                log("FAILED to spawn: " .. desc)
                next_job()
            end
        end,
    }
end

local function mason_job(names, want_update)
    return {
        desc = (want_update and "mason update: " or "mason install: ") .. table.concat(names, ", "),
        run = function(next_job)
            local ok, mr = pcall(require, "mason-registry")
            if not ok then
                log("mason not available — skipped")
                return next_job()
            end
            local function start()
                -- pkg:install() always fetches the latest version, so it is
                -- also the upgrade path — on updates the "already installed"
                -- skip must not apply, and completion is the install handle
                -- closing (is_installed is already true throughout).
                local handles = {}
                for _, name in ipairs(names) do
                    local okp, pkg = pcall(mr.get_package, name)
                    if okp and (want_update or not pkg:is_installed()) then
                        local okh, handle = pcall(pkg.install, pkg)
                        if okh and handle then
                            handles[#handles + 1] = handle
                        end
                    end
                end
                poll(function()
                    for _, handle in ipairs(handles) do
                        local okc, closed = pcall(handle.is_closed, handle)
                        if okc and not closed then
                            return false
                        end
                    end
                    for _, name in ipairs(names) do
                        if not mr.is_installed(name) then
                            return false
                        end
                    end
                    return true
                end, 600000, function(all_done)
                    log(all_done and ("mason packages " .. (want_update and "updated" or "installed"))
                        or "mason: timed out / some installs failed (see :Mason)")
                    next_job()
                end)
            end
            -- a fresh machine has no registry cache yet; if refresh throws
            -- (its API has moved across mason majors), still install against
            -- whatever cache exists rather than stalling the job queue
            if type(mr.refresh) ~= "function" or not pcall(mr.refresh, vim.schedule_wrap(start)) then
                start()
            end
        end,
    }
end

local function treesitter_job(langs)
    return {
        desc = "treesitter parsers: " .. #langs .. " to compile",
        run = function(next_job)
            local ok, ts = pcall(require, "nvim-treesitter")
            if not ok then
                log("nvim-treesitter not available — skipped")
                return next_job()
            end
            pcall(ts.install, langs)
            poll(function()
                for _, lang in ipairs(langs) do
                    if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) == 0 then
                        return false
                    end
                end
                return true
            end, 600000, function(all_done)
                log(all_done and "parsers compiled" or "parsers: timed out (check :TSInstall output)")
                next_job()
            end)
        end,
    }
end

local function restore_job()
    return {
        desc = "lazy restore (plugins from lazy-lock.json)",
        run = function(next_job)
            local ok = pcall(function()
                require("lazy").restore({ wait = false, show = false })
            end)
            if not ok then
                log("lazy restore failed to start")
                return next_job()
            end
            local plugins_entry
            for _, e in ipairs(registry.entries) do
                if e.id == "plugins" then
                    plugins_entry = e
                end
            end
            poll(function()
                local okc, status = pcall(plugins_entry.check.fn)
                return okc and status == "ok"
            end, 600000, function(done_ok)
                log(done_ok and "plugins restored" or "plugins: restore still incomplete (see :Lazy)")
                next_job()
            end)
        end,
    }
end

-- Build the job list that fixes the given predicate ("missing" or update).
-- Batch installs honor the registry contract: optional entries are skipped
-- unless their installer is mason (a headless `Doctor sync` must not pull
-- multi-GB SDKs like the JDK or dotnet onto a machine that may never edit
-- those stacks). include_optional=true is the per-row install, where the
-- user explicitly asked for that one dependency.
-- Runs cmd in a visible terminal split: choco wants an elevated shell and
-- apt/dnf/pacman go through sudo — both need a tty for prompts, and the
-- output doubles as the progress indicator. Headless falls back to a plain
-- spawn and lets failures land in the log.
local function terminal_job(desc, cmd)
    return {
        desc = desc,
        run = function(next_job)
            if #vim.api.nvim_list_uis() == 0 then
                return shell_job(desc, cmd).run(next_job)
            end
            vim.cmd("botright 12new")
            local win = vim.api.nvim_get_current_win()
            local ok = pcall(vim.fn.jobstart, cmd, {
                term = true,
                on_exit = vim.schedule_wrap(function(_, code)
                    if code == 0 then
                        log("done: " .. desc)
                        -- keep failed runs on screen for inspection
                        if vim.api.nvim_win_is_valid(win) then
                            pcall(vim.api.nvim_win_close, win, true)
                        end
                    else
                        log("FAILED (" .. code .. "): " .. desc .. " — output left open in the split")
                    end
                    next_job()
                end),
            })
            if not ok then
                pcall(vim.api.nvim_win_close, win, true)
                log("FAILED to spawn: " .. desc)
                next_job()
            end
        end,
    }
end

-- One job per system package manager, from a list of package names.
local function system_job(pm, names, want_update)
    local label = pm .. (want_update and " upgrade: " or " install: ") .. table.concat(names, ", ")
    if pm == "brew" then
        local verb = want_update and "upgrade" or "install"
        return shell_job(label, vim.list_extend({ "brew", verb }, names))
    elseif pm == "choco" then
        local verb = want_update and "upgrade" or "install"
        -- needs an admin shell; the terminal split shows choco's own error
        -- if nvim wasn't started elevated
        return terminal_job(label, vim.list_extend({ "choco", verb, "-y" }, names))
    elseif pm == "apt-get" then
        return terminal_job(label, vim.list_extend({ "sudo", "apt-get", "install", "-y" }, names))
    elseif pm == "dnf" then
        return terminal_job(label, vim.list_extend({ "sudo", "dnf", "install", "-y" }, names))
    elseif pm == "pacman" then
        return terminal_job(label, vim.list_extend({ "sudo", "pacman", "-S", "--noconfirm", "--needed" }, names))
    end
end

local function build_install_jobs(want_update, include_optional)
    local sys, sys_cask, jobs, mason_pkgs, ts_missing, unmanaged = {}, {}, {}, {}, nil, {}
    for _, entry in ipairs(registry.entries) do
        local res = M.state.results[entry.id] or {}
        local wanted = want_update and (res.latest ~= nil)
            or (not want_update and (res.status == "missing" or res.status == "outdated"))
        -- The optional-skip contract covers INSTALLS only: pulling a multi-GB
        -- SDK nobody asked for is the thing to avoid. An update mark proves
        -- the tool is already installed, so upgrades always qualify.
        if wanted and not want_update and entry.optional and not include_optional
            and not (entry.install and entry.install.mason)
        then
            wanted = false
        end
        if wanted and entry.install then
            local ins = entry.install
            if ins.mason then
                mason_pkgs[#mason_pkgs + 1] = ins.mason
            elseif ins.cmd and not want_update then
                jobs[#jobs + 1] = shell_job(table.concat(ins.cmd, " "), ins.cmd)
            elseif ins.restore_plugins and not want_update then
                jobs[#jobs + 1] = restore_job()
            elseif ins.treesitter and not want_update then
                ts_missing = true
            else
                local pm, name, is_cask = pkg_for(entry)
                if pm then
                    local bucket = is_cask and sys_cask or sys
                    bucket[#bucket + 1] = name
                else
                    unmanaged[#unmanaged + 1] = entry.name
                end
            end
        end
    end
    if #unmanaged > 0 then
        if not package_manager() then
            local hint = ({
                mac = "install Homebrew first",
                windows = "install Chocolatey first (https://chocolatey.org/install)",
                linux = "no apt-get/dnf/pacman found",
            })[registry.os]
            set_note("can't install " .. table.concat(unmanaged, ", ") .. " — " .. hint)
        else
            log("no " .. package_manager() .. " package known for: " .. table.concat(unmanaged, ", ") .. " — install manually")
        end
    end
    local out = {}
    local pm = package_manager()
    if pm and #sys > 0 then
        out[#out + 1] = system_job(pm, sys, want_update)
    end
    if pm == "brew" and #sys_cask > 0 then
        local verb = want_update and "upgrade" or "install"
        -- terminal, not vim.system: casks wrapping .pkg installers (dotnet-sdk,
        -- fonts to /Library) sudo-prompt mid-install, which a tty-less spawn
        -- can only fail
        out[#out + 1] = terminal_job("brew " .. verb .. " --cask: " .. table.concat(sys_cask, ", "),
            vim.list_extend({ "brew", verb, "--cask" }, sys_cask))
    end
    if #mason_pkgs > 0 then
        out[#out + 1] = mason_job(mason_pkgs, want_update)
    end
    if ts_missing then
        -- recompute the actual missing set at run time
        local missing = {}
        for _, lang in ipairs(registry.treesitter_parsers) do
            if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) == 0 then
                missing[#missing + 1] = lang
            end
        end
        if #missing > 0 then
            out[#out + 1] = treesitter_job(missing)
        end
    end
    vim.list_extend(out, jobs)
    return out
end

-- cb receives did_run: false on the busy/nothing-to-do early exits, so
-- callers don't treat a skipped batch as a completed one. empty_note is the
-- persistent panel message for the nothing-to-do case (each caller knows
-- what "nothing" means for it).
local function run_batch(label, jobs, cb, empty_note)
    if M.state.busy then
        vim.notify("Doctor is already busy: " .. M.state.busy, vim.log.levels.WARN)
        if cb then
            cb(false)
        end
        return
    end
    if #jobs == 0 then
        set_note(empty_note or "nothing to do")
        notify_change()
        if cb then
            cb(false)
        end
        return
    end
    M.state.busy = label
    set_note(label .. " running… (" .. #jobs .. " steps — see log)")
    log("── " .. label .. " (" .. #jobs .. " steps)")
    local log_start = #M.state.log
    notify_change()
    run_queue(jobs, function()
        M.state.busy = nil
        local failed = 0
        for i = log_start + 1, #M.state.log do
            if M.state.log[i]:find("FAILED", 1, true) then
                failed = failed + 1
            end
        end
        set_note(label .. " finished" .. (failed > 0 and " — " .. failed .. " FAILED line(s) in the log" or " ✓"))
        log("── " .. label .. " finished")
        vim.notify("Doctor: " .. label .. " finished", vim.log.levels.INFO)
        -- a palette repaint mid-batch may have kicked off a probe pass whose
        -- async probes are still in flight; M.probe(force) no-ops while
        -- pending > 0, so wait it out or the panel keeps mid-install rows
        poll(function()
            return M.state.pending == 0
        end, 30000, function()
            M.probe(true)
            if cb then
                cb(true)
            end
        end)
    end)
end

-- Exposed for headless tests (same pattern as references._gather etc.).
M._build_install_jobs = build_install_jobs

function M.install_missing(cb)
    run_batch("install missing", build_install_jobs(false), cb,
        "nothing required is missing — ⏎ on an optional ✗ row installs just that one")
end

function M.update_all(cb)
    local jobs = build_install_jobs(true)
    run_batch("update outdated", jobs, function(did_run)
        if did_run then
            -- upgrades applied: drop every ↑ mark, then re-detect so a
            -- failed upgrade gets its mark back instead of vanishing
            for _, res in pairs(M.state.results) do
                res.latest = nil
            end
            M.check_updates()
        end
        if cb then
            cb(did_run)
        end
    end, "nothing marked outdated — run “Check for updates” first")
end

-- Install a single registry entry (the per-row <CR> action — an explicit
-- request, so optional entries install too).
function M.install_one(entry)
    local res = M.state.results[entry.id] or {}
    local saved = {}
    -- run build_install_jobs against a state where only this entry is missing
    for id, r in pairs(M.state.results) do
        if id ~= entry.id then
            saved[id] = r
            M.state.results[id] = { status = "ok" }
        end
    end
    local jobs = build_install_jobs(res.latest ~= nil and res.status == "ok", true)
    for id, r in pairs(saved) do
        M.state.results[id] = r
    end
    run_batch(entry.name, jobs)
end

-- ── frontends ──────────────────────────────────────────────────────────

local function counts()
    local c = { missing = 0, optional_missing = 0, updates = 0, ok = 0, checking = 0 }
    for _, entry in ipairs(registry.entries) do
        local res = M.state.results[entry.id] or {}
        if res.status == "missing" or res.status == "outdated" then
            if entry.optional then
                c.optional_missing = c.optional_missing + 1
            else
                c.missing = c.missing + 1
            end
        elseif res.status == "ok" then
            c.ok = c.ok + 1
        elseif res.status == "checking" then
            c.checking = c.checking + 1
        end
        if res.latest then
            c.updates = c.updates + 1
        end
    end
    return c
end

-- Rows for the palette's Doctor category (util/palette.lua renders them;
-- items carry hl + keep_open, which the palette understands).
function M.palette_items()
    M.probe()
    local items = {}
    local c = counts()
    local summary
    if M.state.busy then
        summary = "⟳ " .. M.state.busy .. "…  (live — see log)"
    elseif c.checking > 0 then
        summary = "… checking " .. c.checking .. " of " .. #registry.entries
    else
        summary = ("%d ok · %d missing · %d optional missing · %d updates"):format(
            c.ok, c.missing, c.optional_missing, c.updates)
    end
    items[#items + 1] = {
        desc = summary,
        section = true,
        hl = (c.missing > 0 and "DiagnosticError") or (c.updates + c.optional_missing > 0 and "DiagnosticWarn")
            or "DiagnosticOk",
    }

    local seen_groups = {}
    for _, entry in ipairs(registry.entries) do
        if not seen_groups[entry.group] then
            seen_groups[entry.group] = true
            items[#items + 1] = { desc = entry.group, section = true }
        end
        local res = M.state.results[entry.id] or { status = "checking" }
        local status = res.status or "unknown"
        local glyph = GLYPH[status] or "?"
        local hl = HL[status]
        if status == "missing" and entry.optional then
            hl = "DiagnosticWarn"
        end
        local desc = glyph .. " " .. entry.name
        if res.version then
            desc = desc .. " " .. res.version
        end
        if res.latest then
            desc = desc .. "  ↑" .. res.latest
            if status == "ok" then
                hl = "DiagnosticWarn"
            end
        end
        local installer
        if entry.install then
            local ins = entry.install
            if ins.mason then
                installer = "mason"
            elseif ins.treesitter then
                installer = "TS"
            elseif ins.restore_plugins then
                installer = "lazy"
            elseif ins.cmd then
                installer = "cmd"
            else
                -- show the manager that would actually run on this OS
                local pm = pkg_for(entry)
                installer = pm or "manual"
            end
        end
        items[#items + 1] = {
            desc = desc,
            keys = installer or "",
            hl = hl,
            keep_open = true,
            action = function()
                -- read live state, not the render-time snapshot: an async
                -- probe/install may have flipped this row since it was built
                local live = M.state.results[entry.id] or {}
                local fixable = (live.status == "missing" or live.status == "outdated" or live.latest)
                    and entry.install
                if fixable then
                    M.install_one(entry)
                else
                    vim.notify(
                        entry.name .. " — " .. entry.needed_for .. (live.detail and ("\n" .. live.detail) or ""),
                        vim.log.levels.INFO
                    )
                end
            end,
        }
    end

    items[#items + 1] = { desc = "Actions", section = true }
    -- Last action's outcome, kept until the next action replaces it. It sits
    -- HERE, next to the buttons: the list is longer than the pane, so when
    -- the selection is down at the actions the top rows are scrolled away —
    -- and the floating notify fades while the palette holds focus.
    if M.state.checking_updates then
        items[#items + 1] = { desc = "⟳ checking for updates…", section = true, hl = "DiagnosticInfo" }
    elseif M.state.note then
        items[#items + 1] = { desc = "› " .. M.state.note, section = true, hl = "Comment" }
    end
    items[#items + 1] = {
        desc = "Install all missing", keys = "⏎", keep_open = true,
        action = function() M.install_missing() end,
    }
    items[#items + 1] = {
        desc = "Check for updates", keys = "⏎", keep_open = true,
        action = function() M.check_updates() end,
    }
    items[#items + 1] = {
        desc = "Update all outdated", keys = "⏎", keep_open = true,
        action = function() M.update_all() end,
    }
    items[#items + 1] = {
        desc = "Re-check everything", keys = "⏎", keep_open = true,
        action = function() M.probe(true) end,
    }
    items[#items + 1] = {
        desc = "Open Doctor log", keys = "⏎",
        action = function() M.open_log() end,
    }
    return items
end

function M.open_log()
    local buf = vim.api.nvim_create_buf(false, true)
    -- flatten defensively: entries logged before the newline-splitting in
    -- log() existed (or by future callers bypassing it) must not crash here
    local lines = {}
    for _, entry in ipairs(M.state.log) do
        for piece in entry:gmatch("[^\r\n]+") do
            lines[#lines + 1] = piece
        end
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "(log is empty)" })
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_height(0, math.min(15, math.max(3, #M.state.log)))
end

local function report_lines()
    local lines = {}
    local group = nil
    for _, entry in ipairs(registry.entries) do
        if entry.group ~= group then
            group = entry.group
            lines[#lines + 1] = ""
            lines[#lines + 1] = group
        end
        local res = M.state.results[entry.id] or { status = "unknown" }
        local mark = GLYPH[res.status] or "?"
        local extra = {}
        if res.version then
            extra[#extra + 1] = res.version
        end
        if res.detail then
            extra[#extra + 1] = res.detail
        end
        if res.latest then
            extra[#extra + 1] = "update: " .. res.latest
        end
        lines[#lines + 1] = ("  %s %-34s %s"):format(mark, entry.name, table.concat(extra, " — "))
    end
    local c = counts()
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("%d ok · %d missing · %d optional missing · %d updates"):format(
        c.ok, c.missing, c.optional_missing, c.updates)
    return lines
end

-- Blocking probe for the synchronous frontends (report/health/sync).
local function probe_and_wait(timeout_ms)
    M.probe(true)
    vim.wait(timeout_ms or 15000, function()
        return M.state.pending == 0
    end, 100)
end

-- `:checkhealth doctor` (bridged from lua/doctor/health.lua).
function M.health()
    local h = vim.health
    h.start("dotfiles dependencies (util/doctor)")
    probe_and_wait()
    for _, entry in ipairs(registry.entries) do
        local res = M.state.results[entry.id] or { status = "unknown" }
        local label = entry.name
            .. (res.version and (" " .. res.version) or "")
            .. (res.detail and (" — " .. res.detail) or "")
        if res.status == "ok" then
            h.ok(label)
        elseif res.status == "missing" or res.status == "outdated" then
            local advice = "needed for: " .. entry.needed_for
            if entry.optional then
                h.warn(label .. " (optional)", { advice })
            else
                h.error(label, { advice })
            end
        else
            h.warn(label)
        end
    end
end

-- One-shot machine setup: everything the editor layer can do by itself.
-- Blocking on purpose — it is the headless bootstrap entry point, and when
-- run interactively you asked for a full sync anyway.
function M.sync()
    local headless = #vim.api.nvim_list_uis() == 0
    local function say(line)
        if headless then
            io.write(line .. "\n")
        else
            vim.notify(line, vim.log.levels.INFO)
        end
    end
    say("Doctor: probing…")
    probe_and_wait()
    local jobs = build_install_jobs(false)
    if #jobs == 0 then
        say("Doctor: nothing to install — all good.")
    else
        local finished = false
        run_batch("sync", jobs, function()
            finished = true
        end)
        -- pump the loop until the async batch (and its re-probe) is done
        vim.wait(45 * 60 * 1000, function()
            return finished
        end, 500)
        vim.wait(30000, function()
            return M.state.pending == 0
        end, 100)
    end
    for _, line in ipairs(report_lines()) do
        say(line)
    end
    for _, line in ipairs(M.state.log) do
        if line:find("FAILED", 1, true) then
            say(line)
        end
    end
end

-- :Doctor [report|sync|install|update|log] — no argument opens the palette.
function M.command(fargs)
    local sub = fargs[1]
    if sub == nil or sub == "" then
        require("util.palette").open("Doctor")
    elseif sub == "report" then
        probe_and_wait()
        vim.notify(table.concat(report_lines(), "\n"), vim.log.levels.INFO)
    elseif sub == "sync" then
        M.sync()
    elseif sub == "install" then
        probe_and_wait()
        M.install_missing()
    elseif sub == "update" then
        probe_and_wait()
        M.check_updates(function()
            M.update_all()
        end)
    elseif sub == "log" then
        M.open_log()
    else
        vim.notify("Doctor: unknown subcommand '" .. sub .. "'", vim.log.levels.ERROR)
    end
end

return M
