-- Everything this config needs from the machine, as data. One entry per
-- dependency; util/doctor/init.lua probes, installs and updates from this
-- list, the palette's Doctor category renders it, and `:checkhealth doctor`
-- reports it — so a dependency added here shows up everywhere at once.
--
-- Entry shape:
--   id         unique slug (state key)
--   name       display name
--   group      section header in the Doctor panel
--   needed_for what breaks without it (shown on <CR>)
--   optional   true = only some stacks/projects need it; missing renders as
--              a warning, not an error, and `sync` skips auto-installing it
--              unless its installer is mason (mason packages are cheap and
--              expected by ensure_installed anyway)
--   check      { bin = "exe" } executable lookup, or { fn = function() ... }
--              returning status ("ok"|"missing"|"warn"|"manual"), detail
--   version    { cmd = {...}, min = "x.y.z" } — async `cmd`, first x.y[.z]
--              in its output is the version; below min = "outdated"
--   install    { brew = "formula" } | { cask = "name" } | { mason = "pkg" }
--              | { cmd = {...} } — absent means Doctor can only report it
local M = {}

-- Root of the dotfiles nvim config (this file lives at
-- <root>/lua/util/doctor/registry.lua).
local here = vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))
M.config_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(here))))

-- Kept in sync with plugins/treesitter.lua, which installs from this list.
M.treesitter_parsers = {
    "python", "php", "vue", "typescript", "javascript", "c_sharp", "java",
    "lua", "html", "angular", "css", "scss", "json", "yaml", "toml", "bash",
    "markdown", "markdown_inline", "regex", "vim", "vimdoc", "gitcommit",
    "diff", "dockerfile", "sql",
}

local uv = vim.uv or vim.loop
local is_mac = uv.os_uname().sysname == "Darwin"

-- status helper for { fn = ... } checks
local function found(path)
    return uv.fs_stat(vim.fn.expand(path)) ~= nil
end

