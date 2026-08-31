-- deps-lsp — the "a newer version exists" layer for dependency manifests,
-- the thing VS Code's Version Lens and the JetBrains IDEs do natively:
-- an inlay hint with the latest published version, a diagnostic when the
-- pinned one is behind/yanked/vulnerable, and a code action on the line that
-- rewrites the constraint. It shows up in the same intentions menu as
-- everything else (<leader>ca / Ctrl+.), plus a "Update N outdated
-- dependencies" code lens per file.
--
-- Installed from the project's GitHub release, not mason — see
-- util/deps_lsp.lua for the pin, the sha256 check and the per-OS arms.
--
-- Registries queried, all public and keyless: registry.npmjs.org,
-- repo.packagist.org, crates.io, pypi.org, api.nuget.org, repo1.maven.org,
-- proxy.golang.org, rubygems.org, pub.dev, jsr.io, and api.osv.dev for the
-- vulnerability diagnostics. It reads no credential file of its own
-- (no .npmrc, no auth.json), so a package on a private registry is simply
-- reported unknown — and its *name* does reach the public registry as a
-- lookup that 404s. That is the one privacy cost of this server; set
-- diagnostics.vulnerabilities_enabled = false below to at least keep the
-- dependency list out of osv.dev.
local deps = require("util.deps_lsp")

deps.ensure_path()

local is_win = vim.fn.has("win32") == 1

-- Only these buffers may start the server. Without the gate, `filetypes`
-- alone would attach it to every .json, .toml and .xml in the project —
-- tsconfig.json, launch.json, every Unity .asset — and each one would open a
-- client that has nothing to say.
local MANIFESTS = {
    "package.json", -- npm / pnpm / yarn / bun
    "composer.json", -- PHP, Laravel
    "deno.json",
    "deno.jsonc",
    "Cargo.toml",
    "pyproject.toml",
    "pom.xml", -- Maven
    "go.mod",
    "Gemfile",
    "pubspec.yaml", -- Dart
}

-- NTFS is case-insensitive, so `Cargo.toml` and `cargo.toml` are the same
-- file there and must both match; on Linux they are two different files and
-- only the exact spelling may.
local lookup = {}
for _, name in ipairs(MANIFESTS) do
    lookup[is_win and name:lower() or name] = true
end

-- .csproj is the one manifest whose name is per-project rather than fixed.
local function is_manifest(base)
    return lookup[base] or base:match("%.csproj$") ~= nil
end

local warned = false

-- Neither inlay hints nor code lenses render just because a server offers
-- them: the client has to switch each on per buffer. Nothing else in this
-- config enables either, so a server whose entire output is hints and a lens
-- would attach cleanly and then show nothing at all.
--
-- enable() rather than the older codelens.refresh(): both go through
-- vim.lsp._capability, which owns the re-request on change itself, so a
-- hand-rolled BufEnter/TextChanged autocmd only duplicates it. refresh() is
-- deprecated in 0.12 and goes away in 0.13.
local function on_attach(client, bufnr)
    if client:supports_method("textDocument/inlayHint") then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end
    if client:supports_method("textDocument/codeLens") then
        vim.lsp.codelens.enable(true, { bufnr = bufnr })
    end
end

---@type vim.lsp.Config
return {
    on_attach = on_attach,
    -- Resolved from PATH at spawn time (deps.ensure_path put our bin dir
    -- there), so installing through Doctor mid-session works without a
    -- restart.
    cmd = { "deps-lsp", "--stdio" },
    -- The filetypes of the manifests above; is_manifest() below is what
    -- actually decides. gomod/ruby/yaml earn their place the same way — the
    -- gate makes an unused entry free.
    filetypes = { "json", "jsonc", "toml", "xml", "gomod", "ruby", "yaml" },
    -- A function rather than root_markers: returning without calling on_dir
    -- is how a vim.lsp.Config declines a buffer outright, which is the only
    -- way to filter by file *name* instead of filetype.
    root_dir = function(bufnr, on_dir)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name == "" then
            return
        end
        -- nvim_buf_get_name hands back backslashes on Windows, and
        -- vim.fs.normalize only rewrites those when actually running there —
        -- so the class matches both separators rather than normalising
        -- first. That also makes the Windows arm testable from a mac.
        local base = name:match("[^/\\]+$") or ""
        if not is_manifest(is_win and base:lower() or base) then
            return
        end
        if not deps.exe() then
            -- Never silently do nothing: without this the manifest just
            -- looks like a file with no version hints, which reads as the
            -- feature being broken rather than absent.
            if not warned then
                warned = true
                vim.notify("deps-lsp is not installed — :Doctor to fetch it", vim.log.levels.WARN)
            end
            return
        end
        -- One client per repo rather than one per manifest: a monorepo with
        -- twenty package.json files would otherwise spawn twenty servers.
        on_dir(vim.fs.root(bufnr, { ".git" }) or vim.fs.dirname(vim.fs.normalize(name)))
    end,
    -- Only fields whose type is certain are set here. The server's settings
    -- struct is `deny_unknown_fields` and its severity fields deserialize as
    -- LSP severity *numbers*, not the names its README shows — one wrong key
    -- or type makes it discard the whole payload and silently fall back to
    -- its defaults. The defaults are already what this config wants
    -- (outdated = HINT, which plugins/lsp.lua keeps out of the inline
    -- virtual text and shows on K).
    init_options = {
        inlay_hints = {
            enabled = true,
            -- Nothing at all on an up-to-date line, IDE-style: the hint is
            -- meant to catch the eye only when there is something to do.
            up_to_date_text = "",
            -- ↑ is the same glyph the Doctor panel marks an update with.
            needs_update_text = "↑ {}",
        },
        cache = {
            -- The default re-checks every package five minutes after the
            -- last fetch; on a 60-dependency Angular package.json left open
            -- all day that is ~720 registry requests an hour for versions
            -- that move weekly at best. Half an hour costs nothing in
            -- freshness and cuts it by 6x.
            refresh_interval_secs = 1800,
        },
        code_lens = { enabled = true },
    },
}
