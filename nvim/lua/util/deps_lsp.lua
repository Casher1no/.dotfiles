-- deps-lsp: locating, installing and version-checking the dependency
-- language server that lua/lsp/deps_lsp.lua drives.
--
-- It is not a mason package and has no brew/choco/apt formula, so the only
-- cross-platform install is the project's own GitHub release: download the
-- archive for this (OS, arch), verify its sha256 against the .sha256 asset
-- published beside it, unpack the single binary into
-- stdpath("data")/deps-lsp and put that directory on PATH.
--
-- The release is pinned (M.VERSION) rather than tracking latest, for the
-- same reason lazy-lock.json exists: an unattended `Doctor sync` on a fresh
-- machine must install the version this config was written against. The
-- server carries `#[serde(deny_unknown_fields)]` on its settings struct, so
-- a renamed option in a future release makes it drop *every* setting we
-- send and fall back to its own defaults — pinning is what keeps
-- lua/lsp/deps_lsp.lua's init_options honest. Bump the pin and Doctor
-- reports the installed copy as outdated (↑), ⏎ reinstalls.
--
-- Decision and action are kept apart so the other two platforms' arms can be
-- tested from one machine: target()/asset()/sha256_cmd()/extract_cmd()/
-- parse_sha256() are pure, install() is the only function that touches the
-- network or the disk.
local M = {}

local uv = vim.uv or vim.loop

M.VERSION = "0.11.0"

local RELEASE = "https://github.com/bug-ops/deps-lsp/releases/download/v%s/%s"

local is_win = vim.fn.has("win32") == 1

-- Where our managed copy lives. Not mason's bin dir: mason owns that, and a
-- foreign binary in it confuses `:Mason` and its uninstall path.
function M.root()
    return vim.fs.joinpath(vim.fn.stdpath("data"), "deps-lsp")
end

function M.bin()
    return vim.fs.joinpath(M.root(), is_win and "deps-lsp.exe" or "deps-lsp")
end

-- ── pure decisions ──────────────────────────────────────────────────────

-- uname (uv.os_uname() shape) -> rust target triple used in the asset names.
-- Returns nil, reason when this machine has no prebuilt binary, so the
-- caller can say so instead of downloading something that cannot run.
function M.target(uname)
    uname = uname or uv.os_uname()
    local machine = (uname.machine or ""):lower()
    local arch = (machine == "arm64" or machine == "aarch64") and "aarch64"
        or ((machine == "x86_64" or machine == "amd64") and "x86_64")
        or nil
    if not arch then
        return nil, "unsupported CPU architecture " .. (uname.machine or "?")
    end
    if is_win then
        return arch .. "-pc-windows-msvc"
    end
    local sysname = uname.sysname or ""
    if sysname == "Darwin" then
        return arch .. "-apple-darwin"
    end
    if sysname == "Linux" then
        -- The gnu build links against glibc and will not start on a musl
        -- distro; the release publishes both, so pick by libc rather than
        -- shipping a binary that dies with a linker error at spawn time.
        local musl = uv.fs_stat("/etc/alpine-release") ~= nil
            or uv.fs_stat("/lib/ld-musl-x86_64.so.1") ~= nil
            or uv.fs_stat("/lib/ld-musl-aarch64.so.1") ~= nil
        return arch .. "-unknown-linux-" .. (musl and "musl" or "gnu")
    end
    return nil, "unsupported OS " .. (sysname ~= "" and sysname or "?")
end

function M.asset(target)
    -- The Windows job packs with 7z, every other job with tar (release.yml).
    local ext = target:find("windows", 1, true) and "zip" or "tar.gz"
    local name = ("deps-lsp-%s.%s"):format(target, ext)
    return {
        name = name,
        url = RELEASE:format(M.VERSION, name),
        sha_url = RELEASE:format(M.VERSION, name .. ".sha256"),
    }
end

-- No one hashing tool spans the three platforms: macOS ships shasum but not
-- sha256sum, Linux ships sha256sum, Windows ships neither and answers with
-- certutil. (vim.fn.sha256() is not an option — Vim strings cannot carry the
-- NUL bytes of a gzip archive intact.)
function M.sha256_cmd(path)
    if is_win then
        return { "certutil", "-hashfile", path, "SHA256" }
    end
    if vim.fn.executable("sha256sum") == 1 then
        return { "sha256sum", path }
    end
    if vim.fn.executable("shasum") == 1 then
        return { "shasum", "-a", "256", path }
    end
    return nil
end

-- Pulls the digest out of whichever of the three formats produced it:
--   sha256sum/shasum  "<hash>  <file>"
--   certutil          a header line, the hash, a trailing status line —
--                     older builds space out the hex byte-wise.
function M.parse_sha256(text)
    if type(text) ~= "string" then
        return nil
    end
    local hash = text:match("%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x")
    if hash then
        return hash:lower()
    end
    -- byte-spaced certutil output: collapse each line before retrying
    for line in text:gmatch("[^\r\n]+") do
        local packed = line:gsub("%s+", "")
        if #packed == 64 and packed:match("^%x+$") then
            return packed:lower()
        end
    end
    return nil
end

-- tar reads both formats, and Windows has shipped bsdtar since Win10 1803 —
-- the same assumption util/doctor/registry.lua's "archive tools" entry
-- already makes for mason's release artifacts.
function M.extract_cmd(archive, dir)
    return { "tar", "-xf", archive, "-C", dir }