M.entries = {
    -- ── Core tools ─────────────────────────────────────────────────────
    {
        id = "git", name = "git", group = "Core tools",
        needed_for = "lazy.nvim bootstrap/updates, gitsigns, telescope git status",
        check = { bin = "git" }, install = { brew = "git" },
    },
    {
        id = "rg", name = "ripgrep", group = "Core tools",
        needed_for = "live grep, word search, PHP reference fallback, LSP heal",
        check = { bin = "rg" },
        version = { cmd = { "rg", "--version" } },
        install = { brew = "ripgrep" },
    },
    {
        id = "fd", name = "fd", group = "Core tools", optional = true,
        needed_for = "faster find_files (telescope falls back to find without it)",
        check = { bin = "fd" }, install = { brew = "fd" },
    },
    {
        id = "node", name = "Node.js", group = "Core tools",
        needed_for = "7 LSP servers run on node (vtsls, intelephense, tailwind, …)",
        check = { bin = "node" },
        version = { cmd = { "node", "--version" }, min = "18.0.0" },
        install = { brew = "node" },
    },
    {
        id = "npm", name = "npm", group = "Core tools",
        needed_for = "mason installs the npm-based servers with it",
        check = { bin = "npm" }, install = { brew = "node" },
    },
    {
        id = "cc", name = "C compiler (clang)", group = "Core tools",
        needed_for = "compiling the 25 treesitter parsers",
        check = { bin = "cc" },
        -- clang ships with the Xcode Command Line Tools, not brew
        install = is_mac and { cmd = { "xcode-select", "--install" } } or nil,
    },
    {
        id = "curl", name = "curl", group = "Core tools",
        needed_for = "mason package downloads",
        check = { bin = "curl" }, install = { brew = "curl" },
    },
    {
        id = "unzip", name = "unzip + tar + gzip", group = "Core tools",
        needed_for = "unpacking mason release artifacts (roslyn, jdtls, …)",
        check = {
            fn = function()
                for _, bin in ipairs({ "unzip", "tar", "gzip" }) do
                    if vim.fn.executable(bin) ~= 1 then
                        return "missing", bin .. " not on PATH"
                    end
                end
                return "ok"
            end,
        },
    },
    {
        id = "claude", name = "Claude Code CLI", group = "Core tools", optional = true,
        needed_for = "the AI sidebar (util/ai/claude.lua)",
        check = { bin = "claude" },
        install = { cmd = { "npm", "install", "-g", "@anthropic-ai/claude-code" } },
    },

    -- ── Language runtimes ──────────────────────────────────────────────
    {
        id = "php", name = "PHP", group = "Language runtimes", optional = true,
        needed_for = "Laravel/PHP projects: artisan, Xdebug target, better-php-sense",
        check = { bin = "php" },
        version = { cmd = { "php", "--version" } },
        install = { brew = "php" },
    },
    {
        id = "python3", name = "Python 3", group = "Language runtimes", optional = true,
        needed_for = "Python projects; debugpy's venv",
        check = { bin = "python3" },
        version = { cmd = { "python3", "--version" } },
        install = { brew = "python" },
    },
    {
        id = "java", name = "JDK", group = "Language runtimes", optional = true,
        needed_for = "Java projects: jdtls runs on it (17+, current builds want 21)",
        check = { bin = "java" },
        version = { cmd = { "java", "-version" }, min = "17.0.0" },
        -- keg-only: needs PATH="$(brew --prefix openjdk@21)/bin:$PATH" afterwards
        install = { brew = "openjdk@21" },
    },
    {
        id = "dotnet", name = ".NET SDK", group = "Language runtimes", optional = true,
        needed_for = "C#/Unity: roslyn LS, netcoredbg, the vstuc debug adapter host",
        check = { bin = "dotnet" },
        version = { cmd = { "dotnet", "--version" } },
        install = { cask = "dotnet-sdk" },
    },

    -- ── Editor layer ───────────────────────────────────────────────────
    {
        id = "nvim", name = "Neovim ≥ 0.12", group = "Editor",
        needed_for = "treesitter main branch, vim.lsp.enable, this whole config",
        check = {
            fn = function()
                local v = vim.version()
                local ok = v.major > 0 or v.minor >= 12
                return ok and "ok" or "missing",
                    ("running %d.%d.%d"):format(v.major, v.minor, v.patch)
            end,
        },
        install = { brew = "neovim" },
    },
    {
        id = "plugins", name = "Plugins (lazy-lock.json)", group = "Editor",
        needed_for = "everything — restore installs the locked plugin versions",
        check = {
            fn = function()
                local ok, cfg = pcall(require, "lazy.core.config")
                if not ok then
                    return "manual", "lazy.nvim not loaded"
                end
                local missing = {}
                for name, plugin in pairs(cfg.plugins) do
                    if plugin.dir and not uv.fs_stat(plugin.dir) then
                        missing[#missing + 1] = name
                    end
                end
                if #missing == 0 then
                    return "ok"
                end
                return "missing", #missing .. " not installed: " .. table.concat(missing, ", ", 1, math.min(3, #missing))
            end,
        },
        install = { restore_plugins = true },
    },
    {
        id = "parsers", name = "Treesitter parsers", group = "Editor",
        needed_for = "IDE-grade highlighting for every language in this config",
        check = {
            fn = function()
                local missing = {}
                for _, lang in ipairs(M.treesitter_parsers) do
                    if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) == 0 then
                        missing[#missing + 1] = lang
                    end
                end
                if #missing == 0 then
                    return "ok", #M.treesitter_parsers .. " installed"
                end
                return "missing", #missing .. " missing: " .. table.concat(missing, ", ", 1, math.min(4, #missing))
            end,
        },
        install = { treesitter = true },
    },

    -- ── Environment ────────────────────────────────────────────────────
    {
        id = "symlink", name = "~/.config/nvim → dotfiles", group = "Environment",
        needed_for = "nvim picking this config up at all",
        check = {
            fn = function()
                local config = uv.fs_realpath(vim.fn.stdpath("config"))
                local root = uv.fs_realpath(M.config_root)
                if config and root and config == root then
                    return "ok"
                end
                return "warn", "config loads from " .. (config or "?") .. ", repo is at " .. (root or "?")
            end,
        },
    },
    {
        id = "truecolor", name = "Truecolor terminal", group = "Environment",
        needed_for = "all 11 themes (termguicolors) render wrong without 24-bit color",
        check = {
            fn = function()
                local ct = vim.env.COLORTERM
                if ct == "truecolor" or ct == "24bit" then
                    return "ok"
                end
                -- GUIs and some terminals don't export COLORTERM but do 24-bit
                return "manual", "COLORTERM=" .. (ct or "unset") .. " — verify colors look right"
            end,
        },
    },
    {
        id = "clipboard", name = "System clipboard", group = "Environment",
        needed_for = "clipboard=unnamedplus (yank ↔ system clipboard)",
        check = {
            fn = function()
                local bins = is_mac and { "pbcopy" } or { "wl-copy", "xclip", "xsel" }
                for _, bin in ipairs(bins) do
                    if vim.fn.executable(bin) == 1 then
                        return "ok", bin
                    end
                end
                return "missing", "no clipboard tool (" .. table.concat(bins, "/") .. ")"
            end,
        },
        install = not is_mac and { cmd = { "sh", "-c", "sudo apt-get install -y wl-clipboard || sudo apt-get install -y xclip" } } or nil,
    },
    {
        id = "nerdfont", name = "Nerd Font   󰋠", group = "Environment",
        needed_for = "every icon in the tree, statusline and this palette",
        -- Undetectable from inside the terminal: the glyphs on this very row
        -- are the test — boxes/questionmarks mean the terminal font isn't a
        -- Nerd Font.
        check = { fn = function()
            return "manual", "if the icons on this row are boxes, set a Nerd Font in the terminal"
        end },
        install = { cask = "font-jetbrains-mono-nerd-font" },
    },
    {
        id = "better-php-sense", name = "better-php-sense", group = "Environment", optional = true,
        needed_for = "the custom PHP LSP layered over intelephense (init.lua)",
        check = { fn = function()
            if found("~/Projects/better-php-sense/bin/server.php") then
                return "ok"
            end
            return "warn", "not cloned — init.lua skips it when absent"
        end },
    },
    {
        id = "vstuc", name = "Unity debug adapter (vstuc)", group = "Environment", optional = true,
        needed_for = "attaching the debugger to the Unity editor (plugins/dap.lua)",
        check = { fn = function()
            local hits = vim.fn.glob(vim.fn.expand("~/.vscode/extensions/visualstudiotoolsforunity.vstuc-*"), false, true)
            if #hits > 0 then
                return "ok"
            end
            return "warn", 'install "Visual Studio Tools for Unity" in VS Code once'
        end },
    },
}

-- Mason-managed servers, formatters and debug adapters. Package names are
-- mason registry names (mason-lspconfig's ensure_installed uses lspconfig
-- aliases; these are what actually lands in ~/.local/share/nvim/mason).
local mason = {
    { pkg = "lua-language-server", needed_for = "editing this config" },
    { pkg = "stylua", needed_for = "formatting this config (util/format.lua)" },
    { pkg = "intelephense", needed_for = "PHP" },
    { pkg = "laravel-ls", needed_for = "Laravel" },
    { pkg = "tailwindcss-language-server", needed_for = "Tailwind" },
    { pkg = "vue-language-server", needed_for = "Vue SFCs" },
    { pkg = "vtsls", needed_for = "TypeScript / JavaScript" },
    { pkg = "angular-language-server", needed_for = "Angular templates" },
    { pkg = "pyright", needed_for = "Python types/navigation" },
    { pkg = "ruff", needed_for = "Python lint + format" },
    { pkg = "html-lsp", needed_for = "HTML" },
    { pkg = "css-lsp", needed_for = "CSS/SCSS/LESS" },
    { pkg = "some-sass-language-server", needed_for = "SCSS workspace symbols" },
    { pkg = "jdtls", needed_for = "Java" },
    { pkg = "roslyn-language-server", needed_for = "C# (roslyn.nvim)" },
    { pkg = "netcoredbg", needed_for = "C# debugging" },
    { pkg = "php-debug-adapter", needed_for = "PHP debugging (Xdebug)" },
    { pkg = "java-debug-adapter", needed_for = "Java debugging" },
    { pkg = "java-test", needed_for = "Java test debugging" },
    { pkg = "debugpy", needed_for = "Python debugging" },
}
for _, m in ipairs(mason) do
    M.entries[#M.entries + 1] = {
        id = "mason:" .. m.pkg,
        name = m.pkg,
        group = "Servers & tools (mason)",
        needed_for = m.needed_for,
        optional = true, -- per-language, but sync installs all of them anyway
        check = { mason = m.pkg },
        install = { mason = m.pkg },
    }
end

return M