end

-- ── locating ────────────────────────────────────────────────────────────

-- Our managed copy wins over PATH so a `cargo install` copy of some other
-- version can't shadow the pinned one; PATH is still honoured as a fallback
-- for machines where the binary came from somewhere else.
function M.exe()
    if uv.fs_stat(M.bin()) then
        return M.bin()
    end
    local found = vim.fn.exepath("deps-lsp")
    return found ~= "" and found or nil
end

-- Puts our bin dir on PATH so `cmd = { "deps-lsp" }` resolves at spawn time
-- rather than at config-load time — without this, installing through Doctor
-- would need a restart before the server could start.
function M.ensure_path()
    local root = M.root()
    local sep = is_win and ";" or ":"
    local current = vim.env.PATH or ""
    for entry in vim.gsplit(current, sep, { plain = true }) do
        if entry == root then
            return
        end
    end
    vim.env.PATH = root .. sep .. current
end

-- Doctor's check.fn: ok / outdated / missing / manual, plus a detail line.
function M.status()
    local exe = M.exe()
    if not exe then
        local _, err = M.target()
        if err then
            -- Visible rather than silent: no release exists for this machine,
            -- so Doctor must not offer an install that cannot work.
            return "manual", err .. " — build it with `cargo install deps-lsp`"
        end
        return "missing", "not installed — ⏎ downloads v" .. M.VERSION
    end
    local ok, out = pcall(function()
        return vim.system({ exe, "--version" }, { text = true }):wait()
    end)
    if not ok or out.code ~= 0 then
        return "warn", exe .. " is not executable"
    end
    local got = (out.stdout or ""):match("(%d+%.%d+%.%d+)")
    if not got then
        return "warn", "unrecognised --version output"
    end
    if vim.version.lt(got, M.VERSION) then
        return "outdated", got .. " installed, config pins " .. M.VERSION
    end
    return "ok", got
end

-- ── install (the only side-effecting function) ──────────────────────────

-- log(line) mirrors util/doctor/init.lua's logger; done() advances its queue.
function M.install(log, done)
    local function finish(msg)
        if msg then
            log("deps-lsp: " .. msg)
        end
        done()
    end

    local target, err = M.target()
    if not target then
        return finish(err .. " — no prebuilt binary, use `cargo install deps-lsp`")
    end
    for _, bin in ipairs({ "curl", "tar" }) do
        if vim.fn.executable(bin) ~= 1 then
            return finish(bin .. " is not on PATH — cannot install")
        end
    end
    local hash_cmd_for = M.sha256_cmd
    if not hash_cmd_for(M.bin()) then
        -- Refusing beats installing an unverified executable.
        return finish("no sha256 tool (sha256sum/shasum) — refusing to install unverified")
    end

    local asset = M.asset(target)
    local root = M.root()
    if vim.fn.mkdir(root, "p") == 0 then
        return finish("could not create " .. root)
    end
    local archive = vim.fs.joinpath(root, asset.name)

    local function fail(msg)
        pcall(uv.fs_unlink, archive)
        finish(msg)
    end

    -- vim.system callbacks run off the main loop; everything touching vim.fn
    -- or vim.env has to be scheduled back onto it.
    local function run(cmd, on_ok)
        local ok = pcall(vim.system, cmd, { text = true }, function(out)
            vim.schedule(function()
                if out.code ~= 0 then
                    return fail(cmd[1] .. " failed (" .. out.code .. "): " .. vim.trim(out.stderr or ""))
                end
                on_ok(out)
            end)
        end)
        if not ok then
            fail("could not spawn " .. cmd[1])
        end
    end

    log("deps-lsp: downloading " .. asset.name .. " (v" .. M.VERSION .. ")")
    -- --proto =https so a redirect cannot downgrade the transport; -f turns a
    -- 404 into a non-zero exit instead of a saved error page.
    run({ "curl", "-fsSL", "--proto", "=https", "-o", archive, asset.url }, function()
        run({ "curl", "-fsSL", "--proto", "=https", asset.sha_url }, function(sha_out)
            local want = M.parse_sha256(sha_out.stdout)
            if not want then
                return fail("could not read the published sha256")
            end
            run(hash_cmd_for(archive), function(hash_out)
                local got = M.parse_sha256(hash_out.stdout)
                if got ~= want then
                    return fail("sha256 mismatch — expected " .. want .. ", got " .. tostring(got))
                end
                log("deps-lsp: sha256 verified")
                run(M.extract_cmd(archive, root), function()
                    pcall(uv.fs_unlink, archive)
                    local bin = M.bin()
                    if not uv.fs_stat(bin) then
                        return fail("archive did not contain " .. vim.fs.basename(bin))
                    end
                    if not is_win then
                        -- tar preserves the mode, but only if the archive
                        -- carried one; 0755 explicitly is cheaper than
                        -- debugging a spawn EACCES later.
                        pcall(uv.fs_chmod, bin, 493)
                    end
                    M.ensure_path()
                    run({ bin, "--version" }, function(v)
                        log("deps-lsp: installed " .. vim.trim(v.stdout or "") .. " → " .. bin)
                        done()
                    end)
                end)
            end)
        end)
    end)
end

return M
